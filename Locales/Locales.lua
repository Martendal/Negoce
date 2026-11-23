-- Négoce : langues. Le texte français sert de clé ; chaque langue traduit ces clés.
--   L["Patrimoine"]                → texte dans la langue choisie
--   ns.Lf("il y a %d min", 5)      → string.format sur le texte traduit
-- Une clé sans traduction s'affiche en français : outils/test_hors_jeu.lua vérifie qu'il n'en
-- manque aucune.
--
-- La langue suit celle du client (français sur un client frFR, anglais sinon), sauf si le joueur
-- en a choisi une avec /negoce langue (réglage du compte, lu au chargement de l'addon).
-- Les textes sont traduits au moment où ils s'affichent, jamais au chargement des fichiers.
local ADDON, ns = ...

ns.LOCALES = {}

local function clientLanguage()
  return (GetLocale and GetLocale() == "frFR") and "fr" or "en"
end

ns.lang = clientLanguage()

-- pref : "fr", "en" ou nil (langue du client).
function ns.SetLanguage(pref)
  if pref ~= "fr" and pref ~= "en" then pref = nil end
  ns.langPref = pref
  ns.lang = pref or clientLanguage()
end

ns.L = setmetatable({}, {
  __index = function(_, key)
    if ns.lang == "fr" then return key end
    local t = ns.LOCALES[ns.lang]
    return t and t[key] or key
  end,
})

function ns.Lf(key, ...)
  return string.format(ns.L[key], ...)
end
