# Négoce

Addon pour **WoW Forever** : ton entreprise dans le jeu. Patrimoine, portefeuille, prix de l'hôtel
des ventes, prix de revient et rentabilité des recettes de métier. Il observe et calcule, il
n'achète ni ne vend jamais à ta place. Interface en français.

*An addon for WoW Forever that tracks your gold, auction house prices, cost price of your items
and profitability of profession recipes. French interface only for now.*

## Utilisation

- **Ouvrir** : bouton de la minicarte, ou `/negoce` (`/ng`).
- **Prix de l'HV** : à l'hôtel des ventes, bouton « Négoce : scanner les prix ». Tes recherches
  mettent aussi les prix à jour.
- **Finances** : patrimoine (or + stock) et sa courbe, portefeuille avec coût de revient moyen
  par objet, flux d'or, achats et ventes avec la marge de chaque vente. Le coût de revient
  apparaît aussi dans l'infobulle des objets.
- **Production** : graphe des recettes (matières, composants, produits finis), coût et bénéfice
  de chaque recette, recettes que tu connais ou toutes celles du métier.

## Développement

| Élément | Rôle |
|---|---|
| `Data/Recettes.lua` | table des recettes, générée par `outils/generer_donnees.py` (tables du client sur wago.tools, produit `wowf`) : à relancer après un patch |
| `Art/` | textures, générées par `outils/generer_textures.py` |
| `outils/test_hors_jeu.lua` | essai de la logique contre une fausse API : `lua outils/test_hors_jeu.lua` |
| `.pkgmeta` | construction du .zip par le [packager de BigWigs](https://github.com/BigWigsMods/packager) |

Les bibliothèques (`Libs/` : LibStub, CallbackHandler, LibDataBroker, LibDBIcon) ne sont pas
dans le dépôt : le packager les ajoute au .zip. Pour jouer depuis une copie du dépôt, récupère
le .zip publié ou copie ces bibliothèques depuis un autre addon.

## Publier une version

1. Mettre le même numéro dans `Negoce.toc` (`## Version`) et `Core.lua` (`ns.VERSION`).
2. Commit, puis tag et push : `git tag v1.2.0 && git push && git push origin v1.2.0`.
3. L'action GitHub *Publier* lance le test hors jeu, construit le .zip et l'envoie sur
   CurseForge.
