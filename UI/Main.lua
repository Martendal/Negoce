-- Négoce : fenêtre principale, onglets, bouton de la minicarte et commandes.
local ADDON, ns = ...
local UI = ns.UI

local WIDTH, HEIGHT, HEADER = 1100, 740, 62
UI.CONTENT_W, UI.CONTENT_H = WIDTH, HEIGHT - HEADER

ns.tabs = {}     -- { key, label, build(parent) -> cadre avec :Refresh() }
local order = {} -- clés dans l'ordre d'affichage
function ns.AddTab(key, label, build)
  ns.tabs[key] = { key = key, label = label, build = build }
  order[#order + 1] = key
end

local win

local function showTab(key)
  if not ns.tabs[key] then key = order[1] end
  ns.db.ui.tab = key
  UI.HideMenu()
  for k, tab in pairs(ns.tabs) do
    if k == key then
      if not tab.frame then
        tab.frame = tab.build(win.content)
        tab.frame:SetAllPoints(win.content)
      end
      tab.frame:Show()
      ns.Try("onglet " .. key, tab.frame.Refresh, tab.frame)
    elseif tab.frame then
      tab.frame:Hide()
    end
  end
  win.tabs:Select(key)
end

local function updateStatus()
  if not win then return end
  local market = ns.Market()
  local state, count = ns.ScanState()
  if state == "scan" then
    win.status:SetText(UI.Hex("accent") .. "Scan en cours… " .. count .. " objets|r")
  elseif market.scan then
    win.status:SetText("Prix de l'HV relevés " .. ns.Ago(market.scan))
  else
    win.status:SetText("Aucun scan de l'HV pour l'instant")
  end
end

local function build()
  win = CreateFrame("Frame", "NegoceFrame", UIParent)
  win:SetSize(WIDTH, HEIGHT)
  win:SetFrameStrata("HIGH")
  win:SetToplevel(true)
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:SetMovable(true)
  win:Hide()
  tinsert(UISpecialFrames, "NegoceFrame") -- se ferme avec Échap

  local pos = ns.db.ui.pos
  if pos then
    win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    win:SetPoint("CENTER")
  end
  if ns.db.ui.scale then win:SetScale(ns.db.ui.scale) end

  -- Ombre portée, fond, liseré
  local shadow = win:CreateTexture(nil, "BACKGROUND", nil, -8)
  shadow:SetTexture(UI.ART .. "ombre.tga")
  shadow:SetVertexColor(0, 0, 0, 1)
  if shadow.SetTextureSliceMargins then
    shadow:SetTextureSliceMargins(48, 48, 48, 48)
    shadow:SetPoint("TOPLEFT", -30, 30)
    shadow:SetPoint("BOTTOMRIGHT", 30, -30)
  else
    shadow:Hide()
  end
  win.bg = UI.Slice(win, "rond", "bg", 0.985, "BACKGROUND", -6)
  win.edge = UI.Slice(win, "contour", "line", 1, "BACKGROUND", -5)

  -- En-tête : on déplace la fenêtre en la tirant par là.
  local header = CreateFrame("Frame", nil, win)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() win:StartMoving() end)
  header:SetScript("OnDragStop", function()
    win:StopMovingOrSizing()
    local point, _, rel, x, y = win:GetPoint(1)
    ns.db.ui.pos = { point, rel, x, y }
  end)
  local rule = UI.Fill(header, "line", 0.8, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", 16, 0)
  rule:SetPoint("BOTTOMRIGHT", -16, 0)

  local logo = header:CreateTexture(nil, "ARTWORK")
  logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  logo:SetSize(30, 30)
  logo:SetPoint("LEFT", 20, 0)
  local title = UI.Text(header, 19, "accent")
  title:SetPoint("LEFT", logo, "RIGHT", 10, 7)
  title:SetText("Négoce")
  local who = UI.Text(header, 11, "muted")
  who:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  who:SetText((ns.db.char.name or "") .. " · " .. ns.MarketKey())

  local entries = {}
  for _, key in ipairs(order) do
    entries[#entries + 1] = { key = key, label = ns.tabs[key].label, w = 120 }
  end
  win.tabs = UI.Segment(header, entries, showTab, 120, 30)
  win.tabs:SetPoint("LEFT", 190, 0)

  local close = UI.Button(header, "×", 30, 30, function() win:Hide() end)
  close.label:SetFont(STANDARD_TEXT_FONT, 18, "")
  close:SetPoint("RIGHT", -16, 0)

  win.status = UI.Text(header, 11, "muted", "RIGHT")
  win.status:SetPoint("RIGHT", close, "LEFT", -14, 0)

  win.content = CreateFrame("Frame", nil, win)
  win.content:SetPoint("TOPLEFT", 0, -HEADER)
  win.content:SetPoint("BOTTOMRIGHT")

  win:SetScript("OnShow", function()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    updateStatus()
    showTab(ns.db.ui.tab or order[1])
  end)
  win:SetScript("OnHide", function()
    UI.HideMenu()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
  end)
end

function ns.Toggle()
  if not ns.db then return end
  if not win then build() end
  win:SetShown(not win:IsShown())
end

-- Quelque chose a changé dans les données : on redessine l'onglet affiché.
ns.Listen(function()
  if not win or not win:IsShown() then return end
  updateStatus()
  local tab = ns.tabs[ns.db.ui.tab or order[1]]
  if tab and tab.frame and tab.frame:IsShown() then
    ns.Try("onglet " .. tab.key, tab.frame.Refresh, tab.frame)
  end
end)
ns.scanListeners[#ns.scanListeners + 1] = updateStatus

---------------------------------------------------------------------------
-- Bouton de la minicarte
---------------------------------------------------------------------------

ns.AtLogin(function()
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and icon) then return end
  local broker = LDB:NewDataObject("Negoce", {
    type = "launcher",
    text = "Négoce",
    icon = "Interface\\Icons\\INV_Misc_Coin_01",
    OnClick = function() ns.Toggle() end,
    OnTooltipShow = function(tt)
      tt:AddLine("|cffe0b050Négoce|r")
      local list = ns.db.wealth
      local last = list[#list]
      if last then
        tt:AddDoubleLine("Or", ns.Money(last.g), 0.7, 0.7, 0.7, 1, 1, 1)
        tt:AddDoubleLine("Stock", ns.Money(last.s), 0.7, 0.7, 0.7, 1, 1, 1)
        tt:AddDoubleLine("Patrimoine", ns.Money(last.g + last.s + (last.m or 0)), 0.7, 0.7, 0.7, 1, 0.82, 0)
      end
      tt:AddLine("Clic : ouvrir ou fermer", 0.6, 0.6, 0.6)
    end,
  })
  icon:Register("Negoce", broker, ns.db.minimap)
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

SLASH_NEGOCE1, SLASH_NEGOCE2 = "/negoce", "/ng"
SlashCmdList["NEGOCE"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "scan" then
    ns.StartScan()
  elseif msg == "erreurs" then
    local errors = ns.db.errors
    if #errors == 0 then ns.Print("aucune erreur enregistrée.") end
    for i = math.max(1, #errors - 9), #errors do
      local e = errors[i]
      ns.Print(date("%d/%m %H:%M", e.t) .. " [" .. e.w .. "] " .. e.m)
    end
  elseif msg == "minicarte" then
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    ns.db.minimap.hide = not ns.db.minimap.hide
    if icon then
      if ns.db.minimap.hide then icon:Hide("Negoce") else icon:Show("Negoce") end
    end
  elseif msg:match("^taille") then
    local scale = tonumber(msg:match("([%d%.]+)"))
    if scale and scale >= 0.6 and scale <= 1.4 then
      ns.db.ui.scale = scale
      if win then win:SetScale(scale) end
    else
      ns.Print("taille entre 0.6 et 1.4, par exemple : /negoce taille 0.9")
    end
  elseif msg == "suivi" then
    if ns.PrintTracking then ns.PrintTracking(15) end
  elseif msg == "infobulle" then
    ns.db.ui.noTooltip = not ns.db.ui.noTooltip or nil
    ns.Print(ns.db.ui.noTooltip and "bloc Négoce masqué dans les infobulles." or "bloc Négoce affiché dans les infobulles.")
  elseif msg == "aide" then
    ns.Print("/negoce : ouvrir la fenêtre · scan · suivi · infobulle · taille 0.9 · minicarte · erreurs")
  else
    ns.Toggle()
  end
end
