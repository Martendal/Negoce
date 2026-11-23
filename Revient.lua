-- Négoce : prix de revient. Chaque objet a un coût moyen, tenu à jour à chaque entrée ou sortie.
--
-- Trois réserves par objet, chacune { q = quantité, c = coût total } :
--   pool : ce qui est dans tes sacs et ta banque ;
--   tr   : ce que tu as mis en vente à l'HV (jusqu'à la vente ou au retour par courrier) ;
--   pend : ce que tu as acheté à l'HV et pas encore retiré du courrier.
--
-- Les entrées et sorties sont déduites en comparant deux relevés des sacs et de la banque, et
-- classées d'après le contexte (fenêtres ouvertes, dernières actions) :
--   butin, quête, échange, courrier d'un joueur : entrée à 0 ;
--   achat au marchand, achat à l'HV : entrée au prix payé ;
--   fabrication : les composants sortent à leur coût moyen, le produit entre avec ce coût ;
--   vente, envoi, utilisation : sortie au coût moyen.
local ADDON, ns = ...
local L = ns.L

local LOG_MAX = 400
local PEND_DAYS = 31

ns.SOURCES = {
  butin = "butin", quete = "quête", marchand = "achat marchand", hv = "achat HV",
  fab = "fabrication", courrier = "courrier", echange = "échange", hors_suivi = "hors suivi",
  autre = "autre", compo = "composant utilisé", vente_hv = "vente HV",
  vente_marchand = "vente marchand", envoi = "envoyé", utilise = "utilisé ou détruit",
  mise_en_vente = "mis en vente", retour_hv = "retour de l'HV",
}

---------------------------------------------------------------------------
-- Réserves
---------------------------------------------------------------------------

local function put(map, id, q, c)
  local e = map[id]
  if not e then
    e = { q = 0, c = 0 }
    map[id] = e
  end
  e.q = e.q + q
  e.c = e.c + (c or 0)
  return e
end

-- Retire jusqu'à q unités au coût moyen de la réserve : quantité retirée, coût retiré.
local function take(map, id, q)
  local e = map[id]
  if not e or e.q <= 0 or q <= 0 then return 0, 0 end
  local n = math.min(q, e.q)
  local cost = e.c * n / e.q
  e.q = e.q - n
  e.c = e.c - cost
  if e.q <= 0 then map[id] = nil end
  return n, cost
end

local function track() return ns.db and ns.db.track end

-- Journal des mouvements : les mouvements identiques qui se suivent sont regroupés.
local function log(id, n, src, cost)
  local list = ns.db.track.log
  local now = time()
  local last = list[#list]
  if last and last.id == id and last.s == src and (now - last.t) <= 60 then
    last.n = last.n + n
    last.c = (last.c or 0) + (cost or 0)
    last.t = now
    return
  end
  ns.Append(list, { t = now, id = id, n = n, s = src, c = cost or 0 }, LOG_MAX)
end

-- Coût moyen d'un objet à l'unité, sur tout ce que tu en possèdes : coût, quantité suivie.
function ns.UnitCost(id)
  local T = track()
  if not T then return nil end
  local q, c = 0, 0
  local e = T.pool[id]
  if e then q, c = q + e.q, c + e.c end
  e = T.tr[id]
  if e then q, c = q + e.q, c + e.c end
  e = T.pend[id]
  if e then q, c = q + e.q, c + e.c end
  if q <= 0 then return nil end
  return math.max(0, c) / q, q
end

---------------------------------------------------------------------------
-- Ce que les autres modules signalent
---------------------------------------------------------------------------

-- Mise en vente : les objets vont quitter les sacs sans quitter ton patrimoine.
local pendingPost = {}
function ns.NotePost(id, qty)
  if not id then return end
  local p = pendingPost[id]
  if not p or (GetTime() - p.t) > 20 then
    p = { q = 0 }
    pendingPost[id] = p
  end
  p.q = p.q + (qty or 1)
  p.t = GetTime()
end

-- Achat à l'HV lu sur une facture : les objets attendent dans le courrier.
function ns.NotePurchase(e)
  local T = track()
  if not T or not e.id or not e.q or e.q <= 0 then return end
  put(T.pend, e.id, e.q, e.p or 0).t = time()
end

-- Vente à l'HV lue sur une facture : les objets sortent de la réserve « en vente » et leur coût
-- est noté sur la vente (cr), ce qui fige la marge.
function ns.RealizeSale(e)
  local T = track()
  if not T or not e.id then return end
  local q, exact = e.q, true
  if not q then
    -- Quantité illisible sur la facture : on l'estime pour garder les réserves justes, mais
    -- la vente n'aura pas de marge affichée.
    exact = false
    local posts = ns.db.posts
    for i = #posts, math.max(1, #posts - 400), -1 do
      local p = posts[i]
      if p.id == e.id and p.u and p.u > 0 then
        q = math.floor((e.p or 0) / p.u + 0.5)
        break
      end
    end
    local held = T.tr[e.id] and T.tr[e.id].q or 0
    q = math.max(1, math.min(q or 1, math.max(1, held)))
  end
  local got, cost = take(T.tr, e.id, q)
  if got < q then
    -- Vendu sans être passé par le suivi : on prend le coût moyen du stock, sans y toucher.
    local unit = ns.UnitCost(e.id)
    if unit then
      cost = cost + unit * (q - got)
    elseif got > 0 then
      cost = cost * q / got
    else
      cost = nil
    end
  end
  if exact and cost then e.cr = math.floor(cost + 0.5) end
  log(e.id, -q, "vente_hv", cost or 0)
end

-- Achats au marchand : prix à l'unité de ce qu'on vient d'acheter ou de racheter.
local merchantBuys = {}
local function noteMerchant(id, unit)
  if id and unit then merchantBuys[id] = { u = unit, t = GetTime() } end
end

ns.Hook("BuyMerchantItem", function(index)
  if not (GetMerchantItemID and ns.MerchantItem) then return end
  local price, stack = ns.MerchantItem(index)
  if price then noteMerchant(GetMerchantItemID(index), price / math.max(1, stack or 1)) end
end)

ns.Hook("BuybackItem", function(index)
  if not (GetBuybackItemInfo and GetBuybackItemLink) then return end
  local _, _, price, qty = GetBuybackItemInfo(index)
  local id = ns.ItemIDFromLink(GetBuybackItemLink(index))
  if price then noteMerchant(id, price / math.max(1, qty or 1)) end
end)

ns.On("CHAT_MSG_LOOT", function() ns.MarkContext("loot") end)

---------------------------------------------------------------------------
-- Relevé : quantité de chaque objet dans les sacs et la banque.
---------------------------------------------------------------------------

local function mainTotals()
  local out = {}
  local function merge(src)
    if not src or not src.items then return end
    for id, e in pairs(src.items) do out[id] = (out[id] or 0) + e.c end
  end
  merge(ns.db.bags)
  merge(ns.db.bank)
  return out
end

---------------------------------------------------------------------------
-- Premier lancement : le stock que tu as déjà. Ce que tes achats à l'HV déjà enregistrés
-- couvrent garde leur prix (les plus récents d'abord), le reste démarre à 0.
---------------------------------------------------------------------------

local function init()
  local db = ns.db
  local T = { v = 1, seen = mainTotals(), pool = {}, tr = {}, pend = {}, log = {} }

  local bought = {}
  for _, p in ipairs(db.purchases) do
    if p.id and p.q and p.q > 0 then
      bought[p.id] = bought[p.id] or {}
      table.insert(bought[p.id], p)
    end
  end
  local selling = {}
  if db.auctions then
    for _, a in ipairs(db.auctions.list) do
      if a.id and a.st ~= 1 then selling[a.id] = (selling[a.id] or 0) + (a.q or 1) end
    end
  end
  local mail = db.mail and db.mail.items or {}

  local ids = {}
  for id in pairs(T.seen) do ids[id] = true end
  for id in pairs(selling) do ids[id] = true end
  for id in pairs(mail) do ids[id] = true end

  for id in pairs(ids) do
    local list = bought[id]
    local i, left = list and #list or 0, nil
    -- Prend n unités sur tes achats, du plus récent au plus ancien : quantité couverte, coût.
    local function draw(n)
      local got, cost = 0, 0
      while got < n and i >= 1 do
        local p = list[i]
        left = left or p.q
        local k = math.min(left, n - got)
        got, cost = got + k, cost + (p.p / p.q) * k
        left = left - k
        if left <= 0 then i, left = i - 1, nil end
      end
      return got, cost
    end
    local inMail = mail[id] and mail[id].c or 0
    if inMail > 0 then
      local got, cost = draw(inMail)
      if got > 0 then put(T.pend, id, got, cost).t = time() end
    end
    if selling[id] then
      local _, cost = draw(selling[id])
      put(T.tr, id, selling[id], cost)
    end
    if T.seen[id] then
      local _, cost = draw(T.seen[id])
      put(T.pool, id, T.seen[id], cost)
    end
  end
  db.track = T
end

---------------------------------------------------------------------------
-- Classement des mouvements
---------------------------------------------------------------------------

-- Sorties « hors suivi » de la session : si l'objet réapparaît peu après (relevé incomplet à la
-- connexion ou à l'ouverture de la banque), il retrouve son coût.
local lost = {}

local function restore(T, id, n)
  local l = lost[id]
  if not l or (GetTime() - l.t) > 600 or l.q <= 0 then return 0 end
  local m = math.min(n, l.q)
  local cost = l.c * m / l.q
  l.q, l.c = l.q - m, l.c - cost
  put(T.pool, id, m, cost)
  log(id, m, "hors_suivi", cost)
  return m
end

-- Fabrications : un produit apparaît et tous les composants d'une de ses recettes diminuent.
local function crafts(T, delta)
  local made = {}
  for id, d in pairs(delta) do
    if d > 0 and ns.byProduct[id] then
      for _, r in ipairs(ns.byProduct[id]) do
        local ok = #r.reag > 0
        for _, c in ipairs(r.reag) do
          if not (delta[c.id] and delta[c.id] < 0) then
            ok = false
            break
          end
        end
        if ok then
          made[#made + 1] = { id = id, n = d, r = r, runs = d / math.max(1, r.qty) }
          break
        end
      end
    end
  end
  if #made == 0 then return end

  -- Un même composant peut servir à deux recettes du même relevé : chacune prend sa part.
  local need = {}
  for _, m in ipairs(made) do
    for _, c in ipairs(m.r.reag) do need[c.id] = (need[c.id] or 0) + c.n * m.runs end
  end
  local spent = {}
  for id in pairs(need) do
    local n = -delta[id]
    local _, cost = take(T.pool, id, n)
    spent[id] = cost
    log(id, -n, "compo", cost)
    delta[id] = nil
  end
  for _, m in ipairs(made) do
    local cost = 0
    for _, c in ipairs(m.r.reag) do
      cost = cost + spent[c.id] * (c.n * m.runs) / need[c.id]
    end
    put(T.pool, m.id, m.n, cost)
    log(m.id, m.n, "fab", cost)
    delta[m.id] = nil
  end
end

local function exits(T, id, n, offline)
  if not offline then
    -- Mise en vente : l'objet passe dans la réserve « en vente » avec son coût.
    local post = pendingPost[id]
    local m = 0
    if post and post.q > 0 and (GetTime() - post.t) <= 20 then
      m = math.min(n, post.q)
      post.q = post.q - m
    elseif ns.Seen("auction", 5) then
      m = n -- à l'HV, un objet ne quitte les sacs que pour être mis en vente
    end
    if m > 0 then
      local _, cost = take(T.pool, id, m)
      put(T.tr, id, m, cost)
      log(id, -m, "mise_en_vente", cost)
      n = n - m
    end
  end
  if n <= 0 then return end
  local src = "utilise"
  if offline then
    src = "hors_suivi"
  elseif ns.Seen("merchant", 5) then
    src = "vente_marchand"
  elseif ns.Seen("mail", 5) then
    src = "envoi"
  elseif ns.Seen("trade", 5) then
    src = "echange"
  end
  local _, cost = take(T.pool, id, n)
  if offline then
    local l = lost[id]
    if not l or (GetTime() - l.t) > 600 then
      l = { q = 0, c = 0 }
      lost[id] = l
    end
    l.q, l.c, l.t = l.q + n, l.c + cost, GetTime()
  end
  log(id, -n, src, cost)
end

local function entries(T, id, n, offline)
  if offline then
    n = n - restore(T, id, n)
    if n > 0 then
      put(T.pool, id, n, 0)
      log(id, n, "hors_suivi", 0)
    end
    return
  end
  -- Marchand : au prix payé.
  local buy = merchantBuys[id]
  if buy and (GetTime() - buy.t) <= 15 then
    put(T.pool, id, n, buy.u * n)
    log(id, n, "marchand", buy.u * n)
    return
  end
  if ns.Seen("merchant", 5) then
    local cost = (ns.VendorPrice(id) or 0) * n
    put(T.pool, id, n, cost)
    log(id, n, "marchand", cost)
    return
  end
  -- Courrier : d'abord tes achats à l'HV en attente, puis tes invendus qui reviennent, et
  -- enfin ce qu'un joueur t'envoie.
  if ns.Seen("mail", 5) then
    local m, cost = take(T.pend, id, n)
    if m > 0 then
      put(T.pool, id, m, cost)
      log(id, m, "hv", cost)
      n = n - m
    end
    if n > 0 then
      m, cost = take(T.tr, id, n)
      if m > 0 then
        put(T.pool, id, m, cost)
        log(id, m, "retour_hv", cost)
        n = n - m
      end
    end
    if n > 0 then
      put(T.pool, id, n, 0)
      log(id, n, "courrier", 0)
    end
    return
  end
  local src = "autre"
  if ns.Seen("trade", 5) then
    src = "echange"
  elseif ns.Seen("quest", 5) then
    src = "quete"
  elseif ns.Seen("loot", 6) then
    src = "butin"
  end
  if src == "autre" then n = n - restore(T, id, n) end
  if n > 0 then
    put(T.pool, id, n, 0)
    log(id, n, src, 0)
  end
end

---------------------------------------------------------------------------
-- Suivi : appelé après chaque relevé des sacs ou de la banque.
--   offline = true quand le changement s'est fait sans que l'addon le voie (ouverture de la
--   banque). Le premier relevé d'une session est toujours traité ainsi.
---------------------------------------------------------------------------

local first = true

function ns.TrackItems(offline)
  local db = ns.db
  if not db or not db.bags then return end
  local cur = mainTotals()
  if not db.track then
    if next(cur) == nil then return end -- sacs pas encore chargés
    init()
    first = false
    return
  end
  local T = db.track
  -- Sacs vides alors qu'on connaissait un stock : le jeu n'a pas fini de charger, on attend.
  if next(cur) == nil and next(T.seen) ~= nil then return end

  local delta, any = {}, false
  for id, n in pairs(cur) do
    local d = n - (T.seen[id] or 0)
    if d ~= 0 then delta[id], any = d, true end
  end
  for id, n in pairs(T.seen) do
    if not cur[id] then delta[id], any = -n, true end
  end
  T.seen = cur
  offline = offline or first
  first = false
  if not any then return end

  if not offline then crafts(T, delta) end
  for id, d in pairs(delta) do
    if d < 0 then exits(T, id, -d, offline) end
  end
  for id, d in pairs(delta) do
    if d > 0 then entries(T, id, d, offline) end
  end
end

-- Achats jamais retirés du courrier : au bout d'un mois le courrier a expiré.
ns.AtLogin(function()
  local T = track()
  if not T then return end
  local limit = time() - PEND_DAYS * 86400
  for id, e in pairs(T.pend) do
    if (e.t or 0) < limit then T.pend[id] = nil end
  end
end)

-- Derniers mouvements, pour vérifier en jeu que le classement est juste : /negoce suivi
function ns.PrintTracking(count)
  local T = track()
  if not T or #T.log == 0 then
    ns.Print(L["aucun mouvement d'objet enregistré pour l'instant."])
    return
  end
  for i = math.max(1, #T.log - (count or 15) + 1), #T.log do
    local e = T.log[i]
    ns.Print(string.format("%s  %+d %s · %s · %s", date("%H:%M", e.t), e.n, ns.ItemName(e.id),
      ns.SOURCES[e.s] and L[ns.SOURCES[e.s]] or e.s, ns.Money(e.c)))
  end
end
