#!/usr/bin/env python3
"""Génère Data/Recettes.lua à partir des tables du client WoW Forever.

Les tables viennent de wago.tools (produit « wowf ») :
    https://wago.tools/db2/<Table>/csv?branch=wowf
Tables lues : SkillLine (locale frFR), SkillLineAbility, SpellReagents, SpellEffect, ItemSparse.

Usage :
    python3 outils/generer_donnees.py            # télécharge puis génère
    python3 outils/generer_donnees.py <dossier>  # utilise des CSV déjà téléchargés
"""
import csv
import os
import sys
import tempfile
import urllib.request

BRANCHE = "wowf"
RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORTIE = os.path.join(RACINE, "Data", "Recettes.lua")
TABLES = ["SkillLine", "SkillLineAbility", "SpellReagents", "SpellEffect", "ItemSparse"]

# Catégories de SkillLine : 11 = métiers principaux, 9 = métiers secondaires.
CATEGORIES = {"9", "11"}
EFFET_CREER_OBJET = "24"

# Composants vendus par les marchands en stock illimité (fil, teintures, fioles, fondants,
# épices...). Les tables du client ne disent pas qui vend quoi : cette liste est tenue à la
# main, et l'addon la complète en jeu chaque fois que tu ouvres un marchand.
MARCHANDS = [
    2320, 2321, 4291, 8343, 14341,                      # fils
    2324, 2325, 2604, 2605, 6260, 4340, 4341, 4342, 6261, 10290,  # teintures et décolorant
    3371, 3372, 8925, 18256,                            # fioles
    2880, 3466, 3857, 18567,                            # fondants, charbon
    4289,                                               # sel
    6217, 4470, 11291,                                  # bâtonnet de cuivre, bois
    2678, 2692, 3713, 159, 1179, 17194, 2665, 2596, 2894,  # épices et boissons de cuisine
    4399, 4400, 10647, 10648,                           # crosses, parchemin, encre d'ingénieur
    2928, 2930, 8924, 8923, 5173,                       # composants de poisons
    6530, 6529,                                         # pêche
]


def telecharger(dossier):
    for table in TABLES:
        url = f"https://wago.tools/db2/{table}/csv?branch={BRANCHE}"
        if table == "SkillLine":
            url += "&locale=frFR"
        chemin = os.path.join(dossier, table + ".csv")
        print("téléchargement", table)
        requete = urllib.request.Request(url, headers={"User-Agent": "generer-donnees"})
        with urllib.request.urlopen(requete, timeout=300) as reponse, open(chemin, "wb") as f:
            f.write(reponse.read())


def lire(dossier, table):
    chemin = os.path.join(dossier, table + ".csv")
    if table == "SkillLine" and os.path.exists(os.path.join(dossier, "SkillLine_fr.csv")):
        chemin = os.path.join(dossier, "SkillLine_fr.csv")
    with open(chemin, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def generer(dossier):
    metiers = {
        l["ID"]: l["DisplayName_lang"]
        for l in lire(dossier, "SkillLine")
        if l["CategoryID"] in CATEGORIES and "DNT" not in l["DisplayName_lang"]
    }

    composants = {}
    for l in lire(dossier, "SpellReagents"):
        liste = []
        for i in range(8):
            objet, nombre = int(l[f"Reagent_{i}"]), int(l[f"ReagentCount_{i}"])
            if objet > 0 and nombre > 0:
                liste.append((objet, nombre))
        if liste:
            composants[l["SpellID"]] = liste

    produits = {}
    for l in lire(dossier, "SpellEffect"):
        if l["Effect"] == EFFET_CREER_OBJET and int(l["EffectItemType"]) > 0:
            quantite = max(1, int(round(float(l["EffectBasePointsF"] or 0))))
            produits.setdefault(l["SpellID"], (int(l["EffectItemType"]), quantite))

    objets = {l["ID"]: l for l in lire(dossier, "ItemSparse")}

    lignes, vus, utilises = [], set(), set()
    for l in lire(dossier, "SkillLineAbility"):
        sort, metier = l["Spell"], l["SkillLine"]
        if metier not in metiers or sort not in composants or sort not in produits:
            continue
        if (sort, metier) in vus:
            continue
        objet, quantite = produits[sort]
        if str(objet) not in objets:
            continue
        # Une recette qui consomme son propre produit (« Le mortier : rechargé ») le recharge,
        # elle ne le fabrique pas : on l'écarte.
        if any(o == objet for o, _ in composants[sort]):
            continue
        # Un composant absent des objets du jeu : la recette n'est pas faisable, et la garder
        # sans lui donnerait un coût trop bas.
        if any(str(o) not in objets for o, _ in composants[sort]):
            continue
        liste = composants[sort]
        vus.add((sort, metier))
        utilises.add(metier)
        niveau = int(l["TrivialSkillLineRankLow"] or 0) or int(l["MinSkillLineRank"] or 0)
        lignes.append((int(metier), niveau, int(sort), objet, quantite, liste))
    lignes.sort()

    marchands = []
    for objet in MARCHANDS:
        l = objets.get(str(objet))
        if not l:
            continue
        prix, lot = int(l["BuyPrice"]), max(1, int(l["VendorStackCount"]))
        if prix > 0:
            marchands.append((objet, -(-prix // lot)))

    os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
    with open(SORTIE, "w", encoding="utf-8") as f:
        f.write("-- Fichier généré par outils/generer_donnees.py : ne pas modifier à la main.\n")
        f.write(f"-- Source : tables du client WoW Forever (wago.tools, produit {BRANCHE}).\n")
        f.write("local _, ns = ...\n\n")
        f.write("ns.DATA = ns.DATA or {}\n\n")
        f.write("-- [id du métier] = nom\n")
        f.write("ns.DATA.metiers = {\n")
        for ident in sorted(utilises, key=int):
            f.write(f'  [{ident}] = "{metiers[ident]}",\n')
        f.write("}\n\n")
        f.write("-- [objet] = prix d'achat chez le marchand, à l'unité, en cuivre\n")
        f.write("ns.DATA.marchands = {\n")
        for objet, prix in marchands:
            f.write(f"  [{objet}] = {prix},\n")
        f.write("}\n\n")
        f.write("-- Une recette par ligne : sort;métier;niveau;objet créé;quantité;composant:nombre,...\n")
        f.write("ns.DATA.recettes = [[\n")
        for metier, niveau, sort, objet, quantite, liste in lignes:
            comp = ",".join(f"{o}:{n}" for o, n in liste)
            f.write(f"{sort};{metier};{niveau};{objet};{quantite};{comp}\n")
        f.write("]]\n")
    print(f"{len(lignes)} recettes, {len(utilises)} métiers, {len(marchands)} prix marchands -> {SORTIE}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        generer(sys.argv[1])
    else:
        with tempfile.TemporaryDirectory() as dossier:
            telecharger(dossier)
            generer(dossier)
