-- Négoce : thème et briques d'interface (panneaux arrondis, textes, boutons, onglets, listes).
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
UI.ART = ART

-- Palette : fond sombre et chaud, accents bronze et or comme les cadres de Forever.
UI.C = {
  bg      = { 0.075, 0.066, 0.058 },
  panel   = { 0.115, 0.102, 0.090 },
  card    = { 0.155, 0.138, 0.120 },
  hover   = { 0.205, 0.182, 0.156 },
  line    = { 0.260, 0.225, 0.185 },
  accent  = { 0.878, 0.690, 0.314 },
  text    = { 0.930, 0.902, 0.855 },
  muted   = { 0.610, 0.565, 0.505 },
  faint   = { 0.400, 0.368, 0.325 },
  green   = { 0.400, 0.840, 0.540 },
  red     = { 0.905, 0.435, 0.380 },
  blue    = { 0.425, 0.720, 1.000 },
}

function UI.Color(key, alpha)
  local c = UI.C[key] or UI.C.text
  return c[1], c[2], c[3], alpha or 1
end

-- Code couleur pour du texte : UI.Hex("green") .. "+12" .. "|r"
function UI.Hex(key)
  local c = UI.C[key] or UI.C.text
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------

-- Texture arrondie étirée en 9 tranches. file : "rond" (grands coins), "pastille" (petits coins),
-- "contour" (bord d'un pixel).
function UI.Slice(frame, file, colorKey, alpha, layer, sublevel)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
  if t.SetTextureSliceMargins then
    t:SetTexture(ART .. file .. ".tga")
    local m = (file == "pastille") and 8 or 14
    t:SetTextureSliceMargins(m, m, m, m)
    if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
      t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
    t:SetVertexColor(UI.Color(colorKey, alpha))
  elseif file == "contour" then
    t:SetColorTexture(0, 0, 0, 0)
  else
    t:SetColorTexture(UI.Color(colorKey, alpha))
  end
  t:SetAllPoints(frame)
  return t
end

function UI.Recolor(tex, colorKey, alpha)
  if tex.SetTextureSliceMargins then
    tex:SetVertexColor(UI.Color(colorKey, alpha))
  else
    tex:SetColorTexture(UI.Color(colorKey, alpha))
  end
end

function UI.Fill(frame, colorKey, alpha, layer, sublevel)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
  t:SetColorTexture(UI.Color(colorKey, alpha))
  return t
end

---------------------------------------------------------------------------
-- Textes
---------------------------------------------------------------------------

function UI.Text(parent, size, colorKey, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
  fs:SetTextColor(UI.Color(colorKey or "text"))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

---------------------------------------------------------------------------
-- Panneaux et boutons
---------------------------------------------------------------------------

function UI.Panel(parent, w, h, colorKey, file)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f.bg = UI.Slice(f, file or "rond", colorKey or "panel")
  return f
end

-- Bouton en pastille. Renvoie le bouton ; button:SetActive(bool) le met en valeur.
function UI.Button(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 26)
  b.bg = UI.Slice(b, "pastille", "card")
  b.label = UI.Text(b, 12, "muted", "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(label)
  local function paint()
    if b.active then
      UI.Recolor(b.bg, "accent", 1)
      b.label:SetTextColor(UI.Color("bg"))
    elseif b.over then
      UI.Recolor(b.bg, "hover", 1)
      b.label:SetTextColor(UI.Color("text"))
    else
      UI.Recolor(b.bg, "card", 1)
      b.label:SetTextColor(UI.Color("muted"))
    end
  end
  b:SetScript("OnEnter", function() b.over = true paint() end)
  b:SetScript("OnLeave", function() b.over = false paint() end)
  b:SetScript("OnClick", function()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    if onClick then onClick(b) end
  end)
  function b:SetActive(on) self.active = on and true or false paint() end
  function b:SetLabel(text)
    self.label:SetText(text)
  end
  return b
end

-- Rangée de boutons dont un seul est actif. entries = { { key, label }, ... }.
-- Renvoie un cadre ; seg:Select(key) change la sélection sans appeler onSelect.
function UI.Segment(parent, entries, onSelect, buttonWidth, height)
  local f = CreateFrame("Frame", nil, parent)
  f.buttons = {}
  local x = 0
  for i, e in ipairs(entries) do
    local w = e.w or buttonWidth or 90
    local b = UI.Button(f, e.label, w, height or 26, function()
      f:Select(e.key)
      if onSelect then onSelect(e.key) end
    end)
    b:SetPoint("LEFT", f, "LEFT", x, 0)
    b.key = e.key
    f.buttons[i] = b
    x = x + w + 6
  end
  f:SetSize(math.max(1, x - 6), height or 26)
  function f:Select(key)
    self.key = key
    for _, b in ipairs(self.buttons) do b:SetActive(b.key == key) end
  end
  return f
end

-- Icône d'objet aux bords rognés, avec un fin liseré.
function UI.Icon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.border = UI.Fill(f, "line", 1, "BACKGROUND")
  f.border:SetAllPoints()
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("TOPLEFT", 1, -1)
  f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  function f:SetItem(id)
    local icon = id and ns.Item(id).icon
    self.tex:SetTexture(icon or 134400) -- point d'interrogation
  end
  return f
end

function UI.ItemTooltip(owner, id, anchor)
  if not id then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
  if GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(id)
  else
    GameTooltip:SetHyperlink("item:" .. id)
  end
  GameTooltip:Show()
end

-- Clic avec Maj sur un objet : met son lien dans la discussion, comme partout dans le jeu.
function UI.ItemClick(id)
  local link = id and ns.Item(id).link
  if link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
    ChatEdit_InsertLink(link)
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Liste défilante. Les lignes sont créées une fois puis réutilisées.
--   build(row)               : crée le contenu d'une ligne
--   update(row, item, index) : remplit une ligne
---------------------------------------------------------------------------

function UI.List(parent, w, h, rowH, build, update)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f.rows, f.data, f.offset = {}, {}, 0
  local visible = math.floor(h / rowH)

  for i = 1, visible do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(w - 10, rowH)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
    row.hl = UI.Slice(row, "pastille", "hover", 0.7)
    row.hl:Hide()
    row:HookScript("OnEnter", function(self) self.hl:Show() end)
    row:HookScript("OnLeave", function(self) self.hl:Hide() end)
    build(row)
    f.rows[i] = row
  end

  local track = UI.Fill(f, "line", 0.5, "ARTWORK")
  track:SetPoint("TOPRIGHT", -2, 0)
  track:SetSize(3, h)
  local thumb = UI.Fill(f, "accent", 0.8, "OVERLAY")
  thumb:SetWidth(3)

  f.empty = UI.Text(f, 13, "muted", "CENTER")
  f.empty:SetPoint("CENTER", 0, 0)
  f.empty:SetWidth(w - 80)
  f.empty:SetWordWrap(true)
  f.empty:Hide()

  function f:Render()
    local n = #self.data
    local maxOffset = math.max(0, n - visible)
    if self.offset > maxOffset then self.offset = maxOffset end
    if self.offset < 0 then self.offset = 0 end
    for i = 1, visible do
      local row, item = self.rows[i], self.data[self.offset + i]
      if item then
        row.item = item
        update(row, item, self.offset + i)
        row:Show()
      else
        row.item = nil
        row:Hide()
      end
    end
    if n > visible then
      local size = math.max(24, h * visible / n)
      thumb:SetHeight(size)
      thumb:ClearAllPoints()
      thumb:SetPoint("TOPRIGHT", -2, -(h - size) * (self.offset / maxOffset))
      thumb:Show()
      track:Show()
    else
      thumb:Hide()
      track:Hide()
    end
    self.empty:SetShown(n == 0)
  end

  function f:SetData(data, emptyText)
    self.data = data or {}
    if emptyText then self.empty:SetText(emptyText) end
    self:Render()
  end

  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(self, delta)
    self.offset = self.offset - delta * 2
    self:Render()
  end)
  return f
end

---------------------------------------------------------------------------
-- Petit menu déroulant. entries = { { label, onClick }, ... }
---------------------------------------------------------------------------

local menu
function UI.Menu(anchor, entries)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu.bg = UI.Slice(menu, "pastille", "card")
    menu.edge = UI.Slice(menu, "pastille", "line", 1, "BACKGROUND", -1)
    menu.edge:ClearAllPoints()
    menu.edge:SetPoint("TOPLEFT", -1, 1)
    menu.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    menu.items = {}
    menu:EnableMouse(true)
  end
  if menu:IsShown() and menu.anchor == anchor then
    menu:Hide()
    return
  end
  menu.anchor = anchor
  for _, b in ipairs(menu.items) do b:Hide() end
  local y = 6
  for i, e in ipairs(entries) do
    local b = menu.items[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetSize(168, 22)
      b.hl = UI.Slice(b, "pastille", "hover")
      b.hl:Hide()
      b.label = UI.Text(b, 12, "text")
      b.label:SetPoint("LEFT", 10, 0)
      b:SetScript("OnEnter", function(self) self.hl:Show() end)
      b:SetScript("OnLeave", function(self) self.hl:Hide() end)
      menu.items[i] = b
    end
    b.label:SetText(e.label)
    b:SetScript("OnClick", function()
      menu:Hide()
      e.onClick()
    end)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 6, -y)
    b:Show()
    y = y + 22
  end
  menu:SetSize(180, y + 6)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  menu:Show()
end

function UI.HideMenu()
  if menu then menu:Hide() end
end
