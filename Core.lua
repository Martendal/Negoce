-- Négoce : noyau. Bases de données, événements du jeu, messages internes, objets, monnaie.
-- L'addon observe et calcule : il n'achète, ne vend et ne poste jamais rien à ta place.
local ADDON, ns = ...
local L = ns.L

ns.VERSION = "1.2.0"
ns.AH_CUT = 0.05          -- part prélevée par l'hôtel des ventes sur une vente
ns.MAX_MONEY_LOG = 6000   -- mouvements d'or gardés
ns.MAX_LOG = 2000         -- achats, ventes, mises en vente gardés
ns.MAX_WEALTH = 4000      -- points de la courbe de patrimoine gardés
ns.HISTORY_DAYS = 21      -- jours d'historique de prix gardés par objet

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

function ns.Append(list, entry, max)
  list[#list + 1] = entry
  if max then
    while #list > max do table.remove(list, 1) end
  end
  return entry
end

function ns.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

function ns.Print(msg)
  print(ns.Lf("%s : %s", "|cffe0b050Négoce|r", tostring(msg)))
end

local errorAnnounced = false
function ns.Error(where, err)
  local db = ns.db
  if db then
    db.errors = db.errors or {}
    ns.Append(db.errors, { t = time(), w = tostring(where), m = tostring(err) }, 50)
  end
  if (db and db.debug) or not errorAnnounced then
    errorAnnounced = true
    ns.Print(ns.Lf("erreur dans %s (détails : /negoce erreurs)", tostring(where)))
  end
end

-- Appelle fn sans jamais propager d'erreur ; renvoie ses résultats ou nil.
function ns.Try(where, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    ns.Error(where, a)
    return nil
  end
  return a, b, c
end

---------------------------------------------------------------------------
-- Monnaie
---------------------------------------------------------------------------

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"

local function thousands(n)
  local sep = ns.lang == "fr" and " " or ","
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
  return (out:gsub("^" .. sep, ""))
end

-- Montant avec les icônes de pièces. Les grosses sommes perdent le cuivre, puis l'argent,
-- pour rester lisibles. withSign ajoute un « + » devant les gains.
-- short retire le cuivre dès qu'il y a de l'or, pour les endroits étroits.
function ns.Money(c, withSign, short)
  if c == nil then return "—" end
  c = math.floor(c + 0.5)
  local sign = ""
  if c < 0 then sign = "-" elseif withSign and c > 0 then sign = "+" end
  c = math.abs(c)
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local cu = c % 100
  if g >= 1000 then
    return sign .. thousands(g) .. GOLD
  elseif g >= 10 or (short and g > 0) then
    return string.format("%s%d%s %02d%s", sign, g, GOLD, s, SILVER)
  elseif g > 0 then
    return string.format("%s%d%s %02d%s %02d%s", sign, g, GOLD, s, SILVER, cu, COPPER)
  elseif s > 0 then
    return string.format("%s%d%s %02d%s", sign, s, SILVER, cu, COPPER)
  end
  return string.format("%s%d%s", sign, cu, COPPER)
end

-- « il y a 5 min », « il y a 3 h », « il y a 2 j ».

-- Date courte : jour et mois, avec l'heure si withTime. Le format dépend de la langue
-- (« 23/11 14:05 », « Nov 23 14:05 »).
function ns.Date(t, withTime)
  return date(withTime and L["%d/%m %H:%M"] or L["%d/%m"], t)
end
function ns.Ago(t)
  if not t then return L["jamais"] end
  local d = math.max(0, time() - t)
  if d < 90 then return L["à l'instant"] end
  if d < 3600 then return ns.Lf("il y a %d min", math.floor(d / 60)) end
  if d < 86400 then return ns.Lf("il y a %d h", math.floor(d / 3600)) end
  return ns.Lf("il y a %d j", math.floor(d / 86400))
end

---------------------------------------------------------------------------
-- Événements du jeu : chaque module s'abonne avec ns.On(event, fn).
-- Chaque gestionnaire tourne sous pcall : un bug dans un module n'arrête pas les autres.
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
ns.unknownEvents = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then ns.unknownEvents[#ns.unknownEvents + 1] = event end
  end
  local list = handlers[event]
  list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then ns.Error(event, err) end
  end
end)

-- Accroche une fonction après une fonction du jeu, sans jamais casser si elle n'existe pas.
function ns.Hook(tbl, name, fn)
  if type(tbl) == "string" then
    fn, name, tbl = name, tbl, nil
    if type(_G[name]) ~= "function" then return false end
    hooksecurefunc(name, function(...)
      local ok, err = pcall(fn, ...)
      if not ok then ns.Error(name, err) end
    end)
    return true
  end
  if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
  hooksecurefunc(tbl, name, function(...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.Error(name, err) end
  end)
  return true
end

---------------------------------------------------------------------------
-- Messages internes : les modules de données préviennent la fenêtre que quelque chose a changé.
-- Les rafraîchissements sont regroupés (un tous les 0,3 s au plus).
---------------------------------------------------------------------------

local listeners = {}
function ns.Listen(fn) listeners[#listeners + 1] = fn end

local pendingRefresh = false
function ns.Changed()
  if pendingRefresh then return end
  pendingRefresh = true
  C_Timer.After(0.3, function()
    pendingRefresh = false
    for i = 1, #listeners do
      local ok, err = pcall(listeners[i])
      if not ok then ns.Error("rafraîchissement", err) end
    end
  end)
end

---------------------------------------------------------------------------
-- Objets : nom, qualité, icône, prix de vente au marchand. Les infos qui ne sont pas encore
-- en cache sont demandées au jeu ; la fenêtre se rafraîchit quand elles arrivent.
---------------------------------------------------------------------------

local itemCache = {}
local requested = {}

function ns.Item(id)
  local it = itemCache[id]
  if it and it.name then return it end
  it = it or { id = id }
  itemCache[id] = it
  local name, link, quality, _, _, _, _, maxStack, _, icon, sellPrice
  if C_Item and C_Item.GetItemInfo then
    name, link, quality, _, _, _, _, maxStack, _, icon, sellPrice = C_Item.GetItemInfo(id)
  end
  if name then
    it.name, it.link, it.quality, it.stack, it.icon, it.sell = name, link, quality, maxStack, icon, sellPrice or 0
  else
    if not it.icon and C_Item and C_Item.GetItemIconByID then
      it.icon = C_Item.GetItemIconByID(id)
    end
    if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
      requested[id] = true
      pcall(C_Item.RequestLoadItemDataByID, id)
    end
  end
  return it
end

function ns.ItemName(id)
  return ns.Item(id).name or ns.Lf("Objet %d", id)
end

ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
  if itemID and requested[itemID] then
    requested[itemID] = nil
    ns.Changed()
  end
end)

local QUALITY = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.93, 0.90, 0.85 }, [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1.00, 0.50, 0.00 },
}
function ns.QualityColor(q)
  local c = QUALITY[q or 1] or QUALITY[1]
  return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Bases de données
--   NegoceDB   : une par personnage (or, stock, achats, ventes, recettes connues, réglages).
--   NegocePrix : partagée par le compte, car ce sont des données de marché et non de perso
--                (prix de l'hôtel des ventes par marché, prix des marchands).
---------------------------------------------------------------------------

local function initDB()
  NegoceDB = NegoceDB or {}
  local db = NegoceDB
  db.schema = 1
  db.char = db.char or {}
  db.minimap = db.minimap or {}
  if db.minimap.showInCompartment == nil then db.minimap.showInCompartment = true end
  db.ui = db.ui or {}
  db.moneyLog = db.moneyLog or {}
  db.wealth = db.wealth or {}
  db.purchases = db.purchases or {}
  db.sales = db.sales or {}
  db.posts = db.posts or {}
  db.known = db.known or {}
  db.errors = db.errors or {}
  ns.db = db

  NegocePrix = NegocePrix or {}
  local px = NegocePrix
  px.schema = 1
  px.markets = px.markets or {}
  px.vendors = px.vendors or {}
  px.recipes = px.recipes or {}
  ns.px = px
  ns.SetLanguage(px.lang)
end

function ns.NextSeq()
  local db = ns.db
  db.seq = (db.seq or 0) + 1
  return db.seq
end

ns.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  initDB()
end)

function ns.UpdateChar()
  local c = ns.db.char
  local name = UnitName("player")
  if name and name ~= UNKNOWNOBJECT and name ~= "Unknown" then c.name = name end
  local classLocal, classToken = UnitClass("player")
  c.class, c.classLocal = classToken, classLocal
  c.faction = UnitFactionGroup("player")
  c.level = UnitLevel("player")
  c.updated = time()
end

ns.On("PLAYER_LOGIN", function()
  if not ns.db then initDB() end
  ns.UpdateChar()
  if ns.OnLogin then
    for i = 1, #ns.OnLogin do ns.Try("connexion", ns.OnLogin[i]) end
  end
end)

-- Les modules ajoutent ici ce qu'ils doivent faire à la connexion, une fois la base prête.
ns.OnLogin = {}
function ns.AtLogin(fn) ns.OnLogin[#ns.OnLogin + 1] = fn end

ns.On("PLAYER_ENTERING_WORLD", function()
  if ns.db then ns.UpdateChar() end
end)
