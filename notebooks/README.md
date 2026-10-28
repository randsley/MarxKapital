# Notebooks

Worked examples of MarxKapital in two formats:

- **`jupyter/`**: six narrative notebooks, committed with their outputs, so they can be read on GitHub without running anything.
- **`pluto/`**: three interactive [Pluto](https://plutojl.org) notebooks with sliders, which recompute as you change the parameters.

Everything runs offline on the synthetic defaults. The prose and the MarxKapital API are both in English.

## Jupyter

| Notebook | Contents |
|---|---|
| [01_accumulation_basics](jupyter/01_accumulation_basics.ipynb) | Departments, the rate of profit, the two-department model, N departments, raising the rate of exploitation |
| [02_values_and_prices](jupyter/02_values_and_prices.ipynb) | Labor values, prices of production, the wage–profit frontier and its curvature, the transformation problem |
| [03_calibration_and_shocks](jupyter/03_calibration_and_shocks.ipynb) | INE and AMECO calibration (synthetic), validation, international comparison, time series, wage shocks |
| [04_coupled_sectors_and_ad](jupyter/04_coupled_sectors_and_ad.ipynb) | Capital mobility, realization and rationing, exact Jacobians, the rationing map's spectrum and its bifurcation |
| [05_tssi_valuation](jupyter/05_tssi_valuation.ipynb) | TSSI against simultaneist valuation, the production lag, stability and bifurcation of TSSI prices |
| [06_growth_cycles_chaos](jupyter/06_growth_cycles_chaos.ipynb) | Balanced growth, the wage-share sweep, the Hopf bifurcation and limit cycles, the Hopf boundary, Lyapunov exponents, hysteresis |

## Pluto

| Notebook | What you can change |
|---|---|
| [frontier_explorer](pluto/frontier_explorer.jl) | The economy (sectors, seed, density of `A`) and the rate of profit: the frontier, its curvature, prices against values |
| [accumulation_explorer](pluto/accumulation_explorer.jl) | Sectors, horizon, rate of exploitation, coupling mechanism, capital mobility, and a wage shock |
| [cycles_explorer](pluto/cycles_explorer.jl) | `μ_v`, the speed of price adjustment `β` and the rates of surplus value, in the cross-dual model: eigenvalues, trajectory, phase portrait, stability along `μ_v` |

## Running them

Install the model's dependencies, plus the notebook tools, from the repository root:

```bash
julia install_deps.jl --notebooks     # adds IJulia, Pluto, PlutoUI and JSON
```

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
julia test/notebooks.jl          # as in CI
julia test/notebooks.jl --all    # including the slow cells
```

The committed Jupyter outputs keep only the PNG of each plot. If you change a notebook, re-execute it and strip the extra plot formats before committing:

```bash
jupyter nbconvert --to notebook --execute --inplace notebooks/jupyter/0*.ipynb
julia notebooks/strip_outputs.jl
```
