-- Négoce : journal de l'or. Chaque variation est horodatée et classée selon son origine,
-- déduite des fenêtres ouvertes et des dernières actions (butin, marchand, HV, courrier...).
local ADDON, ns = ...

local open = {}   -- fenêtres ouvertes d'après les événements
local recent = {} -- dernière fois (GetTime) qu'un contexte a été vu

local function mark(kind) recent[kind] = GetTime() end
local function within(kind, seconds)
  local t = recent[kind]
  return t ~= nil and (GetTime() - t) <= seconds
end
ns.MarkContext = mark

ns.CATEGORIES = {
  depart = "Solde de départ",
  hors_suivi = "Hors suivi",
  butin = "Butin",
  quete = "Quêtes",
  marchand_vente = "Ventes marchand",
  marchand_achat = "Achats marchand",
  reparation = "Réparations",
  formation = "Formation",
  vol = "Vols",
  hv_vente = "Ventes HV",
  hv_achat = "Achats HV",
  hv_depot = "Dépôts HV",
  hv_autre = "HV (autre)",
  courrier = "Courrier reçu",
  courrier_envoi = "Courrier payé",
  echange = "Échanges",
  autre = "Autre",
}

---------------------------------------------------------------------------
-- Fenêtres. Source la plus fiable : la fenêtre de l'interface est-elle affichée ?
-- Les événements d'ouverture/fermeture servent de secours (un événement de fermeture
-- peut manquer : on l'a vu en jeu avec la boîte aux lettres).
---------------------------------------------------------------------------

local WINDOW_ORDER = { "auction", "mail", "merchant", "trainer", "taxi", "trade" }
local GRACE = { taxi = 5, trade = 5 }
local FRAMES = {
  auction = { "AuctionHouseFrame", "AuctionFrame" },
  mail = { "MailFrame" },
  merchant = { "MerchantFrame" },
  trainer = { "ClassTrainerFrame" },
  taxi = { "TaxiFrame", "FlightMapFrame" },
  trade = { "TradeFrame" },
}

-- true / false si l'interface sait répondre, nil si la fenêtre n'existe pas (encore).
local function frameShown(kind)
  local known = false
  for _, name in ipairs(FRAMES[kind] or {}) do
    local f = _G[name]
    if type(f) == "table" and f.IsShown then
      known = true
      if f:IsShown() then return true end
    end
  end
  if known then return false end
  return nil
end

local function isOpenNow(kind)
  local shown = frameShown(kind)
  if shown ~= nil then return shown end
  return open[kind] or false
end

local function setOpen(kind, state)
  open[kind] = state
  mark(kind) -- ouverture comme fermeture : l'or peut arriver juste après la fermeture
end

local windows = {
  MERCHANT_SHOW = { "merchant", true },        MERCHANT_CLOSED = { "merchant", false },
  MAIL_SHOW = { "mail", true },                MAIL_CLOSED = { "mail", false },
  AUCTION_HOUSE_SHOW = { "auction", true },    AUCTION_HOUSE_CLOSED = { "auction", false },
  TRAINER_SHOW = { "trainer", true },          TRAINER_CLOSED = { "trainer", false },
  TAXIMAP_OPENED = { "taxi", true },           TAXIMAP_CLOSED = { "taxi", false },
  TRADE_SHOW = { "trade", true },              TRADE_CLOSED = { "trade", false },
  LOOT_OPENED = { "loot", true },              LOOT_CLOSED = { "loot", false },
}
for event, def in pairs(windows) do
  local kind, state = def[1], def[2]
  ns.On(event, function() setOpen(kind, state) end)
end

-- Clients modernes : un gestionnaire unique d'interactions avec les PNJ.
local INTERACTION_KINDS = {
  Merchant = "merchant", MailInfo = "mail", Auctioneer = "auction",
  Trainer = "trainer", TaxiNode = "taxi", TradePartner = "trade",
}
local function interactionKind(interactionType)
  local enum = Enum and Enum.PlayerInteractionType
  if not enum then return nil end
  for name, kind in pairs(INTERACTION_KINDS) do
    if enum[name] ~= nil and enum[name] == interactionType then return kind end
  end
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, t)
  local kind = interactionKind(t)
  if kind then setOpen(kind, true) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, t)
  local kind = interactionKind(t)
  if kind then setOpen(kind, false) end
end)

ns.On("LOOT_READY", function() mark("loot") end)
ns.On("CHAT_MSG_MONEY", function() mark("loot") end)
ns.On("QUEST_TURNED_IN", function() mark("quest") end)
ns.Hook("GetQuestReward", function() mark("quest") end)
ns.Hook("RepairAllItems", function() mark("repair") end)
ns.Hook("TakeTaxiNode", function() mark("taxi") end)

---------------------------------------------------------------------------
-- Courrier : on note ce qu'on retire (vente HV ou courrier normal) pour classer l'or qui arrive.
---------------------------------------------------------------------------
ns.mailQueue = {}
local function queueMail(index)
  if not index or not GetInboxHeaderInfo then return end
  local money = select(5, GetInboxHeaderInfo(index)) or 0
  if money <= 0 then return end
  local cat = "courrier"
  if GetInboxInvoiceInfo then
    local kind = GetInboxInvoiceInfo(index)
    if kind == "seller" then cat = "hv_vente" end
  end
  ns.mailQueue[#ns.mailQueue + 1] = { t = GetTime(), m = money, c = cat }
  mark("mail_take")
end
ns.Hook("TakeInboxMoney", queueMail)
ns.Hook("AutoLootMailItem", queueMail)

local function mailCategory(delta)
  local q = ns.mailQueue
  while q[1] and (GetTime() - q[1].t) > 30 do table.remove(q, 1) end
  for i = 1, #q do
    if q[i].m == delta then
      return table.remove(q, i).c
    end
  end
  if q[1] then return table.remove(q, 1).c end
  return nil
end

---------------------------------------------------------------------------
-- Classement
---------------------------------------------------------------------------

local function byWindow(kind, d)
  if kind == "auction" then
    if d < 0 then
      if within("ah_post", 10) then return "hv_depot" end
      return "hv_achat"
    end
    return "hv_autre"
  elseif kind == "mail" then
    if d > 0 then return mailCategory(d) or "courrier" end
    return "courrier_envoi"
  elseif kind == "merchant" then
    return d > 0 and "marchand_vente" or "marchand_achat"
  elseif kind == "trainer" then
    return "formation"
  elseif kind == "taxi" then
    return "vol"
  elseif kind == "trade" then
    return "echange"
  end
  return "autre"
end

local function classify(d)
  if within("repair", 3) or (d < 0 and isOpenNow("merchant") and InRepairMode and InRepairMode()) then
    return "reparation"
  end
  -- De l'or retiré d'un courrier : on le reconnaît même si la fenêtre a l'air fermée.
  if d > 0 and within("mail_take", 10) then
    local c = mailCategory(d)
    if c then return c end
  end
  -- 1) fenêtres ouvertes en ce moment : la plus récemment ouverte l'emporte
  local best, bestT
  for _, kind in ipairs(WINDOW_ORDER) do
    if isOpenNow(kind) then
      local t = recent[kind] or 0
      if not bestT or t > bestT then best, bestT = kind, t end
    end
  end
  if best then return byWindow(best, d) end
  -- 2) sinon la fenêtre fermée le plus récemment (l'or arrive parfois juste après)
  for _, kind in ipairs(WINDOW_ORDER) do
    local t = recent[kind]
    if t and (GetTime() - t) <= (GRACE[kind] or 2) and (not bestT or t > bestT) then
      best, bestT = kind, t
    end
  end
  if best then return byWindow(best, d) end
  if within("quest", 3) then return "quete" end
  if open.loot or within("loot", 3) then return "butin" end
  return "autre"
end
ns.Classify = classify

-- Une fenêtre (ou une action) est-elle en cours, ou vue il y a moins de `seconds` secondes ?
function ns.Seen(kind, seconds)
  return isOpenNow(kind) or within(kind, seconds or 0)
end

-- Un gain « autre » est revu une seconde plus tard : avec le ramassage automatique,
-- l'or arrive parfois juste avant l'événement de butin ou de quête.
local function reviewLater(entry, moneyTime)
  C_Timer.After(1.5, function()
    if entry.c ~= "autre" then return end
    if recent.quest and recent.quest >= moneyTime - 0.5 then
      entry.c = "quete"
    elseif recent.loot and recent.loot >= moneyTime - 0.5 then
      entry.c = "butin"
    end
  end)
end

ns.On("PLAYER_MONEY", function()
  local db = ns.db
  if not db then return end
  local m = GetMoney()
  local last = ns.lastMoney
  ns.lastMoney = m
  ns.moneyReady = true
  if last == nil then return end
  local d = m - last
  if d == 0 then return end
  local c = classify(d)
  local entry = { t = time(), d = d, m = m, c = c }
  if c == "autre" and d > 0 then reviewLater(entry, GetTime()) end
  if c == "hv_depot" and ns.lastPost and not ns.lastPost.dep then
    ns.lastPost.dep = -d
  end
  ns.Append(db.moneyLog, entry, ns.MAX_MONEY_LOG)
  ns.Try("patrimoine", ns.Sample)
  ns.Changed()
end)

ns.AtLogin(function()
  local db = ns.db
  local function start()
    local money = GetMoney()
    local known = db.char.money
    if known == nil then
      -- Première utilisation : on note le solde de départ.
      ns.Append(db.moneyLog, { t = time(), d = 0, m = money, c = "depart" }, ns.MAX_MONEY_LOG)
    elseif known ~= money then
      -- L'or a changé pendant que l'addon ne tournait pas.
      ns.Append(db.moneyLog, { t = time(), d = money - known, m = money, c = "hors_suivi" }, ns.MAX_MONEY_LOG)
    end
    ns.lastMoney = money
    ns.moneyReady = true
    ns.Try("patrimoine", ns.Sample, true)
    ns.Changed()
  end
  -- À la connexion le jeu répond parfois 0 avant de connaître la vraie somme : si le solde
  -- connu n'était pas nul, on attend quelques secondes avant de le croire.
  if GetMoney() == 0 and (db.char.money or 0) > 0 then
    C_Timer.After(5, function() if not ns.moneyReady then start() end end)
  else
    start()
  end
end)

-- Totaux par catégorie depuis une date : { [catégorie] = { i = entrées, o = sorties } }.
function ns.FlowTotals(since)
  local out = {}
  local log = ns.db.moneyLog
  for i = #log, 1, -1 do
    local e = log[i]
    if e.t < since then break end
    if e.c ~= "depart" then
      local c = out[e.c]
      if not c then
        c = { i = 0, o = 0 }
        out[e.c] = c
      end
      if e.d > 0 then c.i = c.i + e.d else c.o = c.o - e.d end
    end
  end
  return out
end
