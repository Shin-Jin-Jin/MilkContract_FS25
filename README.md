# MilkContract (FS25)

A Farming Simulator 25 mod that turns plain milk selling into a proper little business: sign supply contracts with a range of dairies, each with its own price, quotas, payout rhythm and terms. While a contract runs, the agreed amount is collected from your barn automatically every day and paid at the contract price.

Works for **cow milk** and **buffalo milk** (barn tank) and **goat milk** (pallet pickup), with a cow/goat/buffalo switch in the menu and one contract per milk type at a time.

## Features

- Milk contract system with many different dairies
- Fixed prices, minimum or maximum quotas, and four payout intervals (monthly / quarterly / half-yearly / yearly)
- Daily automatic pickup straight from the barn storage; surplus stays in storage for you to sell yourself
- Rotating offers, freshly assembled every year (base dairy + random selection per milk type)
- Random contract durations (3–24 months) with a price bonus for longer commitment (contracts with obligations)
- Strict price ladder: the more a dairy demands, the more it pays — all prices scale with the game's milk price
- Timely notice before a contract ends, plus renewal on the old terms with a loyalty bonus
- Support for **cow, goat AND buffalo milk** — tank for cow/buffalo, spawned pallets for goat
- Cow/goat/buffalo switch in the menu (native page selector); a separate contract per milk type
- Shortfall penalty on unmet minimum quotas, shown up front at signing
- Dynamic quotas and requirements (incl. herd health and a young-animal share): per-dairy variance spans, rolled each year and fixed on the contract
- Non-fulfilment handling: on renewal the shortfall is carried over as a redelivery target instead of a cash penalty
- Early cancellation for a termination fee, with a confirmation dialog
- Confirmation dialogs before signing, renewing and cancelling
- HUD messages on payout, expiry, expiry warning, renewal and penalty
- Animal-welfare requirements (herd health) at the premium dairies
- Saveable and multiplayer-ready (server-authoritative; offers are seed-deterministic)

## Dairies

### Cow milk

| Dairy | Price (× milk price) | Quantity | Payout | Requirements |
|---|---|---|---|---|
| Discount Dairy | 0.95× (fixed) | free | monthly | - |
| Cooperative | 1.00× (market-linked) | free | monthly | - |
| Alpine Dairy Co-op | 1.03× (market-linked) | free | quarterly | - |
| Market Trader | 1.05× (market-linked) | free | monthly | - |
| World Market Export | 1.06× (market-linked) | free | quarterly | - |
| Klein Farm Dairy | 1.10× (fixed) | max 4000 l/mo (±800) | monthly | - |
| FreshLogistics Inc. | 1.14× (fixed) | min 70% (±15) | monthly | - |
| South Cheese Works | 1.16× (fixed) | min 55% (±10) | half-yearly | - |
| Nordmilch Plant | 1.18× (fixed) | min 85% (±10) | half-yearly | - |
| BioLand Dairy | 1.32× (fixed) | min 60% (±12) | yearly | health >=80% |
| Weidehof Manufactory | 1.48× (fixed) | min 50% (±10) | yearly | health >=85%, young >=15% (<12 M) |
| Demeter Farm | 1.52× (fixed) | min 45% (±8) | yearly | health >=90%, young >=15% (<15 M) |

### Goat milk

| Dairy | Price (× milk price) | Quantity | Payout | Requirements |
|---|---|---|---|---|
| Creekside Goat Farm | 1.02× (market-linked) | free | monthly | - |
| Goat Farm Shop | 1.04× (market-linked) | free | monthly | - |
| Goat-Milk Export | 1.06× (market-linked) | free | quarterly | - |
| Goat-Milk Soap Workshop | 1.13× (market-linked) | min 55% | quarterly | - |
| Regional Goat Dairy | 1.14× (market-linked) | min 70% | monthly | - |
| Hillside Fresh Cheesery | 1.15× (market-linked) | min 60% | monthly | - |
| Bergblick Goat Cheesery | 1.16× (market-linked) | min 60% (±12) | half-yearly | - |
| Alpengold Fine Cheesery | 1.18× (market-linked) | min 65% (±12) | half-yearly | - |
| Goat-Milk Natural Cosmetics | 1.31× (market-linked) | min 50% (±10) | yearly | health >=80% |
| Gourmet Goat Delicacies | 1.32× (market-linked) | min 40% (±10) | half-yearly | health >=85% |
| Demeter Goat Farm | 1.33× (market-linked) | min 45% (±8) | yearly | health >=90% |
| Sonnenwiese Organic Goat Farm | 1.48× (market-linked) | min 50% (±10) | yearly | health >=85%, young >=12% (<10 M) |

### Buffalo milk

| Dairy | Price (× milk price) | Quantity | Payout | Requirements |
|---|---|---|---|---|
| Riverside Buffalo Farm | 1.02× (market-linked) | free | monthly | - |
| Buffalo Farm Shop | 1.04× (market-linked) | free | monthly | - |
| Buffalo-Milk Export | 1.06× (market-linked) | free | quarterly | - |
| Buffalo Gelateria | 1.12× (market-linked) | min 50% (±10) | quarterly | - |
| Ricotta Cheesery | 1.13× (market-linked) | min 55% (±12) | monthly | - |
| Regional Buffalo Dairy | 1.14× (market-linked) | min 70% (±10) | monthly | - |
| Mozzarella Workshop | 1.15× (market-linked) | min 60% (±12) | half-yearly | - |
| South Buffalo Cheesery | 1.16× (market-linked) | min 60% (±12) | half-yearly | - |
| Buffalo Fine Cheesery | 1.18× (market-linked) | min 65% (±10) | half-yearly | - |
| Gourmet Buffalo Delicacies | 1.31× (market-linked) | min 40% (±10) | half-yearly | health >=85% |
| Delicatessen Dairy | 1.32× (market-linked) | min 50% (±10) | yearly | health >=85% |
| Organic Buffalo Farm | 1.50× (market-linked) | min 45% (±8) | yearly | health >=90%, young >=12% (<10 M) |

> Every price is a factor on the game's own milk price for that fill type, so contracts scale with the economy difficulty. Fixed-price dairies lock their price per liter at signing; market-linked ones follow the milk price. The ladder is strict per milk type: no-obligation < maximum cap < minimum quota < quota + herd health < quota + health + young-animal share. Contracts with obligations get a term bonus of +0.5 % per month above 3 months (max +10.5 % at 24 months); the bands are spaced so the bonus never lets a lower tier overtake a higher one. Terms are rolled per offer (3–24 months). Values live in `molkereien.xml` and can be edited without touching code.

## How it works

- **Signing** — pick a dairy for the current milk type and confirm. You need a barn that currently produces that milk type; otherwise a dialog explains what is missing. Duration and bonus price (and, for fixed-price dairies, the price per liter) are locked in at signing.
- **Delivery** — each in-game day the contract takes the agreed milk from the barn (cow: tank; goat: pallets) and credits it at the contract price.
- **Payout** — accrued money is paid out on the contract-relative rhythm (and always at contract end).
- **Expiry & renewal** — in the last month you're warned and can renew on the old terms plus a loyalty bonus. If a minimum quota wasn't met, renewing carries the shortfall over as extra target (new target = normal target + carry-over); letting it lapse instead charges the shortfall penalty.
- **Early cancellation** — possible any time with a confirmation dialog; contracts with obligations charge a termination fee (remaining contract value × 1.2), no-obligation contracts are free to cancel.
- **Supply warning** — if a running contract's barn is gone or stops producing milk, you get a one-time message.

## Installation

1. Download the mod `.zip`.
2. Place it in your FS25 `mods` folder.
3. Enable **MilkContract** in the in-game mod selection.
4. Open the in-game menu and select the **Milk Contract** page.

## Compatibility

- Cow husbandries use the milk-tank specialization; goat (and similar pallet-output) husbandries use the pallet specialization — both are detected automatically.
- Compatible with mods that change goat milk into a bulk/IBC-tank pallet, since the mod reads and drains whatever pallet the husbandry spawns for that fill type.

## Console commands (testing)

Open the developer console (`~`) — state-changing commands run on host / single-player only:

| Command | Description |
|---|---|
| `mcStatus` | Overview: offers per milk type, active contracts, market prices |
| `mcStalls` | Barns & volumes per milk type (tank vs pallets) |
| `mcRotate` / `mcReroll` | Rotate / re-roll the current offer |
| `mcPeriod` | Advance one month (triggers payout, expiry, end, yearly rotation) |
| `mcSign <dairyId>` | Sign a contract immediately (no arg lists all IDs) |
| `mcCancel [cow\|goat]` | Cancel a contract (no arg cancels all) |
| `mcExtend [cow\|goat]` | Extend a contract |

## Configuration

All dairies and their conditions live in `molkereien.xml` (data-driven). Tunable constants in the scripts: default penalty factor, loyalty bonus, early-cancellation factor, and the duration/offer ranges.

## Version

Mod version 1.0.0.0 · modDesc `descVersion="115"` (FS25)

## License / Credits

Author: Shin_Jin_Jin. Uses only standard GIANTS engine interfaces. Not affiliated with GIANTS Software.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.
