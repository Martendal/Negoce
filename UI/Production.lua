-- Négoce : onglet Production. Graphe des recettes : matières premières à gauche, composants au
-- milieu, produits finis à droite, reliés selon les recettes. Un clic sur un objet allume sa
-- chaîne de fabrication et affiche le détail de sa rentabilité.
local ADDON, ns = ...
local UI = ns.UI
local L = ns.L

local PAD = 20
local DETAIL_W = 290
local NODE_H, NODE_GAP = 42, 7
local MAX_PRODUCTS = 60
local SRC = { hv = "HV", marchand = "marchand", fab = "fabriqué" }
local SHORT = { hv = "HV", marchand = "march.", fab = "fab." }

---------------------------------------------------------------------------
-- Construction du graphe (données seulement)
---------------------------------------------------------------------------

-- Recettes candidates selon les filtres. Renvoie la liste et la fonction de filtre.
local function candidates(ui, skills)
  local known = ns.db.known
  local function allow(r)
    if ui.prodSkill == 0 then
      if not skills[r.skill] then return false end
    elseif r.skill ~= ui.prodSkill then
      return false
    end
    if ui.prodKnown and not known[r.spell] then return false end
    return true
  end
  local list = {}
  for _, r in pairs(ns.recipes) do
    if allow(r) then list[#list + 1] = r end
  end
  return list, allow
end

local function buildGraph(ui, skills)
  local list, allow = candidates(ui, skills)
  ns.costFilter = allow
  ns.ResetCosts()

  -- Une recette par objet fabriqué : la moins chère.
  local recipeOf = {}
  for _, r in ipairs(list) do
    if recipeOf[r.item] == nil then
      recipeOf[r.item] = ns.CheapestRecipe(r.item, allow) or r
    end
  end

  -- Produits affichés : filtrés par la recherche et la rentabilité, classés par bénéfice.
  local search = ui.prodSearch and ui.prodSearch ~= "" and ui.prodSearch:lower() or nil
  local products = {}
  for item, r in pairs(recipeOf) do
    local bilan = ns.RecipeProfit(r)
    local keep = true
    if ui.prodProfit and not (bilan.profit and bilan.profit > 0) then keep = false end
    if keep and search then
      local name = ns.Item(item).name
      keep = name ~= nil and name:lower():find(search, 1, true) ~= nil
    end
    if keep then products[#products + 1] = { item = item, r = r, bilan = bilan } end
  end
  table.sort(products, function(a, b)
    local pa, pb = a.bilan.profit or -math.huge, b.bilan.profit or -math.huge
    if pa ~= pb then return pa > pb end
    return a.item < b.item
  end)
  local total = #products
  for i = #products, MAX_PRODUCTS + 1, -1 do products[i] = nil end

  -- Nœuds : les produits retenus, puis leurs composants, et ainsi de suite jusqu'aux matières.
  local nodes, queue = {}, {}
  local function node(item)
    local n = nodes[item]
    if not n then
      n = { id = item, r = recipeOf[item], uses = {}, parts = {} }
      nodes[item] = n
      queue[#queue + 1] = n
    end
    return n
  end
  for _, p in ipairs(products) do node(p.item).bilan = p.bilan end
  local i = 1
  while queue[i] do
    local n = queue[i]
    i = i + 1
    if n.r then
      n.bilan = n.bilan or ns.RecipeProfit(n.r)
      for _, c in ipairs(n.r.reag) do
        local part = node(c.id)
        n.parts[#n.parts + 1] = { node = part, n = c.n }
        part.uses[#part.uses + 1] = n
      end
    end
  end

  -- Profondeur : 0 pour une matière première, sinon 1 + la plus grande de ses composants.
  local function depth(n, guard)
    if n.depth then return n.depth end
    if not n.r or guard[n] then return 0 end
    guard[n] = true
    local d = 0
    for _, p in ipairs(n.parts) do d = math.max(d, depth(p.node, guard)) end
    guard[n] = nil
    n.depth = d + 1
    return n.depth
  end
  local maxMid = 0
  for _, n in pairs(nodes) do
    n.depth = n.r and depth(n, {}) or 0
    if n.r and #n.uses > 0 then maxMid = math.max(maxMid, n.depth) end
  end

  -- Colonnes : 1 = matières, 2..k-1 = composants par profondeur, k = produits finis.
  local last = math.max(3, maxMid + 2)
  local columns = {}
  for c = 1, last do columns[c] = {} end
  for _, n in pairs(nodes) do
    if not n.r then
      n.col = 1
    elseif #n.uses == 0 then
      n.col = last
    else
      n.col = math.min(last - 1, n.depth + 1)
    end
    table.insert(columns[n.col], n)
  end

  -- Ordre : les produits par bénéfice ; les autres colonnes se rangent en face de ce qu'elles
  -- alimentent, pour que les liens se croisent le moins possible.
  table.sort(columns[last], function(a, b)
    local pa = a.bilan and a.bilan.profit or -math.huge
    local pb = b.bilan and b.bilan.profit or -math.huge
    if pa ~= pb then return pa > pb end
    return a.id < b.id
  end)
  for index, n in ipairs(columns[last]) do n.row = index end
  for c = last - 1, 1, -1 do
    for _, n in ipairs(columns[c]) do
      local sum, count = 0, 0
      for _, u in ipairs(n.uses) do
        if u.row then sum, count = sum + u.row, count + 1 end
      end
      n.weight = count > 0 and sum / count or math.huge
    end
    table.sort(columns[c], function(a, b)
      if a.weight ~= b.weight then return a.weight < b.weight end
      return a.id < b.id
    end)
    for index, n in ipairs(columns[c]) do n.row = index end
  end

  return { nodes = nodes, columns = columns, shown = #products, total = total, candidates = #list }
end

---------------------------------------------------------------------------
-- Construction de l'onglet
---------------------------------------------------------------------------

local function build(parent)
  local f = CreateFrame("Frame", nil, parent)
  local W, H = UI.CONTENT_W - PAD * 2, UI.CONTENT_H
  local ui = ns.db.ui
  if ui.prodKnown == nil then ui.prodKnown = true end
  ui.prodSkill = ui.prodSkill or 0
  ui.prodSearch = ""
  local graph, selected
  local resetScroll = true

  -------------------------------------------------------------------------
  -- Barre de filtres
  -------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, f)
  bar:SetSize(W, 28)
  bar:SetPoint("TOPLEFT", PAD, -16)

  local skillButton = UI.Button(bar, "", 190, 28, function(self)
    local entries = {}
    local skills = ns.PlayerSkills()
    local function entry(id, label)
      entries[#entries + 1] = { label = label, onClick = function()
        ui.prodSkill = id
        selected = nil
        resetScroll = true
        f:Refresh()
      end }
    end
    entry(0, L["Tous mes métiers"])
    local ids = {}
    for id in pairs(ns.DATA.metiers) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
      local ma, mb = skills[a] and 0 or 1, skills[b] and 0 or 1
      if ma ~= mb then return ma < mb end
      return ns.SkillName(a) < ns.SkillName(b)
    end)
    for _, id in ipairs(ids) do
      entry(id, (skills[id] and (UI.Hex("accent") .. "● |r") or "   ") .. ns.SkillName(id))
    end
    UI.Menu(self, entries)
  end)
  skillButton:SetPoint("LEFT", 0, 0)
  local arrow = skillButton:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  arrow:SetRotation(-math.pi / 2)
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -10, 0)
  arrow:SetVertexColor(UI.Color("muted"))

  local knownButton = UI.Button(bar, L["Mes recettes"], 110, 28, function()
    ui.prodKnown = not ui.prodKnown
    selected = nil
    resetScroll = true
    f:Refresh()
  end)
  knownButton:SetPoint("LEFT", skillButton, "RIGHT", 8, 0)

  local profitButton = UI.Button(bar, L["Rentables"], 96, 28, function()
    ui.prodProfit = not ui.prodProfit
    selected = nil
    resetScroll = true
    f:Refresh()
  end)
  profitButton:SetPoint("LEFT", knownButton, "RIGHT", 8, 0)

  local searchBox = CreateFrame("EditBox", nil, bar)
  searchBox:SetSize(190, 28)
  searchBox:SetPoint("LEFT", profitButton, "RIGHT", 8, 0)
  searchBox.bg = UI.Slice(searchBox, "pastille", "card")
  searchBox:SetFont(STANDARD_TEXT_FONT, 12, "")
  searchBox:SetTextColor(UI.Color("text"))
  searchBox:SetTextInsets(12, 12, 0, 0)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(40)
  searchBox.placeholder = UI.Text(searchBox, 12, "faint")
  searchBox.placeholder:SetPoint("LEFT", 12, 0)
  searchBox.placeholder:SetText(L["Chercher un produit…"])
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    self.placeholder:SetShown(text == "")
    if text ~= ui.prodSearch then
      ui.prodSearch = text
      selected = nil
      resetScroll = true
      f:Refresh()
    end
  end)

  local summary = UI.Text(bar, 11, "muted", "RIGHT")
  summary:SetPoint("RIGHT", 0, 0)

  -------------------------------------------------------------------------
  -- Zone du graphe
  -------------------------------------------------------------------------
  local graphW, graphH = W - DETAIL_W - 12, H - 60 - 16
  local graphPanel = UI.Panel(f, graphW, graphH, "panel")
  graphPanel:SetPoint("TOPLEFT", PAD, -60)

  -- Titres des colonnes : ils suivent le défilement latéral et sont rognés aux bords du panneau.
  local titles = {}
  local head = CreateFrame("Frame", nil, graphPanel)
  head:SetPoint("TOPLEFT", 8, -8)
  head:SetSize(graphW - 16, 22)
  head:SetClipsChildren(true)

  local scroll = CreateFrame("ScrollFrame", nil, graphPanel)
  scroll:SetPoint("TOPLEFT", 8, -34)
  scroll:SetSize(graphW - 16, graphH - 42 - 14)
  local canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(graphW - 16, graphH - 42 - 14)
  scroll:SetScrollChild(canvas)

  -- Barre de défilement latéral, visible seulement quand le graphe dépasse.
  local track = UI.Fill(graphPanel, "line", 0.6, "ARTWORK")
  track:SetPoint("BOTTOMLEFT", 8, 8)
  track:SetSize(graphW - 16, 4)
  local thumb = CreateFrame("Button", nil, graphPanel)
  thumb:SetHeight(14)
  thumb.tex = UI.Fill(thumb, "accent", 0.85, "OVERLAY")
  thumb.tex:SetPoint("LEFT")
  thumb.tex:SetPoint("RIGHT")
  thumb.tex:SetHeight(4)

  local function ranges()
    return math.max(0, canvas:GetWidth() - scroll:GetWidth()), math.max(0, canvas:GetHeight() - scroll:GetHeight())
  end

  -- Seul endroit qui déplace la vue : borne les valeurs, replace les titres et la barre.
  local function scrollTo(h, v)
    local hrange, vrange = ranges()
    h = math.max(0, math.min(hrange, h or scroll:GetHorizontalScroll()))
    v = math.max(0, math.min(vrange, v or scroll:GetVerticalScroll()))
    scroll:SetHorizontalScroll(h)
    scroll:SetVerticalScroll(v)
    for _, t in ipairs(titles) do
      if t.x then
        t:ClearAllPoints()
        t:SetPoint("LEFT", head, "LEFT", t.x - h, 0)
      end
    end
    local trackW = graphW - 16
    if hrange > 0 then
      local size = math.max(40, trackW * scroll:GetWidth() / canvas:GetWidth())
      thumb:SetWidth(size)
      thumb:ClearAllPoints()
      thumb:SetPoint("LEFT", track, "LEFT", (trackW - size) * h / hrange, 0)
      thumb:Show()
      track:Show()
    else
      thumb:Hide()
      track:Hide()
    end
  end

  local function cursor()
    local x, y = GetCursorPosition()
    local scale = scroll:GetEffectiveScale()
    return x / scale, y / scale
  end

  -- Molette : haut et bas. Maj + molette, ou molette quand rien ne dépasse en hauteur : gauche et droite.
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local _, vrange = ranges()
    if IsShiftKeyDown() or vrange == 0 then
      scrollTo(self:GetHorizontalScroll() - delta * 90, nil)
    else
      scrollTo(nil, self:GetVerticalScroll() - delta * 60)
    end
  end)

  -- Fond du graphe : on le tire pour se déplacer dans tous les sens ; un simple clic retire la
  -- surbrillance.
  local backdrop = CreateFrame("Button", nil, canvas)
  backdrop:SetAllPoints()
  local drag
  backdrop:SetScript("OnMouseDown", function(self)
    local x, y = cursor()
    drag = { x = x, y = y, h = scroll:GetHorizontalScroll(), v = scroll:GetVerticalScroll(), moved = false }
    self:SetScript("OnUpdate", function()
      local cx, cy = cursor()
      local dx, dy = cx - drag.x, cy - drag.y
      if math.abs(dx) > 3 or math.abs(dy) > 3 then drag.moved = true end
      if drag.moved then scrollTo(drag.h - dx, drag.v + dy) end
    end)
  end)
  backdrop:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    if drag and not drag.moved then
      selected = nil
      f:Paint()
    end
    drag = nil
  end)

  -- Barre du bas : on la tire aussi.
  local barDrag
  thumb:SetScript("OnMouseDown", function(self)
    barDrag = { x = cursor(), h = scroll:GetHorizontalScroll() }
    self:SetScript("OnUpdate", function()
      local hrange = ranges()
      local free = (graphW - 16) - thumb:GetWidth()
      if free > 0 then scrollTo(barDrag.h + (cursor() - barDrag.x) * hrange / free, nil) end
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  thumb:SetScript("OnEnter", function(self) self.tex:SetHeight(6) end)
  thumb:SetScript("OnLeave", function(self) self.tex:SetHeight(4) end)

  local emptyText = UI.Text(graphPanel, 13, "muted", "CENTER")
  emptyText:SetPoint("CENTER", 0, 0)
  emptyText:SetWidth(graphW - 160)
  emptyText:SetWordWrap(true)
  emptyText:SetSpacing(4)

  -------------------------------------------------------------------------
  -- Panneau de détail
  -------------------------------------------------------------------------
  local detail = UI.Panel(f, DETAIL_W, graphH, "panel")
  detail:SetPoint("TOPLEFT", graphPanel, "TOPRIGHT", 12, 0)
  detail.icon = UI.Icon(detail, 38)
  detail.icon:SetPoint("TOPLEFT", 16, -16)
  detail.name = UI.Text(detail, 14, "text")
  detail.name:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 10, -2)
  detail.name:SetWidth(DETAIL_W - 80)
  detail.sub = UI.Text(detail, 11, "muted")
  detail.sub:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
  detail.sub:SetWidth(DETAIL_W - 80)
  detail.hint = UI.Text(detail, 12, "muted", "CENTER")
  detail.hint:SetPoint("CENTER", 0, 0)
  detail.hint:SetWidth(DETAIL_W - 50)
  detail.hint:SetWordWrap(true)
  detail.hint:SetSpacing(4)
  detail.hint:SetText(L["Clique sur un objet du graphe pour allumer sa chaîne de fabrication et voir sa rentabilité."])
  detail.rows = {}
  local function detailRow(i)
    local row = detail.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, detail)
      row:SetSize(DETAIL_W - 32, 20)
      row.left = UI.Text(row, 12, "text")
      row.left:SetPoint("LEFT", 0, 0)
      row.left:SetWidth(DETAIL_W - 32 - 112)
      row.right = UI.Text(row, 12, "text", "RIGHT")
      row.right:SetPoint("RIGHT", 0, 0)
      row.rule = UI.Fill(row, "line", 0.7, "ARTWORK")
      row.rule:SetHeight(1)
      row.rule:SetPoint("TOPLEFT", 0, 4)
      row.rule:SetPoint("TOPRIGHT", 0, 4)
      detail.rows[i] = row
    end
    return row
  end

  local function showDetail(n)
    for _, row in ipairs(detail.rows) do row:Hide() end
    local shown = n ~= nil
    detail.icon:SetShown(shown)
    detail.name:SetShown(shown)
    detail.sub:SetShown(shown)
    detail.hint:SetShown(not shown)
    if not n then return end

    local item = ns.Item(n.id)
    detail.icon:SetItem(n.id)
    detail.name:SetText(item.name or ns.Lf("Objet %d", n.id))
    detail.name:SetTextColor(ns.QualityColor(item.quality))

    local y, index = -70, 0
    local function line(left, right, opts)
      index = index + 1
      local row = detailRow(index)
      opts = opts or {}
      if opts.gap then y = y - 10 end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 16, y)
      row.left:SetText(left)
      row.left:SetTextColor(UI.Color(opts.color or "text"))
      row.right:SetText(right or "")
      row.rule:SetShown(opts.rule == true)
      row:Show()
      y = y - 21
    end

    local holdings = ns.Holdings()[n.id]
    local owned = holdings and holdings.q or 0

    if n.r then
      local r, bilan = n.r, n.bilan or ns.RecipeProfit(n.r)
      local known = ns.db.known[r.spell]
      detail.sub:SetText(ns.SkillName(r.skill) .. (r.lvl > 0 and (" · " .. ns.Lf("niveau %d", r.lvl)) or "") ..
        (known and "" or (" · " .. UI.Hex("red") .. L["non apprise"] .. "|r")))
      line(L["COMPOSANTS"], r.qty > 1 and ns.Lf("pour %d", r.qty) or "", { color = "faint" })
      for _, c in ipairs(r.reag) do
        local cost, src = ns.BestCost(c.id)
        line(c.n .. " × " .. ns.ItemName(c.id),
          cost and (ns.Money(cost * c.n) .. UI.Hex("faint") .. " " .. (SHORT[src] and L[SHORT[src]] or "") .. "|r") or (UI.Hex("red") .. L["prix inconnu"] .. "|r"))
      end
      line(L["Coût de fabrication"], bilan.complete and ns.Money(bilan.cost) or (UI.Hex("red") .. L["incomplet"] .. "|r"), { gap = true, rule = true })
      -- Ce que la fabrication te coûte vraiment : tes composants en stock à leur prix de
      -- revient, les autres au prix du marché.
      local real, mine, realComplete = 0, false, true
      for _, c in ipairs(r.reag) do
        local own = ns.UnitCost and ns.UnitCost(c.id)
        local cost = own or ns.BestCost(c.id)
        if own then mine = true end
        if cost then real = real + cost * c.n else realComplete = false end
      end
      if not (mine and realComplete) then real = nil end
      if real then line("  " .. L["avec ton stock"], ns.Money(real), { color = "muted" }) end
      if bilan.sale then
        line(ns.Lf("Vente (%s)", L[SRC[bilan.saleSrc]]), ns.Money(bilan.sale))
        if bilan.saleSrc == "hv" then
          line(L["Taxe de l'HV (5 %)"], UI.Hex("muted") .. ns.Money(-(bilan.sale - bilan.net)) .. "|r")
        end
      else
        line(L["Vente"], UI.Hex("faint") .. L["aucun prix"] .. "|r")
      end
      if bilan.profit then
        local color = bilan.profit >= 0 and "green" or "red"
        line(L["Bénéfice"], UI.Hex(color) .. ns.Money(bilan.profit, true) .. "|r", { gap = true, rule = true })
        if bilan.margin then
          line(L["Marge"], UI.Hex(color) .. ns.Lf("%+.0f %%", bilan.margin * 100) .. "|r")
        end
      end
      if real and bilan.net then
        local profit = bilan.net - real
        line("  " .. L["avec ton stock"], UI.Hex(profit >= 0 and "green" or "red") .. ns.Money(profit, true) .. "|r", { color = "muted" })
      end
      local market = ns.MarketPrice(n.id)
      if market and bilan.complete and r.qty > 0 then
        local craft = bilan.cost / r.qty
        line(craft < market and L["Moins cher à fabriquer"] or L["Moins cher à acheter"],
          ns.Lf("%s / u", ns.Money(math.abs(market - craft))), { gap = true, color = "muted" })
      end
    else
      detail.sub:SetText(L["Matière première"])
      local market, when, qty = ns.MarketPrice(n.id)
      local vendor = ns.VendorPrice(n.id)
      line(L["PRIX D'ACHAT"], "", { color = "faint" })
      line(L["Hôtel des ventes"], market and ns.Money(market) or (UI.Hex("faint") .. L["aucun prix"] .. "|r"))
      if market then line("  " .. ns.Lf("relevé %s", ns.Ago(when)), qty and ns.Lf("%d en vente", qty) or "", { color = "muted" }) end
      line(L["Marchand"], vendor and ns.Money(vendor) or (UI.Hex("faint") .. "—|r"))
    end
    line(L["En stock"], owned > 0 and tostring(owned) or (UI.Hex("faint") .. "0|r"), { gap = true, rule = true })
    local ownCost = owned > 0 and ns.UnitCost and ns.UnitCost(n.id)
    if ownCost then line(L["Ton coût de revient / u"], ns.Money(ownCost)) end
    if #n.uses == 1 then
      line(L["Sert à 1 recette du graphe"], "", { color = "muted" })
    elseif #n.uses > 1 then
      line(ns.Lf("Sert à %d recettes du graphe", #n.uses), "", { color = "muted" })
    end
  end

  -------------------------------------------------------------------------
  -- Nœuds et liens (réutilisés d'un affichage à l'autre)
  -------------------------------------------------------------------------
  local nodePool, linePool = {}, {}
  local shownNodes, shownLines = {}, {}

  local function acquireNode(i)
    local b = nodePool[i]
    if b then return b end
    b = CreateFrame("Button", nil, canvas)
    b:SetFrameLevel(canvas:GetFrameLevel() + 3)
    b.bg = UI.Slice(b, "pastille", "card")
    b.edge = UI.Slice(b, "pastille", "accent", 1, "BACKGROUND", -1)
    b.edge:ClearAllPoints()
    b.edge:SetPoint("TOPLEFT", -1.5, 1.5)
    b.edge:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
    b.edge:Hide()
    b.icon = UI.Icon(b, 30)
    b.icon:SetPoint("LEFT", 6, 0)
    b.name = UI.Text(b, 12, "text")
    b.name:SetPoint("TOPLEFT", 42, -6)
    b.sub = UI.Text(b, 11, "muted")
    b.sub:SetPoint("BOTTOMLEFT", 42, 6)
    b.count = UI.Text(b, 10, "faint", "RIGHT")
    b.count:SetPoint("TOPRIGHT", -8, -7)
    b:SetScript("OnEnter", function(self)
      UI.Recolor(self.bg, "hover", 1)
      UI.ItemTooltip(self, self.node.id)
    end)
    b:SetScript("OnLeave", function(self)
      UI.Recolor(self.bg, "card", 1)
      GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
      if UI.ItemClick(self.node.id) then return end
      selected = (selected ~= self.node.id) and self.node.id or nil
      f:Paint()
    end)
    nodePool[i] = b
    return b
  end

  local function acquireLine(i)
    local l = linePool[i]
    if not l then
      l = canvas:CreateLine(nil, "ARTWORK")
      linePool[i] = l
    end
    return l
  end

  local function fillNode(b, n, width)
    local item = ns.Item(n.id)
    b.node = n
    b:SetSize(width, NODE_H)
    b.icon:SetItem(n.id)
    b.sub:SetWidth(width - 42 - 6)
    b.name:SetText(item.name or ns.Lf("Objet %d", n.id))
    b.name:SetTextColor(ns.QualityColor(item.quality))
    local holdings = graph.holdings[n.id]
    local owned = holdings and holdings.q > 0
    b.count:SetText(owned and ("×" .. holdings.q) or "")
    -- Le nom prend toute la largeur, sauf la place de la quantité possédée quand il y en a une.
    b.name:SetWidth(width - 42 - (owned and 40 or 8))

    if n.r and #n.uses == 0 then
      -- Produit fini : le bénéfice d'une fabrication.
      local bilan = n.bilan
      if bilan.profit then
        local color = bilan.profit >= 0 and "green" or "red"
        local margin = bilan.margin and ("  " .. ns.Lf("%+.0f %%", bilan.margin * 100)) or ""
        b.sub:SetText(UI.Hex(color) .. ns.Money(bilan.profit, true) .. margin .. "|r")
      elseif not bilan.complete then
        b.sub:SetText(UI.Hex("faint") .. L["coût incomplet"] .. "|r")
      else
        b.sub:SetText(UI.Hex("faint") .. ns.Lf("coût %s · pas de prix de vente", ns.Money(bilan.cost)) .. "|r")
      end
    else
      -- Matière ou composant : le meilleur moyen de se le procurer.
      local cost, src = ns.BestCost(n.id)
      local craft = n.r and n.bilan and n.bilan.complete and (n.bilan.cost / n.r.qty) or nil
      local buy, buySrc = ns.BuyPrice(n.id)
      if craft and buy then
        -- Composant qu'on peut fabriquer ou acheter : les deux prix, le moins cher en premier.
        local a = ns.Money(craft, false, true) .. " " .. L[SHORT.fab]
        local z = ns.Money(buy, false, true) .. " " .. L[SHORT[buySrc]]
        if buy < craft then a, z = z, a end
        b.sub:SetText(a .. UI.Hex("faint") .. " · " .. z .. "|r")
      elseif cost then
        b.sub:SetText(ns.Money(cost) .. UI.Hex("faint") .. " · " .. (SRC[src] and L[SRC[src]] or "") .. "|r")
      else
        b.sub:SetText(UI.Hex("faint") .. L["prix inconnu"] .. "|r")
      end
    end
    if n.r and not ns.db.known[n.r.spell] then
      b.name:SetAlpha(0.75)
    else
      b.name:SetAlpha(1)
    end
  end

  -- Objets de la chaîne de l'objet sélectionné : ce qu'il faut pour le faire, et ce qu'il sert à faire.
  local function chain(n)
    local set = { [n] = true }
    local function up(x)
      for _, p in ipairs(x.parts) do
        if not set[p.node] then
          set[p.node] = true
          up(p.node)
        end
      end
    end
    local function down(x)
      for _, u in ipairs(x.uses) do
        if not set[u] then
          set[u] = true
          down(u)
        end
      end
    end
    up(n)
    local upstream = {}
    for k in pairs(set) do upstream[k] = true end
    down(n)
    return set, upstream
  end

  -- Met à jour les couleurs selon la sélection, sans rien reconstruire.
  function f:Paint()
    local node = selected and graph and graph.nodes[selected]
    if selected and not node then selected = nil end
    local set = node and chain(node)
    for _, b in ipairs(shownNodes) do
      local inChain = not set or set[b.node]
      b:SetAlpha(inChain and 1 or 0.22)
      b.edge:SetShown(node ~= nil and b.node == node)
    end
    for _, l in ipairs(shownLines) do
      if not set then
        l:SetColorTexture(UI.Color("muted", 0.22))
        l:SetThickness(1.2)
      elseif set[l.from] and set[l.to] then
        l:SetColorTexture(UI.Color("accent", 0.95))
        l:SetThickness(2.2)
      else
        l:SetColorTexture(UI.Color("muted", 0.05))
        l:SetThickness(1)
      end
    end
    showDetail(node)
  end

  local COLUMN_TITLES = { first = "MATIÈRES PREMIÈRES", mid = "COMPOSANTS", last = "PRODUITS FINIS" }

  local function layout()
    for _, b in ipairs(shownNodes) do b:Hide() end
    for _, l in ipairs(shownLines) do l:Hide() end
    for _, t in ipairs(titles) do t:Hide() end
    shownNodes, shownLines = {}, {}

    local columns = graph.columns
    local ncol = #columns
    local viewW = scroll:GetWidth()
    local nodeW = math.floor(math.max(184, math.min(216, (viewW - (ncol - 1) * 64) / ncol)))
    local gapX = math.max(48, (viewW - ncol * nodeW) / math.max(1, ncol - 1))
    local canvasW = math.max(viewW, ncol * nodeW + (ncol - 1) * gapX)
    local rows = 0
    for _, col in ipairs(columns) do rows = math.max(rows, #col) end
    local canvasH = math.max(scroll:GetHeight(), rows * (NODE_H + NODE_GAP) + 12)
    canvas:SetSize(canvasW, canvasH)
    -- On garde la position quand les données bougent en arrière-plan ; un changement de filtre
    -- ramène en haut à gauche.
    local keepH, keepV = scroll:GetHorizontalScroll(), scroll:GetVerticalScroll()
    if resetScroll then keepH, keepV = 0, 0 end
    resetScroll = false

    local used = 0
    for c, col in ipairs(columns) do
      local x = (c - 1) * (nodeW + gapX)
      local title = titles[c]
      if not title then
        title = UI.Text(head, 10, "faint")
        titles[c] = title
      end
      title.x = x + 4
      title:SetText(L[c == 1 and COLUMN_TITLES.first or (c == ncol and COLUMN_TITLES.last or COLUMN_TITLES.mid)])
      title:SetShown(#col > 0 or c == 1 or c == ncol)
      for index, n in ipairs(col) do
        used = used + 1
        local b = acquireNode(used)
        n.x, n.y = x, 6 + (index - 1) * (NODE_H + NODE_GAP)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", canvas, "TOPLEFT", n.x, -n.y)
        fillNode(b, n, nodeW)
        b:Show()
        shownNodes[#shownNodes + 1] = b
      end
    end

    local count = 0
    for _, n in pairs(graph.nodes) do
      for _, p in ipairs(n.parts) do
        count = count + 1
        local l = acquireLine(count)
        l.from, l.to = p.node, n
        l:SetStartPoint("TOPLEFT", canvas, p.node.x + nodeW, -(p.node.y + NODE_H / 2))
        l:SetEndPoint("TOPLEFT", canvas, n.x, -(n.y + NODE_H / 2))
        l:Show()
        shownLines[#shownLines + 1] = l
      end
    end
    scrollTo(keepH, keepV)
  end

  function f:Refresh()
    local skills = ns.PlayerSkills()
    if ui.prodSkill == 0 then
      skillButton:SetLabel(L["Tous mes métiers"])
    else
      skillButton:SetLabel(ns.SkillName(ui.prodSkill))
    end
    knownButton:SetActive(ui.prodKnown)
    profitButton:SetActive(ui.prodProfit)

    graph = buildGraph(ui, skills)
    graph.holdings = ns.Holdings()
    layout()

    if graph.shown == 0 then
      local why
      if graph.candidates == 0 and ui.prodKnown then
        why = L["Aucune recette connue ici pour l'instant.\nOuvre ta fenêtre de métier une fois pour que Négoce lise tes recettes, ou désactive « Mes recettes » pour voir toutes celles du métier."]
      elseif graph.candidates == 0 and ui.prodSkill == 0 then
        why = L["Aucun métier de fabrication détecté sur ce personnage.\nChoisis un métier dans le menu pour explorer ses recettes."]
      elseif graph.candidates == 0 then
        why = L["Aucune recette pour ce métier."]
      elseif ui.prodProfit then
        why = L["Aucune recette rentable avec les prix connus.\nUn scan de l'HV récent donne de meilleurs résultats."]
      else
        why = L["Aucun produit ne correspond à la recherche."]
      end
      emptyText:SetText(why)
      emptyText:Show()
      summary:SetText("")
    else
      emptyText:Hide()
      if graph.total > graph.shown then
        summary:SetText(ns.Lf("%d produits les plus rentables sur %d", graph.shown, graph.total))
      elseif graph.shown == 1 then
        summary:SetText(L["1 produit"])
      else
        summary:SetText(ns.Lf("%d produits", graph.shown))
      end
    end
    self:Paint()
  end

  return f
end

ns.AddTab("production", "Production", build)
