# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MarxKapital: a Julia model of Marxian economics (accumulation, exploitation, organic composition, falling rate of profit, values → prices of production, wage-profit frontier) with calibration against Portuguese national accounts (INE/Eurostat) and AMECO data. It also contains an academic paper (`paper/`) whose every number is generated from code.

## Commands

```bash
julia install_deps.jl                         # one-time: Pkg.add the deps (see "Loading model" below)
julia --project=. test/runtests.jl            # full suite (offline; 207 tests)
julia --project=. examples/demo.jl            # full demo
julia --project=. paper/gerar_resultados.jl   # regenerate paper figures/tables (needs network)
julia --project=. paper/monte_carlo.jl        # Monte Carlo sweeps for the paper (offline)
julia --project=. paper/matrix_audit.jl       # audit of real matrix A (needs network)
julia --project=. paper/jacobiana_bifurcacao.jl  # Jacobian/bifurcation/TSSI figures + figures/jacobian_stats.tex (offline)
julia --project=. paper/acumulacao_bifurcacao.jl # balanced growth/Hopf/cycles/chaos figures + figures/acumulacao_stats.tex (offline, ~30 min)
latexmk -pdf paper/main.tex                   # build the paper
julia install_deps.jl --notebooks             # also IJulia, Pluto, PlutoUI, JSON (for notebooks/)
julia test/notebooks.jl                       # smoke-run every notebook offline (--all: include "slow" cells)
julia notebooks/limpar_saidas.jl              # after re-executing Jupyter notebooks: keep only PNG plot outputs
```

Set `GKSwstype=100` when running headless (CI does; the paper scripts set it themselves).

There is no per-testset filter. To run a single test, load the code in a REPL and run that `@testset` block by hand:

```julia
using Test; include("src/MarxKapital.jl")
# paste the @testset from test/runtests.jl
```

CI (`.github/workflows/test.yml`) runs `julia install_deps.jl` then `julia test/runtests.jl` on Julia 1.10 and 1, on push/PR to `main`, then installs PlutoUI and JSON and runs `julia test/notebooks.jl`.

## Loading model (important)

This is **not** a registered package and is not loaded with `using MarxKapital`. `Project.toml` deliberately has no `[deps]` (no hand-written UUIDs); deps are installed by `install_deps.jl`, and `Manifest.toml` is gitignored. Code is loaded script-style with `include("src/MarxKapital.jl")`, which does all the `using`s and then `include`s the source files **in order**. Everything ends up in `Main`. When adding a source file, add its `include` to `src/MarxKapital.jl` after whatever it depends on (`estruturas.jl` first; `eurostat_sdmx.jl` before `calibracao_pt.jl`; `ameco_sdmx.jl` before `ameco.jl`). New dependencies go in the `deps` list in `install_deps.jl` and in a `using` in the loader.

## Language conventions

- All identifiers, keyword args, comments, and console output are in **Portuguese**, including non-ASCII names (`simular_Ndept`, `acoplado`, `racionamento`, `realização`, `fonte_dados`, `inventário_perpétuo`, `:sintético`, `listar_países_ameco`, `ParâmetrosCalibrados`). Keep new code consistent; the API is intentionally untranslated.
- Docs are bilingual: `README.md` (English, the default) and `README.pt.md`; the others are Portuguese originals (`CHANGELOG.md`, `docs/LIMITACOES.md`, `docs/ESTADO_DO_PROJETO.md`) with `.en.md` translations. Change both versions together.

## Architecture

- `estruturas.jl`: the `Departamento` type (validated invariants: `k = c/v`, reinvestment shares `σ_c + σ_v + γ = 1`, depreciation `δ`), `ParâmetrosCalibrados`, `DadosINE`, `DadosAMECO`, and the AMECO country/mnemonic dictionaries.
- `nucleo.jl`: technical matrix `A` (always normalized to spectral radius < 1) and ODE systems integrated with DifferentialEquations.jl (Tsit5). ODE params are a **NamedTuple** (for type stability), not a Dict.
  - `sistema_Ndept!` is the default, with sectors independent and `A` unused in the dynamics.
  - `sistema_Ndept_io!` (`acoplado=true`) couples sectors through `A` with three optional, independent mechanisms. The first is capital mobility `μ·(rᵢ−r̄)·Cᵢ`, with `r̄` **C-weighted** so the term sums to exactly 0 (tested). The second is aggregate realization pressure (`realização=true`). The third is exact per-sector quantity rationing (`racionamento=true`), solved by fixed point in `_resolver_racionamento`. Both supply-constrained mechanisms use genuine gross output reconstructed as `x = W/(1−Σᵢ A[i,j])`, not the value-added flow `W = δC+V+S`.
- `analise.jl`: profit rates, labor values `λ = (I−A)⁻¹ l`, `R_max` from the spectral radius of `Aᵀ`, Sraffian prices `p = w(1+r̄)[I−(1+r̄)Aᵀ]⁻¹ l`, and the transformation problem.
- `distributiva.jl` (wage-profit frontier and calibration validation score) and `choques.jl` (wage shocks; base and shock share a `seed`).
- Data layer: `calibracao_pt.jl` (INE, 19/10/3 sectors), `ameco.jl` (calibration, comparison, time series), `ameco_sdmx.jl` (official AMECO SDMX API), `ameco_download.jl` (legacy TXT/CSV parser), and `eurostat_sdmx.jl` (real sectoral data and the IOT matrix `A` from `NAIO_10_CP1700`, `stk_flow=DOM`; **not** `NAIO_10_CP1620`, which is a margins satellite table and was a past bug).
- `diferenciacao.jl`: ForwardDiff Jacobians/Hessians of the ODE RHS and the rationing map spectrum (`jacobiana_racionamento`). The rationing fixed point is differentiated via the implicit function theorem (`_racionamento_dual` in `nucleo.jl`), so model code on the AD path must stay **generic in number type**: no `ones(N)`/`zeros(N)` buffers written with `.=` from state-dependent values, no `try/catch` that swallows `MethodError` (see `_razão_preço_valor`).
- Rationing damping defaults to `RELAXAÇÃO_PADRÃO = 2/3` (`nucleo.jl`), the minimax-optimal value given the spectrum in `[−1, 0]`; don't hard-code a relaxation elsewhere.
- `cruzado.jl`: optional cross-dual dynamics (`preços_mercado=true`, state `[C; V; q]` with log market prices `q`, `sistema_cruzado!`). Needs `acoplado=true` and cannot be combined with `realização`/`racionamento`. Without it there is **no interior balanced growth**, because sectoral profit rates don't depend on relative size. `μ_v` (mobility of variable capital, default 0) works in both coupled systems.
- `crescimento.jl`: the RHS is homogeneous of degree 1, so steady states are balanced-growth rays. They are fixed points of `sistema_normalizado` in free simplex coordinates (`_do_livre`/`_para_livre`; prices mean-zero). Also `crescimento_equilibrado` (warm-up + Newton), `com_parâmetro` (`:μ`, `:μ_v`, `:ω`, `:escala_e`) and `varrimento_salarial`.
- `tssi.jl`: TSSI valuation layer (fixed lag τ) over trajectories; does not change the dynamics. `bifurcacao.jl`: BifurcationKit continuation of fixed points of *maps* (rationing step, TSSI price map), with fold/flip/Neimark–Sacker classified from multipliers (BK's own detectors assume ODEs and miss flips). `bifurcacao_acumulação` continues balanced growth of the cross-dual ODE (BK's own Hopf detection; `dsmax` ≤ 0.01 or close Hopf pairs are missed). It seeds limit-cycle collocation from the Hopf normal-form predictor (`BK.predictor`), because BK's automatic branch switching hits a singular Jacobian here. Check cycles with `ciclo_simulado`. `expoentes_lyapunov` (Benettin method, exact Jacobian; ≈100 s at N=6) classifies irregular motion, and `histerese_simulada` detects coexisting attractors with up/down sweeps. BifurcationKit is imported as `BK` (prefixed) to avoid name clashes; in 0.8.8 the collocation type is `BK.Collocation`.
- `exemplos.jl` holds the ready-made examples, `ajuda_modelo()`, and `testar_modelo()` (internal battery, also called from the tests). `visualizacao.jl` holds the plots.
- `notebooks/` (English prose only, not bilingual): `jupyter/*.ipynb` are committed **executed**, with PNG-only plot outputs, and load the model with a relative `include` from their own folder. `pluto/*.jl` activate the repo environment in their first cell (which disables Pluto's package manager) and must `using` every package they call directly, because Pluto doesn't see packages loaded inside the `include`. Edit Pluto notebooks in Pluto, so the file format and cell order stay valid. When the API changes, `test/notebooks.jl` catches broken notebooks; re-execute and strip the Jupyter ones.

## Data and testing invariants

- **Defaults are synthetic.** Real data are opt-in (`fonte_dados=:eurostat`, `dados_setoriais=:eurostat`, `método=:sdmx`/`:auto`). The AMECO path falls back to synthetic data or fixed weights with a warning. The INE path raises an error instead of degrading silently when real data were requested explicitly.
- The test suite must stay **offline**. Network paths are checked manually with `verificar_sdmx_ameco()`, `verificar_eurostat_setorial()`, and `paper/matrix_audit.jl`.
- `seed` in `simular_Ndept` only fixes matrix `A`. `criar_departamentos` uses the global RNG, so tests call `Random.seed!` before simulating.
- The Eurostat IOT is a benchmark table, not annual (PT: 2010/2013/2015/2017/2020); a missing year falls back to the nearest one with a warning.
- No number in `paper/main.tex` is entered by hand. Figures and tables come from the `paper/*.jl` scripts into `paper/figures/` (committed, as is `paper/main.pdf`). Sections 3.3–3.5/5.5 read their numbers as `\newcommand` macros from `paper/figures/jacobian_stats.tex`, and Sections 3.6/5.6 from `paper/figures/acumulacao_stats.tex`; rerun `paper/jacobiana_bifurcacao.jl` after changing rationing/TSSI code, and `paper/acumulacao_bifurcacao.jl` after changing the cross-dual, balanced-growth or accumulation-bifurcation code.
- `docs/LIMITACOES.md` is the record of known limitations and their fixes. Update it (both languages) when a model limitation changes.

## Releases

The version string appears in `Project.toml`, `CITATION.cff`, the status line of both READMEs (`README.md`, `README.pt.md`), and both CHANGELOGs (Keep a Changelog format, semver). Bump them all together. GitHub releases are archived to Zenodo. The software DOI and the paper DOI are separate.
