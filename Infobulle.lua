-- Négoce : infobulle des objets. Ajoute ton coût de revient, le cours de l'HV et la marge nette
-- partout où le jeu décrit un objet. Avec Maj : les montants pour la pile survolée (ou pour
-- tout ce que tu possèdes) et, pour un objet fabricable, son coût de fabrication au marché.
--   /negoce infobulle : afficher ou masquer ce bloc.
local ADDON, ns = ...

local ACCENT = { 0.88, 0.69, 0.31 }
local LABEL = { 0.72, 0.70, 0.66 }

-- Quantité que tu possèdes dans les sacs et la banque, et sa part non liée.
local function owned(id)
  local q, free = 0, 0
  local function merge(src)
    local e = src and src.items and src.items[id]
    if e then q, free = q + e.c, free + e.c - (e.b or 0) end
  end
  merge(ns.db.bags)
  merge(ns.db.bank)
  return q, free
end

-- Taille de la pile survolée, quand l'infobulle vient d'une case de sac.
local function hoveredStack(tooltip)
  local ok, count = pcall(function()
    local owner = tooltip:GetOwner()
    if owner and owner.GetBagID and owner.GetID then
      local info = C_Container.GetContainerItemInfo(owner:GetBagID(), owner:GetID())
      return info and info.stackCount
    end
  end)
  if ok and type(count) == "number" and count > 0 then return count end
end

local function addLines(tooltip, id)
  local db = ns.db
  if not db or not id or (db.ui and db.ui.noTooltip) then return end
  local unit, tracked = nil, nil
  if ns.UnitCost then unit, tracked = ns.UnitCost(id) end
  local market = ns.MarketPrice(id)
  if not unit and not (market and market > 0) then return end

  local have, free = owned(id)
  local bound = have > 0 and free == 0
  local shift = IsShiftKeyDown and IsShiftKeyDown()
  local mult, suffix = 1, ""
  if shift then
    mult = hoveredStack(tooltip) or tracked or 1
    if mult > 1 then suffix = " ×" .. mult end
  end
  local function row(label, value)
    tooltip:AddDoubleLine(label .. suffix, value, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
  end

  tooltip:AddLine(" ")
  tooltip:AddLine("Négoce", ACCENT[1], ACCENT[2], ACCENT[3])
  if unit then
    local count = (not shift and tracked and tracked > 1) and ("  |cff8c8880(×" .. tracked .. ")|r") or ""
    row("Coût de revient", ns.Money(unit * mult) .. count)
  end
  if market and market > 0 and not bound then
    row("Cours HV", ns.Money(market * mult))
    if unit then
      local margin = (market * (1 - ns.AH_CUT) - unit) * mult
      local color = margin >= 0 and "|cff5ccb6b" or "|cffe0605a"
      row("Marge nette", color .. ns.Money(margin, true) .. "|r")
    end
  end
  if shift and ns.byProduct[id] then
    ns.ResetCosts()
    local _, craft = ns.CheapestRecipe(id)
    if craft then row("Fabrication au marché", ns.Money(craft * mult)) end
  end
end

local function onItem(tooltip, id)
  ns.Try("infobulle", addLines, tooltip, id)
end

ns.AtLogin(function()
  local processor = TooltipDataProcessor
  local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
  if processor and processor.AddTooltipPostCall and itemType then
    processor.AddTooltipPostCall(itemType, function(tooltip, data)
      if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
      local id = data and data.id
      if not id and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        id = ns.ItemIDFromLink(link)
      end
      onItem(tooltip, id)
    end)
    return
  end
  -- Clients sans le processeur d'infobulles : l'ancien script des infobulles d'objets.
  for _, tooltip in pairs({ GameTooltip, ItemRefTooltip }) do
    if type(tooltip) == "table" and tooltip.HookScript then
      pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        onItem(self, ns.ItemIDFromLink(link))
      end)
    end
  end
end)
