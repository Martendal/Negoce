-- Négoce : prix. Scan de l'hôtel des ventes, prix des marchands, estimation d'un objet.
--
-- Le scan envoie une recherche vide puis demande les pages suivantes jusqu'au bout : le jeu
-- renvoie pour chaque objet son prix le plus bas et la quantité en vente. Les recherches que tu
-- fais toi-même à l'HV mettent aussi les prix à jour, sans rien faire de plus.
local ADDON, ns = ...
local L = ns.L

local AH = C_AuctionHouse

---------------------------------------------------------------------------
-- Marché : un hôtel des ventes par jeu de règles et par faction.
---------------------------------------------------------------------------

local function ruleset()
  local rules, enum = C_GameRules, Enum and Enum.GameRule
  if rules and rules.IsGameRuleActive and enum then
    local function active(name)
      if enum[name] == nil then return false end
      local ok, on = pcall(rules.IsGameRuleActive, enum[name])
      return ok and on
    end
    if active("PvPRuleset") then return "PvP" end
    if active("RPRuleset") then return "RP" end
    if active("HardcoreRuleset") then return "HC" end
    return "PvE"
  end
  return (GetRealmName and GetRealmName()) or "?"
end

function ns.MarketKey()
  if not ns.marketKey then
    ns.marketKey = ruleset() .. "-" .. (UnitFactionGroup("player") or "?")
  end
  return ns.marketKey
end

function ns.Market()
  local key = ns.MarketKey()
  local m = ns.px.markets[key]
  if not m then
    m = { items = {} }
    ns.px.markets[key] = m
  end
  return m
end

local function today() return math.floor(time() / 86400) end

---------------------------------------------------------------------------
-- Lecture des prix
---------------------------------------------------------------------------

-- Prix le plus bas vu à l'HV pour un objet : prix, date du relevé, quantité en vente.
function ns.MarketPrice(id)
  local e = ns.Market().items[id]
  if e then return e.p, e.t, e.q end
end

-- Prix d'achat chez un marchand (stock illimité), à l'unité.
function ns.VendorPrice(id)
  return ns.px.vendors[id] or (ns.DATA and ns.DATA.marchands[id])
end

-- Meilleur prix d'achat : prix, "hv" ou "marchand".
function ns.BuyPrice(id)
  local market, vendor = ns.MarketPrice(id), ns.VendorPrice(id)
  if market and vendor then
    if vendor <= market then return vendor, "marchand" end
    return market, "hv"
  elseif vendor then
    return vendor, "marchand"
  elseif market then
    return market, "hv"
  end
end

-- Valeur d'un objet que tu possèdes : cours de l'HV, sinon ce qu'en donne le marchand.
-- Un objet lié ne se revend qu'au marchand.
function ns.Value(id, bound)
  local sell = ns.Item(id).sell or 0
  if bound then return sell, "marchand" end
  local market = ns.MarketPrice(id)
  if market and market > 0 then return market, "hv" end
  return sell, "marchand"
end

-- Historique d'un objet : liste triée de { jour, prix }.
function ns.PriceHistory(id)
  local e = ns.Market().items[id]
  local out = {}
  if e and e.h then
    for day, price in pairs(e.h) do out[#out + 1] = { day = day, p = price } end
    table.sort(out, function(a, b) return a.day < b.day end)
  end
  return out
end

---------------------------------------------------------------------------
-- Écriture des prix
---------------------------------------------------------------------------

local function store(id, price, qty, now, day)
  if not id or not price or price <= 0 then return end
  local items = ns.Market().items
  local e = items[id]
  if not e then
    e = {}
    items[id] = e
  end
  e.p, e.q, e.t = price, qty, now
  e.h = e.h or {}
  local old = e.h[day]
  if not old or price < old then e.h[day] = price end
end

-- Relevé passif : une ligne vue pendant une de tes recherches. Un même objet peut apparaître
-- sous plusieurs variantes dans la même page : on garde alors la moins chère.
local passive = {}
local function storePassive(id, price, qty)
  if not id or not price or price <= 0 then return end
  local now = time()
  local seen = passive[id]
  if seen and (now - seen.t) < 30 and seen.p <= price then return end
  passive[id] = { t = now, p = price }
  store(id, price, qty, now, today())
end

local function prune()
  local limit = today() - ns.HISTORY_DAYS
  for _, market in pairs(ns.px.markets) do
    for _, e in pairs(market.items) do
      if e.h then
        for day in pairs(e.h) do
          if day < limit then e.h[day] = nil end
        end
      end
    end
  end
end
ns.AtLogin(prune)

---------------------------------------------------------------------------
-- Scan complet
---------------------------------------------------------------------------

local scan = nil -- { min = {}, qty = {}, count, started, lastEvent, wantMore }
ns.scanListeners = {}

local function notifyScan()
  for i = 1, #ns.scanListeners do pcall(ns.scanListeners[i]) end
end

function ns.ScanState()
  if scan then return "scan", scan.count end
  return "repos", 0
end

local function ready()
  if AH and AH.IsThrottledMessageSystemReady then
    local ok, r = pcall(AH.IsThrottledMessageSystemReady)
    if ok then return r end
  end
  return true
end

local function addResults(results)
  if not results then return end
  for i = 1, #results do
    local r = results[i]
    local id = r.itemKey and r.itemKey.itemID
    local price, qty = r.minPrice, r.totalQuantity or 0
    if id and price and price > 0 and qty > 0 then
      if scan then
        local old = scan.min[id]
        if not old then
          scan.count = scan.count + 1
          scan.min[id] = price
          scan.qty[id] = qty
        else
          if price < old then scan.min[id] = price end
          scan.qty[id] = scan.qty[id] + qty
        end
      else
        storePassive(id, price, qty)
      end
    end
  end
end

local function finishScan(complete)
  local s = scan
  scan = nil
  if s.ticker then s.ticker:Cancel() end
  if not complete then
    ns.Print(L["scan interrompu : aucun prix n'a été modifié."])
    notifyScan()
    return
  end
  -- Écriture par tranches pour ne pas figer le jeu.
  local ids = {}
  for id in pairs(s.min) do ids[#ids + 1] = id end
  local now, day, i = time(), today(), 0
  local function chunk()
    local last = math.min(#ids, i + 400)
    while i < last do
      i = i + 1
      local id = ids[i]
      store(id, s.min[id], s.qty[id], now, day)
    end
    if i < #ids then
      C_Timer.After(0, chunk)
    else
      local market = ns.Market()
      market.scan, market.count = now, #ids
      ns.Print(ns.Lf("scan terminé : %d objets relevés.", #ids))
      if ns.Sample then ns.Try("patrimoine", ns.Sample, true) end
      notifyScan()
      ns.Changed()
    end
  end
  chunk()
end

local function step()
  if not scan then return end
  local full = true
  if AH.HasFullBrowseResults then
    local ok, r = pcall(AH.HasFullBrowseResults)
    if ok then full = r end
  end
  if full then
    finishScan(true)
  else
    scan.wantMore = true
  end
end

local function tick()
  if not scan then return end
  local now = GetTime()
  if scan.wantMore and ready() then
    scan.wantMore = false
    scan.lastEvent = now
    pcall(AH.RequestMoreBrowseResults)
  elseif not scan.sent and ready() then
    scan.sent = true
    scan.lastEvent = now
    local ok, err = pcall(AH.SendBrowseQuery, { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    if not ok then
      ns.Error("scan", err)
      finishScan(false)
      return
    end
  elseif scan.sent and (now - scan.lastEvent) > 25 then
    -- Plus de nouvelles du serveur : on redemande la suite une fois, puis on abandonne.
    if scan.retried then
      finishScan(false)
    else
      scan.retried = true
      scan.wantMore = true
    end
  end
  notifyScan()
end

function ns.StartScan()
  if scan then return end
  if not (AH and AH.SendBrowseQuery and AH.RequestMoreBrowseResults) then
    ns.Print(L["ce client n'expose pas l'hôtel des ventes moderne : scan impossible."])
    return
  end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    ns.Print(L["ouvre l'hôtel des ventes pour scanner les prix."])
    return
  end
  scan = { min = {}, qty = {}, count = 0, started = GetTime(), lastEvent = GetTime() }
  scan.ticker = C_Timer.NewTicker(0.25, tick)
  notifyScan()
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  if not (AH and AH.GetBrowseResults) then return end
  if scan and not scan.sent then return end
  if scan then
    -- Cet événement redonne la liste entière reçue jusqu'ici : on repart de zéro pour ne pas
    -- compter deux fois les quantités.
    scan.lastEvent, scan.retried = GetTime(), nil
    scan.min, scan.qty, scan.count = {}, {}, 0
  end
  addResults(AH.GetBrowseResults())
  if scan then step() else ns.Changed() end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(_, added)
  if scan and not scan.sent then return end
  if scan then scan.lastEvent, scan.retried = GetTime(), nil end
  addResults(added)
  if scan then step() else ns.Changed() end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
  if scan then finishScan(false) end
end)

-- Détail d'un objet empilable : le prix unitaire le plus bas est exact.
local function commodity(_, itemID)
  if scan or not (AH and AH.GetNumCommoditySearchResults and itemID) then return end
  local n = AH.GetNumCommoditySearchResults(itemID) or 0
  if n == 0 then return end
  local best, qty = nil, 0
  for i = 1, n do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice then
      if not best or r.unitPrice < best then best = r.unitPrice end
      qty = qty + (r.quantity or 0)
    end
  end
  if best then
    passive[itemID] = nil
    storePassive(itemID, best, qty)
    ns.Changed()
  end
end
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", commodity)

---------------------------------------------------------------------------
-- Bouton de scan dans la fenêtre de l'HV
---------------------------------------------------------------------------

local button
local function updateButton()
  if not button then return end
  local state, count = ns.ScanState()
  if state == "scan" then
    button:SetText(ns.Lf("Scan… %d objets", count))
    button:Disable()
  else
    button:SetText(L["Négoce : scanner les prix"])
    button:Enable()
  end
end
ns.scanListeners[#ns.scanListeners + 1] = updateButton

ns.On("AUCTION_HOUSE_SHOW", function()
  if button or not AuctionHouseFrame then return end
  button = CreateFrame("Button", "NegoceScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
  button:SetSize(190, 22)
  button:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, 2)
  button:SetScript("OnClick", function() ns.StartScan() end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Négoce")
    GameTooltip:AddLine(L["Relève le prix le plus bas de chaque objet en vente."], 1, 1, 1, true)
    local market = ns.Market()
    GameTooltip:AddLine(ns.Lf("Dernier scan : %s", ns.Ago(market.scan)), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  updateButton()
end)

---------------------------------------------------------------------------
-- Marchands : on retient le prix de ce qu'ils vendent en stock illimité.
---------------------------------------------------------------------------

local function merchantItem(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(index)
    if info then
      return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    end
    return nil
  end
  if GetMerchantItemInfo then
    local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(index)
    return price, stack, available, extended
  end
end

ns.MerchantItem = merchantItem

ns.On("MERCHANT_SHOW", function()
  if not (GetMerchantNumItems and GetMerchantItemID) then return end
  local changed = false
  for i = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID(i)
    local price, stack, available, extended = merchantItem(i)
    if id and price and price > 0 and available == -1 and not extended then
      local unit = math.ceil(price / math.max(1, stack or 1))
      if ns.px.vendors[id] ~= unit then
        ns.px.vendors[id] = unit
        changed = true
      end
    end
  end
  if changed then ns.Changed() end
end)
