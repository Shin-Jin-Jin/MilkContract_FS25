# MilkContract (FS25)

A Farming Simulator 25 mod that turns plain milk selling into a proper little business: sign supply contracts with a range of dairies, each with its own price, quotas, payout rhythm and terms. While a contract runs, the agreed amount is collected from your barn automatically every day and paid at the contract price.

Works for **cow milk** and **buffalo milk** (barn tank) and **goat milk** (pallet pickup), with a cow/goat/buffalo switch in the menu and one contract per milk type at a time.

## Features

- Milk contract system with many different dairies
- Fixed prices, minimum or maximum quotas, and four payout intervals (monthly / quarterly / half-yearly / yearly)
- Daily automatic pickup straight from the barn storage; surplus stays in storage for you to sell yourself
- Rotating offers, freshly assembled every year (base dairy + random selection per milk type)
- Random contract durations (3–24 months) with a price bonus for longer commitment
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

| Dairy | Price / liter | Quantity | Payout | Term | Requirements |
|---|---|---|---|---|---|
| Cooperative | Market x1.0 | free | monthly | 6 M | - |
| Nordmilch Plant | 1.05/l | min 85% (±10) | half-yearly | 12 M | - |
| Market Trader | Market x1.15 | free | monthly | 6 M | - |
| BioLand Dairy | 1.55/l | min 60% (±12) | yearly | 24 M | health >=80% |
| Weidehof Manufactory | 1.84/l | min 50% (±10) | yearly | 24 M | health >=85%, calves >=12M |
| Klein Farm Dairy | 1.90/l | max 4000 l/mo (±800) | monthly | 12 M | - |
| Alpine Dairy Co-op | Market x1.05 | free | quarterly | 12 M | - |
| FreshLogistics Inc. | 1.10/l | min 70% (±15) | monthly | 12 M | - |
| South Cheese Works | 1.45/l | min 55% (±10) | half-yearly | 18 M | - |
| Discount Dairy | 0.95/l | free | monthly | 6 M | - |
| World Market Export | Market x1.25 | free | quarterly | 12 M | - |
| Demeter Farm | 1.95/l | min 45% (±8) | yearly | 24 M | health >=90%, calves >=15M |

### Goat milk

| Dairy | Price / liter | Quantity | Payout | Term | Requirements |
|---|---|---|---|---|---|
| Creekside Goat Farm | Market x1.05 | free | monthly | 6 M | - |
| Bergblick Goat Cheesery | Market x1.20 | min 60% (±12) | half-yearly | 18 M | - |
| Sonnenwiese Organic Goat Farm | Market x1.35 | min 50% (±10) | yearly | 24 M | health >=85% |
| Goat-Milk Soap Workshop | Market x1.15 | min 55% | quarterly | 12 M | - |
| Alpengold Fine Cheesery | Market x1.30 | min 65% (±12) | half-yearly | 18 M | - |
| Goat-Milk Natural Cosmetics | Market x1.40 | min 50% (±10) | yearly | 12 M | health >=80% |
| Goat Farm Shop | Market x1.10 | free | monthly | 6 M | - |
| Regional Goat Dairy | Market x1.08 | min 70% | monthly | 12 M | - |
| Goat-Milk Export | Market x1.28 | free | quarterly | 12 M | - |
| Hillside Fresh Cheesery | Market x1.18 | min 60% | monthly | 12 M | - |
| Demeter Goat Farm | Market x1.45 | min 45% (±8) | yearly | 24 M | health >=90% |
| Gourmet Goat Delicacies | Market x1.50 | min 40% (±10) | half-yearly | 18 M | health >=85% |

### Buffalo milk

| Dairy | Price / liter | Quantity | Payout | Term | Requirements |
|---|---|---|---|---|---|
| Riverside Buffalo Farm | Market x1.05 | free | monthly | 6 M | - |
| Mozzarella Workshop | Market x1.30 | min 60% (±12) | half-yearly | 18 M | - |
| Buffalo Fine Cheesery | Market x1.35 | min 65% (±10) | half-yearly | 18 M | - |
| Delicatessen Dairy | Market x1.45 | min 50% (±10) | yearly | 24 M | health >=85% |
| Buffalo Farm Shop | Market x1.10 | free | monthly | 6 M | - |
| Regional Buffalo Dairy | Market x1.08 | min 70% (±10) | monthly | 12 M | - |
| Buffalo-Milk Export | Market x1.30 | free | quarterly | 12 M | - |
| Ricotta Cheesery | Market x1.18 | min 55% (±12) | monthly | 12 M | - |
| Buffalo Gelateria | Market x1.40 | min 50% (±10) | quarterly | 12 M | - |
| Organic Buffalo Farm | Market x1.45 | min 45% (±8) | yearly | 24 M | health >=90% |
| Gourmet Buffalo Delicacies | Market x1.50 | min 40% (±10) | half-yearly | 18 M | health >=85% |
| South Buffalo Cheesery | Market x1.22 | min 60% (±12) | half-yearly | 18 M | - |

> Market-priced dairies pay the daily market price of that fill type multiplied by the given factor; fixed-price dairies pay a set amount per liter. Displayed prices do not include the duration bonus. Values are defined in `molkereien.xml` and can be edited without touching code.

## How it works

- **Signing** — pick a dairy for the current milk type and confirm. Duration and bonus price are locked in at signing.
- **Delivery** — each in-game day the contract takes the agreed milk from the barn (cow: tank; goat: pallets) and credits it at the contract price.
- **Payout** — accrued money is paid out on the contract-relative rhythm (and always at contract end).
- **Expiry & renewal** — in the last month you're warned and can renew on the old terms plus a loyalty bonus. If a minimum quota wasn't met, renewing carries the shortfall over as extra target (new target = normal target + carry-over); letting it lapse instead charges the shortfall penalty.
- **Early cancellation** — possible any time against a termination fee (remaining contract value × 1.2), with a confirmation dialog.

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

Mod version 0.4.1.0 · modDesc `descVersion="111"` (FS25)

## License / Credits

Author: Shin_Jin_Jin. Uses only standard GIANTS engine interfaces. Not affiliated with GIANTS Software.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.
