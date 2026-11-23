-- Essai de Négoce hors du jeu : charge l'addon contre une fausse API de WoW, simule une
-- connexion, un scan de l'HV, des sacs, du courrier, puis ouvre la fenêtre et ses deux onglets.
-- Ne remplace pas un essai en jeu : vérifie seulement que la logique tourne sans erreur.
--
--   lua outils/test_hors_jeu.lua        (depuis la racine du dépôt)
--
-- Sans argument, l'essai tourne deux fois : client français (frFR), puis anglais (enUS). En
-- anglais il vérifie en plus que chaque texte affiché a sa traduction.

-- Dossier de l'addon : le parent du dossier de ce script.
local ROOT = (arg and arg[0] or ""):match("^(.-)outils/[^/]*$") or ""

local LOCALE = arg and arg[1]
if not LOCALE then
  local lua, script = arg[-1] or "lua", arg[0]
  local ok = true
  for _, locale in ipairs({ "frFR", "enUS" }) do
    io.write("\n=== Client ", locale, " ===\n")
    io.flush()
    local r = os.execute(string.format("%q %q %s", lua, script, locale))
    if r ~= true and r ~= 0 then ok = false end
  end
  io.write(ok and "\nTout passe, dans les deux langues.\n" or "\nDes essais échouent.\n")
  os.exit(ok and 0 or 1)
end
local now = 1794440000
local clock = 100

---------------------------------------------------------------------------
-- Faux objets d'interface : toute méthode inconnue ne fait rien.
---------------------------------------------------------------------------
local Widget = {}
Widget.__index = function(_, key)
  local m = rawget(Widget, key)
  if m then return m end
  return function() end
end
local function widget(kind)
  return setmetatable({ kind = kind, w = 0, h = 0, shown = true, scripts = {}, level = 1 }, Widget)
end
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:SetWidth(w) self.w = w end
function Widget:SetHeight(h) self.h = h end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:Show() self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Widget:Hide() self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Widget:SetShown(on) if on then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:CreateTexture() return widget("Texture") end
function Widget:CreateFontString() return widget("FontString") end
function Widget:CreateLine() return widget("Line") end
function Widget:GetFrameLevel() return self.level end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetLeft() return 0 end
function Widget:IsMouseOver() return false end
local shownTexts = {} -- tout ce qui s'affiche : textes, infobulles, messages du chat
function Widget:SetText(t)
  self.text = t
  if type(t) == "string" then shownTexts[#shownTexts + 1] = t end
end
function Widget:GetText() return self.text or "" end
function Widget:GetVerticalScroll() return self.vs or 0 end
function Widget:SetVerticalScroll(v) self.vs = v end
function Widget:GetHorizontalScroll() return 0 end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:RegisterEvent() end

local eventFrames = {}
function CreateFrame(kind)
  local f = widget(kind)
  eventFrames[#eventFrames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(eventFrames) do
    if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

---------------------------------------------------------------------------
-- Fausse API du jeu
---------------------------------------------------------------------------
UIParent, GameTooltip = widget("Frame"), widget("GameTooltip")
local tipLines = {}
function GameTooltip:GetItem() return "x", "|Hitem:2840|h[x]|h" end
function GameTooltip:AddDoubleLine(left, right)
  tipLines[#tipLines + 1] = left .. " = " .. right
  shownTexts[#shownTexts + 1] = left
end
function GameTooltip:AddLine(text) shownTexts[#shownTexts + 1] = text end
UISpecialFrames, SlashCmdList = {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
tinsert = table.insert
function time() return now end
function GetTime() return clock end
date = os.date
function hooksecurefunc(a, b, c)
  if type(a) == "table" then
    local old = a[b]
    a[b] = function(...) local r = old(...) c(...) return r end
  else
    local old = _G[a]
    _G[a] = function(...) local r = old(...) b(...) return r end
  end
end
function print(...)
  local line = table.concat({ ... }, " ")
  shownTexts[#shownTexts + 1] = line
  io.write("  [jeu] ", line, "\n")
end
function GetLocale() return LOCALE end

local timers = {}
C_Timer = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  NewTicker = function(_, fn)
    local t = { fn = fn }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = function() end
    C_Timer.ticker = t
    return t
  end,
}
local function runTimers()
  for _ = 1, 20 do
    local list = timers
    timers = {}
    if #list == 0 then break end
    for _, fn in ipairs(list) do fn() end
  end
end

local money = 1234567
function GetMoney() return money end
function UnitName() return "Testeur" end
function UnitClass() return "Chasseur", "HUNTER" end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 24 end
function GetRealmName() return "Test" end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i)
  if i == 1 then return "Ingénierie", nil, 120, 150, 0, 0, 202 end
  return "Minage", nil, 105, 150, 0, 0, 186
end
function IsPlayerSpell() return false end
-- Marchand : une seule ligne, de la pierre brute à 20 l'unité.
function GetMerchantNumItems() return 1 end
function GetMerchantItemID() return 2835 end
C_MerchantFrame = { GetItemInfo = function() return { price = 20, stackCount = 1, numAvailable = -1 } end }
function BuyMerchantItem() end

local ITEMS = {
  [2840] = { "Barre de cuivre", 1, 10 }, [2770] = { "Minerai de cuivre", 1, 5 },
  [2589] = { "Etoffe de lin", 1, 13 }, [4357] = { "Poudre d'explosion grossière", 1, 4 },
  [2835] = { "Pierre brute", 1, 2 }, [4359] = { "Poignée de boulons en cuivre", 1, 12 },
}
C_Item = {
  GetItemInfo = function(id)
    local it = ITEMS[id]
    if not it then return "Objet test " .. id, "|Hitem:" .. id .. "|h[x]|h", 1, 1, 1, "", "", 20, "", 134400, 7 end
    return it[1], "|Hitem:" .. id .. "|h[" .. it[1] .. "]|h", it[2], 1, 1, "", "", 20, "", 134400, it[3]
  end,
  GetItemIconByID = function() return 134400 end,
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] or ("Objet test " .. id) end,
  RequestLoadItemDataByID = function() end,
  GetItemID = function(loc) return loc end,
}

local BAGS = {
  [0] = { { itemID = 2840, stackCount = 20 }, { itemID = 2589, stackCount = 12, isBound = false }, { itemID = 4357, stackCount = 5 } },
  [1] = { { itemID = 2770, stackCount = 40 } },
}
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
  GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
Enum = { BagIndex = { ReagentBag = 5, Bank = -1, BankBag_1 = 6 }, UITextureSliceMode = { Stretched = 0 } }

-- HV : trois pages de résultats.
local PAGES = {
  { { itemKey = { itemID = 2840 }, minPrice = 95, totalQuantity = 400 }, { itemKey = { itemID = 2770 }, minPrice = 40, totalQuantity = 900 } },
  { { itemKey = { itemID = 4357 }, minPrice = 60, totalQuantity = 80 }, { itemKey = { itemID = 4359 }, minPrice = 380, totalQuantity = 30 } },
  { { itemKey = { itemID = 2835 }, minPrice = 12, totalQuantity = 500 }, { itemKey = { itemID = 2840 }, minPrice = 90, totalQuantity = 10 } },
}
local page, sentQuery = 0, false
AuctionHouseFrame = widget("Frame")
C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return true end,
  SendBrowseQuery = function() sentQuery = true page = 1 end,
  RequestMoreBrowseResults = function() page = page + 1 end,
  HasFullBrowseResults = function() return page >= #PAGES end,
  GetBrowseResults = function()
    local all = {}
    for i = 1, page do for _, r in ipairs(PAGES[i]) do all[#all + 1] = r end end
    return all
  end,
  GetNumOwnedAuctions = function() return 1 end,
  GetOwnedAuctionInfo = function() return { itemKey = { itemID = 4359 }, quantity = 10, buyoutAmount = 400, status = 0 } end,
  QueryOwnedAuctions = function() end,
  PostCommodity = function() end,
  PostItem = function() end,
}

-- Courrier : une facture d'achat (10 barres de cuivre pour 800) et une facture de vente.
local MAILS = {
  { money = 0, invoice = { "buyer", "Barre de cuivre", "Vendeur", 800, 800, 0, 0 }, item = { 2840, 10 }, days = 29.9 },
  { money = 1900, invoice = { "seller", "Poignée de boulons en cuivre", "Acheteur", 2000, 2000, 100, 100 }, days = 29.8 },
}
function GetInboxNumItems() return #MAILS end
function GetInboxHeaderInfo(i)
  local m = MAILS[i]
  return nil, nil, "HV", "Sujet", m.money, 0, m.days, m.item and 1 or nil
end
function GetInboxInvoiceInfo(i) return table.unpack(MAILS[i].invoice) end
function GetInboxItemLink(i, j)
  local m = MAILS[i]
  if j == 1 and m.item then return "|Hitem:" .. m.item[1] .. "|h[x]|h" end
end
function GetInboxItem(i)
  local m = MAILS[i]
  return "x", m.item[1], 134400, m.item[2], 1, true
end

---------------------------------------------------------------------------
-- Chargement de l'addon dans l'ordre du .toc
---------------------------------------------------------------------------
local ns = {}
local failures = 0
local function check(label, ok, detail)
  if ok then
    io.write("ok    ", label, "\n")
  else
    failures = failures + 1
    io.write("ECHEC ", label, detail and (" : " .. tostring(detail)) or "", "\n")
  end
end

for line in io.lines(ROOT .. "Negoce.toc") do
  local file = line:match("^([%w_\\]+%.lua)%s*$")
  if file and not file:find("^Libs") then
    local chunk, err = loadfile(ROOT .. file:gsub("\\", "/"))
    if not chunk then error(err) end
    chunk("Negoce", ns)
  end
end

-- Clés demandées en anglais sans traduction.
local missing = {}
do
  local mt = getmetatable(ns.L)
  local index = mt.__index
  mt.__index = function(t, key)
    if ns.lang == "en" and key ~= "" and ns.LOCALES.en[key] == nil then missing[key] = true end
    return index(t, key)
  end
end

fire("ADDON_LOADED", "Negoce")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
runTimers()

local count = 0
for _ in pairs(ns.recipes) do count = count + 1 end
check("table de recettes chargée (" .. count .. ")", count > 1500)
check("solde de départ noté", #ns.db.moneyLog == 1 and ns.db.moneyLog[1].c == "depart")
check("sacs lus", ns.db.bags and ns.db.bags.items[2840] and ns.db.bags.items[2840].c == 20)

-- Scan de l'HV
fire("AUCTION_HOUSE_SHOW")
ns.StartScan()
for _ = 1, 10 do
  if C_Timer.ticker and not C_Timer.ticker.cancelled then C_Timer.ticker.fn() end
  if sentQuery then
    sentQuery = false
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  elseif page > 1 and page <= #PAGES and ns.ScanState() == "scan" then
    fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", PAGES[page])
  end
  runTimers()
end
check("scan terminé", ns.ScanState() == "repos" and ns.Market().scan ~= nil)
check("prix le plus bas gardé (barre de cuivre = 90)", ns.MarketPrice(2840) == 90, ns.MarketPrice(2840))
local _, _, qty = ns.MarketPrice(2840)
check("quantités additionnées (410)", qty == 410, qty)
fire("OWNED_AUCTIONS_UPDATED")

-- Courrier et factures
fire("MAIL_INBOX_UPDATE")
fire("MAIL_INBOX_UPDATE") -- une seconde lecture ne doit rien dupliquer
check("un achat enregistré une seule fois", #ns.db.purchases == 1, #ns.db.purchases)
local p = ns.db.purchases[1]
check("achat : objet et quantité lus sur la pièce jointe", p and p.id == 2840 and p.q == 10 and p.p == 800)
check("une vente enregistrée", #ns.db.sales == 1 and ns.db.sales[1].net == 2000)

-- Positions
local positions = {}
for _, row in ipairs(ns.Positions()) do positions[row.id] = row end
local bar = positions[2840]
check("position barre de cuivre : 30 détenues (20 sacs + 10 courrier)", bar and bar.q == 30, bar and bar.q)
-- 20 barres déjà en stock (coût 0) + 10 achetées 800 : coût moyen 800 / 30.
check("coût de revient moyen = 800 / 30", bar and math.abs(bar.unitCost - 800 / 30) < 0.01 and math.abs(bar.cost - 800) < 0.01, bar and bar.unitCost)
check("marge latente = 30 × 90 × 0,95 − 800 = 1765", bar and math.abs(bar.gain - 1765) < 0.01, bar and bar.gain)
check("achat en attente dans le courrier", ns.db.track.pend[2840] and ns.db.track.pend[2840].q == 10)
check("enchère en cours comptée dans le stock", positions[4359] and positions[4359].ah == 10)

-- Flux d'or : une vente au marchand
AuctionHouseFrame.shown = false
fire("AUCTION_HOUSE_CLOSED")
clock = clock + 10
fire("MERCHANT_SHOW")
clock = clock + 1
money = money + 500
fire("PLAYER_MONEY")
local last = ns.db.moneyLog[#ns.db.moneyLog]
check("gain classé en vente au marchand", last.d == 500 and last.c == "marchand_vente", last.c)
fire("MERCHANT_CLOSED")
runTimers()
check("point de patrimoine enregistré", #ns.db.wealth >= 1 and ns.db.wealth[#ns.db.wealth].g == money)

---------------------------------------------------------------------------
-- Prix de revient : entrées, fabrication, mise en vente, vente.
---------------------------------------------------------------------------
local track = ns.db.track
local function near(a, b) return a and b and math.abs(a - b) < 0.01 end
local function bagsChanged()
  fire("BAG_UPDATE_DELAYED")
  runTimers()
end

-- Retrait de l'achat du courrier : les 10 barres entrent à 800.
clock = clock + 30
fire("MAIL_SHOW")
BAGS[0][1].stackCount = 30
MAILS[1].item = nil
fire("MAIL_INBOX_UPDATE")
bagsChanged()
fire("MAIL_CLOSED")
check("achat HV retiré du courrier : 30 barres pour 800", track.pool[2840] and track.pool[2840].q == 30 and near(track.pool[2840].c, 800), track.pool[2840] and track.pool[2840].c)
check("plus rien en attente", track.pend[2840] == nil)
check("pas d'achat en double après relecture du courrier", #ns.db.purchases == 1, #ns.db.purchases)

-- Butin : 30 minerais ramassés, à 0.
clock = clock + 30
fire("LOOT_OPENED")
BAGS[1][1].stackCount = 70
bagsChanged()
fire("LOOT_CLOSED")
check("butin à 0", track.pool[2770].q == 70 and track.pool[2770].c == 0)
check("mouvement classé en butin", track.log[#track.log].s == "butin", track.log[#track.log].s)

-- Achat au marchand : 5 pierres brutes à 20.
clock = clock + 30
fire("MERCHANT_SHOW")
BuyMerchantItem(1, 5)
BAGS[1][2] = { itemID = 2835, stackCount = 5 }
bagsChanged()
fire("MERCHANT_CLOSED")
check("achat marchand au prix payé (5 × 20)", track.pool[2835] and near(track.pool[2835].c, 100), track.pool[2835] and track.pool[2835].c)

-- Fabrication : des boulons à partir de barres (coût moyen 800 / 30 la barre).
clock = clock + 30
local recipe = ns.recipes[3922]
local barsUsed = recipe.reag[1].n * 2
BAGS[0][1].stackCount = 30 - barsUsed
BAGS[1][3] = { itemID = 4359, stackCount = recipe.qty * 2 }
bagsChanged()
check("fabrication : les barres sortent du stock", track.pool[2840].q == 30 - barsUsed and near(track.pool[2840].c, 800 * (30 - barsUsed) / 30), track.pool[2840].c)
check("fabrication : le produit reçoit le coût des composants", track.pool[4359] and track.pool[4359].q == recipe.qty * 2 and near(track.pool[4359].c, 800 * barsUsed / 30), track.pool[4359] and track.pool[4359].c)

-- Mise en vente de 10 barres à 150, puis vente.
clock = clock + 30
AuctionHouseFrame.shown = true
fire("AUCTION_HOUSE_SHOW")
local barCost = track.pool[2840].c / track.pool[2840].q
C_AuctionHouse.PostCommodity(2840, 2, 10, 150)
BAGS[0][1].stackCount = BAGS[0][1].stackCount - 10
bagsChanged()
check("mise en vente : 10 barres passent en réserve avec leur coût", track.tr[2840] and track.tr[2840].q == 10 and near(track.tr[2840].c, barCost * 10), track.tr[2840] and track.tr[2840].c)
check("coût moyen inchangé par la mise en vente", near(ns.UnitCost(2840), barCost), ns.UnitCost(2840))
AuctionHouseFrame.shown = false
fire("AUCTION_HOUSE_CLOSED")
clock = clock + 30
MAILS[3] = { money = 1425, invoice = { "seller", "Barre de cuivre", "Acheteur", 1500, 1500, 0, 75 }, days = 29.7 }
fire("MAIL_SHOW")
fire("MAIL_INBOX_UPDATE")
fire("MAIL_CLOSED")
local sale = ns.db.sales[#ns.db.sales]
check("vente reconnue (10 barres)", sale.id == 2840 and sale.q == 10, sale.q)
check("coût noté sur la vente", sale.cr == math.floor(barCost * 10 + 0.5), sale.cr)
check("réserve « en vente » vidée", track.tr[2840] == nil)

-- Invendus qui reviennent par courrier : ils retrouvent leur coût.
clock = clock + 30
C_AuctionHouse.PostCommodity(2840, 2, 4, 150)
fire("AUCTION_HOUSE_SHOW")
BAGS[0][1].stackCount = BAGS[0][1].stackCount - 4
bagsChanged()
fire("AUCTION_HOUSE_CLOSED")
clock = clock + 30
fire("MAIL_SHOW")
BAGS[0][1].stackCount = BAGS[0][1].stackCount + 4
bagsChanged()
fire("MAIL_CLOSED")
check("retour de l'HV : coût moyen retrouvé", track.tr[2840] == nil and near(ns.UnitCost(2840), barCost), ns.UnitCost(2840))

-- Changement fait sans l'addon (banque) : le surplus entre à 0.
clock = clock + 30
BAGS[-1] = { { itemID = 2589, stackCount = 8 } }
fire("BANKFRAME_OPENED")
runTimers()
fire("BANKFRAME_CLOSED")
check("contenu de la banque découvert : entrée à 0", track.pool[2589].q == 20 and track.pool[2589].c == 0, track.pool[2589].q)

-- Infobulle
GameTooltip.scripts.OnTooltipSetItem(GameTooltip)
check("infobulle : coût de revient, cours et marge", #tipLines == 3, table.concat(tipLines, " | "))
MAILS[3] = nil
clock = clock + 30

-- Coûts et rentabilité : poignée de boulons en cuivre (3922) = 1 barre de cuivre
ns.ResetCosts()
local bolts = ns.recipes[3922]
check("recette des boulons présente", bolts ~= nil and bolts.item == 4359)
if bolts then
  local bilan = ns.RecipeProfit(bolts)
  -- La barre coûte 90 à l'HV mais 40 à fondre soi-même (1 minerai) : c'est ce coût qui compte.
  local cost, src = ns.BestCost(2840)
  check("barre de cuivre : moins chère à fabriquer (40) qu'à acheter (90)", cost == 40 and src == "fab", cost)
  check("coût des boulons = coût d'une barre fabriquée", bilan.complete and bilan.cost == 40 * bolts.reag[1].n, bilan.cost)
  check("bénéfice calculé avec la taxe de l'HV", bilan.profit and math.abs(bilan.profit - (380 * bolts.qty * 0.95 - bilan.cost)) < 0.01, bilan.profit)
end

-- Fenêtre et onglets
ns.db.known[3922] = true
ns.db.known[2657] = true -- fonte du cuivre
for i = 1, 5 do
  ns.db.wealth[#ns.db.wealth + 1] = { t = now - (6 - i) * 3600, g = 1000000 + i * 5000, s = 20000, m = 0 }
end
table.sort(ns.db.wealth, function(a, b) return a.t < b.t end)
local ok, err = pcall(ns.Toggle)
check("ouverture de la fenêtre (onglet Finances)", ok, err)
for _, view in ipairs({ "flux", "journal", "portefeuille" }) do
  ns.db.ui.finView = view
  ok, err = pcall(function() ns.tabs.finances.frame:Refresh() end)
  check("Finances, vue " .. view, ok, err)
end
ns.db.ui.tab = "production"
ok, err = pcall(function()
  ns.Toggle()
  ns.Toggle()
end)
check("onglet Production (mes recettes)", ok and ns.tabs.production.frame ~= nil, err)
for _, setup in ipairs({
  { "toutes les recettes d'ingénierie", function(ui) ui.prodKnown = false ui.prodSkill = 202 end },
  { "recettes rentables seulement", function(ui) ui.prodProfit = true end },
  { "tous les métiers d'un coup (forge)", function(ui) ui.prodProfit = false ui.prodSkill = 164 end },
  { "recherche", function(ui) ui.prodSearch = "objet" end },
}) do
  setup[2](ns.db.ui)
  ok, err = pcall(function() ns.tabs.production.frame:Refresh() end)
  check("Production, " .. setup[1], ok, err)
end
-- Détail d'un produit fini et d'une matière première : clic sur leur nœud du graphe.
ns.db.ui.prodSkill, ns.db.ui.prodSearch, ns.db.ui.prodKnown = 202, "", false
ns.tabs.production.frame:Refresh()
local clicked = { product = false, raw = false }
for _, w in ipairs(eventFrames) do
  local n = rawget(w, "node")
  if n and w.scripts.OnClick and w.shown then
    local kind = n.r and #n.uses == 0 and "product" or (not n.r and "raw") or nil
    if kind and not clicked[kind] then
      ok, err = pcall(w.scripts.OnClick, w)
      check("Production, détail d'un " .. (kind == "product" and "produit fini" or "matière première"), ok, err)
      clicked[kind] = true
    end
  end
end
check("Production, deux nœuds cliqués", clicked.product and clicked.raw)

-- Bouton de l'HV, commandes
local scanButton
for _, w in ipairs(eventFrames) do local t = rawget(w, "text") if w.scripts.OnClick and type(t) == "string" and t:find("Négoce") then scanButton = w end end
if scanButton and scanButton.scripts.OnEnter then scanButton.scripts.OnEnter(scanButton) end
for _, cmd in ipairs({ "suivi", "aide", "erreurs", "taille 3", "langue xx" }) do
  ok, err = pcall(SlashCmdList.NEGOCE, cmd)
  check("commande /negoce " .. cmd, ok, err)
end
ok, err = pcall(SlashCmdList.NEGOCE, "tooltip")
check("commande anglaise /negoce tooltip", ok and ns.db.ui.noTooltip == true, err)
SlashCmdList.NEGOCE("infobulle")

-- Choix de la langue : enregistré pour le compte, appliqué tout de suite.
local before = ns.lang
SlashCmdList.NEGOCE(before == "fr" and "language en" or "langue fr")
check("choix de la langue enregistré", ns.px.lang ~= nil and ns.lang == ns.px.lang and ns.lang ~= before, ns.px.lang)
SlashCmdList.NEGOCE("langue auto")
check("retour à la langue du client", ns.px.lang == nil and ns.lang == before, ns.lang)

if LOCALE == "enUS" then
  check("langue choisie : anglais", ns.lang == "en", ns.lang)
  -- Toutes les clés écrites dans le code (L["…"] et ns.Lf("…")) ont leur traduction.
  local unescape = function(text) return load("return \"" .. text .. "\"")() end
  for _, file in ipairs({ "Core.lua", "Prix.lua", "Stock.lua", "Flux.lua", "Positions.lua", "Revient.lua",
    "Infobulle.lua", "Recettes.lua", "UI/Theme.lua", "UI/Chart.lua", "UI/Main.lua", "UI/Finances.lua", "UI/Production.lua" }) do
    local src = io.open(ROOT .. file):read("a")
    for key in src:gmatch('L%["(.-[^\\])"%]') do
      if ns.LOCALES.en[unescape(key)] == nil then missing[unescape(key)] = true end
    end
    for key in src:gmatch('Lf%("(.-[^\\])"') do
      if ns.LOCALES.en[unescape(key)] == nil then missing[unescape(key)] = true end
    end
  end
  -- Les textes rangés dans des tables (catégories de l'or, mouvements d'objets, métiers).
  for _, list in ipairs({ ns.CATEGORIES, ns.SOURCES, ns.DATA.metiers }) do
    for _, text in pairs(list) do
      if ns.LOCALES.en[text] == nil then missing[text] = true end
    end
  end
  local list = {}
  for key in pairs(missing) do list[#list + 1] = key end
  table.sort(list)
  check("aucun texte sans traduction anglaise", #list == 0, table.concat(list, " | "))

  -- Rien de français à l'écran, hormis les noms d'objets du jeu (en français dans cet essai).
  local names = { "Négoce" }
  for _, it in pairs(ITEMS) do names[#names + 1] = it[1] end
  local french = {}
  for _, text in ipairs(shownTexts) do
    local t = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _, name in ipairs(names) do t = t:gsub(name:gsub("%p", "%%%0"), "") end
    t = t:gsub("Objet test %d+", "")
    local accent = false
    for _, c in ipairs({ "é", "è", "ê", "à", "â", "ù", "û", "ç", "ô", "î", "ï", "É", "È", "À" }) do
      if t:find(c, 1, true) then accent = true end
    end
    if accent or t:find("«") or t:find("%f[%a]de%f[%A]") or t:find("%f[%a]sur%f[%A]")
      or t:find("%f[%a]pour%f[%A]") or t:find("%f[%a]aucun") or t:find("%f[%a]il y a%f[%A]") then
      french[#french + 1] = text
    end
  end
  check("aucun texte français affiché en anglais", #french == 0, table.concat(french, " | "))
end

check("aucune erreur interne enregistrée", #ns.db.errors == 0, ns.db.errors[1] and (ns.db.errors[1].w .. " : " .. ns.db.errors[1].m))

io.write(failures == 0 and "\nTout passe.\n" or ("\n" .. failures .. " échec(s).\n"))
os.exit(failures == 0 and 0 or 1)
