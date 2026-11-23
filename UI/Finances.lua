-- Négoce : onglet Finances. Patrimoine, courbe, portefeuille, flux d'or, achats et ventes.
local ADDON, ns = ...
local UI = ns.UI

local PAD = 20
local PERIODS = {
  { key = "1j", label = "1 j", seconds = 86400 },
  { key = "7j", label = "7 j", seconds = 7 * 86400 },
  { key = "30j", label = "30 j", seconds = 30 * 86400 },
  { key = "tout", label = "Tout" },
}

local function periodStart(key)
  for _, p in ipairs(PERIODS) do
    if p.key == key and p.seconds then return time() - p.seconds end
  end
  return 0
end

local function signed(amount)
  if not amount then return UI.Hex("faint") .. "—|r" end
  local color = amount > 0 and "green" or (amount < 0 and "red" or "muted")
  return UI.Hex(color) .. ns.Money(amount, true) .. "|r"
end

---------------------------------------------------------------------------
-- Colonnes d'une liste : en-tête cliquable (tri) et cellules de texte alignées.
---------------------------------------------------------------------------

local function buildHeader(parent, cols, onSort)
  local header = CreateFrame("Frame", nil, parent)
  header:SetSize(parent:GetWidth(), 22)
  header.labels = {}
  for _, col in ipairs(cols) do
    local b = CreateFrame("Button", nil, header)
    b:SetSize(col.w, 22)
    b:SetPoint("LEFT", col.x, 0)
    local label = UI.Text(b, 10, "faint", col.justify)
    label:SetAllPoints()
    label:SetText(col.label:upper())
    header.labels[col.key] = label
    if col.sort and onSort then
      b:SetScript("OnClick", function() onSort(col.sort) end)
      b:SetScript("OnEnter", function() label:SetTextColor(UI.Color("text")) end)
      b:SetScript("OnLeave", function() label:SetTextColor(UI.Color("faint")) end)
    end
  end
  return header
end

local function buildCells(row, cols, size)
  row.cells = {}
  for _, col in ipairs(cols) do
    local fs = UI.Text(row, size or 12, "text", col.justify)
    fs:SetPoint("LEFT", col.x, 0)
    fs:SetWidth(col.w)
    row.cells[col.key] = fs
  end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function build(parent)
  local f = CreateFrame("Frame", nil, parent)
  local W = UI.CONTENT_W - PAD * 2
  local ui = ns.db.ui
  ui.period = ui.period or "7j"
  ui.finView = ui.finView or "portefeuille"
  ui.sort = ui.sort or "value"

  -- Chiffres clés
  local cards = {}
  local cardW = (W - 36) / 4
  for i, def in ipairs({ { "total", "PATRIMOINE" }, { "gold", "OR" }, { "stock", "STOCK" }, { "market", "MARCHÉ" } }) do
    local card = UI.Panel(f, cardW, 78, "panel")
    card:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + 12), -16)
    card.label = UI.Text(card, 10, "faint")
    card.label:SetPoint("TOPLEFT", 16, -12)
    card.label:SetText(def[2])
    card.value = UI.Text(card, 19, i == 1 and "accent" or "text")
    card.value:SetPoint("TOPLEFT", 16, -28)
    card.sub = UI.Text(card, 11, "muted")
    card.sub:SetPoint("TOPLEFT", 16, -54)
    card.sub:SetWidth(cardW - 28)
    cards[def[1]] = card
  end

  -- Courbe
  local chartPanel = UI.Panel(f, W, 230, "panel")
  chartPanel:SetPoint("TOPLEFT", PAD, -106)
  local chartTitle = UI.Text(chartPanel, 13, "text")
  chartTitle:SetPoint("TOPLEFT", 16, -13)
  chartTitle:SetText("Évolution du patrimoine")
  local legend = UI.Text(chartPanel, 11, "muted")
  legend:SetPoint("LEFT", chartTitle, "RIGHT", 18, 0)
  legend:SetText(UI.Hex("accent") .. "—|r patrimoine    " .. UI.Hex("blue") .. "—|r or seul")
  local periodEntries = {}
  for _, p in ipairs(PERIODS) do periodEntries[#periodEntries + 1] = { key = p.key, label = p.label } end
  local periods = UI.Segment(chartPanel, periodEntries, function(key)
    ui.period = key
    f:Refresh()
  end, 54, 24)
  periods:SetPoint("TOPRIGHT", -14, -9)
  local chart = UI.Chart(chartPanel, W - 20, 186)
  chart:SetPoint("TOPLEFT", 10, -40)

  -- Vues du bas
  local views = UI.Segment(f, {
    { key = "portefeuille", label = "Portefeuille", w = 120 },
    { key = "flux", label = "Flux d'or", w = 120 },
    { key = "journal", label = "Achats et ventes", w = 140 },
  }, function(key)
    ui.finView = key
    f:Refresh()
  end, 120, 26)
  views:SetPoint("TOPLEFT", PAD, -348)
  local hint = UI.Text(f, 11, "muted", "RIGHT")
  hint:SetPoint("TOPRIGHT", -PAD, -354)

  local listPanel = UI.Panel(f, W, UI.CONTENT_H - 382 - 16, "panel")
  listPanel:SetPoint("TOPLEFT", PAD, -382)
  local listW, listH = W - 16, listPanel:GetHeight() - 36

  -- Portefeuille
  local pfCols = {
    { key = "name", label = "Objet", x = 44, w = 300, sort = "name" },
    { key = "q", label = "Quantité", x = 350, w = 70, justify = "RIGHT", sort = "q" },
    { key = "where", label = "Où", x = 438, w = 190 },
    { key = "cost", label = "Revient / u", x = 630, w = 100, justify = "RIGHT" },
    { key = "unit", label = "Cours / u", x = 736, w = 100, justify = "RIGHT" },
    { key = "value", label = "Valeur", x = 842, w = 96, justify = "RIGHT", sort = "value" },
    { key = "gain", label = "+ / −", x = 942, w = 86, justify = "RIGHT", sort = "gain" },
  }
  local pfHeader = buildHeader(listPanel, pfCols, function(key)
    ui.sort = key
    f:Refresh()
  end)
  pfHeader:SetPoint("TOPLEFT", 8, -8)
  local pfList = UI.List(listPanel, listW, listH, 32, function(row)
    row.icon = UI.Icon(row, 24)
    row.icon:SetPoint("LEFT", 10, 0)
    buildCells(row, pfCols)
    row:HookScript("OnEnter", function(self) if self.item then UI.ItemTooltip(self, self.item.id, "ANCHOR_TOPLEFT") end end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self) if self.item then UI.ItemClick(self.item.id) end end)
  end, function(row, p)
    local item = ns.Item(p.id)
    row.icon:SetItem(p.id)
    row.cells.name:SetText(item.name or ("Objet " .. p.id))
    row.cells.name:SetTextColor(ns.QualityColor(item.quality))
    row.cells.q:SetText(p.q)
    local where = {}
    if p.bags > 0 then where[#where + 1] = "sacs " .. p.bags end
    if p.bank > 0 then where[#where + 1] = "banque " .. p.bank end
    if p.mail > 0 then where[#where + 1] = "courrier " .. p.mail end
    if p.ah > 0 then where[#where + 1] = "en vente " .. p.ah end
    row.cells.where:SetText(table.concat(where, " · "))
    row.cells.where:SetTextColor(UI.Color("muted"))
    if p.unitCost then
      row.cells.cost:SetText(ns.Money(p.unitCost))
    else
      row.cells.cost:SetText(UI.Hex("faint") .. "—|r")
    end
    row.cells.unit:SetText(ns.Money(p.unit) .. (p.src == "marchand" and (UI.Hex("faint") .. " m|r") or ""))
    row.cells.value:SetText(ns.Money(p.value))
    row.cells.gain:SetText(signed(p.gain))
  end)
  pfList:SetPoint("TOPLEFT", 8, -32)

  -- Flux d'or
  local fxCols = {
    { key = "name", label = "Origine", x = 14, w = 210 },
    { key = "bars", label = "", x = 230, w = 400 },
    { key = "i", label = "Entrées", x = 640, w = 120, justify = "RIGHT" },
    { key = "o", label = "Sorties", x = 768, w = 120, justify = "RIGHT" },
    { key = "net", label = "Solde", x = 896, w = 130, justify = "RIGHT" },
  }
  local fxHeader = buildHeader(listPanel, fxCols)
  fxHeader:SetPoint("TOPLEFT", 8, -8)
  local fxList = UI.List(listPanel, listW, listH, 32, function(row)
    buildCells(row, fxCols)
    row.barIn = UI.Fill(row, "green", 0.85, "ARTWORK")
    row.barIn:SetPoint("LEFT", 230, 5)
    row.barOut = UI.Fill(row, "red", 0.85, "ARTWORK")
    row.barOut:SetPoint("LEFT", 230, -5)
  end, function(row, c)
    row.cells.name:SetText(c.label)
    row.cells.i:SetText(c.i > 0 and (UI.Hex("green") .. ns.Money(c.i) .. "|r") or (UI.Hex("faint") .. "—|r"))
    row.cells.o:SetText(c.o > 0 and (UI.Hex("red") .. ns.Money(c.o) .. "|r") or (UI.Hex("faint") .. "—|r"))
    row.cells.net:SetText(signed(c.i - c.o))
    row.barIn:SetSize(math.max(1, 400 * c.i / c.max), 6)
    row.barIn:SetShown(c.i > 0)
    row.barOut:SetSize(math.max(1, 400 * c.o / c.max), 6)
    row.barOut:SetShown(c.o > 0)
  end)
  fxList:SetPoint("TOPLEFT", 8, -32)

  -- Achats et ventes
  local jrCols = {
    { key = "date", label = "Date", x = 14, w = 100 },
    { key = "kind", label = "", x = 118, w = 60 },
    { key = "name", label = "Objet", x = 212, w = 236 },
    { key = "q", label = "Quantité", x = 452, w = 64, justify = "RIGHT" },
    { key = "p", label = "Montant", x = 522, w = 110, justify = "RIGHT" },
    { key = "fees", label = "Taxe", x = 638, w = 86, justify = "RIGHT" },
    { key = "net", label = "Net", x = 730, w = 110, justify = "RIGHT" },
    { key = "cost", label = "Revient", x = 846, w = 86, justify = "RIGHT" },
    { key = "margin", label = "Marge", x = 936, w = 92, justify = "RIGHT" },
  }
  local jrHeader = buildHeader(listPanel, jrCols)
  jrHeader:SetPoint("TOPLEFT", 8, -8)
  local jrList = UI.List(listPanel, listW, listH, 32, function(row)
    row.icon = UI.Icon(row, 24)
    row.icon:SetPoint("LEFT", 180, 0)
    buildCells(row, jrCols)
    row:HookScript("OnEnter", function(self) if self.item and self.item.id then UI.ItemTooltip(self, self.item.id, "ANCHOR_TOPLEFT") end end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, e)
    row.icon:SetItem(e.id)
    row.cells.date:SetText(date("%d/%m %H:%M", e.t))
    row.cells.date:SetTextColor(UI.Color("muted"))
    row.cells.kind:SetText(e.sale and (UI.Hex("green") .. "Vente|r") or (UI.Hex("blue") .. "Achat|r"))
    row.cells.name:SetText(e.n or (e.id and ns.ItemName(e.id)) or "?")
    row.cells.q:SetText(e.q or (UI.Hex("faint") .. "—|r"))
    row.cells.p:SetText(ns.Money(e.p))
    row.cells.fees:SetText(e.sale and (e.cut or 0) > 0 and ns.Money(e.cut) or (UI.Hex("faint") .. "—|r"))
    row.cells.net:SetText(signed(e.sale and (e.net or e.p) or -e.p))
    -- Marge d'une vente : prix moins la taxe de l'HV, moins ce que les objets t'avaient coûté.
    if e.sale and e.cr then
      row.cells.cost:SetText(ns.Money(e.cr))
      row.cells.margin:SetText(signed(e.p - (e.cut or 0) - e.cr))
    else
      row.cells.cost:SetText(UI.Hex("faint") .. "—|r")
      row.cells.margin:SetText(UI.Hex("faint") .. "—|r")
    end
  end)
  jrList:SetPoint("TOPLEFT", 8, -32)

  local lists = {
    portefeuille = { pfHeader, pfList },
    flux = { fxHeader, fxList },
    journal = { jrHeader, jrList },
  }

  -------------------------------------------------------------------------
  -- Remplissage
  -------------------------------------------------------------------------

  local function refreshCards(since)
    local db = ns.db
    local gold = GetMoney()
    local positions = ns.Positions()
    local stock, lines = 0, 0
    for _, p in ipairs(positions) do
      stock = stock + p.value
      lines = lines + 1
    end
    local mailGold = db.mail and db.mail.money or 0
    local total = gold + stock + mailGold

    cards.total.value:SetText(ns.Money(total))
    -- Variation depuis le début de la période : dernier point connu avant, sinon le premier après.
    local base
    for _, pt in ipairs(db.wealth) do
      if pt.t <= since or not base then base = pt end
      if pt.t > since then break end
    end
    if base and #db.wealth > 1 then
      cards.total.sub:SetText(signed(total - (base.g + base.s + (base.m or 0))) .. " sur la période")
    else
      cards.total.sub:SetText("suivi démarré à l'instant")
    end

    cards.gold.value:SetText(ns.Money(gold))
    cards.gold.sub:SetText(mailGold > 0 and ("+ " .. ns.Money(mailGold) .. " au courrier") or "en poche")

    cards.stock.value:SetText(ns.Money(stock))
    local bank = db.bank and ("banque vue " .. ns.Ago(db.bank.updated)) or "banque jamais vue : ouvre-la une fois"
    cards.stock.sub:SetText(lines .. " objets · " .. bank)

    local market = ns.Market()
    if market.scan then
      cards.market.value:SetText((market.count or 0) .. " prix")
      cards.market.sub:SetText("relevés " .. ns.Ago(market.scan))
    else
      cards.market.value:SetText("Aucun prix")
      cards.market.sub:SetText("à l'HV : « Négoce : scanner les prix »")
    end
    return positions
  end

  local function refreshChart(since)
    local points = {}
    for _, pt in ipairs(ns.db.wealth) do
      if pt.t >= since then
        points[#points + 1] = { t = pt.t, a = pt.g + pt.s + (pt.m or 0), b = pt.g }
      end
    end
    chart:SetSeries(points, "Patrimoine", "Or")
  end

  local function refreshPortfolio(positions)
    local key = ui.sort
    table.sort(positions, function(a, b)
      if key == "name" then
        return (ns.Item(a.id).name or "") < (ns.Item(b.id).name or "")
      end
      local va, vb = a[key] or -math.huge, b[key] or -math.huge
      if va ~= vb then return va > vb end
      return a.id < b.id
    end)
    local gain, hasGain = 0, false
    for _, p in ipairs(positions) do
      if p.gain then gain, hasGain = gain + p.gain, true end
    end
    hint:SetText(hasGain and ("Marge si tu vendais tout, taxe de l'HV déduite : " .. signed(gain)) or
      "Le prix de revient se calcule dès que tes sacs ont été lus.")
    pfList:SetData(positions, "Rien en stock pour l'instant.")
  end

  local function refreshFlows(since)
    local totals = ns.FlowTotals(since)
    local rows, max, inSum, outSum = {}, 1, 0, 0
    for cat, c in pairs(totals) do
      rows[#rows + 1] = { label = ns.CATEGORIES[cat] or cat, i = c.i, o = c.o }
      max = math.max(max, c.i, c.o)
      inSum, outSum = inSum + c.i, outSum + c.o
    end
    for _, r in ipairs(rows) do r.max = max end
    table.sort(rows, function(a, b) return (a.i + a.o) > (b.i + b.o) end)
    hint:SetText("Sur la période : " .. signed(inSum - outSum))
    fxList:SetData(rows, "Aucun mouvement d'or sur la période.")
  end

  local function refreshJournal(since)
    local rows = {}
    for _, e in ipairs(ns.db.purchases) do
      if e.t >= since then rows[#rows + 1] = e end
    end
    local profit, counted = 0, 0
    for _, e in ipairs(ns.db.sales) do
      if e.t >= since then
        e.sale = true
        rows[#rows + 1] = e
        if e.cr then profit, counted = profit + e.p - (e.cut or 0) - e.cr, counted + 1 end
      end
    end
    table.sort(rows, function(a, b) return a.t > b.t end)
    if counted > 0 then
      hint:SetText("Bénéfice réalisé sur " .. counted .. " vente" .. (counted > 1 and "s" or "") .. " : " .. signed(profit))
    else
      hint:SetText("Lu sur les factures de l'HV quand tu ouvres ta boîte aux lettres.")
    end
    jrList:SetData(rows, "Aucun achat ni vente à l'HV sur la période.")
  end

  function f:Refresh()
    local since = periodStart(ui.period)
    periods:Select(ui.period)
    views:Select(ui.finView)
    local positions = refreshCards(since)
    refreshChart(since)
    for key, pair in pairs(lists) do
      pair[1]:SetShown(key == ui.finView)
      pair[2]:SetShown(key == ui.finView)
    end
    if ui.finView == "flux" then
      refreshFlows(since)
    elseif ui.finView == "journal" then
      refreshJournal(since)
    else
      refreshPortfolio(positions)
    end
  end

  return f
end

ns.AddTab("finances", "Finances", build)
