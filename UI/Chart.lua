-- Négoce : courbe. Une série principale (trait épais et aire) et une série secondaire (trait fin),
-- avec lecture des valeurs au survol.
local ADDON, ns = ...
local UI = ns.UI

local PAD_LEFT, PAD_RIGHT, PAD_TOP, PAD_BOTTOM = 8, 8, 10, 20
local STEP = 5 -- largeur d'une colonne, en pixels

-- Valeur d'une série au temps t (interpolation entre les deux points voisins).
local function valueAt(points, field, t, cursor)
  local n = #points
  while cursor < n and points[cursor + 1].t <= t do cursor = cursor + 1 end
  local a, b = points[cursor], points[cursor + 1]
  if not b or b.t == a.t or t <= a.t then return a[field], cursor end
  local k = (t - a.t) / (b.t - a.t)
  return a[field] + (b[field] - a[field]) * k, cursor
end

function UI.Chart(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local plotW, plotH = w - PAD_LEFT - PAD_RIGHT, h - PAD_TOP - PAD_BOTTOM
  local columns = math.floor(plotW / STEP)

  local lines, lines2, bars, grid = {}, {}, {}, {}
  for i = 1, 3 do
    local g = UI.Fill(f, "line", 0.45, "BACKGROUND", 1)
    g:SetHeight(1)
    g:SetPoint("BOTTOMLEFT", PAD_LEFT, PAD_BOTTOM + plotH * (i - 1) / 2)
    g:SetPoint("BOTTOMRIGHT", -PAD_RIGHT, PAD_BOTTOM + plotH * (i - 1) / 2)
    local label = UI.Text(f, 10, "faint", "LEFT")
    label:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 2, 2)
    grid[i] = { line = g, label = label }
  end

  local startLabel = UI.Text(f, 10, "faint", "LEFT")
  startLabel:SetPoint("BOTTOMLEFT", PAD_LEFT, 2)
  local endLabel = UI.Text(f, 10, "faint", "RIGHT")
  endLabel:SetPoint("BOTTOMRIGHT", -PAD_RIGHT, 2)

  local empty = UI.Text(f, 13, "muted", "CENTER")
  empty:SetPoint("CENTER", 0, 0)
  empty:SetText("La courbe se dessine au fil de tes sessions.")

  -- Lecture au survol
  local cursorLine = UI.Fill(f, "text", 0.25, "ARTWORK", 3)
  cursorLine:SetSize(1, plotH)
  cursorLine:Hide()
  local dot = f:CreateTexture(nil, "OVERLAY")
  dot:SetTexture(UI.ART .. "disque.tga")
  dot:SetVertexColor(UI.Color("accent"))
  dot:SetSize(10, 10)
  dot:Hide()
  local tip = CreateFrame("Frame", nil, f)
  tip:SetSize(190, 56)
  tip:SetFrameLevel(f:GetFrameLevel() + 5)
  tip.bg = UI.Slice(tip, "pastille", "bg", 0.95)
  tip.date = UI.Text(tip, 10, "muted")
  tip.date:SetPoint("TOPLEFT", 10, -7)
  tip.main = UI.Text(tip, 12, "text")
  tip.main:SetPoint("TOPLEFT", 10, -21)
  tip.second = UI.Text(tip, 11, "muted")
  tip.second:SetPoint("TOPLEFT", 10, -37)
  tip:Hide()

  local function segment(pool, i, layerLevel, thickness, colorKey, alpha)
    local l = pool[i]
    if not l then
      l = f:CreateLine(nil, "ARTWORK", nil, layerLevel)
      l:SetThickness(thickness)
      l:SetColorTexture(UI.Color(colorKey, alpha))
      pool[i] = l
    end
    return l
  end

  local function hideFrom(pool, from)
    for i = from, #pool do pool[i]:Hide() end
  end

  -- points : liste triée de { t, a = série principale, b = série secondaire (facultative) }.
  function f:SetSeries(points, labelA, labelB)
    self.samples = nil
    self.labelA, self.labelB = labelA, labelB
    cursorLine:Hide() dot:Hide() tip:Hide()
    local n = #points
    if n < 2 or points[n].t <= points[1].t then
      hideFrom(lines, 1) hideFrom(lines2, 1) hideFrom(bars, 1)
      for i = 1, 3 do grid[i].label:SetText("") end
      startLabel:SetText("") endLabel:SetText("")
      empty:Show()
      return
    end
    empty:Hide()

    local t0, t1 = points[1].t, points[n].t
    local hasB = points[1].b ~= nil
    local samples, lo, hi = {}, nil, nil
    local ca, cb = 1, 1
    for i = 0, columns do
      local t = t0 + (t1 - t0) * i / columns
      local a, b
      a, ca = valueAt(points, "a", t, ca)
      if hasB then b, cb = valueAt(points, "b", t, cb) end
      samples[i + 1] = { t = t, a = a, b = b }
      lo = math.min(lo or a, a, b or a)
      hi = math.max(hi or a, a, b or a)
    end
    if hi - lo < 1 then hi = lo + 1 end
    local pad = (hi - lo) * 0.10
    lo, hi = math.max(0, lo - pad), hi + pad
    local function y(v) return PAD_BOTTOM + (v - lo) / (hi - lo) * plotH end
    local function x(i) return PAD_LEFT + (i - 1) * STEP end

    for i = 1, columns do
      local s, e = samples[i], samples[i + 1]
      local la = segment(lines, i, 2, 2, "accent", 1)
      la:SetStartPoint("BOTTOMLEFT", f, x(i), y(s.a))
      la:SetEndPoint("BOTTOMLEFT", f, x(i + 1), y(e.a))
      la:Show()

      local bar = bars[i]
      if not bar then
        bar = UI.Fill(f, "accent", 0.10, "BACKGROUND", 2)
        bars[i] = bar
      end
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", x(i), PAD_BOTTOM)
      bar:SetSize(STEP, math.max(1, (y(s.a) + y(e.a)) / 2 - PAD_BOTTOM))
      bar:Show()

      if hasB then
        local lb = segment(lines2, i, 1, 1, "blue", 0.75)
        lb:SetStartPoint("BOTTOMLEFT", f, x(i), y(s.b))
        lb:SetEndPoint("BOTTOMLEFT", f, x(i + 1), y(e.b))
        lb:Show()
      end
    end
    hideFrom(lines, columns + 1)
    hideFrom(bars, columns + 1)
    hideFrom(lines2, hasB and (columns + 1) or 1)

    for i = 1, 3 do
      grid[i].label:SetText(ns.Money(lo + (hi - lo) * (i - 1) / 2))
    end
    local span = t1 - t0
    local fmt = span > 86400 * 2 and "%d/%m" or "%d/%m %H:%M"
    startLabel:SetText(date(fmt, t0))
    endLabel:SetText(date(fmt, t1))

    self.samples, self.y, self.x = samples, y, x
  end

  f:SetScript("OnUpdate", function(self)
    local samples = self.samples
    if not samples or not self:IsMouseOver() then
      if tip:IsShown() then cursorLine:Hide() dot:Hide() tip:Hide() end
      return
    end
    local cx = GetCursorPosition() / self:GetEffectiveScale() - self:GetLeft()
    local i = math.floor((cx - PAD_LEFT) / STEP + 0.5) + 1
    if i < 1 then i = 1 elseif i > #samples then i = #samples end
    if i == self.hoverIndex and tip:IsShown() then return end
    self.hoverIndex = i
    local s = samples[i]
    local px, py = self.x(i), self.y(s.a)
    cursorLine:ClearAllPoints()
    cursorLine:SetPoint("BOTTOMLEFT", px, PAD_BOTTOM)
    cursorLine:Show()
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", self, "BOTTOMLEFT", px, py)
    dot:Show()
    tip.date:SetText(date("%d/%m à %H:%M", s.t))
    tip.main:SetText((self.labelA or "") .. "  " .. ns.Money(s.a))
    tip.second:SetText(s.b and ((self.labelB or "") .. "  " .. ns.Money(s.b)) or "")
    tip:ClearAllPoints()
    if px > w / 2 then
      tip:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", px - 12, h - 8)
    else
      tip:SetPoint("TOPLEFT", self, "BOTTOMLEFT", px + 12, h - 8)
    end
    tip:Show()
  end)

  return f
end
