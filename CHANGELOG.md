# Changelog

All notable changes to **MilkContract** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and the project uses Farming Simulator's four-part version numbers.

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
