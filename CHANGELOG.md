# Changelog

All notable changes to **MilkContract** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and the project uses Farming Simulator's four-part version numbers.

## [1.0.0.0]

First public Modhub release.

### Modhub review round 2
- **Warning when no milk-producing barn exists**: clicking "Sign contract" without a barn for that milk type — or with a barn whose animals currently give no milk — now opens a dialog explaining what is missing, instead of silently doing nothing. The detail panel shows the same hint in a warning colour.
- **Barn detection no longer depends on `hasMilkProduction`**: tank barns are recognised by the milk fill types they can deliver; actual production is checked via `litersPerHour`. Signing with zero production is blocked (it would have produced a 0 l minimum target).
- **Supply warning for running contracts**: if the barn is sold/removed or stops producing milk, a one-time message is shown (re-armed once milk flows again).
- **Price rebalancing**: no-obligation contracts could pay more than contracts with requirements (e.g. World Market Export 2.63 €/l vs. Weidehof Manufactory 2.15 €/l), because fixed prices were absolute € values while market prices scale with the game's milk price/economy difficulty, and every contract got the term bonus. Now:
  - All prices are factors on the game's milk price; fixed-price dairies lock their € price per liter at signing.
  - Strict ladder per milk type: no-obligation (0.95–1.06×) < maximum cap (1.10×) < minimum quota (1.12–1.18×) < quota + herd health (1.31–1.33×) < quota + health + young-animal share (1.48–1.52×).
  - Term bonus (now +0.5 %/month above 3, max +10.5 %) and renewal loyalty bonus apply only to contracts with obligations; the bands are spaced so no term lets a lower tier overtake a higher one.
  - The menu now shows a concrete €/l price for every dairy (`~` = market-linked), so offers are directly comparable.
- **Multiplayer**: clients now receive the full contract state (deliveries, payouts, requirements) and get real contract objects, so the menu status and cancel fee work on clients; state is re-synced daily and at every period change.
- `descVersion` 114 -> 115.
- Savegames: fixed-price contracts from earlier test versions are migrated to the new relative price on load.

### Added
- **In-menu "no matching barn" warning**: selecting a dairy whose milk type you have no barn for now shows the hint directly in the Milk Contract page's detail panel, instead of an easy-to-miss HUD side notification on another page.
- **Progress line for maximum-cap ("free up to X/month") contracts**: shows the current month's usage against the cap *and* the running total delivered (`0 / 3,862 l (0 %) (this month) · total 40 l`), so the line stays meaningful even right after a period reset.

### Fixed
- **Maximum-cap contracts collected only a fraction of the cap**: the monthly limit was wrongly scaled by `daysPerPeriod / 30`, shrinking e.g. a 3,862 l/month cap to ~129 l at the default 1 day per month. The monthly cap now applies per period as intended, so a contract that should fill within a month actually does.
- Savegames created with the old, shrunken cap are self-healed on load.
- The "no matching barn" status text is no longer truncated in the detail panel (value field widened, texts shortened).

### Changed
- Version bumped 0.4.1.0 -> 1.0.0.0; `descVersion` 111 -> 114 (-> 115 in review round 2).
- Mod title capitalized ("Milk Contract" / "Milchvertrag").
- Early cancellation of a no-obligation ("free") contract no longer charges a termination penalty.
- A contract can no longer be signed without owning a barn that produces the matching milk type.
- Removed the embedded changelog from the modDesc description, removed debug log output, fixed GUI colour-preset warnings, and resized the menu icon to a power-of-two texture for the Modhub release.

## [0.4.1.0]

### Added
- **Dynamic quotas and requirements**: each dairy can define a variance span in `molkereien.xml` (`percentVariance`, `litersVariance`, and `variance` on health/young). A concrete value is rolled within the span when the yearly offer is built (seed-deterministic, MP-safe) and fixed on the contract at signing.
- **Young-animal requirement** (`minYoungShare`): a dairy can require a minimum share of the herd to be younger than a per-dairy age limit; sampled over the contract term like herd health.
- `mcAnimals` console command to dump raw animal clusters (age, health, count) for diagnostics.

### Fixed
- Herd-health check now reads the correct husbandry per milk type (previously always read cow barns).
- Removed the last `pcall` (empty-pallet deletion now calls delete directly, so errors are visible).

### Changed
- Version bumped 0.4.0.0 -> 0.4.1.0; docs updated.

## [0.4.0.0]

### Added
- **Buffalo milk** as a full third milk type (`milkType="buffalo"`, fill type `BUFFALOMILK`, tank-based like cow milk).
- 12 buffalo dairies with buffalo-typical themes (mozzarella, fine cheese, ricotta, gelateria, delicacies …), all market-priced.
- Menu selector now pages through **cow / goat / buffalo**; one contract per milk type can run at the same time (up to three in parallel).
- **Dynamic quotas and requirements**: each dairy can define a variance span in `molkereien.xml` (`percentVariance`, `litersVariance`, and `variance` on health/calf). When the yearly offer is built, a concrete value is rolled within the span (seed-deterministic, MP-safe) and fixed on the contract at signing.
- Diagnostic console command `mcStalls` now lists **every** milk-producing husbandry by its real fill-type name (cow/goat/buffalo and any others), with kind, daily amount, storage and market price.

### Changed
- README and in-game help updated for three milk types; version bumped 0.3.0.0 → 0.4.0.0.

### Notes
- Savegame format extended (`effQuotaPercent`, `effHealth`, `effCalf`). Saves from 0.3.x load with sensible defaults; existing contracts keep their base conditions.

## [0.3.0.0]

### Added
- **Goat milk** support (pallet-based husbandries via `spec_husbandryPallets`; contract milk is drained from the spawned pallets).
- Fill-type-aware backend: husbandry detection, daily estimate, stored volume and market price resolve per fill type (MILK / GOATMILK).
- 12 goat dairies (market-priced) with goat-typical themes; cow line-up unchanged at 12 → 24 dairies total.
- Parallel contracts: one contract per farm **and** milk type; native cow/goat page selector in the menu.
- Non-fulfilment penalty on unmet minimum quotas (general default factor), shown as its own detail row at signing.
- Renewal carries the shortfall over as extra target (redelivery) instead of a cash penalty; letting the contract lapse charges the penalty.
- Early cancellation against a termination fee (remaining value × 1.2), with a confirmation dialog.
- Confirmation dialogs before signing, renewing and cancelling.
- HUD notification when a contract ends unfulfilled, including the exact penalty amount.
- Native help pages in the game's help menu (via modDesc `<helpLines>`).

### Fixed
- Register `milkType` / `fillType` / `duration` in the XML schema (goat dairies were read as cow).
- Console command callbacks receive `self` as the first argument.
- Replace characters missing from the font (en dash, `≥`).

### Notes
- **Breaking:** savegame format extended (`milkType`, `priceBonus`, `carriedDebt`, `offerSeed`). Saves from 0.2.x load with defaults, but contracts created before this version may reset — back up your savegame before updating.

## [0.2.0.0]

### Added
- Milk contract system with several cow dairies (price, minimum/maximum quota, payout interval, animal-welfare requirements).
- Daily automatic pickup from the barn storage; surplus stays in storage.
- In-game menu page with dairy list and contract status.
- Dynamic offers (base dairy + random selection), yearly rotation.
- Random contract durations with a price bonus for longer terms.
- Payout intervals (monthly / quarterly / half-yearly / yearly), contract-relative.
- Renewal with loyalty bonus and expiry warning.
- Persistence and multiplayer support (server-authoritative).
