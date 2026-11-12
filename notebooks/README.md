# Notebooks

Worked examples of MarxKapital in two formats:

- **`jupyter/`**: fourteen narrative notebooks, committed with their outputs, so they can be read on GitHub without running anything.
- **`pluto/`**: three interactive [Pluto](https://plutojl.org) notebooks with sliders, which recompute as you change the parameters.

Everything runs offline. Notebooks 1–6 and the Pluto notebooks use the synthetic defaults; notebooks 7 and 8 use real AMECO data from a static extract, `data/ameco_eu27.csv` (rebuild it with `julia data/build_ameco_eu.jl`, which needs network; provenance in `data/ameco_eu27_PROVENANCE.md`), and notebooks 9–14 real Eurostat sectoral accounts (Portugal; 26 EU countries) from `data/eurostat_eu_sectors.csv` (26 EU countries; `julia data/build_eurostat_sectors.jl`; provenance in `data/eurostat_eu_sectors_PROVENANCE.md`). The prose and the MarxKapital API are both in English.

## Jupyter

| Notebook | Contents |
|---|---|
| [01_accumulation_basics](jupyter/01_accumulation_basics.ipynb) | Departments, the rate of profit, the two-department model, N departments, raising the rate of exploitation |
| [02_values_and_prices](jupyter/02_values_and_prices.ipynb) | Labor values, prices of production, the wage–profit frontier and its curvature, the transformation problem |
| [03_calibration_and_shocks](jupyter/03_calibration_and_shocks.ipynb) | INE and AMECO calibration (synthetic), validation, international comparison, time series, wage shocks |
| [04_coupled_sectors_and_ad](jupyter/04_coupled_sectors_and_ad.ipynb) | Capital mobility, realization and rationing, exact Jacobians, the rationing map's spectrum and its bifurcation |
| [05_tssi_valuation](jupyter/05_tssi_valuation.ipynb) | TSSI against simultaneist valuation, the production lag, stability and bifurcation of TSSI prices |
| [06_growth_cycles_chaos](jupyter/06_growth_cycles_chaos.ipynb) | Balanced growth, the wage-share sweep, the Hopf bifurcation and limit cycles, the Hopf boundary, Lyapunov exponents, hysteresis |
| [07_eu_profit_rates](jupyter/07_eu_profit_rates.ipynb) | **Real data.** `e`, `k` and `r` for the EU27 member states, 1995–2024: the self-employment adjustment, trends, an exact split of the change in `r` into exploitation and composition, and why the valuation decides the trend in `k` |
| [08_capital_mobility](jupyter/08_capital_mobility.ipynb) | **Real data.** The model's capital-mobility coefficient `μ` estimated from EU27 capital flows, 1996–2024: between and within countries, common shocks, a spatial panel with Driscoll–Kraay errors and spatial CCE (via [SpatialEconometrics.jl](https://github.com/randsley/SpatialEconometrics.jl)), before and after 2008, and the estimates back in the model |
| [09_sectoral_mobility](jupyter/09_sectoral_mobility.ipynb) | **Real data.** `μ` between Portugal's 15 market sectors, 2002–2023, from Eurostat's accounts by industry: capital received beyond own surplus against the lagged profit-rate gap, between and within sectors, Driscoll–Kraay errors, why the self-employment adjustment flips the sign, before and after 2008 |
| [10_eu_sectoral_mobility](jupyter/10_eu_sectoral_mobility.ipynb) | **Real data.** The same `μ` between the 15 market sectors of 26 EU countries, with country × year effects for each national credit cycle: negative in almost every country, robust to trimming and to instrumenting the gap; the decomposition that shows what fails is the model's common reinvestment share; year-by-year `μₜ` and why the break at 2008 is in that share, not in `μ` |
| [11_reinvestment_and_mobility](jupyter/11_reinvestment_and_mobility.ipynb) | **Real data.** The model's investment function with a reinvestment share that falls with relative profitability (`η`): `μ` turns positive, `η` is not identified and is calibrated from the margin of reinvestment, the 2008 break is in depreciation; and why `η` = 1 destabilizes the model |
| [12_incremental_profit_rates](jupyter/12_incremental_profit_rates.ipynb) | **Real data.** Shaikh's incremental rate of profit, the return on new investment: its gaps are mostly transitory but not equalized, and capital follows the average-rate gap, not the incremental one; why the model's mobility term keeps the average rate |
| [13_investment_floor_and_market_prices](jupyter/13_investment_floor_and_market_prices.ipynb) | **Real data.** The linear reinvestment form on every row, losses included: `η̂` ≈ 0.15 and `μ̂` ≈ 0.06; no exit of capital through investment, but a floor on gross investment near replacement; and stable interior balanced growth of Portugal's market sectors at market prices |
| [14_variable_capital_mobility_and_tssi_dynamics](jupyter/14_variable_capital_mobility_and_tssi_dynamics.ipynb) | **Real data.** The mobility of variable capital `μ_v` estimated on the EU panel (≈ 0.02–0.07), 33 times below the Hopf point of Portugal's calibrated economy, so the accumulation cycles are outside the empirical range; and accumulation driven by profit rates on capital at historical cost (TSSI), which here barely changes balanced growth or the response to a price shock |

## Pluto

| Notebook | What you can change |
|---|---|
| [frontier_explorer](pluto/frontier_explorer.jl) | The economy (sectors, seed, density of `A`) and the rate of profit: the frontier, its curvature, prices against values |
| [accumulation_explorer](pluto/accumulation_explorer.jl) | Sectors, horizon, rate of exploitation, coupling mechanism, capital mobility, and a wage shock |
| [cycles_explorer](pluto/cycles_explorer.jl) | `μ_v`, the speed of price adjustment `β` and the rates of surplus value, in the cross-dual model: eigenvalues, trajectory, phase portrait, stability along `μ_v` |

## Running them

Install the model's dependencies, plus the notebook tools, from the repository root:

```bash
julia install_deps.jl --notebooks     # adds IJulia, Pluto, PlutoUI, JSON and SpatialEconometrics
```

Notebook 8 uses [SpatialEconometrics.jl](https://github.com/randsley/SpatialEconometrics.jl), which is not registered: `install_deps.jl` adds it from GitHub at the commit pinned in `SPATIALECONOMETRICS`, so the notebook's results do not move with the package. It is a notebook-only dependency; `src/` never loads it.

**Jupyter.** Start Jupyter from the repository and open a notebook in `notebooks/jupyter/`. The notebooks load the model with `include(joinpath("..", "..", "src", "MarxKapital.jl"))`, so the working directory must be the notebook's folder (the Jupyter default).

```bash
julia -e 'using IJulia; notebook(dir = pwd())'   # or: jupyter lab
```

**Pluto.** Start Pluto and open a file from `notebooks/pluto/`:

```bash
julia -e 'using Pluto; Pluto.run()'
```

The Pluto notebooks activate the repository's environment in their first cell. This turns off Pluto's built-in package manager, so they use the packages installed by `install_deps.jl`.

The first run of each notebook takes a minute or so while Julia compiles. In notebook 6, the two cells tagged `slow` (Lyapunov exponents and hysteresis) take a few minutes.

## Testing

`test/notebooks.jl` runs the code cells of every notebook offline, skipping cells tagged `slow`. CI runs it after the main test suite.

```bash
julia install_deps.jl --notebook-test   # only what the smoke test needs (as in CI)
julia test/notebooks.jl          # as in CI
julia test/notebooks.jl --all    # including the slow cells
```

The committed Jupyter outputs keep only the PNG of each plot. If you change a notebook, re-execute it and strip the extra plot formats before committing:

```bash
jupyter nbconvert --to notebook --execute --inplace notebooks/jupyter/0*.ipynb
julia notebooks/strip_outputs.jl
```
