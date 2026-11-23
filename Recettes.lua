-- Négoce : recettes. Table des recettes de tous les métiers, recettes que tu connais, coût de
-- fabrication et rentabilité.
local ADDON, ns = ...

ns.recipes = {}   -- [sort] = { spell, skill, lvl, item, qty, reag = { { id, n }, ... } }
ns.byProduct = {} -- [objet] = { recette, ... }

local function register(r)
  if ns.recipes[r.spell] then return end
  -- Une recette qui consomme son propre produit le recharge, elle ne le fabrique pas.
  for _, c in ipairs(r.reag) do
    if c.id == r.item then return end
  end
  ns.recipes[r.spell] = r
  local list = ns.byProduct[r.item]
  if not list then
    list = {}
    ns.byProduct[r.item] = list
  end
  list[#list + 1] = r
end

-- Table générée à partir des données du client (Data/Recettes.lua).
local function loadStatic()
  local data = ns.DATA and ns.DATA.recettes
  if not data then return end
  for spell, skill, lvl, item, qty, reagents in data:gmatch("(%d+);(%d+);(%d+);(%d+);(%d+);([%d:,]+)") do
    local reag = {}
    for id, n in reagents:gmatch("(%d+):(%d+)") do
      reag[#reag + 1] = { id = tonumber(id), n = tonumber(n) }
    end
    register({
      spell = tonumber(spell), skill = tonumber(skill), lvl = tonumber(lvl),
      item = tonumber(item), qty = tonumber(qty), reag = reag,
    })
  end
  ns.DATA.recettes = nil -- la chaîne ne sert plus : on rend la mémoire
end
loadStatic()

-- Recettes apprises en jeu et absentes de la table générée.
ns.AtLogin(function()
  for spell, r in pairs(ns.px.recipes) do
    if not ns.recipes[spell] and r.item and r.reag then
      register({ spell = spell, skill = r.skill, lvl = r.lvl or 0, item = r.item, qty = r.qty or 1, reag = r.reag })
    end
  end
end)

function ns.SkillName(skill)
  local name = ns.DATA and ns.DATA.metiers[skill]
  return name and ns.L[name] or ns.Lf("Métier %s", tostring(skill))
end

---------------------------------------------------------------------------
-- Tes métiers et tes recettes
---------------------------------------------------------------------------

-- { [id du métier] = { name, rank, max } }
function ns.PlayerSkills()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ids = { GetProfessions() }
  for k = 1, 6 do
    local idx = ids[k]
    if idx then
      local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
      if skillLine then out[skillLine] = { name = name, rank = rank or 0, max = maxRank or 0 } end
    end
  end
  return out
end

local function knownSpell(spell)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spell)
    if ok and known then return true end
  end
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, spell)
    if ok and known then return true end
  end
  return false
end

-- À la connexion : le jeu sait parfois dire si une recette est apprise sans ouvrir le métier.
local function probeKnown()
  local skills = ns.PlayerSkills()
  local known = ns.db.known
  for spell, r in pairs(ns.recipes) do
    if skills[r.skill] and not known[spell] and knownSpell(spell) then known[spell] = true end
  end
end
ns.AtLogin(function() C_Timer.After(3, function() ns.Try("recettes", probeKnown) ns.Changed() end) end)

-- Fenêtre de métier ouverte : on lit la liste exacte des recettes apprises.
local function scanTradeSkill()
  local ts = C_TradeSkillUI
  if not (ts and ts.GetAllRecipeIDs and ts.GetRecipeInfo) or not ns.db then return end
  if ts.IsTradeSkillLinked and ts.IsTradeSkillLinked() then return end -- métier d'un autre joueur
  if ts.IsTradeSkillGuild and ts.IsTradeSkillGuild() then return end
  local skill
  if ts.GetBaseProfessionInfo then
    local info = ts.GetBaseProfessionInfo()
    skill = info and (info.professionID or info.parentProfessionID)
  end
  local ids = ts.GetAllRecipeIDs() or {}
  local known = ns.db.known
  for _, id in ipairs(ids) do
    local info = ts.GetRecipeInfo(id)
    if info and info.learned then
      known[id] = true
      if not ns.recipes[id] and ts.GetRecipeSchematic then
        local ok, sch = pcall(ts.GetRecipeSchematic, id, false)
        if ok and sch and sch.outputItemID and sch.reagentSlotSchematics then
          local reag = {}
          for _, slot in ipairs(sch.reagentSlotSchematics) do
            local first = slot.reagents and slot.reagents[1]
            if slot.required ~= false and first and first.itemID and (slot.quantityRequired or 0) > 0 then
              reag[#reag + 1] = { id = first.itemID, n = slot.quantityRequired }
            end
          end
          if #reag > 0 then
            local r = { spell = id, skill = skill, lvl = 0, item = sch.outputItemID, qty = sch.quantityMin or 1, reag = reag }
            ns.px.recipes[id] = { skill = r.skill, item = r.item, qty = r.qty, reag = reag }
            register(r)
          end
        end
      end
    end
  end
  ns.db.knownScan = time()
  ns.Changed()
end

local scanPending = false
local function scheduleTradeSkill()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.5, function()
    scanPending = false
    ns.Try("métier", scanTradeSkill)
  end)
end
ns.On("TRADE_SKILL_SHOW", scheduleTradeSkill)
ns.On("TRADE_SKILL_LIST_UPDATE", scheduleTradeSkill)
ns.On("NEW_RECIPE_LEARNED", function(_, spell)
  if ns.db and spell then
    ns.db.known[spell] = true
    ns.Changed()
  end
end)

---------------------------------------------------------------------------
-- Coûts. Le coût d'un objet est le moins cher de : l'acheter (HV ou marchand), le fabriquer.
-- Les résultats sont gardés le temps d'un affichage ; ns.ResetCosts() les oublie.
---------------------------------------------------------------------------

local memo, visiting = {}, {}
function ns.ResetCosts() memo, visiting = {}, {} end

-- Coût des composants d'une recette pour une fabrication : coût, complet (tous les prix connus).
function ns.RecipeCost(r)
  local total, complete = 0, true
  for _, c in ipairs(r.reag) do
    local cost = ns.BestCost(c.id)
    if cost then total = total + cost * c.n else complete = false end
  end
  return total, complete
end

-- Recette la moins chère pour fabriquer un objet, parmi celles autorisées par allow(recette).
function ns.CheapestRecipe(id, allow)
  local best, bestCost
  for _, r in ipairs(ns.byProduct[id] or {}) do
    if not allow or allow(r) then
      local cost, complete = ns.RecipeCost(r)
      if complete then
        cost = cost / r.qty
        if not bestCost or cost < bestCost then best, bestCost = r, cost end
      elseif not best then
        best = r
      end
    end
  end
  return best, bestCost
end

-- Meilleur coût d'un objet à l'unité : coût, source ("hv", "marchand" ou "fab").
function ns.BestCost(id)
  local m = memo[id]
  if m then return m[1], m[2] end
  local cost, src = ns.BuyPrice(id)
  if not visiting[id] and ns.byProduct[id] then
    visiting[id] = true
    local _, craft = ns.CheapestRecipe(id, ns.costFilter)
    visiting[id] = nil
    if craft and (not cost or craft < cost) then cost, src = craft, "fab" end
  end
  memo[id] = { cost, src }
  return cost, src
end

-- Bilan d'une recette pour une fabrication :
--   { cost, complete, sale = prix de vente de tout ce qui est fabriqué, saleSrc, net, profit, margin }
function ns.RecipeProfit(r)
  local cost, complete = ns.RecipeCost(r)
  local out = { cost = cost, complete = complete }
  local market = ns.MarketPrice(r.item)
  if market and market > 0 then
    out.sale, out.saleSrc = market * r.qty, "hv"
    out.net = out.sale * (1 - ns.AH_CUT)
  else
    local sell = ns.Item(r.item).sell or 0
    if sell > 0 then
      out.sale, out.saleSrc, out.net = sell * r.qty, "marchand", sell * r.qty
    end
  end
  if complete and out.net then
    out.profit = out.net - cost
    if cost > 0 then out.margin = out.profit / cost end
  end
  return out
end
