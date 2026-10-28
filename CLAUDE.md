# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MarxKapital: a Julia model of Marxian economics (accumulation, exploitation, organic composition, falling rate of profit, values → prices of production, wage-profit frontier) with calibration against Portuguese national accounts (INE/Eurostat) and AMECO data. It also contains an academic paper (`paper/`) whose every number is generated from code.

## Commands

```bash
julia install_deps.jl                         # one-time: Pkg.add the deps (see "Loading model" below)
julia --project=. test/runtests.jl            # full suite (offline; 213 tests)
julia --project=. examples/demo.jl            # full demo
julia --project=. paper/generate_results.jl   # regenerate paper figures/tables (needs network)
julia --project=. paper/monte_carlo.jl        # Monte Carlo sweeps for the paper (offline)
julia --project=. paper/matrix_audit.jl       # audit of real matrix A (needs network)
julia --project=. paper/jacobian_bifurcation.jl  # Jacobian/bifurcation/TSSI figures + figures/jacobian_stats.tex (offline)
julia --project=. paper/accumulation_bifurcation.jl # balanced growth/Hopf/cycles/chaos figures + figures/accumulation_stats.tex (offline, ~30 min)
latexmk -pdf paper/main.tex                   # build the paper
julia install_deps.jl --notebooks             # also IJulia, Pluto, PlutoUI, JSON (for notebooks/)
julia test/notebooks.jl                       # smoke-run every notebook offline (--all: include "slow" cells)
julia notebooks/strip_outputs.jl              # after re-executing Jupyter notebooks: keep only PNG plot outputs
```

Set `GKSwstype=100` when running headless (CI does; the paper scripts set it themselves).

There is no per-testset filter. To run a single test, load the code in a REPL and run that `@testset` block by hand:

```julia
using Test; include("src/MarxKapital.jl")
# paste the @testset from test/runtests.jl
```

CI (`.github/workflows/test.yml`) runs `julia install_deps.jl` then `julia test/runtests.jl` on Julia 1.10 and 1, on push/PR to `main`, then installs PlutoUI and JSON and runs `julia test/notebooks.jl`.

## Loading model (important)

This is **not** a registered package and is not loaded with `using MarxKapital`. `Project.toml` deliberately has no `[deps]` (no hand-written UUIDs); deps are installed by `install_deps.jl`, and `Manifest.toml` is gitignored. Code is loaded script-style with `include("src/MarxKapital.jl")`, which does all the `using`s and then `include`s the source files **in order**. Everything ends up in `Main`. When adding a source file, add its `include` to `src/MarxKapital.jl` after whatever it depends on (`types.jl` first; `eurostat_sdmx.jl` before `calibration_pt.jl`; `ameco_sdmx.jl` before `ameco.jl`). New dependencies go in the `deps` list in `install_deps.jl` and in a `using` in the loader.

## Language conventions

- Since v1.0.0 all identifiers, keyword args, file names, comments and console output are in **English** (US spelling: labor, analyze). Up to v0.8.x they were Portuguese; `docs/GLOSSARY.md` is the old → new migration table. Keep new code in English, and keep the verb prefixes the API uses (`compute_`, `simulate_`, `fetch_`, `check_`, `calibrate_`, …). Data strings are English too (AMECO country names such as `"Germany"`, NACE section titles, the 3 macro sectors `"Primary"/"Secondary"/"Tertiary"`).
- Past CHANGELOG entries keep the Portuguese identifiers they were written with; don't rewrite history.
- Docs are bilingual, English primary: `README.md`, `CHANGELOG.md`, `docs/LIMITATIONS.md`, `docs/PROJECT_STATUS.md`, each with a `.pt.md` Portuguese version. Change both versions together. `docs/GLOSSARY.md` is English only.

## Architecture

- `types.jl`: the `Department` type (validated invariants: `k = c/v`, reinvestment shares `σ_c + σ_v + γ = 1`, depreciation `δ`), `CalibratedParameters`, `INEData`, `AMECOData`, and the AMECO country/mnemonic dictionaries.
- `core.jl`: technical matrix `A` (always normalized to spectral radius < 1) and ODE systems integrated with DifferentialEquations.jl (Tsit5). ODE params are a **NamedTuple** (for type stability), not a Dict.
  - `system_Ndept!` is the default, with sectors independent and `A` unused in the dynamics.
  - `system_Ndept_io!` (`coupled=true`) couples sectors through `A` with three optional, independent mechanisms. The first is capital mobility `μ·(rᵢ−r̄)·Cᵢ`, with `r̄` **C-weighted** so the term sums to exactly 0 (tested). The second is aggregate realization pressure (`realization=true`). The third is exact per-sector quantity rationing (`rationing=true`), solved by fixed point in `_solve_rationing`. Both supply-constrained mechanisms use genuine gross output reconstructed as `x = W/(1−Σᵢ A[i,j])`, not the value-added flow `W = δC+V+S`.
- `analysis.jl`: profit rates, labor values `λ = (I−A)⁻¹ l`, `R_max` from the spectral radius of `Aᵀ`, Sraffian prices `p = w(1+r̄)[I−(1+r̄)Aᵀ]⁻¹ l`, and the transformation problem.
- `distribution.jl` (wage-profit frontier and calibration validation score) and `shocks.jl` (wage shocks; base and shock share a `seed`).
- Data layer: `calibration_pt.jl` (INE, 19/10/3 sectors), `ameco.jl` (calibration, comparison, time series), `ameco_sdmx.jl` (official AMECO SDMX API), `ameco_download.jl` (legacy TXT/CSV parser), and `eurostat_sdmx.jl` (real sectoral data and the IOT matrix `A` from `NAIO_10_CP1700`, `stk_flow=DOM`; **not** `NAIO_10_CP1620`, which is a margins satellite table and was a past bug).
- `differentiation.jl`: ForwardDiff Jacobians/Hessians of the ODE RHS and the rationing map spectrum (`rationing_jacobian`). The rationing fixed point is differentiated via the implicit function theorem (`_rationing_dual` in `core.jl`), so model code on the AD path must stay **generic in number type**: no `ones(N)`/`zeros(N)` buffers written with `.=` from state-dependent values, no `try/catch` that swallows `MethodError` (see `_price_value_ratio`).
- Rationing damping defaults to `DEFAULT_RELAXATION = 2/3` (`core.jl`), the minimax-optimal value given the spectrum in `[−1, 0]`; don't hard-code a relaxation elsewhere.
- `cross_dual.jl`: optional cross-dual dynamics (`market_prices=true`, state `[C; V; q]` with log market prices `q`, `cross_dual_system!`). Needs `coupled=true` and cannot be combined with `realization`/`rationing`. Without it there is **no interior balanced growth**, because sectoral profit rates don't depend on relative size. `μ_v` (mobility of variable capital, default 0) works in both coupled systems.
- `growth.jl`: the RHS is homogeneous of degree 1, so steady states are balanced-growth rays. They are fixed points of `normalized_system` in free simplex coordinates (`_from_free`/`_to_free`; prices mean-zero). Also `balanced_growth` (warm-up + Newton), `with_parameter` (`:μ`, `:μ_v`, `:ω`, `:e_scale`) and `wage_sweep`.
- `tssi.jl`: TSSI valuation layer (fixed lag τ) over trajectories; does not change the dynamics. `bifurcation.jl`: BifurcationKit continuation of fixed points of *maps* (rationing step, TSSI price map), with fold/flip/Neimark–Sacker classified from multipliers (BK's own detectors assume ODEs and miss flips). `accumulation_bifurcation` continues balanced growth of the cross-dual ODE (BK's own Hopf detection; `dsmax` ≤ 0.01 or close Hopf pairs are missed). It seeds limit-cycle collocation from the Hopf normal-form predictor (`BK.predictor`), because BK's automatic branch switching hits a singular Jacobian here. Check cycles with `simulated_cycle`. `lyapunov_exponents` (Benettin method, exact Jacobian; ≈100 s at N=6) classifies irregular motion, and `simulated_hysteresis` detects coexisting attractors with up/down sweeps. BifurcationKit is imported as `BK` (prefixed) to avoid name clashes; in 0.8.8 the collocation type is `BK.Collocation`.
- `examples.jl` holds the ready-made examples, `model_help()`, and `test_model()` (internal battery, also called from the tests). `plotting.jl` holds the plots.
- `notebooks/` (English prose only, not bilingual): `jupyter/*.ipynb` are committed **executed**, with PNG-only plot outputs, and load the model with a relative `include` from their own folder. `pluto/*.jl` activate the repo environment in their first cell (which disables Pluto's package manager) and must `using` every package they call directly, because Pluto doesn't see packages loaded inside the `include`. Edit Pluto notebooks in Pluto, so the file format and cell order stay valid. When the API changes, `test/notebooks.jl` catches broken notebooks; re-execute and strip the Jupyter ones.

## Data and testing invariants

- **Defaults are synthetic.** Real data are opt-in (`data_source=:eurostat`, `sector_data=:eurostat`, `method=:sdmx`/`:auto`). The AMECO path falls back to synthetic data or fixed weights with a warning. The INE path raises an error instead of degrading silently when real data were requested explicitly.
- The test suite must stay **offline**. Network paths are checked manually with `check_ameco_sdmx()`, `check_eurostat_sectoral()`, and `paper/matrix_audit.jl`.
- `seed` in `simulate_Ndept` only fixes matrix `A`. `create_departments` uses the global RNG, so tests call `Random.seed!` before simulating.
- The Eurostat IOT is a benchmark table, not annual (PT: 2010/2013/2015/2017/2020); a missing year falls back to the nearest one with a warning.
- No number in `paper/main.tex` is entered by hand. Figures and tables come from the `paper/*.jl` scripts into `paper/figures/` (committed, as is `paper/main.pdf`). Sections 3.3–3.5/5.5 read their numbers as `\newcommand` macros from `paper/figures/jacobian_stats.tex`, and Sections 3.6/5.6 from `paper/figures/accumulation_stats.tex`; rerun `paper/jacobian_bifurcation.jl` after changing rationing/TSSI code, and `paper/accumulation_bifurcation.jl` after changing the cross-dual, balanced-growth or accumulation-bifurcation code.
- `docs/LIMITATIONS.md` is the record of known limitations and their fixes. Update it (both languages) when a model limitation changes.

## Releases

The version string appears in `Project.toml`, `CITATION.cff`, the status line of both READMEs (`README.md`, `README.pt.md`), and both CHANGELOGs (Keep a Changelog format, semver). Bump them all together. GitHub releases are archived to Zenodo. The software DOI and the paper DOI are separate.
