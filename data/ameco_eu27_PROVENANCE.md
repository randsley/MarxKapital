# AMECO extract for the EU27: provenance

> Source: European Commission, DG ECFIN, AMECO database, 2026 release,
> extracted 2026-11-09.

AMECO is Commission content, reusable under Commission Decision
2011/833/EU and licensed CC BY 4.0: credit the source and indicate
changes. The changes made here are the ones listed below.

`ameco_eu27.csv` holds 28 areas (the 27 member states and the
EU27 aggregate), 1995-2025, one row per area and year. It is
built by `data/build_ameco_eu.jl` with the package's own SDMX downloader
(`download_ameco_sdmx`), so the series and the scale factors are those of
`AMECO_SDMX_MAP` in `src/ameco_sdmx.jl`. Load a country with
`build_ameco_data` (see notebook 07).

**Forecasts removed.** AMECO series carry the Commission's forecasts for
the release year and the next, unmarked. Every year from 2026 on is
dropped (`_apply_forecast_rule`), so 2025 is the last actual year.

**Units.** Monetary series use AMECO's UNIT code 0, national currency:
euros for euro-area members, the national currency elsewhere (zloty,
forint, koruna, krona, krone, lev, leu), and euros for the EU27
aggregate. Compare countries only through ratios, such as the rate of
profit or the wage share, never through levels. `net_capital_stock`
(`OKND`) is at constant prices of AMECO's reference year; every other
monetary series is at current prices.
`analyze_time_series_with_data(...; valuation = :consistent)` puts them on
one basis. Values are stored to six significant figures.

**The EU27 aggregate** uses AMECO's standard aggregation where the series
has one, and otherwise the euro-weighted mean of national growth rates
(`_select_agg_method`), as `OVGD` and `PIGT` have no standard aggregation.

| column | AMECO item | dataflow |
|---|---|---|
| `CFC` | `UKCT` | `AMECO_CHAPTER03-05` |
| `CPI` | `ZCPIH` | `AMECO_CHAPTER02-04` |
| `GDP_constant` | `OVGD` | `AMECO_CHAPTER06-01` |
| `GDP_current` | `UVGD` | `AMECO_CHAPTER06-01` |
| `GDP_deflator` | computed: `UVGD / OVGD × 100` | |
| `GFCF` | `UIGT` | `AMECO_CHAPTER03-01` |
| `GFCF_deflator` | `PIGT` | `AMECO_CHAPTER03-01` |
| `budget_balance` | `UBLG` | `AMECO_CHAPTER16-03` |
| `compensation` | `UWCD` | `AMECO_CHAPTER07-01` |
| `compensation_per_employee` | `HWCDW` | `AMECO_CHAPTER07-04` |
| `current_account` | `UBCA` | `AMECO_CHAPTER10-01` |
| `employees` | `NWTD` | `AMECO_CHAPTER01-07` |
| `employment_total` | `NETD` | `AMECO_CHAPTER01-04` |
| `exports` | `UXGS` | `AMECO_CHAPTER09-01` |
| `government_expenditure` | `UUTG` | `AMECO_CHAPTER16-02` |
| `government_revenue` | `URTG` | `AMECO_CHAPTER16-01` |
| `imports` | `UMGS` | `AMECO_CHAPTER09-02` |
| `labor_force` | `NLTN` | `AMECO_CHAPTER01-02` |
| `labor_productivity` | `ZVGDE` | `AMECO_CHAPTER08-02` |
| `net_capital_stock` | `OKND` | `AMECO_CHAPTER08-01` |
| `private_consumption` | `UCPH` | `AMECO_CHAPTER02-01` |
| `public_consumption` | `UCTG` | `AMECO_CHAPTER02-05` |
| `public_debt` | `UDGGL` | `AMECO_CHAPTER18-02` |
| `trade_balance` | computed: `DXGT − DMGT`, goods only | `AMECO_CHAPTER11-01` |
| `unemployment_rate` | `ZUTN` | `AMECO_CHAPTER01-03` |
| `unit_labor_costs` | `PLCD` | `AMECO_CHAPTER07-07` |
