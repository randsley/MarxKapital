# MarxKapital

*[🇵🇹 Ler em português](README.pt.md)*

Mathematical modeling of Marxian economic theory in Julia: accumulation,
exploitation, organic composition, the tendential fall in the rate of
profit, the transformation of values into prices, the wage-profit
distributive frontier, and empirical calibration with national (Portuguese
INE) and European (**AMECO**, all countries in the database) data.

> Status: **v1.0.0** — functional for demonstration,
> methodological development, and an academic paper in `paper/`, with
> automated tests in CI
> ([![Tests](https://github.com/randsley/MarxKapital/actions/workflows/test.yml/badge.svg)](https://github.com/randsley/MarxKapital/actions/workflows/test.yml))
> ([![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705369.svg)](https://doi.org/10.5281/zenodo.21705369))
> ([![Paper DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705608.svg)](https://doi.org/10.5281/zenodo.21705608)).
> **Real** sectoral and AMECO data are available as an option (via
> official SDMX APIs), but the defaults remain **synthetic**.
> Before any serious empirical use, read
> [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) (limitations).

## Installation

```bash
git clone <this-repository> marxkapital
cd marxkapital
julia install_deps.jl        # installs DifferentialEquations, Plots, DataFrames, CSV, HTTP, StatsPlots, ForwardDiff, BifurcationKit
```

## Quick start

```julia
include("src/MarxKapital.jl")
model_help()                  # help / model overview

# Classical and generalized model
example_2dept()                # two-department example
example_Ndept(10)              # N-department example

# N departments coupled through A: capital mobility, aggregate realization
# pressure, or exact per-sector quantity rationing (optional, independent)
simulate_Ndept(10, coupled = true, μ = 0.3)
simulate_Ndept(10, coupled = true, realization = true)
simulate_Ndept(10, coupled = true, rationing = true)

# Values → prices of production
example_transformation()

# Portuguese national-accounts calibration (synthetic by default;
# data_source=:eurostat for real data)
params, validation = example_portugal()
params_real = calibrate_portugal_model(year = 2022, data_source = :eurostat)

# AMECO — any country in the database (sector_data=:eurostat for real
# sectoral data, EU/EEA countries)
list_ameco_countries()           # list AMECO countries
params, data = calibrate_with_ameco_v2("Germany", year = 2022)   # method = :auto

# International comparison
compare_ameco_countries(["Portugal", "Spain", "Germany", "France"], year = 2022)

# Time series
analyze_ameco_time_series("Portugal", years = 2000:2022)

# Wage-policy shock
depts = create_departments(6)
simulate_wage_shock(depts, 0.10)   # +10% wages
```

Or run the full demo:

```bash
julia --project=. examples/demo.jl
```

*Note: since v1.0.0 the code and its API are in English. Up to v0.8.x
function, keyword-argument and file names were in Portuguese
(`simular_Ndept`, `acoplado`, `racionamento`, `fonte_dados`, …);
[`docs/GLOSSARY.md`](docs/GLOSSARY.md) maps every old name to its new
one.*

## Notebooks

[`notebooks/`](notebooks/README.md) has worked examples, in English, that
run offline:

- six Jupyter notebooks, committed with their outputs so they can be read on
  GitHub: accumulation basics, values and prices, calibration and wage
  shocks, coupled sectors and automatic differentiation, TSSI valuation,
  and balanced growth, cycles and chaos;
- three interactive Pluto notebooks with sliders: the wage–profit frontier,
  accumulation with coupling and wage shocks, and accumulation cycles in
  the cross-dual model.

```bash
julia install_deps.jl --notebooks     # adds IJulia, Pluto, PlutoUI, JSON
julia -e 'using Pluto; Pluto.run()'   # then open a file in notebooks/pluto/
```

## AMECO data

`fetch_ameco_data("Portugal", method = ...)` accepts:

| method       | behavior                                                             |
|--------------|----------------------------------------------------------------------|
| `:auto`      | official SDMX API → recent local file → synthetic (fallback with warning) |
| `:sdmx`      | forces retrieval via the official AMECO SDMX API                       |
| `:download`  | alias for `:sdmx` (the legacy TXT download was discontinued)        |
| `:local`     | requires `ameco_data/ameco_full.txt` already downloaded (legacy path) |
| `:csv`       | processes an exported CSV (`file="..."`, legacy path)            |
| `:synthetic` | generates plausible synthetic series                                    |
| `:manual`    | shows download instructions and returns synthetic data                    |

Since 2026-07 AMECO exposes an [official SDMX REST
API](https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1)
(the same platform as Eurostat's newer data tool) — the static TXT file
that the `:local`/`:csv` methods still support was discontinued by the
Commission. Run `check_ameco_sdmx()` to confirm access before a real
analysis; see `docs/LIMITATIONS.md` item 3 for the exact status of each
variable. AMECO series also carry the Commission's forecasts for the
release year and the next one, unmarked; the SDMX path drops those years
by default, with a warning (`include_forecasts=true` keeps them; see item
12).

## Automatic differentiation, TSSI and bifurcations

Exact Jacobians and Hessians by forward-mode automatic differentiation
(ForwardDiff), a temporal single-system (TSSI) valuation layer, and
numerical continuation of fixed points (BifurcationKit):

```julia
Random.seed!(5)
sol, depts, p = simulate_Ndept(6, T = 60.0, seed = 5, coupled = true, realization = true)
X = sol.u[end]

system_jacobian(p, X)             # exact ∂f/∂X of the ODE right-hand side (also with rationing=true)
parameter_jacobian(p, X, :μ)       # ∂f/∂μ (any field of p, scalar or vector)
system_hessian(p, X)              # H[k,i,j] = ∂²f_k/∂X_i∂X_j
frontier_curvature(p.A, p.l, 0.2)   # w(r), w'(r), w''(r) of the wage-profit frontier

# Rationing map: exact Jacobian at the fixed point, spectrum, stability bound
# α_max and the radius-minimizing relaxation α
A = create_technical_matrix(12, density = 0.5); σ_c = fill(0.5, 12)
S = 5 .+ 10rand(12); O = 0.3 .+ 0.5rand(12)
rationing_jacobian(A, σ_c, S, O)

# TSSI: inputs bought at t−τ are costed at t−τ prices (fixed lag τ);
# compared against simultaneist (current-price) valuation
v = tssi_valuation(sol, p; τ = 1.0, h = 0.5)
# depreciation at historical cost (book value of fixed capital, v.book_value)
tssi_valuation(sol, p; τ = 1.0, h = 0.5, depreciation = :historical)
tssi_stability(tssi_data(X, p))   # does TSSI converge to simultaneist prices?

# Bifurcations: damped rationing iteration in the demand scale s, and the
# TSSI price map in the surplus-value scale (τ fixed)
rationing_bifurcation(A, σ_c, S, O; scale = (0.005, 2.0))
tssi_bifurcation(X, p; τ = 1.0, scale = (0.05, 10.0))
```

The rationing fixed point is differentiated through the implicit function
theorem (not by unrolling the iteration), so `system_jacobian` works with
`rationing=true`. A result from this analysis: ordered by rationing
severity, the rationing map's Jacobian is triangular with spectrum in
`[−1, 0]`, and `−1` is an eigenvalue once any sector is rationed. Damped
iteration therefore converges locally for every relaxation `α ∈ (0, 1)`,
while undamped iteration (`α = 1`) sits exactly on a flip boundary (see
`paper/main.tex`, Proposition 1). The default relaxation is `α = 2/3`
(`DEFAULT_RELAXATION`), which minimizes the local contraction rate: about
30% fewer iterations than the previous 0.5, converging in all 6870 test
runs (`paper/main.tex`, Table 2). The TSSI layer is valuation only: the
dynamics are unchanged.

## Balanced growth and accumulation cycles

With the optional cross-dual dynamics (`market_prices=true`), market
prices respond to sectoral excess demand and capital moves on profit
rates at those prices (Flaschel–Semmler). This gives the coupled model
interior balanced-growth rays. Without market prices it has none: capital
concentrates in one sector. The ODE is homogeneous of degree 1, so
balanced growth is a fixed point of the system normalized to the simplex,
and it can be continued and its bifurcations analyzed:

```julia
Random.seed!(5)
sol, _, p = simulate_Ndept(6, T = 1.0, seed = 5, coupled = true, μ = 0.5,
                          market_prices = true)          # β = 0.5 by default
X0 = sol.u[1]

eq = balanced_growth(p, X0)       # g★, r★, k★, shares, eigenvalues, stability
wage_sweep(p, X0; variant = :uniform)          # g★, r★ against the wage share ω

# Hopf bifurcation in the mobility of variable capital μ_v (off by default),
# with the normal form and the branch of limit cycles (collocation, Floquet)
pb = merge(p, (β = 0.1,))
res = accumulation_bifurcation(pb, X0, :μ_v; interval = (0.0, 2.5))
res.hopf[1]                               # θ, frequency, period, Lyapunov coefficient
simulated_cycle(pb, :μ_v, 1.1, X0)        # check the cycle by direct simulation
hopf_curve(pb, X0)                        # Hopf boundary μ_v,H(ω)
lyapunov_exponents(pb, :μ_v, 1.9, X0)     # λ₁ > 0: chaos
simulated_hysteresis(pb, :μ_v, 1.30:0.01:1.56, X0)   # coexisting attractors
# exit friction (off by default): outflows damped as a sector's share shrinks
simulated_cycle(merge(pb, (exit_friction = 0.05,)), :μ_v, 2.4, X0).min_share
```

In every random economy tested, balanced growth loses stability at a
supercritical Hopf bifurcation in `μ_v`. A higher wage share moves the
boundary up. At higher `μ_v` the cycles give way to a torus, to a window
where a stable cycle and the torus coexist, and to chaos. See `paper/main.tex`, Sections 3.6 and 5.6, and
`docs/LIMITATIONS.md` item 11.

## Real sectoral data (Eurostat)

Both calibration paths use synthetic structure or fixed sectoral weights
by default. Real Eurostat sectoral data are available as an option
(`src/eurostat_sdmx.jl`):

```julia
# Portuguese national accounts (INE) — 19 (:detailed), 10 (:medium), or 3
# (:macro) sectors, with a real technical matrix A (Eurostat IOT)
params_real = calibrate_portugal_model(year = 2022, data_source = :eurostat, aggregation = :detailed)

# AMECO (3 macro-sectors), with a real technical matrix A (aggregated from
# the 19-sector matrix)
params_real, data = calibrate_with_ameco_v2("Portugal", year = 2022, sector_data = :eurostat)

# Capital stock via perpetual-inventory method instead of the directly
# reported figure (optional)
params_pim = calibrate_portugal_model(year = 2022, data_source = :eurostat, perpetual_inventory = true)

# Real final demand (from the same input-output table) in the dynamics:
# real A, household consumption basket, and rationing net of final
# consumption and exports (params_real.final_demand is nothing on synthetic data)
depts = departments_from_params(params_real)
simulate_Ndept_custom(depts; coupled = true, market_prices = true, A = params_real.A,
                      basket = consumption_basket(params_real.final_demand))
simulate_Ndept_custom(depts; coupled = true, rationing = true, A = params_real.A,
                      final_demand_share = exogenous_demand_share(params_real.final_demand))

# Manual check of Eurostat access (not run in the automated test suite)
check_eurostat_sectoral()
```

Only covers EU/EEA countries; outside that coverage, or if the request
fails, the AMECO path automatically falls back to fixed weights and a
random matrix `A` (with a warning) — the Portuguese-only INE path raises
an error instead of silently degrading, since it is an explicit request
for real data. The real matrix `A` uses `NAIO_10_CP1700` (the genuine
symmetric input-output table — `NAIO_10_CP1620`, used previously, turned
out to be a trade-and-transport-margins satellite table, not the IOT
itself; see `docs/LIMITATIONS.md` item 4-bis) with domestic-use flows
only (`stk_flow=DOM`), no negative cells, reconciled directly against the
gross output published by the table itself (`P1`). Since this table is a
benchmark product (not annual — Portugal: 2010/2013/2015/2017/2020), a
request for a year without a published table falls back to the nearest
available year, with a warning. See `docs/LIMITATIONS.md` items 4 and
4-bis for the exact status.

## Repository structure

```
marxkapital/
├── src/
│   ├── MarxKapital.jl      # loader (using + includes)
│   ├── types.jl            # types and constants (AMECO)
│   ├── core.jl             # matrices, departments, ODEs, simulation
│   ├── analysis.jl         # profit rates, labor values, prices, transformation
│   ├── distribution.jl     # wage-profit curve and calibration validation
│   ├── shocks.jl           # wage shocks
│   ├── differentiation.jl  # automatic differentiation: Jacobians, Hessians, rationing spectrum
│   ├── tssi.jl             # temporal single-system (TSSI) valuation, fixed lag τ
│   ├── cross_dual.jl       # cross-dual dynamics: market prices and capital mobility
│   ├── growth.jl           # balanced growth: normalized system, wage-share sweep
│   ├── bifurcation.jl      # continuation and bifurcations: maps, Hopf, limit cycles (BifurcationKit)
│   ├── calibration_pt.jl   # Portuguese (INE) calibration, synthetic and real (Eurostat)
│   ├── ameco.jl            # AMECO: synthetic, calibration, comparison, series
│   ├── ameco_sdmx.jl       # official AMECO SDMX API
│   ├── ameco_download.jl   # automatic download + TXT/CSV parser (legacy)
│   ├── eurostat_sdmx.jl    # Eurostat SDMX API: real sectoral data + IOT
│   ├── plotting.jl         # plots
│   └── examples.jl         # ready-made examples + help + test_model
├── test/
│   ├── runtests.jl         # test suite
│   └── notebooks.jl        # smoke test: runs every notebook offline
├── examples/demo.jl
├── notebooks/              # worked examples (see notebooks/README.md)
│   ├── jupyter/            # six narrative notebooks, with outputs
│   └── pluto/              # three interactive notebooks
├── docs/LIMITATIONS.md     # required reading (+ .pt.md in Portuguese)
├── paper/                  # academic paper (LaTeX), reproducible from real data
│   ├── main.tex            # methodology + empirical application (Portugal)
│   ├── generate_results.jl # generates every figure/table in the paper
│   ├── matrix_audit.jl     # technical matrix A audit (manual check)
│   ├── monte_carlo.jl      # systematic sweeps (convergence, dispersion)
│   ├── jacobian_bifurcation.jl # exact Jacobian, bifurcations, TSSI (offline)
│   ├── accumulation_bifurcation.jl # balanced growth, Hopf, cycles (offline)
│   └── figures/
├── data/                   # (empty; downloaded data lands here, not version-controlled)
├── install_deps.jl
├── Project.toml
├── CHANGELOG.md
├── LICENSE
├── README.md               # English (default)
└── README.pt.md            # Portuguese
```

## Foundations

Categories: `c` (constant capital), `v` (variable capital), `s = e·v`
(surplus value), `k = c/v` (organic composition), `r = e/(k+1)` (profit
rate). Accumulation dynamics are integrated with `DifferentialEquations.jl`
(Tsit5). Labor values `λ = (I − A)⁻¹ l` and Sraffian prices of production
`p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ l`, with the maximum profit rate `R_max`
derived from the spectral radius of `Aᵀ`.

## Tests

```bash
julia --project=. test/runtests.jl
```

254 tests, run automatically in CI (GitHub Actions, Julia 1.10 and 1) on
every push to `main` — see `.github/workflows/test.yml`. CI then runs every
notebook (`julia test/notebooks.jl`, see `notebooks/README.md`). The suite covers
the default synthetic/opt-in paths and runs fully offline; the real-data
paths (`method=:sdmx`, `data_source=:eurostat`, `sector_data=:eurostat`)
require network access and are not in CI — check them manually with
`check_ameco_sdmx()`, `check_eurostat_sectoral()`, and
`paper/matrix_audit.jl`.

## Limitations

Read [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md). In summary: (1) the
matrix A only feeds back into the N-department simulation optionally
(`coupled=true`), with three available mechanisms — capital mobility
(conserves aggregate constant capital exactly, by construction),
aggregate realization pressure (`realization=true`), and exact per-sector
quantity rationing (`rationing=true`, solved by fixed point, no DAE
required); both supply-constrained mechanisms reconstruct genuine gross
output from the model's own state (not a value-added-type approximation),
and investment demand is converted to output scale before A is applied;
(2) the wage-shock `R_max` uses the simulation's real matrix and
coefficients; (3) the AMECO download uses the official SDMX API (26
series obtained, 24 mapped directly + 2 calculated); (4)-(5) real
sectoral calibration (Eurostat), including a real matrix A on both paths
(`NAIO_10_CP1700`, domestic-use flows only, no negative cells, reconciled
exactly against the table's own published output — a benchmark table, not
annual), available as an option, but with fixed weights/random matrix A
by default; (6) synthetic data remains the default behavior; (7) capital
stock can be computed via perpetual inventory
(`perpetual_inventory=true`) instead of the directly reported figure,
also optional.

## Academic paper

[`paper/main.tex`](paper/main.tex) presents a methodological component
(the model, the three coupling mechanisms, the rationing mechanism as a
fixed point) and an empirical application to Portugal, with every
figure/table generated reproducibly from real data
(`paper/generate_results.jl`, `paper/monte_carlo.jl`,
`paper/matrix_audit.jl` — no number entered by hand). Compile with
`latexmk -pdf paper/main.tex`.

Published on Zenodo with its own DOI, separate from the software DOI:
[10.5281/zenodo.21705608](https://doi.org/10.5281/zenodo.21705608).

## License

MIT — see [`LICENSE`](LICENSE).
