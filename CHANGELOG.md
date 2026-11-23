# Négoce changelog

## v1.2.0

- English interface. Négoce follows your game language; type `/negoce language en`, `fr` or `auto` to switch.
- English names for all commands: `help`, `scan`, `tracking`, `tooltip`, `scale`, `minimap`, `errors`, `language`.
- Recipe data updated from the current WoW Forever client.
- Recipes that recharge an item, such as "The Mortar: Reloaded", no longer count as a way to craft it. This gave a wrong profit for the Goblin Mortar.
- Recipes that need an item missing from the game are ignored, instead of showing a cost that is too low.

## v1.1.0

- Cost price: the average cost of each item you own, kept up to date as items come in (loot at 0, purchases at the price paid, crafts at the cost of their reagents) and go out.
- Margin on every auction house sale.
- Cost price, AH price and net margin in item tooltips. Hold Shift for the whole stack.
- `/negoce tracking` lists the latest item movements.

## v1.0.0

- First version: net worth and its chart, portfolio, gold flows by source, AH purchases and sales read from mail invoices, AH price scan, and the Production tab with the recipe graph and the profit of each recipe.
