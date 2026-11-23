-- Négoce : positions. Achats et ventes à l'hôtel des ventes (lus sur les factures du courrier),
-- mises en vente, et lignes du portefeuille (le prix de revient est tenu dans Revient.lua).
local ADDON, ns = ...

local AH = C_AuctionHouse
local AH_MAIL_DAYS = 30 -- durée de vie d'un courrier de l'HV

---------------------------------------------------------------------------
-- Mises en vente : on note l'objet, la quantité et le prix à l'unité. La facture d'une vente
-- ne donne que le nom et la somme : c'est cette note qui permet de retrouver objet et quantité.
---------------------------------------------------------------------------

local function itemIDFromLocation(loc)
  if loc and C_Item and C_Item.GetItemID then
    local ok, id = pcall(C_Item.GetItemID, loc)
    if ok then return id end
  end
end

local function recordPost(id, qty, unit)
  if not ns.db or not id then return end
  local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ns.Item(id).name
  local e = { t = time(), id = id, n = name, q = qty, u = unit, k = ns.NextSeq() }
  ns.Append(ns.db.posts, e, ns.MAX_LOG)
  ns.lastPost = e
  ns.MarkContext("ah_post")
  if ns.NotePost then ns.NotePost(id, qty) end
end

if AH then
  ns.Hook(AH, "PostItem", function(loc, _, qty, _, buyout)
    qty = qty or 1
    recordPost(itemIDFromLocation(loc), qty, buyout and math.floor(buyout / qty) or nil)
  end)
  ns.Hook(AH, "PostCommodity", function(loc, _, qty, unitPrice)
    recordPost(itemIDFromLocation(loc), qty or 1, unitPrice)
  end)
  -- Prix inhabituel : le jeu demande une confirmation, le dépôt part à ce moment-là.
  ns.Hook(AH, "ConfirmPostCommodity", function() ns.MarkContext("ah_post") end)
  ns.Hook(AH, "ConfirmPostItem", function() ns.MarkContext("ah_post") end)
  ns.Hook(AH, "PlaceBid", function() ns.MarkContext("ah_buy") end)
  ns.Hook(AH, "ConfirmCommoditiesPurchase", function() ns.MarkContext("ah_buy") end)
end

-- Retrouve l'objet et la quantité d'une vente à partir de tes mises en vente récentes.
local function matchPost(name, amount)
  local posts = ns.db.posts
  local fallback
  for i = #posts, math.max(1, #posts - 400), -1 do
    local p = posts[i]
    if p.n == name then
      fallback = fallback or p
      if p.u and p.u > 0 and amount % p.u == 0 then
        local qty = amount / p.u
        if qty >= 1 and qty <= (p.q or qty) then return p.id, qty end
      end
    end
  end
  if fallback then return fallback.id, nil end
end

---------------------------------------------------------------------------
-- Factures du courrier. Chaque facture n'est enregistrée qu'une fois, même si on la revoit à
-- chaque ouverture de la boîte.
---------------------------------------------------------------------------

local function recordInvoices(invoices)
  local db = ns.db
  local matched = {}
  for _, inv in ipairs(invoices) do
    local list = inv.kind == "seller" and db.sales or db.purchases
    local found = false
    for k = #list, math.max(1, #list - 300), -1 do
      local s = list[k]
      if not matched[s] and s.n == inv.n and s.p == inv.p and math.abs(s.t - inv.t) <= 600 then
        matched[s] = true
        found = true
        -- Une facture revue peut préciser ce qui manquait.
        s.id = s.id or inv.id
        s.q = s.q or inv.q
        break
      end
    end
    if not found then
      local e = { t = inv.t, n = inv.n, id = inv.id, q = inv.q, p = inv.p, k = ns.NextSeq() }
      if inv.kind == "seller" then
        e.dep, e.cut = inv.dep, inv.cut
        e.net = inv.p + inv.dep - inv.cut
        if not e.id or not e.q then
          local id, qty = matchPost(inv.n, inv.p)
          e.id, e.q = e.id or id, e.q or qty
        end
      end
      ns.Append(list, e, ns.MAX_LOG)
      matched[e] = true
      if inv.kind == "seller" then
        if ns.RealizeSale then ns.Try("revient", ns.RealizeSale, e) end
      elseif ns.NotePurchase then
        ns.Try("revient", ns.NotePurchase, e)
      end
    end
  end
end

function ns.ReadInvoices()
  if not (GetInboxInvoiceInfo and GetInboxNumItems) then return end
  local now = time()
  local invoices = {}
  for i = 1, GetInboxNumItems() or 0 do
    local kind, itemName, _, bid, _, deposit, cut, _, _, count = GetInboxInvoiceInfo(i)
    if (kind == "seller" or kind == "buyer") and itemName then
      local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
      local inv = {
        kind = kind,
        n = itemName,
        p = bid or 0,
        dep = deposit or 0,
        cut = cut or 0,
        q = (count and count > 0) and count or nil,
        -- date estimée d'après le temps qu'il reste au courrier avant d'expirer
        t = now - math.floor((AH_MAIL_DAYS - (daysLeft or AH_MAIL_DAYS)) * 86400 + 0.5),
      }
      if kind == "buyer" then
        -- L'objet acheté est joint au courrier : il donne l'identifiant et la quantité exacts.
        local id, qty = ns.InboxItem(i, 1)
        if id then inv.id, inv.q = id, qty end
      end
      invoices[#invoices + 1] = inv
    end
  end
  if #invoices > 0 then recordInvoices(invoices) end
end

-- Lignes du portefeuille :
--   { id, q, bags, bank, mail, ah, unit = cours, src = "hv"|"marchand", value,
--     unitCost = coût de revient moyen à l'unité, cost = coût de tout ce que tu en possèdes,
--     gain = ce que rapporterait la vente de tout, taxe de l'HV déduite, moins ce coût }
function ns.Positions()
  local rows = {}
  for id, h in pairs(ns.Holdings()) do
    local value, unit = ns.HoldingValue(h)
    local _, src = ns.Value(id, h.free == 0)
    local row = {
      id = id, q = h.q, bags = h.bags, bank = h.bank, mail = h.mail, ah = h.ah,
      unit = unit, src = src, value = value,
    }
    local unitCost = ns.UnitCost and ns.UnitCost(id)
    if unitCost then
      row.unitCost, row.cost = unitCost, unitCost * h.q
      local net = value
      if src == "hv" then net = value - unit * h.free * ns.AH_CUT end
      row.gain = net - row.cost
    end
    if value > 0 or (row.cost or 0) > 0 then rows[#rows + 1] = row end
  end
  return rows
end
