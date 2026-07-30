# MarxKapital

*[🇵🇹 Ler em português](README.md)*

Mathematical modeling of Marxian economic theory in Julia: accumulation,
exploitation, organic composition, the tendential fall in the rate of
profit, the transformation of values into prices, the wage-profit
distributive frontier, and empirical calibration with national (Portuguese
INE) and European (**AMECO**, all countries in the database) data.

> Status: **v0.6.1** — functional for demonstration,
> methodological development, and an academic paper in `paper/`, with
> automated tests in CI
> ([![Tests](https://github.com/randsley/MarxKapital/actions/workflows/test.yml/badge.svg)](https://github.com/randsley/MarxKapital/actions/workflows/test.yml))
> ([![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705370.svg)](https://doi.org/10.5281/zenodo.21705370))
> ([![Paper DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705609.svg)](https://doi.org/10.5281/zenodo.21705609)).
> **Real** sectoral and AMECO data are available as an option (via
> official SDMX APIs), but the defaults remain **synthetic**.
> Before any serious empirical use, read
> [`docs/LIMITACOES.en.md`](docs/LIMITACOES.en.md) (limitations).

## Installation

```bash
git clone <this-repository> marxkapital
cd marxkapital
julia install_deps.jl        # installs DifferentialEquations, Plots, DataFrames, CSV, HTTP, StatsPlots
```

## Quick start

```julia
include("src/MarxKapital.jl")
ajuda_modelo()                 # help / model overview

# Classical and generalized model
exemplo_2dept()                 # two-department example
exemplo_Ndept(10)                # N-department example

# N departments coupled through A: capital mobility, aggregate realization
# pressure, or exact per-sector quantity rationing (optional, independent)
simular_Ndept(10, acoplado = true, μ = 0.3)
simular_Ndept(10, acoplado = true, realização = true)
simular_Ndept(10, acoplado = true, racionamento = true)

# Values → prices of production
exemplo_transformacao()

# Portuguese national-accounts calibration (synthetic by default;
# fonte_dados=:eurostat for real data)
params, validação = exemplo_portugal()
params_real = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat)

# AMECO — any country in the database (dados_setoriais=:eurostat for real
# sectoral data, EU/EEA countries)
listar_países_ameco()            # list AMECO countries
params, dados = calibrar_com_ameco_v2("Alemanha", ano = 2022)   # "Alemanha" = Germany; método = :auto

# International comparison
comparar_países_ameco(["Portugal", "Espanha", "Alemanha", "França"], ano = 2022)

# Time series
analisar_série_temporal_ameco("Portugal", anos = 2000:2022)

# Wage-policy shock
depts = criar_departamentos(6)
simular_choque_salarial(depts, 0.10)   # +10% wages
```

Or run the full demo:

```bash
julia --project=. examples/demo.jl
```

*Note: function and keyword-argument names remain in Portuguese
throughout the codebase (`simular_Ndept`, `acoplado`, `racionamento`,
`fonte_dados`, etc.) — this README explains what each call does, but the
API itself is not translated.*

## AMECO data

`obter_dados_ameco("Portugal", método = ...)` accepts:

| método (method) | behavior                                                        |
|--------------|----------------------------------------------------------------------|
| `:auto`      | official SDMX API → recent local file → synthetic (fallback with warning) |
| `:sdmx`      | forces retrieval via the official AMECO SDMX API                       |
| `:download`  | alias for `:sdmx` (the legacy TXT download was discontinued)        |
| `:local`     | requires `dados_ameco/ameco_completo.txt` already downloaded (legacy path) |
| `:csv`       | processes an exported CSV (`ficheiro="..."`, legacy path)            |
| `:sintético` | generates plausible synthetic series                                    |
| `:manual`    | shows download instructions and returns synthetic data                    |

Since 2026-07 AMECO exposes an [official SDMX REST
API](https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1)
(the same platform as Eurostat's newer data tool) — the static TXT file
that the `:local`/`:csv` methods still support was discontinued by the
Commission. Run `verificar_sdmx_ameco()` to confirm access before a real
analysis; see `docs/LIMITACOES.en.md` item 3 for the exact status of each
variable.

## Real sectoral data (Eurostat)

Both calibration paths use synthetic structure or fixed sectoral weights
by default. Real Eurostat sectoral data are available as an option
(`src/eurostat_sdmx.jl`):

```julia
# Portuguese national accounts (INE) — 19 (:detalhada), 10 (:média), or 3
# (:macro) sectors, with a real technical matrix A (Eurostat IOT)
params_real = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat, agregação = :detalhada)

# AMECO (3 macro-sectors), with a real technical matrix A (aggregated from
# the 19-sector matrix)
params_real, dados = calibrar_com_ameco_v2("Portugal", ano = 2022, dados_setoriais = :eurostat)

# Capital stock via perpetual-inventory method instead of the directly
# reported figure (optional)
params_pim = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat, inventário_perpétuo = true)

# Manual check of Eurostat access (not run in the automated test suite)
verificar_eurostat_setorial()
```

Only covers EU/EEA countries; outside that coverage, or if the request
fails, the AMECO path automatically falls back to fixed weights and a
random matrix `A` (with a warning) — the Portuguese-only INE path raises
an error instead of silently degrading, since it is an explicit request
for real data. The real matrix `A` uses `NAIO_10_CP1700` (the genuine
symmetric input-output table — `NAIO_10_CP1620`, used previously, turned
out to be a trade-and-transport-margins satellite table, not the IOT
itself; see `docs/LIMITACOES.en.md` item 4-bis) with domestic-use flows
only (`stk_flow=DOM`), no negative cells, reconciled directly against the
gross output published by the table itself (`P1`). Since this table is a
benchmark product (not annual — Portugal: 2010/2013/2015/2017/2020), a
request for a year without a published table falls back to the nearest
available year, with a warning. See `docs/LIMITACOES.en.md` items 4 and
4-bis for the exact status.

## Repository structure

```
marxkapital/
├── src/
│   ├── MarxKapital.jl      # loader (using + includes)
│   ├── estruturas.jl       # types and constants (AMECO)
│   ├── nucleo.jl           # matrices, departments, ODEs, simulation
│   ├── analise.jl          # profit rates, labor values, prices, transformation
│   ├── distributiva.jl     # wage-profit curve and calibration validation
│   ├── choques.jl          # wage shocks
│   ├── calibracao_pt.jl    # Portuguese (INE) calibration, synthetic and real (Eurostat)
│   ├── ameco.jl            # AMECO: synthetic, calibration, comparison, series
│   ├── ameco_sdmx.jl       # official AMECO SDMX API
│   ├── ameco_download.jl   # automatic download + TXT/CSV parser (legacy)
│   ├── eurostat_sdmx.jl    # Eurostat SDMX API: real sectoral data + IOT
│   ├── visualizacao.jl     # plots
│   └── exemplos.jl         # ready-made examples + help + testar_modelo
├── test/runtests.jl
├── examples/demo.jl
├── docs/LIMITACOES.md      # required reading (docs/LIMITACOES.en.md for English)
├── paper/                  # academic paper (LaTeX), reproducible from real data
│   ├── main.tex            # methodology + empirical application (Portugal)
│   ├── gerar_resultados.jl # generates every figure/table in the paper
│   ├── matrix_audit.jl     # technical matrix A audit (manual check)
│   ├── monte_carlo.jl      # systematic sweeps (convergence, dispersion)
│   └── figures/
├── data/                   # (empty; downloaded data lands here, not version-controlled)
├── install_deps.jl
├── Project.toml
├── CHANGELOG.md
├── LICENSE
└── README.md
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

111 tests, run automatically in CI (GitHub Actions, Julia 1.10 and 1) on
every push to `main` — see `.github/workflows/test.yml`. The suite covers
the default synthetic/opt-in paths and runs fully offline; the real-data
paths (`método=:sdmx`, `fonte_dados=:eurostat`, `dados_setoriais=:eurostat`)
require network access and are not in CI — check them manually with
`verificar_sdmx_ameco()`, `verificar_eurostat_setorial()`, and
`paper/matrix_audit.jl`.

## Limitations

Read [`docs/LIMITACOES.en.md`](docs/LIMITACOES.en.md). In summary: (1) the
matrix A only feeds back into the N-department simulation optionally
(`acoplado=true`), with three available mechanisms — capital mobility
(conserves aggregate constant capital exactly, by construction),
aggregate realization pressure (`realização=true`), and exact per-sector
quantity rationing (`racionamento=true`, solved by fixed point, no DAE
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
(`inventário_perpétuo=true`) instead of the directly reported figure,
also optional.

## Academic paper

[`paper/main.tex`](paper/main.tex) presents a methodological component
(the model, the three coupling mechanisms, the rationing mechanism as a
fixed point) and an empirical application to Portugal, with every
figure/table generated reproducibly from real data
(`paper/gerar_resultados.jl`, `paper/monte_carlo.jl`,
`paper/matrix_audit.jl` — no number entered by hand). Compile with
`latexmk -pdf paper/main.tex`.

Published on Zenodo with its own DOI, separate from the software DOI:
[10.5281/zenodo.21705609](https://doi.org/10.5281/zenodo.21705609).

## License

MIT — see [`LICENSE`](LICENSE).
