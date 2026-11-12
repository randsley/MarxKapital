# Changelog

*[🇵🇹 Ler em português](CHANGELOG.pt.md)*

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705369.svg)](https://doi.org/10.5281/zenodo.21705369)

Format based on Keep a Changelog. Semantic versioning.

## [Unreleased]

### Added
- A linear reinvestment form and an exit for unprofitable capital
  (`simulate_Ndept(_custom)`, all opt-in; the defaults are bit-identical):
  - `reinvestment_form = :linear` reinvests `σ_c·[(1−η)Π + η·r̄·K]`, with
    `r̄ = ΣΠ/ΣK`. It is defined for losses, so `η` now works in the
    cross-dual system (market prices), where it needs this form. With a
    common `σ_c` it leaves aggregate reinvestment unchanged.
  - `exit_rate = φ` and `exit_hurdle = h`: sectors whose profit rate is
    below `h·r̄` scrap `φ·(h·r̄ − r)·C` of constant capital a year
    (`_exit_flow`). With `h = 0` only loss-making sectors do.
  - `investment_floor = θ`: gross reinvestment is at least `θ·δ·C`
    (`_investment_floor`), the irreversibility the EU panel shows. With
    market prices, the extra investment comes out of capitalist
    consumption. `estimate_investment_floor` estimates `θ` from the years
    with losses (`compute_investment_panel` gains the depreciation rate
    `dk`).
  - All of them work with the Jacobians, `balanced_growth`,
    `with_parameter` (`:exit_rate`, `:exit_hurdle`, `:investment_floor`)
    and `parameter_jacobian`.
- `estimate_investment_function(...; form = :linear, exit_hurdle)`: the
  linear form on the EU panel, including the years with losses that the
  power form drops. It is linear in `(λ(1−η), λη)`, so it also estimates
  `η` freely (`unrestricted`, with delta-method errors). `exit_hurdle` adds
  the exit regressor. `compute_investment_panel` gains `kv`, `rbar_K` and
  `valid_linear`, and `estimate_fe_ols` returns the clustered covariance
  matrix (`V_cluster`).
- Calibration options for the floor on `e` (`calibrate_portugal_model`, all
  opt-in; the defaults are unchanged):
  - `sectors = :market` leaves out real estate and the non-market services
    (L, O, P, Q, `NON_MARKET_SECTIONS`). What the market sectors buy from
    them is treated like imports, and what they buy from the market sectors
    becomes government demand.
  - `e_years` computes `e` over several years.
  - `e_floor` sets the floor (0.1 by default).
  - `self_employed = :imputed_hours` imputes the self-employed's labor
    income per hour worked (`fetch_eurostat_sector_hours`).

  For Portugal 2022 the floor binds in 1 of 15 market sectors (electricity,
  hit by the energy crisis) instead of 4 of 19.
- `docs/NATIONAL_ACCOUNTS.md` (and `.pt.md`), linked from the README: which
  ESA 2010 item and Eurostat series gives each of the model's quantities,
  how each NACE section is treated (market or non-market; the
  productive/unproductive distinction the model does not make), how the
  self-employed are counted, and what the floor on `e` does.
- Notebook 14, `14_variable_capital_mobility_and_tssi_dynamics`: `μ_v`
  estimated on the EU panel (0.037, se 0.016, on the wage bill; 0.024, se
  0.009, on employment), against a Hopf point at `μ_v` ≈ 1.22 in Portugal's
  calibrated cross-dual economy, 33 times higher, so the accumulation
  cycles are outside the empirical range; and the same economy with
  TSSI-driven dynamics, whose balanced growth, stability and response to a
  price shock are almost those at current prices.
- TSSI-driven dynamics, `tssi_dynamics = true` with lag `τ`
  (`simulate_Ndept(_custom)`, both coupled systems; opt-in, the defaults are
  bit-identical): the profit rate that drives mobility, reinvestment, the
  floor and the exit is computed on capital advanced at historical cost,
  with the book value of fixed capital appended to the state (`src/tssi.jl`:
  `_book_value_flow`, `_tssi_price_flow`, `_tssi_initial`). Capital goods
  are bought at market prices in the cross-dual system and at TSSI temporal
  prices, which follow the TSSI map with a continuous lag, in the coupled
  one. `balanced_growth`, the Jacobians and `with_parameter(:tssi_τ)` work
  with it.
- Estimating the mobility of variable capital `μ_v`
  (`src/mobility_estimation.jl`): `compute_labor_panel` builds the panel of
  the model's equation `dV/dt = σ_v·S + μ_v·(r − r̄_V)·V` (growth of the
  wage bill or of employment, last year's `S/V`, and the gap to the
  V-weighted mean profit rate, which sums to zero), and
  `estimate_variable_mobility` estimates `σ_v` and `μ_v` with fixed
  effects and clustered or Driscoll–Kraay errors.
- The perpetual inventory by asset type, `perpetual_inventory = :by_asset`
  (`calibrate_portugal_model`, `calibrate_with_ameco_v2`; `true` is now
  also `:single`). Each asset type's depreciation rate is backed out of
  Eurostat's GFCF and net stock by asset in chain-linked volumes
  (`estimate_asset_depreciation`, `asset_depreciation_rates`), the
  recursion runs in volumes and each asset is revalued by its own GFCF
  deflator (`compute_pim_capital_stock_by_asset`, with
  `fetch_eurostat_sector_gfcf_by_asset_series` and
  `fetch_eurostat_sector_capital_stock_by_asset_series`). For Portugal the
  gap to the reported stock falls from −28.2% to −1.9% in 2022 (from
  −15.4% to −3.3% in 2010).
- Website: the home page (both languages) has an "Empirical findings"
  block with plots from notebooks 10, 11 and 13 (capital mobility and
  reinvestment), taken from the executed notebooks by `build_site.py`
  (`NOTEBOOK_FIGURES`), and links to `docs/NATIONAL_ACCOUNTS.md`, which is
  now a site page. The notebooks section no longer says every notebook
  runs on synthetic data.
- Notebook 13, `13_investment_floor_and_market_prices`: the linear
  reinvestment form estimated on every row of the EU panel, loss years
  included (`η̂` = 0.15, se 0.18; `μ̂` = 0.063), against notebook 11's
  calibrated `η` = 1; no exit of capital through investment (the exit
  coefficient has the wrong sign), but a floor on gross investment at
  0.69 of depreciation (se 0.18); and, with market prices, a stable
  interior balanced growth path of Portugal's market sectors for every
  `η` ≤ 0.9, with the floor dampening the fall of capital after a price
  shock.
- Notebook 12, `12_incremental_profit_rates`: Shaikh's claim that
  competition equalizes incremental, not average, rates of profit, on the
  EU sectoral panel. Incremental-rate gaps are mostly transitory (4–14%
  of their variance is permanent, against 74–78% for average rates) but
  not equalized (a permanent dispersion of 6–8 pp, half that of average
  rates), and very noisy. Capital follows the average-rate gap (`μ̂` = 0.14
  at `η` = 1); the incremental gap adds nothing once both are in. The
  model's mobility term keeps the average rate.
- Shaikh's incremental rate of profit in `src/mobility_estimation.jl`:
  `compute_incremental_panel` adds the return on new investment, the change
  in gross profit over the gross investment before it (real, or at current
  prices; over one year or several), and its gap from the country's
  investment-weighted mean, beside the average-rate gap of
  `compute_mobility_panel`. `estimate_persistence` estimates the
  persistence-of-profits regression (how fast gaps close and the gap each
  sector keeps in the long run), and `hp_filter` smooths a series for display.
  The EU sectoral extract gains `GVA_volume` and `GFCF_volume`
  (chain-linked volumes) for real flows; every existing value is unchanged.
- Notebook 11, `11_reinvestment_and_mobility`: the model's investment
  function on the EU sectoral panel. Allowing reinvestment to depart from
  a fixed share makes `μ̂` positive for every `η` (0.05 at `η` = 0, 0.13
  at 1, trimmed sample), but the panel does not identify `η` (the fit
  changes by 1.1%): investment follows own surplus at about a tenth of
  the average share, and the model's own level fits 57–82% worse.
  Calibrating `η` = 1 gives `μ̂` = 0.13 (se 0.04), positive in every check.
  The gross reinvestment share did not change after 2008 (depreciation
  rose), so no `σ_schedule` is needed. In the model, `η` = 1 lets
  unprofitable sectors accumulate until their profit rate reaches zero.
- Reinvestment share that falls with profitability, and a schedule:
  `simulate_Ndept(_custom)(...; η = 0.0, σ_schedule = nothing)` in the
  coupled system. Each department reinvests `σ_c,ᵢ·m(t)·(r̄/rᵢ)^η` of its
  surplus (`_reinvestment_share`): `η` is the elasticity to relative
  profitability, `m(t)` a piecewise-constant multiplier (the solver stops
  at its breaks). The defaults leave the dynamics bit-identical. Exact
  Jacobians and Hessians (also through rationing), `parameter_jacobian(:η)`
  and `with_parameter(:η)` work; not available with `market_prices`, and a
  schedule is rejected by the balanced-growth tools.
- `estimate_fe_ols` (`src/mobility_estimation.jl`): OLS with several
  regressors and any fixed effects, with classical, Driscoll–Kraay and
  country-clustered errors; `estimate_mobility` is now its one-regressor
  case (same results), and notebook 10 uses it.
  `compute_investment_panel` adds the gross investment rate, `S/K`, the
  country's mean profit rate and each country × sector's reinvestment share
  to the mobility panel; `estimate_investment_function` estimates the
  model's investment function, `σ_c·(r̄/r)^η·S` plus the mobility term,
  over a grid of `η` (with an optional bound on `r/r̄`).
- Notebook 10, `10_eu_sectoral_mobility`: `μ` between the 15 market sectors
  of 26 EU countries, offline, from `data/eurostat_eu_sectors.csv`, with
  country × sector and country × year effects (and sector × year), errors
  clustered by country. `μ̂` ≈ −0.14 (se 0.05) in every specification,
  after trimming, with the gap instrumented by its lag, and in 21 of 26
  countries; Portugal's positive estimate is the exception. Net investment
  rises with the gap (0.08), but less than a common reinvestment share of
  the surplus would (0.21): what the panel rejects is the model's common
  `σ_c`. Year by year, `μ̂ₜ` is negative up to 2009 and near zero after
  (break at 2008: −0.16 to −0.06, t = 2.3), but the response of net
  investment to the gap did not change; the share reinvested net of
  depreciation halved (0.19 to 0.10). The break is not in `μ`.
- `src/mobility_estimation.jl`: `compute_mobility_panel` builds the panel
  of the capital-mobility equation from sectoral accounts, per country
  (transfer `R = I − σS` summing to zero in every country-year, gap to the
  capital-weighted mean profit rate); `estimate_mobility` estimates `μ`
  with any set of fixed effects (`demean_fe`, alternating projections),
  Driscoll–Kraay and country-clustered standard errors;
  `estimate_mobility_between` gives the between estimate. Notebooks 9 and
  10 use them (notebook 9's results are unchanged).
- `data/eurostat_eu_sectors.csv`: Eurostat accounts by industry for the
  19 NACE sections of 26 EU countries (EU27 without Malta), built by
  `data/build_eurostat_sectors.jl` with `_fetch_eurostat_sections_by_geo`
  (one request per series for every country), with a provenance file. It
  replaces the Portugal-only extract; Portugal's rows are unchanged.
- Notebook 9, `09_sectoral_mobility`: the capital-mobility coefficient `μ`
  between Portugal's 15 market sectors, 2002–2023, offline, from
  Portugal's rows of `data/eurostat_eu_sectors.csv`. The
  transfer is net investment beyond a common share of own surplus. Within
  sectors `μ̂` ≈ 0.11 (Driscoll–Kraay se 0.05), but −0.19 to −0.35 with the
  self-employed imputed, because the surplus enters both sides; between
  sectors −0.31. So `μ` between sectors is not identified by these data.
- Imported intermediate inputs in the gross-output reconstruction:
  `fetch_eurostat_import_coefficients` (`mⱼ = IMPⱼ/P1ⱼ` from the IOT's
  `IMP` row, `import_coefficients_from_iot`, `aggregate_import_coefficients`),
  a new `CalibratedParameters` field `import_coefficients` on the Eurostat
  paths, and `import_coefficients` in `simulate_Ndept_custom`, so that with
  the real domestic matrix `xⱼ = Wⱼ/(1 − Σᵢ A[i,j] − mⱼ)`. `_gross_output`
  centralizes the reconstruction, and `_ensure_output_admissibility` takes
  `m`. Portugal: the share of rationed sectors does not change, and
  accumulation rises by 8% (10 sectors) and 31% (19). Opt-in.
- Notebook 7, `07_eu_profit_rates`: `e`, `k` and `r` for the 27 EU member
  states and the EU27 aggregate, 1995–2024, from real AMECO data, offline.
  It adjusts compensation for the self-employed, splits the change in `r`
  exactly into exploitation and composition, and shows that the
  `:current` valuation reverses the trend in `k`.
- `data/ameco_eu27.csv`, the static AMECO extract the notebook reads (2026
  release, forecast years removed), with `data/build_ameco_eu.jl` to
  rebuild it and `data/ameco_eu27_PROVENANCE.md`.
- `self_employed = :imputed` in `calibrate_with_ameco_data`,
  `calibrate_with_ameco_v2` and `analyze_time_series_with_data`: counts each
  self-employed worker at the average employee's compensation. Opt-in; see
  `docs/LIMITATIONS.md` item 4.
- `self_employed = :imputed` also on the sectoral paths:
  `calibrate_portugal_model(...; data_source = :eurostat)`,
  `fetch_portugal_eurostat_data` and `calibrate_with_ameco_data(...;
  sector_data = :eurostat)`, which refused it before. The imputation is per
  NACE section, at the 19 sections before aggregation, from Eurostat's
  employees (`fetch_eurostat_sector_employees`, `SAL_DC`), with
  `impute_self_employed`. For Portugal, 2022, the factor is 2.98 in
  agriculture and 1.05 in manufacturing, and the aggregate `r` falls from
  5.8% to 3.7%. `check_eurostat_sectoral()` checks the employee counts.
  290 tests.
- Notebook 8, `08_capital_mobility`: estimates the model's capital-mobility
  coefficient `μ` from EU27 capital flows (net foreign financing against
  the lagged profit-rate gap), 1996–2024. Between countries `μ̂` ≈ 0.33
  without the financial centres, close to the default of 0.3; within
  countries it is zero on average, 0.15 before 2008 and −0.27 after.
- SpatialEconometrics.jl as a notebook-only dependency of notebook 8,
  pinned to a commit in `install_deps.jl`; `--notebook-test` installs only
  what `test/notebooks.jl` needs, and CI uses it.
- `valuation = :current_cost` in `analyze_time_series_with_data`: current
  prices with the capital stock at current replacement cost, the
  calibration's own price basis.

### Fixed
- `system_hessian` with `rationing = true` failed: the implicit-function
  derivative of the rationing fixed point was first-order only.
  `_rationing_fixed_point` applies the implicit function theorem once per
  level of `Dual`, so second (and higher) derivatives through rationing are
  exact; checked against finite differences of the Jacobian and the
  closed form of the 2-sector example. The values path is unchanged
  (`paper/figures/jacobian_stats.tex` regenerates identically). 296 tests.
- `calibrate_with_ameco_data` (`sector_data = :fixed`) divided AMECO's
  capital stock at constant 2020 prices by compensation at current prices,
  so `k` was too low in every year after 2020 (17–25% in 2024 for Germany,
  Portugal and Poland). The stock is now revalued with the GFCF deflator,
  and the calibrated `k` equals the `:consistent_gfcf` time series.
- AMECO aggregates (EU27, euro area): the SDMX API returns up to three
  aggregation methods per year, and `_fetch_sdmx_series` kept whichever row
  came last, often the PPS-weighted mean of growth rates (EU27 GDP in 2000:
  7,348 bn instead of the standard 7,885 bn). `_select_agg_method` now keeps
  the standard aggregation, or the euro-weighted mean where that is the only
  one. Single countries were not affected. Tested offline.
- AMECO forecast years: when no release year can be read from the SDMX
  `LAST UPDATE` column, `fetch_ameco_data` now warns that forecasts cannot
  be identified instead of keeping them silently. The rule is a pure
  function, `_apply_forecast_rule`, tested offline. See
  `docs/LIMITATIONS.md` item 12.
- Paper: the abstract and Sections 5.4 and 6.2 said that no real per-sector accumulation
  series exists. Eurostat publishes per-sector investment, net capital
  stock and consumption of fixed capital, and the pipeline already fetches
  them; the text now says the coupling mechanisms have not been calibrated
  against them, and why that is a separate problem.
- `docs/PROJECT_STATUS.md`: the current test count, in place of 111.

## [1.1.0] — 2026-10-29

DOI of this version (Zenodo): [10.5281/zenodo.23769203](https://doi.org/10.5281/zenodo.23769203). To cite all versions, use the concept DOI above.

### Added
- **Website** on GitHub Pages (<https://randsley.github.io/MarxKapital/>),
  in English and Portuguese: the README, limitations, project status,
  glossary and changelog, the six Jupyter notebooks rendered to HTML, and
  the paper PDF. Built on every push to `main` by
  `.github/workflows/pages.yml` (`.github/pages/build_site.py`).
- `CalibratedParameters.e_raw`: the rate of exploitation before the 0.1
  floor, on both the INE and AMECO paths (`e == max.(0.1, e_raw)`).
- Paper, Section 5.1: Table 3 lists the sectors at the floor with their raw
  and imposed `e` and `r`, and the text reports the aggregate profit rate
  with and without the floor (6.12% and 5.80% for Portugal 2022), all
  generated by `paper/generate_results.jl` (`figures/table3_floor.tex`,
  `figures/floor_stats.tex`). See `docs/LIMITATIONS.md` item 8.
- **Real final demand** from the final-use columns of the IOT already used
  for `A` (`NAIO_10_CP1700`, domestic use): `final_demand_from_iot`,
  `fetch_eurostat_final_demand`, `aggregate_final_demand`, and the field
  `CalibratedParameters.final_demand` (on the Eurostat paths; `nothing`
  otherwise). Two uses in the dynamics: `consumption_basket` (real household
  consumption shares as the cross-dual basket) and `exogenous_demand_share`
  (rationing net of final consumption and exports, new keyword
  `final_demand_share`). The IOT download is cached for the session.
- `simulate_Ndept_custom(...; A = ...)`: simulate with a given technical
  matrix (e.g. a calibration's real `A`) instead of a random one.
- Paper, Section 5.7 and Table 4: both uses on the Portuguese calibration.
  See `docs/LIMITATIONS.md` items 1 and 11.
- `tssi_valuation(...; depreciation = :historical)`: depreciation valued at
  historical cost, from a per-sector book value of fixed capital bought at
  lagged TSSI prices (returned as `book_value`). The default `:base` is
  unchanged. See `docs/LIMITATIONS.md` item 10.
- **Exit friction** (`exit_friction = ε`, coupled and cross-dual models,
  default 0 = off): capital outflows from a sector are damped by
  `sᵢ/(sᵢ + ε)` as its share `sᵢ` shrinks, with inflows rescaled so the
  mobility terms still sum to exactly 0 (`_mobility_flow`). Also a
  continuation parameter (`with_parameter(p, :exit_friction, θ)`). Paper,
  Section 5.6 and the exit-friction table: smallest sector shares with and
  without friction. See `docs/LIMITATIONS.md` item 11.

## [1.0.0] — 2026-10-29

DOI of this version (Zenodo): [10.5281/zenodo.23750616](https://doi.org/10.5281/zenodo.23750616). To cite all versions, use the concept DOI above.

### Added
- **Notebooks** (`notebooks/`, in English, offline): six Jupyter notebooks
  committed with their outputs (accumulation basics; values, prices and the
  wage–profit frontier; calibration and wage shocks; coupled sectors and
  automatic differentiation; TSSI valuation; balanced growth, cycles and
  chaos) and three interactive Pluto notebooks (wage–profit frontier,
  accumulation with coupling and a wage shock, accumulation cycles in the
  cross-dual model). Guide in `notebooks/README.md`.
- `test/notebooks.jl`: smoke test that runs every notebook offline (except
  cells tagged `slow`), in CI after the main suite. `install_deps.jl
  --notebooks` installs IJulia, Pluto, PlutoUI and JSON;
  `notebooks/strip_outputs.jl` keeps only the PNG of each plot in the
  committed outputs.

### Changed (breaking)
- **The code is now in English.** Every function, type, struct field,
  constant, keyword argument, symbol value, returned field and DataFrame
  column, source file, comment, docstring and console message was
  translated (US spelling). It is a clean break with no aliases: code
  written for v0.8.x must be updated. `docs/GLOSSARY.md` maps every old
  name to its new one. Examples: `simular_Ndept(…; acoplado = true,
  racionamento = true)` → `simulate_Ndept(…; coupled = true,
  rationing = true)`; `calibrar_modelo_portugal(ano = 2022,
  fonte_dados = :eurostat)` → `calibrate_portugal_model(year = 2022,
  data_source = :eurostat)`; `Departamento` → `Department`;
  `ParâmetrosCalibrados` → `CalibratedParameters`; `:sintético` →
  `:synthetic`.
- Source files renamed: `estruturas.jl` → `types.jl`, `nucleo.jl` →
  `core.jl`, `analise.jl` → `analysis.jl`, `distributiva.jl` →
  `distribution.jl`, `choques.jl` → `shocks.jl`, `diferenciacao.jl` →
  `differentiation.jl`, `cruzado.jl` → `cross_dual.jl`, `crescimento.jl` →
  `growth.jl`, `bifurcacao.jl` → `bifurcation.jl`, `calibracao_pt.jl` →
  `calibration_pt.jl`, `visualizacao.jl` → `plotting.jl`, `exemplos.jl` →
  `examples.jl`; paper scripts `gerar_resultados.jl` →
  `generate_results.jl`, `jacobiana_bifurcacao.jl` →
  `jacobian_bifurcation.jl`, `acumulacao_bifurcacao.jl` →
  `accumulation_bifurcation.jl` (and `figures/acumulacao_stats.tex` →
  `figures/accumulation_stats.tex`).
- Data strings are English: AMECO country names (`"Alemanha"` →
  `"Germany"`), the keys of `AMECO_VARIABLE_CODES`, the NACE section
  titles and the macro sectors (`"Primary"`, `"Secondary"`, `"Tertiary"`).
  Metadata keys are `"source"`/`"year"`. The default AMECO download folder
  is `./ameco_data` (file `ameco_full.txt`).
- The medium INE aggregation is `:medium` (was `:média`); national-accounts
  acronyms use the English forms (VAB → GVA, FBCF → GFCF, CCF → CFC,
  PIB → GDP, IPC → CPI).
- Docs are English-primary: `CHANGELOG.md`, `docs/LIMITATIONS.md` (was
  `LIMITACOES`) and `docs/PROJECT_STATUS.md` (was `ESTADO_DO_PROJETO`),
  each with a `.pt.md` Portuguese version. Entries below this one keep the
  Portuguese names they were written with.

### Fixed
- **AMECO forecast years were read as data.** AMECO series include the
  Commission's forecasts for the release year and the next one, and the
  SDMX response doesn't mark them, so a calibration for 2026 or a time
  series reaching 2027 used forecasts silently. `fetch_ameco_data` now
  reads the release year from `LAST UPDATE` and drops those years on the
  SDMX path, with a warning, recording the last actual year in
  `data.notes["last_actual_year"]`; a calibration year beyond it falls back
  to that year. `include_forecasts=true` keeps them (also in
  `calibrate_with_ameco_v2` and `analyze_ameco_time_series`). See
  `docs/LIMITATIONS.md` item 12.
- `docs/LIMITATIONS.md` item 7 brought up to date: no path still deducts a
  flat 10% of the stock, and the perpetual-inventory gap against the
  reported stock is larger than the doc said (−28% in aggregate in 2022,
  from +11% to −36% by sector).
- **AMECO calibration with fixed weights** (`calibrate_with_ameco_data`,
  `sector_data=:fixed`, the default path): it deducted 10% of the capital
  stock as depreciation instead of AMECO's real CFC, and split the stock by
  `[0.10, 0.35, 0.55]`, which gave negative profit rates in the Primary
  sector (and in the Secondary with synthetic data), with `e` at the 0.1
  floor. It now uses the `UKCT` series, split like value added, and
  Eurostat capital-stock shares (`[0.02, 0.16, 0.82]`); `r = e/(k+1)` from
  the floored `e`, and sectors at the floor are reported. See
  `docs/LIMITATIONS.md` item 4.
- `compare_ameco_countries`: the `GDP` and `Wage_Share` columns measured
  capital advanced `Σ(C+V)` and `ΣV/Σ(C+V)`; they now measure value added
  and `ΣV/ΣGVA`.

## [0.8.0] — 2026-10-28

DOI of this version (Zenodo): [10.5281/zenodo.23735182](https://doi.org/10.5281/zenodo.23735182). To cite all versions, use the concept DOI above.

### Added
- `expoentes_lyapunov` (`src/bifurcacao.jl`): largest Lyapunov exponents of
  the normalized system (Benettin's method, exact Jacobian), and
  `histerese_simulada`: up/down parameter sweeps by simulation, to detect
  coexisting attractors.
- **Result:** the irregular regime of the accumulation cycles is chaotic
  (positive largest exponent, robust to the initial condition, tolerance
  and run length; two positive exponents at high `μ_v`), and a stable cycle
  coexists with the torus in a window of `μ_v` (hysteresis). Paper Section
  5.6 and a new figure (exponents and hysteresis) updated.

## [0.7.0] — 2026-10-28

DOI of this version (Zenodo): [10.5281/zenodo.23718359](https://doi.org/10.5281/zenodo.23718359). To cite all versions, use the concept DOI above.

### Added
- **Automatic differentiation** (`src/diferenciacao.jl`, ForwardDiff):
  exact Jacobian of the ODE right-hand side (`jacobiana_sistema`, also
  with `racionamento=true`), parameter sensitivities
  (`jacobiana_parametro`), Hessians (`hessiana_sistema`), exact
  curvature of the wage-profit frontier (`curvatura_fronteira`), and
  the spectrum of the rationing map at its fixed point
  (`jacobiana_racionamento`: eigenvalues, `α_max`, optimal `α`). The
  rationing fixed point is differentiated through the implicit function
  theorem (`_racionamento_dual`).
- **Result:** with sectors ordered by ρ*, the rationing map's Jacobian is
  triangular, with real spectrum in `[−1, 0]`, and `−1` is an eigenvalue
  once any sector is rationed. Damped iteration converges locally for
  every `α ∈ (0, 1)`; `α = 1` sits exactly on a flip boundary. Checked on
  the 270 cases of the `paper/monte_carlo.jl` sweep and proved in
  `paper/main.tex` (Proposition 1).
- **TSSI** (`src/tssi.jl`): temporal single-system valuation along
  trajectories, with a fixed production lag τ (`valorizar_tssi`,
  `mapa_tssi`, `preços_simultâneos`, `estabilidade_tssi`,
  `comparar_tssi_simultaneo`). Valuation layer only; the dynamics are
  unchanged.
- **Bifurcations** (`src/bifurcacao.jl`, BifurcationKit): continuation of
  fixed points of maps, with classification by multipliers (fold, flip,
  Neimark–Sacker): `continuar_ponto_fixo`, `bifurcacao_racionamento`,
  `bifurcacao_tssi`, `plotar_bifurcacao`.
- `paper/jacobiana_bifurcacao.jl` and the paper's new Sections 3.4, 3.5
  and 5.5 (figures 7–9). The quoted numbers are generated into
  `paper/figures/jacobian_stats.tex`, which the paper reads directly.
- New dependencies: `ForwardDiff`, `BifurcationKit` (`install_deps.jl`).
- **Cross-dual dynamics** (`src/cruzado.jl`, opt-in with
  `preços_mercado=true`): market prices that respond to excess demand
  (`β`), profits and capital mobility at those prices (Flaschel–Semmler),
  Walras' law exact. Without it there is no interior balanced growth.
- **Mobility of variable capital** `μ_v` (off by default), in the coupled
  and cross-dual systems; the term sums to exactly 0.
- **Balanced growth** (`src/crescimento.jl`): normalized system on the
  simplex (`sistema_normalizado`, `simular_normalizado`), balanced-growth
  rays by Newton with the exact Jacobian (`crescimento_equilibrado`),
  `indicadores_crescimento`, `com_parâmetro`, and the wage-share sweep
  (`varrimento_salarial`, uniform or proportional).
- **Bifurcations of accumulation** (`src/bifurcacao.jl`):
  `bifurcacao_acumulação` (Hopf with normal form, limit-cycle continuation
  by collocation with Floquet multipliers), `ciclo_simulado` (check by
  simulation, Poincaré section) and `curva_hopf` (Hopf boundary in the
  wage share × `μ_v` plane).
- **Result:** balanced growth loses stability at a supercritical Hopf
  bifurcation in `μ_v` in all 30 random economies tested; the Hopf
  boundary rises with the wage share.
- `paper/acumulacao_bifurcacao.jl` and the new Sections 3.6 and 5.6 of the
  paper (figures 10–11), with the numbers in `paper/figures/acumulacao_stats.tex`.

### Changed
- **Default rationing relaxation: 0.5 → 2/3** (`RELAXAÇÃO_PADRÃO`, used
  by `_resolver_racionamento`, `jacobiana_racionamento` and
  `bifurcacao_racionamento`). With spectrum in `[−1, 0]` and the 0 and −1
  modes always present, 2/3 minimizes the spectral radius (1/3 instead of
  1/2): ≈30% fewer iterations (mean 18.0 vs. 25.8 on the 270-case sweep),
  converging in all 6870 runs per value of α (including random initial
  points and much scarcer supply; Table 2 of the paper). The fixed point
  does not change (difference ≤ 2.4e-9 along the Figure 4 trajectory).
- `README.md` is now the English version (the default); the Portuguese
  one is `README.pt.md`.
- `sistema_Ndept_io!` and `_resolver_racionamento` are generic in the
  number type (they accept `ForwardDiff.Dual`). The price fallback
  (π = 1) now catches only singular systems (`ErrorException`) and
  rethrows other errors instead of masking them (`_razão_preço_valor`).

## [0.6.1] — 2026-07-30

### Added
- `CITATION.cff` and `.zenodo.json`: citation and archival metadata,
  preparing the repository for the GitHub-Zenodo integration (a release
  with no functional changes, solely to trigger the first Zenodo
  archive once the integration was enabled).

## [0.6.0] — 2026-07-30

### Fixed
- **The technical matrix A used the wrong Eurostat dataflow.** An audit
  requested during external review of the paper in `paper/` (meant to
  quantify the effect of a margin-clipping step) revealed that
  `NAIO_10_CP1620` — used since the first integration of the real matrix
  — is not the symmetric IOT table, but rather "Table of trade and
  transport margins," a small satellite table. Building `A` from it
  understated intersectoral flows by more than an order of magnitude
  (implied total intermediate consumption ≈€8.8bn for Portugal 2020,
  against a true ≈€177.8bn) and explained the implausibly low spectral
  radius (ρ(A)≈0.11-0.15) and the implausibly high `R_max` (≈600-700%)
  reported until now. Fixed with `NAIO_10_CP1700` (the real table),
  `stk_flow=DOM` (domestic use only — the table also publishes
  `IMP`/`TOTAL`, unlike the earlier one). Verified: zero negative cells,
  exact reconciliation against `P1` (gross output) published by the
  table itself, ρ(A)≈0.52-0.60, `R_max`≈68-91%. See
  `docs/LIMITATIONS.md` item 4-bis, `paper/matrix_audit.jl`.
- **The dynamical model's gross output (`sistema_Ndept_io!`) omitted
  circulating intermediate consumption.** The `realização`/`racionamento`
  mechanisms used `O=W=δC+V+S` (a value-added-type flow) as supply, not
  gross output in the sense used to build `A`. Fixed by reconstructing
  genuine gross output `x=W/(1-Σᵢ A[i,j])` from the model's own
  cost-output identity, with no new state — valid only for the closed
  synthetic matrices used in these simulations (never applied to the
  real, domestic-use Eurostat matrix). The admissibility condition
  (`Σᵢ A[i,j]<1`) is now checked and fixed once when the simulation is
  assembled (`_garantir_admissibilidade_output`), not reclaimed at every
  evaluation of the ODE's right-hand side.
- **Investment demand in the rationing mechanism applied A to
  expenditure, not to output.** `_resolver_racionamento` received
  `σ_c,ⱼSⱼ` (planned investment expenditure) directly; fixed to
  `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` (desired output expansion, via the current
  capital-output ratio), so that `A` is applied to a quantity in output
  scale, consistent with its own definition.
- **The capital-mobility term did not conserve aggregate constant
  capital.** `r̄` was the aggregate ratio `ΣS/Σ(C+V)`, which does not
  guarantee `Σᵢμ(rᵢ-r̄)Cᵢ=0`. Fixed by using the mean of `r` weighted by
  `C` — the only choice for which the sum is exactly zero by
  construction.
- **The AMECO time series (`analisar_série_temporal_com_dados`) deducted
  a flat 10% depreciation from the capital stock**, instead of real
  consumption of fixed capital (CCF) — this broke the algebraic
  invariance that `e=(Y-V-CCF)/V` should have under a common deflator
  applied to `Y`, `V`, and CCF together. Fixed by using the real AMECO
  CCF series (item `UKCT`); `deflator_FBCF` was also added to
  `MAPA_AMECO_SDMX`, to test sensitivity to the choice of deflator
  (`valorização=:consistente_fbcf`). Verified: `e` is now identical
  across valuation conventions for every year, Portugal and Spain.
- The sectoral calibration table (used in `paper/gerar_resultados.jl`)
  reconstructed VAB as `C+V+e·V` (a stock added to flows), instead of
  reporting the real VAB already computed by the pipeline — off by two
  orders of magnitude relative to the national total.
  `ParâmetrosCalibrados` gained a real `VAB` field.

### Added
- `capital_transferido(d)` / fix to `valor_produto(d)` in
  `estruturas.jl`: distinguishes constant capital *advanced* (a stock,
  `d.c`) from constant capital *transferred* in a period (`δ·c`) — the
  correct magnitude to add to annual flows.
- `paper/` (new): a complete academic paper in LaTeX combining
  methodology (the model, the three coupling mechanisms, rationing as a
  fixed point with existence and antitonicity proofs) and an empirical
  application to Portugal, with every figure/table reproducible from
  real data (`gerar_resultados.jl`, `monte_carlo.jl` — systematic
  convergence and dispersion sweeps, `matrix_audit.jl` — technical
  matrix audit).
- 63 new tests in `test/runtests.jl` (48→111): invariance of `e` under
  deflator, exact conservation of mobility, rationing sensitivity to
  initial conditions/ordering/tolerance, gross-output reconstruction,
  reconstruction admissibility (normal case and rescale case), among
  others.

## [0.5.0] — 2026-07-28

### Added
- `_resolver_racionamento` (`src/nucleo.jl`) and the `racionamento=true`
  keyword in `sistema_Ndept_io!`/`simular_Ndept`/`simular_Ndept_customizado`
  (takes precedence over `realização`): exact per-sector quantity
  rationing à la Bénassy/Barro-Grossman, with Leontief technology — each
  sector's realized reinvestment is bounded by its scarcest input, and
  rationing propagates between suppliers/buyers. Solved by fixed-point
  iteration with under-relaxation (necessary — the unrelaxed version
  oscillates indefinitely, confirmed in a two-sector example) inside the
  ODE right-hand-side calculation — without turning the system into a
  DAE or depending on `NonlinearSolve.jl`. Verified with a closed-form
  example (`ρ₁=√0.8`) and by robustness across 20+ seed/μ combinations
  and at N=19, with no convergence failures.
- `calcular_stock_capital_pim` (`src/eurostat_sdmx.jl`) and the
  `inventário_perpétuo=true` keyword in `calibrar_modelo_portugal`/
  `calibrar_com_ameco_v2`: capital stock computed via the
  perpetual-inventory method (`Kₜ=(1-δ)Kₜ₋₁+FBCFₜ`, `δ` estimated per
  sector from CCF/stock in the reference year), instead of the value
  directly reported by Eurostat. Degrades per sector (not globally) when
  a sector's GFCF series does not reach the requested year. Verified
  with real Portuguese data: the PIM series tracks the reported stock
  across 22 years, with a moderate, growing deviation (expected — a
  single depreciation rate per sector, not differentiated by asset
  type).

## [0.4.0] — 2026-07-28

### Added
- Headless CI via GitHub Actions (`.github/workflows/test.yml`), Julia 1.10 and 1.
- `sistema_Ndept_io!` (optional, `acoplado=true` in `simular_Ndept`/`simular_Ndept_customizado`):
  couples the technical matrix A to the N-department dynamics through a
  capital-mobility term `μ·(rᵢ − r̄)·Cᵢ`, with `rᵢ` computed on capital
  valued at Sraffian prices of production. `sistema_Ndept!` remains the
  "independent sectors" version by default. See `docs/LIMITATIONS.md`
  item 1.
- `calcular_taxas_lucro_precos(sol, p)` in `src/analise.jl`, to
  reproduce outside the ODE the price-weighted profit rates used by the
  coupled system.
- `src/ameco_sdmx.jl`: client for the official AMECO SDMX REST API
  (`descarregar_ameco_sdmx`, `obter_dados_ameco(..., método=:sdmx)`),
  replacing the static-TXT-file download — discontinued by the European
  Commission (confirmed 2026-07). Verified with real Portuguese data
  (GDP, employment, compensation, GFCF, net capital stock);
  `verificar_sdmx_ameco()` performs a manual sanity check. The
  `:auto`/`:download` methods now use the SDMX API as the automatic
  path; the `:local`/`:csv` flows (an already-downloaded TXT/CSV file)
  remain available. See `docs/LIMITATIONS.md` item 3.
- `src/eurostat_sdmx.jl`: real sectoral data via the Eurostat SDMX API
  (VAB, compensation, consumption of fixed capital, employment, GFCF,
  net capital stock — dataflows `NAMA_10_A64`, `NAMA_10_A64_E`,
  `NAMA_10_A64_P5`, `NAMA_10_NFA_ST`), and a real technical matrix `A`
  from the symmetric IOT (`NAIO_10_CP1620`). Opt-in on both calibration
  paths:
  - `calibrar_modelo_portugal(..., fonte_dados=:eurostat)` — 19 NACE
    sectors, real data and a real matrix `A`; raises an error if
    unavailable (no silent fallback).
  - `calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` — 3 macro
    sectors, real data and a real matrix `A` (see next entry); falls
    back to fixed weights and a random A with a warning if the country
    lacks Eurostat coverage or the request fails.
  - `verificar_eurostat_setorial()` performs a manual sanity check.
  - Default behavior on both paths unchanged (synthetic / fixed
    weights); the test suite remains fully offline.
- `MAPA_AMECO_SDMX` (`src/ameco_sdmx.jl`) expanded from 6 to 22 of the
  25 variables in `CÓDIGOS_AMECO_VARIÁVEIS` (private/public consumption,
  exports, imports, paid employment, unemployment rate, labor force,
  compensation per employee, labor productivity, CPI, government
  revenue/expenditure, budget balance, current-account balance, unit
  labor costs, public debt), plus 2 series calculated from already
  mapped series (GDP deflator, goods trade balance) — 24/25 in total.
  Gross capital stock confirmed unavailable in this API (not left
  "pending"). All verified with real calls against Portugal (2022
  deficit, unemployment, and public debt match known values).
- `agregar_matriz_io` (`src/eurostat_sdmx.jl`): aggregation of technical
  matrices by the standard Leontief formula (columns weighted by the
  fine sectors' VAB/output), reusable with real or random matrices. Used
  to (a) build the real 3-sector AMECO matrix `A` from the already-clean
  real 19-sector matrix — the direct route (aggregating raw IOT flows)
  had been tried and rejected in an earlier session for mixing
  trade/transport margins with genuine services; and (b) the new
  `:macro`/`:média` aggregations of the INE path (see next entry). Tested
  offline with a hand-verified synthetic example.
- `calibrar_modelo_portugal` gains real aggregation for
  `agregação=:macro` (3 sectors, same groups as the AMECO path) and
  `:média` (10 sectors, standard NACE Rev.2 "A10" level) via
  `agregar_setores` (`src/calibracao_pt.jl`) — previously both values
  were accepted but silently ignored, always running `:detalhada`.
  Works with synthetic or real (Eurostat) data, with no code
  distinction.
- `sistema_Ndept_io!` gains a second optional mechanism, independent of
  capital mobility: `realização=true` adds an aggregate realization
  pressure (`ρ_real = Σmin(Oᵢ,(A·O)ᵢ)/Σ(A·O)ᵢ`, gross output vs.
  intermediate demand implied by A) that damps reinvestment when the
  technical structure cannot sustain current outputs — without
  introducing new state variables or requiring a
  differential-algebraic-equation (DAE) solver (explicitly out of
  scope). Robustness verified across 20 seed/μ combinations with no
  solver failures.
- `verificar_equilibrio_Ndept(sol, p)` (`src/analise.jl`):
  generalization to N sectors of `verificar_equilibrio_2dept`, an
  after-the-fact check (per-sector deviation `Oᵢ−(A·O)ᵢ` and aggregate
  `ρ_real`).

### Fixed
- `MAPA_AMECO_SDMX`: several mnemonics inherited from
  `CÓDIGOS_AMECO_VARIÁVEIS` (never before verified against the API) were
  wrong — `receitas_governo` (government revenue) and `despesas_governo`
  (government expenditure) had their codes swapped, and
  `consumo_privado`/`exportações`/`importações` used mnemonics already
  retired from the API (`UNCT`/`UXTG`/`UMTG` → `UCPH`/`UXGS`/`UMGS`).
  `_obter_série_sdmx` now accepts `transformação` and `unidade` (not
  every AMECO chapter uses TRANSFORMATION=1/UNIT=0).
- `calcular_precos_producao` now correctly rejects `r̄ ≥ R_max` (it used
  to only detect a literally singular matrix, silently allowing negative
  prices above R_max despite what the docstring promised).
- `simular_choque_salarial`: the reported `R_max` now uses the
  simulation's real technical matrix and labor coefficients (`p_base.A`,
  `l ∝ V`), instead of an auxiliary matrix `A_ref` and `l = ones(N)`. See
  `docs/LIMITATIONS.md` item 2.

## [0.3.0]

### Added
- AMECO integration for every country in the database (EU, Euro Area, US, Japan).
- `obter_dados_ameco` with methods `:auto`, `:download`, `:local`, `:csv`, `:sintético`, `:manual`.
- Automatic download of the TXT database (`descarregar_ameco_automatico`) and a fixed-width parser (`ler_ficheiro_ameco_txt`).
- AMECO CSV processor (`processar_csv_ameco`).
- Calibration from AMECO data (`calibrar_com_ameco_v2`, `calibrar_com_dados_ameco`).
- International comparison (`comparar_países_ameco`) and time series (`analisar_série_temporal_ameco`).
- Reorganization of the code into a modular repository (src/, test/, examples/, docs/).
- Test suite (`test/runtests.jl`) and demo (`examples/demo.jl`).
- `docs/LIMITATIONS.md` documenting known limitations.

### Fixed
- `Statistics` explicitly imported (mean/std/median/var/cor/quantile).
- ODE parameters passed as a `NamedTuple` (type-stable) instead of a `Dict`.
- `matriz_identidade(N)` replaces incorrect uses of LinearAlgebra's `I` constant.
- Calibration validation uses robust histograms (no hard dependency on boxplots).
- Fixed the undefined-`match_obj` bug in the AMECO update flow (the update function was removed/rewritten).
- Optional, shared `seed` across simulations for reproducibility and base-vs-shock comparability.

### Known (see docs/LIMITATIONS.md)
- The technical matrix A did not feed back into the N-department dynamics.
- `R_max` in the wage shock was illustrative (an auxiliary matrix).
- The AMECO parser's URLs and format were heuristic.
- AMECO calibration was limited to macro aggregation (3 sectors) with fixed weights.
- Default data are synthetic.

## [0.2.0]
- Portuguese national-accounts (INE) calibration with 19 NACE sectors (synthetic).
- Wage-profit distributive frontier and validation of calibrated profit rates.

## [0.1.0]
- Two- and N-department model, accumulation via ODEs.
- Labor values, Sraffian prices of production, the transformation problem.
