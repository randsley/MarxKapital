# Eurostat sectoral accounts of Portugal: provenance

> Source: Eurostat, national accounts (ESA 2010) by industry, extracted
> 2026-11-11 from the SDMX dissemination API.

Eurostat data are reusable under the Commission's reuse policy
(Decision 2011/833/EU) and licensed CC BY 4.0: credit the source and
indicate changes. The changes made here are listed below.

`eurostat_pt_sectors.csv` holds the 19 NACE Rev. 2 sections A–S of
Portugal, 2000–2023, one row per section and year: the years
in which every series below is published for every section. It is
built by `data/build_eurostat_pt_sectors.jl` with the package's own
fetcher (`_fetch_eurostat_sections`, `src/eurostat_sdmx.jl`), so the
dataflows and keys are the ones `calibrate_portugal_model(...;
data_source = :eurostat)` uses. Values are stored to six significant
figures. Read it with `CSV.read` (see notebook 09).

**Prices.** Flows are at current prices and the capital stock at
current replacement cost, so ratios such as the rate of profit compare
like with like (the `:current_cost` valuation of the AMECO time
series). Recent years are provisional and may be revised.

| column | dataflow | key | content |
|---|---|---|---|
| `GVA` | `NAMA_10_A64` | `A.CP_MEUR..B1G.PT` | gross value added, current prices, million euros |
| `compensation` | `NAMA_10_A64` | `A.CP_MEUR..D1.PT` | compensation of employees, current prices, million euros |
| `CFC` | `NAMA_10_A64` | `A.CP_MEUR..P51C.PT` | consumption of fixed capital, current prices, million euros |
| `GFCF` | `NAMA_10_A64_P5` | `A.CP_MEUR..N11G.P51G.PT` | gross fixed capital formation, all fixed assets, current prices, million euros |
| `capital_stock` | `NAMA_10_NFA_ST` | `A.CRC_MEUR..N11N.PT` | net fixed capital stock, current replacement cost, million euros (end of year) |
| `employment` | `NAMA_10_A64_E` | `A.THS_PER..EMP_DC.PT` | total employment, domestic concept, thousand persons |
| `employees` | `NAMA_10_A64_E` | `A.THS_PER..SAL_DC.PT` | employees, domestic concept, thousand persons |
