-- Négoce : stock. Ce que tu possèdes dans les sacs, à la banque, au courrier et en vente à l'HV,
-- et la courbe de patrimoine (or + valeur du stock).
local ADDON, ns = ...

local NUM_BAGS = NUM_BAG_SLOTS or 4
local MAX_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16

---------------------------------------------------------------------------
-- Sacs et banque
---------------------------------------------------------------------------

local function numSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    return ok and n or 0
  end
  return 0
end

local function slotInfo(bag, slot)
  local i = C_Container.GetContainerItemInfo(bag, slot)
  if not i then return nil end
  return i.itemID or ns.ItemIDFromLink(i.hyperlink), i.stackCount or 1, i.isBound
end

-- items[itemID] = { c = quantité, b = quantité liée }
local function add(items, id, count, bound)
  if not id then return end
  local e = items[id]
  if not e then
    e = { c = 0 }
    items[id] = e
  end
  e.c = e.c + (count or 1)
  if bound then e.b = (e.b or 0) + (count or 1) end
end

local function scan(bags)
  local items = {}
  for _, bag in ipairs(bags) do
    for slot = 1, numSlots(bag) do
      local id, count, bound = slotInfo(bag, slot)
      if id then add(items, id, count, bound) end
    end
  end
  return { updated = time(), items = items }
end

local function bagList()
  local list = {}
  for b = 0, NUM_BAGS do list[#list + 1] = b end
  local index = Enum and Enum.BagIndex
  if index and index.ReagentBag and index.ReagentBag > NUM_BAGS then
    list[#list + 1] = index.ReagentBag
  end
  return list
end

-- La banque change de forme selon les clients (banque et ses sacs, ou onglets) : on prend tous
-- les conteneurs de banque que ce client déclare, sans jamais reprendre un sac du personnage.
local function bankList()
  local list, seen = {}, {}
  for _, b in ipairs(bagList()) do seen[b] = true end
  local function push(b)
    if b ~= nil and not seen[b] then
      seen[b] = true
      list[#list + 1] = b
    end
  end
  local index = Enum and Enum.BagIndex or {}
  push(index.Bank or BANK_CONTAINER)
  push(index.Reagentbank)
  for i = 1, 7 do push(index["BankBag_" .. i]) end
  for i = 1, 8 do push(index["CharacterBankTab_" .. i]) end
  return list
end

function ns.ScanBags()
  if not ns.db then return end
  ns.db.bags = scan(bagList())
end

function ns.ScanBank()
  if not ns.db or not ns.bankOpen then return end
  ns.db.bank = scan(bankList())
end

-- Les sacs bougent souvent : on regroupe les scans (un toutes les 2 secondes au plus).
local pending = false
local function scheduleScan()
  if pending then return end
  pending = true
  C_Timer.After(2, function()
    pending = false
    ns.Try("sacs", ns.ScanBags)
    if ns.bankOpen then ns.Try("banque", ns.ScanBank) end
    if ns.TrackItems then ns.Try("suivi", ns.TrackItems) end
    ns.Try("patrimoine", ns.Sample)
    ns.Changed()
  end)
end

ns.On("PLAYER_ENTERING_WORLD", scheduleScan)
ns.On("BAG_UPDATE_DELAYED", scheduleScan)
ns.On("BANKFRAME_OPENED", function()
  ns.bankOpen = true
  ns.ScanBank()
  -- Ce que la banque contient de plus ou de moins que la dernière fois a changé sans nous.
  if ns.TrackItems then ns.Try("suivi", ns.TrackItems, true) end
  ns.Changed()
end)
ns.On("BANKFRAME_CLOSED", function() ns.bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() if ns.bankOpen then scheduleScan() end end)

---------------------------------------------------------------------------
-- Courrier : objets et or en attente dans la boîte.
---------------------------------------------------------------------------

function ns.InboxItem(i, j)
  local link = GetInboxItemLink and GetInboxItemLink(i, j)
  local id = ns.ItemIDFromLink(link)
  if not id then return nil end
  -- Selon le client : (nom, itemID, icône, quantité, ...) ou (nom, icône, quantité, ...)
  local n = select("#", GetInboxItem(i, j))
  local count
  if n >= 6 then count = select(4, GetInboxItem(i, j)) else count = select(3, GetInboxItem(i, j)) end
  return id, tonumber(count) or 1
end

function ns.ScanMail()
  local db = ns.db
  if not db or not GetInboxNumItems then return end
  local mail = { updated = time(), money = 0, items = {} }
  for i = 1, GetInboxNumItems() or 0 do
    local _, _, _, _, money, cod, _, hasItem = GetInboxHeaderInfo(i)
    mail.money = mail.money + (money or 0)
    -- Un envoi contre remboursement n'est pas à toi tant que tu ne l'as pas payé.
    if hasItem and (cod or 0) == 0 then
      for j = 1, MAX_ATTACH do
        local id, count = ns.InboxItem(i, j)
        if id then add(mail.items, id, count, false) end
      end
    end
  end
  db.mail = mail
  if ns.ReadInvoices then ns.Try("factures", ns.ReadInvoices) end
  ns.Changed()
end

ns.On("MAIL_INBOX_UPDATE", function() ns.ScanMail() end)

---------------------------------------------------------------------------
-- Enchères en cours
---------------------------------------------------------------------------

local AH = C_AuctionHouse

local function scanOwned()
  local list = {}
  for i = 1, AH.GetNumOwnedAuctions() or 0 do
    local a = AH.GetOwnedAuctionInfo(i)
    if a then
      list[#list + 1] = {
        id = (a.itemKey and a.itemKey.itemID) or ns.ItemIDFromLink(a.itemLink),
        q = a.quantity or 1,
        bo = a.buyoutAmount, -- prix à l'unité pour les objets empilables
        st = a.status,       -- 0 = en vente, 1 = vendu (or en route)
      }
    end
  end
  ns.db.auctions = { updated = time(), list = list }
  ns.Changed()
end

local function queryOwned()
  if AH and AH.QueryOwnedAuctions then pcall(AH.QueryOwnedAuctions, {}) end
end
ns.On("AUCTION_HOUSE_SHOW", queryOwned)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", queryOwned)
ns.On("OWNED_AUCTIONS_UPDATED", function()
  if ns.db and AH and AH.GetNumOwnedAuctions then scanOwned() end
end)

---------------------------------------------------------------------------
-- Avoirs : tout ce que tu possèdes, par objet.
--   holdings[id] = { q = total, bags, bank, mail, ah, free = quantité non liée }
---------------------------------------------------------------------------

function ns.Holdings()
  local db = ns.db
  local out = {}
  local function entry(id)
    local h = out[id]
    if not h then
      h = { id = id, q = 0, bags = 0, bank = 0, mail = 0, ah = 0, free = 0 }
      out[id] = h
    end
    return h
  end
  local function merge(src, field)
    if not src or not src.items then return end
    for id, e in pairs(src.items) do
      local h = entry(id)
      h[field] = h[field] + e.c
      h.q = h.q + e.c
      h.free = h.free + e.c - (e.b or 0)
    end
  end
  merge(db.bags, "bags")
  merge(db.bank, "bank")
  merge(db.mail, "mail")
  if db.auctions then
    for _, a in ipairs(db.auctions.list) do
      if a.id and a.st ~= 1 then
        local h = entry(a.id)
        h.ah = h.ah + a.q
        h.q = h.q + a.q
        h.free = h.free + a.q
      end
    end
  end
  return out
end

-- Valeur d'une ligne d'avoirs : la part libre au cours de l'HV, la part liée au prix marchand.
function ns.HoldingValue(h)
  local unit = ns.Value(h.id, false)
  local total = unit * h.free
  if h.q > h.free then
    total = total + ns.Value(h.id, true) * (h.q - h.free)
  end
  return total, unit
end

function ns.StockValue()
  local total = 0
  for _, h in pairs(ns.Holdings()) do
    total = total + ns.HoldingValue(h)
  end
  return total
end

---------------------------------------------------------------------------
-- Courbe de patrimoine : un point { t, g = or, s = stock, m = or au courrier } au plus toutes les
-- 5 minutes ; entre deux, le dernier point est mis à jour.
---------------------------------------------------------------------------

local SAMPLE_EVERY = 300

function ns.Sample(force)
  local db = ns.db
  if not db then return end
  local gold = GetMoney()
  -- À la connexion le jeu répond parfois 0 avant de connaître la vraie somme.
  if gold == 0 and (db.char.money or 0) > 0 and not ns.moneyReady then return end
  local point = {
    t = time(),
    g = gold,
    s = math.floor(ns.StockValue() + 0.5),
    m = db.mail and db.mail.money or 0,
  }
  local list = db.wealth
  local last = list[#list]
  local previous = list[#list - 1]
  if last and previous and not force and (last.t - previous.t) < SAMPLE_EVERY then
    list[#list] = point
  else
    ns.Append(list, point, ns.MAX_WEALTH)
  end
  db.char.money = gold
end

ns.On("PLAYER_LOGOUT", function()
  if not ns.db then return end
  pcall(ns.ScanBags)
  pcall(ns.Sample, true)
end)
