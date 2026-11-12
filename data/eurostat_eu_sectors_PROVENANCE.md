# Eurostat sectoral accounts of the EU countries: provenance

> Source: Eurostat, national accounts (ESA 2010) by industry, extracted
> 2026-11-12 from the SDMX dissemination API.

Eurostat data are reusable under the Commission's reuse policy
(Decision 2011/833/EU) and licensed CC BY 4.0: credit the source and
indicate changes. The changes made here are listed below.

`eurostat_eu_sectors.csv` holds the 19 NACE Rev. 2 sections A–S of
26 EU countries, one row per country (`geo`, Eurostat code),
section and year. For each country it keeps the years in which every
series below is published for every section; the panel is therefore
balanced within a country and unbalanced across countries. Malta is
left out (no capital stock for sections B and D). It is built by
`data/build_eurostat_sectors.jl` with the package's own parser
(`_fetch_eurostat_sections_by_geo`, `src/eurostat_sdmx.jl`), so the
dataflows and keys are the ones `calibrate_portugal_model(...;
data_source = :eurostat)` uses. Values are stored to six significant
figures. Read it with `CSV.read` (see notebooks 9–12).

**Prices.** Flows are at current prices and the capital stock at
current replacement cost, so ratios such as the rate of profit compare
like with like (the `:current_cost` valuation of the AMECO time
series). Recent years are provisional and may be revised.

**Volumes.** `GVA_volume` and `GFCF_volume` are chain-linked volumes
(reference year 2015), used for real flows (notebook 12): the sector's
GVA deflator is `GVA/GVA_volume`. Chain-linked volumes are not additive
across sections, so use them only in ratios within a section. They are
optional columns: they don't decide which countries and years are
kept, and a value Eurostat doesn't publish is left empty.

| country | years |
|---|---|
| AT | 1995–2025 |
| BE | 1995–2024 |
| BG | 2000–2022 |
| CY | 1995–2023 |
| CZ | 1995–2025 |
| DE | 1995–2024 |
| DK | 2000–2025 |
| EE | 2000–2023 |
| EL | 1995–2023 |
| ES | 1995–2024 |
| FI | 1981–2025 |
| FR | 1978–2025 |
| HR | 1995–2023 |
| HU | 1995–2023 |
| IE | 1995–2024 |
| IT | 1995–2023 |
| LT | 1995–2023 |
| LU | 1995–2023 |
| LV | 1995–2023 |
| NL | 1995–2024 |
| PL | 2000–2023 |
| PT | 2000–2023 |
| RO | 2000–2023 |
| SE | 1993–2023 |
| SI | 2000–2024 |
| SK | 2000–2024 |

| column | dataflow | key | content |
|---|---|---|---|
| `GVA` | `NAMA_10_A64` | `A.CP_MEUR..B1G.<geo>` | gross value added, current prices, million euros |
| `compensation` | `NAMA_10_A64` | `A.CP_MEUR..D1.<geo>` | compensation of employees, current prices, million euros |
| `CFC` | `NAMA_10_A64` | `A.CP_MEUR..P51C.<geo>` | consumption of fixed capital, current prices, million euros |
| `GFCF` | `NAMA_10_A64_P5` | `A.CP_MEUR..N11G.P51G.<geo>` | gross fixed capital formation, all fixed assets, current prices, million euros |
| `capital_stock` | `NAMA_10_NFA_ST` | `A.CRC_MEUR..N11N.<geo>` | net fixed capital stock, current replacement cost, million euros (end of year) |
| `employment` | `NAMA_10_A64_E` | `A.THS_PER..EMP_DC.<geo>` | total employment, domestic concept, thousand persons |
| `employees` | `NAMA_10_A64_E` | `A.THS_PER..SAL_DC.<geo>` | employees, domestic concept, thousand persons |
| `GVA_volume` | `NAMA_10_A64` | `A.CLV15_MEUR..B1G.<geo>` | gross value added, chain-linked volumes (2015), million euros |
| `GFCF_volume` | `NAMA_10_A64_P5` | `A.CLV15_MEUR..N11G.P51G.<geo>` | gross fixed capital formation, all fixed assets, chain-linked volumes (2015), million euros |

Empty volume cells: `GVA_volume` 0, `GFCF_volume` 0.
