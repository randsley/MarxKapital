# MarxKapital — Project Status

*[🇵🇹 Ler em português](ESTADO_DO_PROJETO.md)*

Tracking document, started at version 0.3.0 and updated since; the work
described in the following sections corresponds to version **0.6.0**,
including the fix to the real Eurostat dataflow for the technical
matrix, the reconstruction of genuine gross output in the dynamical
model, the exact conservation of the mobility term, and the academic
paper in `paper/`. Describes what has been done, what remains to be
resolved, and concrete implementation recommendations. Lives in
`docs/ESTADO_DO_PROJETO.md` (this file's Portuguese original), alongside
`docs/LIMITACOES.md`.

Date: last updated 2026-07-30. Project author: Nigel Randsley.

---

## 1. Summary

MarxKapital is a Julia system for the mathematical modeling of Marxian
economic theory: capital accumulation, exploitation, organic
composition, the tendency of the profit rate, the transformation of
values into prices of production, the wage-profit distributive
frontier, and empirical calibration with national (Portuguese INE) and
European (AMECO) data. Functional for demonstration and methodological
development, with automated tests in CI. The default data remain
synthetic/fixed-weight and are not suitable for publishable empirical
analysis in that mode — **real** sectoral and AMECO data are available
as an option, via official SDMX APIs (see `docs/LIMITACOES.md`).

The code was reorganized from a monolithic file into a modular
repository, with tests, examples, and documentation. The AMECO
integration covers every country in the database, with calibration,
international comparison, and time series.

---

## 2. What has been done

### 2.1 Model core (`src/nucleo.jl`, `src/estruturas.jl`)

- `Departamento` (Department) type with invariants validated in the
  constructor: `c`, `v`, `e`, `k = c/v`, reinvestment shares (`σ_c`,
  `σ_v`, `γ`) summing to 1, and depreciation `δ`. Helper methods:
  `taxa_lucro` (profit rate), `mais_valia` (surplus value),
  `capital_total`, `valor_produto`.
- Classical two-department model (means of production and consumption
  goods) and generalized N-department model.
- Construction of a technical matrix `A` with three structures
  (`:aleatoria` random, `:triangular`, `:blocos` blocks), always
  normalized to a spectral radius below 1 (a productive economy). A
  `seed` argument for reproducibility.
- Integration of the accumulation dynamics with
  `DifferentialEquations.jl` (Tsit5), for 2 and N departments.

### 2.2 Value and price analysis (`src/analise.jl`)

- Profit rates, organic compositions, and the average rate over time.
- Labor values `λ = (I − A)⁻¹ l`.
- Maximum profit rate `R_max = 1/λ_max(Aᵀ) − 1`.
- Sraffian prices of production `p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ l`, rejecting
  rates that make the system singular.
- The transformation problem, with comparative visualization (values
  against prices, percentage deviations, divergence as a function of
  the profit rate, correlation).

### 2.3 Distributive analysis and validation (`src/distributiva.jl`)

- Distributive-possibility frontier (wage-profit curve), with
  elasticity and the evolution of relative prices.
- Validation of calibrated profit rates: feasibility relative to
  `R_max`, dispersion, consistency with implied exploitation, position
  on the frontier, and a quality score in [0, 100]. Uses robust
  histograms, with no hard dependency on boxplots.

### 2.4 Policy and shocks (`src/choques.jl`)

- Wage-shock simulation: a `Δw` increase raises `V`, proportionally
  reduces `e`, and adjusts `r`. Compares the base scenario against the
  shock, with the same `seed` in both, guaranteeing comparability.
- Comparison of multiple shock scenarios.

### 2.5 National calibration (`src/calibracao_pt.jl`)

- Generation of synthetic data with the Portuguese sectoral structure
  (19 NACE Rev.3 sections): VAB, compensation, gross operating surplus,
  consumption of fixed capital, employment, gross fixed capital
  formation, and capital stock.
- Processing of Supply and Use Tables, with Marxian indicators per
  sector.
- Estimation of sectoral parameters and the `calibrar_modelo_portugal`
  pipeline.

### 2.6 AMECO integration (`src/ameco.jl`, `src/ameco_download.jl`)

- Data structures (`DadosAMECO`, 29 fields) and dictionaries of
  countries and variable mnemonics.
- Generation of plausible synthetic series (trend plus cycle),
  calibrated by country profile.
- Automatic download of the full TXT database
  (`descarregar_ameco_automatico`), trying multiple URLs and logging
  the retrieval date.
- Fixed-width parser (`ler_ficheiro_ameco_txt`), with parameterizable
  offsets.
- Exported-CSV processor (`processar_csv_ameco`).
- Unified entry point `obter_dados_ameco` with methods `:auto`,
  `:download`, `:local`, `:csv`, `:sintético`, and `:manual`.
- Calibration from AMECO data, international country comparison, and
  time-series analysis of Marxian indicators.

### 2.7 Packaging and documentation

- Repository structure: `src/`, `test/`, `examples/`, `data/`, `docs/`.
- Loader `src/MarxKapital.jl` (script-style, loaded via `include`,
  avoiding fixed UUIDs).
- `install_deps.jl`, `Project.toml`, `.gitignore`, `LICENSE` (MIT),
  `README.md`, `CHANGELOG.md`.
- Test suite (`test/runtests.jl`) and demo (`examples/demo.jl`).
- `docs/LIMITACOES.md` with the known limitations.

### 2.8 Fixes applied in this phase

- Explicit import of `Statistics` (`mean`, `std`, `median`, `var`,
  `cor`, `quantile`).
- ODE parameters passed as a `NamedTuple` (type-stable) instead of a
  `Dict`, eliminating SciMLBase's performance warning.
- Replacement of incorrect uses of LinearAlgebra's `I` constant with
  `matriz_identidade(N)`.
- Calibration validation with robust histograms, no mandatory boxplot.
- Elimination of the undefined-`match_obj` bug in the old AMECO update
  flow.
- Optional `seed`, shared between base and shock scenarios.

### 2.9 Verification by execution (history: static-only until this point)

In this document's early phases, with no Julia available in the
packaging environment, verification was static only (balanced
delimiters, no function called without a definition, argument counts in
positional constructors). Since then, the test suite runs by real
compilation — locally and in CI (GitHub Actions, Julia 1.10 and 1, on
every push to `main`, see `.github/workflows/test.yml`) — 111 tests, all
passing. The real-data (network) paths are checked manually with
`verificar_sdmx_ameco()`/`verificar_eurostat_setorial()`, outside the
automated suite by design (see `docs/LIMITACOES.md`).

---

## 3. What remains to be resolved

Ordered by priority. Full detail is in `docs/LIMITACOES.md`.

### 3.1 Resolved: matrix A did not feed back into the N-department dynamics

In `sistema_Ndept!`, each sector's accumulation depends only on its own
surplus value; the matrix `A` is carried in the parameters but does not
enter the equations. Sectors behave as independent, which contradicts
the logic of expanded reproduction (one sector's output is another
sector's constant capital).

**Fixed, with three optional mechanisms in `sistema_Ndept_io!`
(`acoplado=true`), independent of each other:**
1. Capital mobility: `μ·(rᵢ − r̄)·Cᵢ`, with `rᵢ` valued at Sraffian
   prices of production and `r̄` the mean of `r` weighted by `C` — the
   only choice for which the term conserves aggregate constant capital
   exactly (`Σμ(rᵢ-r̄)Cᵢ=0` by construction, verified by test).
2. Aggregate realization pressure (`realização=true`):
   `ρ_real = Σmin(xᵢ,(A·x)ᵢ)/Σ(A·x)ᵢ` damps reinvestment when the
   technical structure cannot sustain current outputs.
3. Exact per-sector quantity rationing (`racionamento=true`, takes
   precedence over `realização`): solves Bénassy/Barro-Grossman-style
   rationing by fixed-point iteration — each sector bounded by its
   scarcest input (Leontief technology), without needing to expose the
   system as a DAE or a new solver dependency. Verified with a
   closed-form example and by robustness across a systematic sweep of
   270 combinations (N∈{6,12,19}, density∈{0.2,0.4,0.6}), 270/270
   convergences.

In both supply-constrained mechanisms, `xᵢ` is **genuine** gross
output, reconstructed from the model's own state
(`xⱼ=Wⱼ/(1-Σᵢ A[i,j])`, `Wⱼ=δⱼCⱼ+Vⱼ+Sⱼ`) — not the value-added-type flow
`W` used in an earlier fix, which omitted circulating intermediate
consumption. Investment demand in the rationing mechanism uses
`Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` (desired output expansion, via the current
capital-output ratio), not the expenditure `σ_c,ⱼSⱼ` directly.

`sistema_Ndept!` remains the default (independent sectors).
`verificar_equilibrio_Ndept` generalizes the two-department model's
after-the-fact check — see `docs/LIMITACOES.md` item 1 for the details
of each mechanism and the most recent fixes.

### 3.2 Resolved: `R_max` in the wage shock was illustrative

In `simular_choque_salarial`, the reported `R_max` used an auxiliary
matrix `A_ref` and `l = ones(N)`, not the simulation's matrix or labor
coefficients. **Fixed:** it now uses `p_base.A` (returned by
`simular_Ndept_customizado`) and `l = [d.v for d in depts]`, reflecting
the simulated scenario.

### 3.3 Resolved: the AMECO download now uses the official SDMX API

The old static TXT file was discontinued by the Commission (URLs
confirmed dead in 2026-07). **Fixed:** `src/ameco_sdmx.jl` uses the
official AMECO SDMX REST API (`webgate.ec.europa.eu/ecfin/redisstat`),
now the default automatic path (`obter_dados_ameco`, methods
`:auto`/`:sdmx`). Verified with real Portuguese data (GDP, employment,
compensation, GFCF, capital stock). **Nearly fully resolved:**
`MAPA_AMECO_SDMX` now maps 24 variables plus 2 calculated (GDP deflator,
trade balance) — 26 series in total, including `deflator_FBCF` and
`CCF` (consumption of fixed capital), added to fix a valuation problem
in the exploitation time series (see `docs/LIMITACOES.md` item 9); only
gross capital stock was confirmed unavailable in this API (not
"pending") — see `docs/LIMITACOES.md` item 3 for the exact list.

### 3.4 Resolved: AMECO calibration was macro-only, with fixed weights by default

`calibrar_com_dados_ameco` only implements the `:macro` aggregation
(Primary, Secondary, Tertiary). By default, GDP, employment, and
capital-stock splits use fixed per-country weights; countries without a
specific profile fall back to the EU average profile. **Fixed
(optional):** `dados_setoriais=:eurostat` uses real Eurostat sectoral
data instead of fixed weights, with automatic fallback for countries
outside EU/EEA coverage, **now including the matrix `A`**: built at the
19 fine sectors (real, non-negative, dataflow `NAIO_10_CP1700` — see
`docs/LIMITACOES.md` item 4-bis for the earlier dataflow bug, found and
fixed) and aggregated to the 3 macro sectors by the Leontief formula
(`agregar_matriz_io`), rather than aggregating raw IOT flows directly.

### 3.5 Resolved: incomplete INE aggregation

`calibrar_modelo_portugal` accepted the `agregação` argument, but only
`:detalhada` (19 sectors) was wired up. **Fixed:** `:macro` (3 sectors,
the same aggregation as the AMECO path) and `:média` (10 sectors, NACE
Rev.2 "A10" level) implemented via `agregar_setores`, working with both
synthetic and real data.

### 3.6 Resolved (optional): perpetual-inventory capital stock; AMECO depreciation fixed

Constant capital is approximated by the reported capital stock by
default; `inventário_perpétuo=true` replaces this with its own series
(PIM, `Kₜ=(1-δ)Kₜ₋₁+FBCFₜ`, δ estimated per sector from CCF/stock, not
fixed) — see `docs/LIMITACOES.md` item 7. Separately, the AMECO time
series (`analisar_série_temporal_com_dados`) used a flat 10% deduction
from the stock as "depreciation"; fixed to use real AMECO CCF, deflated
consistently with the other terms — see `docs/LIMITACOES.md` item 9.
Still to differentiate: depreciation rates by asset type (structures,
machinery, ICT), which Eurostat does not publish directly.

### 3.7 Cross-cutting: synthetic data by default

Both the INE and AMECO paths use generated data by default. They serve
demonstration and testing, not empirical analysis.

### 3.8 Resolved: tests now run in CI

The `test/runtests.jl` suite (111 tests) runs locally and in CI (GitHub
Actions, Julia 1.10 and 1, `.github/workflows/test.yml`) on every push
to `main`. Covers the default synthetic/opt-in paths; the real-data
(network) paths are left out by design — see §3.3/§4.3.

### 3.9 Resolved: technical matrix A used the wrong Eurostat dataflow

Found during an audit requested in external review of the paper in
`paper/`: `NAIO_10_CP1620` is not the symmetric IOT table (it is a
trade-and-transport-margins satellite table), which understated
intersectoral flows by more than an order of magnitude and explained an
implausible spectral radius and `R_max` reported until this fix. Fixed
with `NAIO_10_CP1700` (the real table), `stk_flow=DOM` (domestic use
only) — see `docs/LIMITACOES.md` item 4-bis for the full history.

### 3.10 Resolved: dynamical model's gross output and investment demand

The output used by the coupling mechanisms (`realização`,
`racionamento`) was a value-added-type flow (`W=δC+V+S`), which omits
circulating intermediate consumption — not gross output in the sense
used to build `A`. Fixed by reconstructing genuine gross output from
the model's own cost-output identity, without new state; investment
demand in the rationing mechanism converts planned expenditure to
output scale via the capital-output ratio, instead of applying `A`
directly to expenditure. See `docs/LIMITACOES.md` item 1.

---

## 4. Implementation recommendations

### 4.1 Couple A to accumulation — done (both steps)

Goal: make the N-department model consistent with the two-department
one, where intersectoral equilibrium is already imposed.

Recommended approach, in two steps:

1. **Reproduction consistency.** Work with gross output per sector.
   Sector `i`'s value output is `Q_i = C_i + V_i + S_i`, with
   `S_i = e_i V_i`. Sector `j`'s constant-capital demand is `A[:, j]`
   applied to its activity level. The realization condition requires
   that the supply of each good equal intermediate use plus final use
   (worker and capitalist consumption, plus net investment). In the
   two-department model this reduces to the condition already checked
   by `verificar_equilibrio_2dept`.

2. **Capital mobility.** Introduce a reallocation term that shifts
   investment toward sectors with an above-average profit rate:

   ```
   dC_i/dt = σ_c,i · S_i − δ_i · C_i + μ · (r_i − r̄) · C_i
   ```

   where `μ` is the mobility coefficient and `r̄` the average profit
   rate. For the sign `(r_i − r̄)` to reflect the input-output
   structure, compute `r_i` on capital valued at prices of production
   (which depend on `A`), not just `e/(k+1)`. This is how `A` enters
   the dynamics through valuation.

Practical suggestion: keep `sistema_Ndept!` as is (documented as the
"independent sectors" version) and add `sistema_Ndept_io!` with the
coupling, selectable by argument. Validate by requiring that, in the
steady-state limit, profit rates converge to `r̄` and sectoral balances
close.

**Step 2 (mobility) — done**, exactly as recommended above.
**Step 1 (reproduction consistency) — done**, with two mechanisms: an
aggregate pressure (`realização=true`) and exact per-sector quantity
rationing (`racionamento=true`, solved by fixed point, no DAE needed) —
see `docs/LIMITACOES.md` item 1.

### 4.2 Fix `R_max` in the shock

Have `simular_Ndept_customizado` return the matrix `A` actually used.
Reuse it in `simular_choque_salarial` to compute `R_max` with the
departments' real labor coefficients (e.g. `l_i` proportional to
employment or to `V_i`), instead of `ones(N)`. This makes the reported
feasibility limit correspond to the simulated scenario.

### 4.3 Strengthen AMECO access (partially done)

- ~~Dynamic file discovery / prefer the official ZIP / validate the TXT
  parser by round-trip~~ — **obsolete**: the TXT file was discontinued
  by the Commission; replaced by the official SDMX API
  (`src/ameco_sdmx.jl`), which returns structured data directly, with
  no fixed-width parsing. The "known value" check (Portugal's GDP) was
  done — see `verificar_sdmx_ameco()` and `docs/LIMITACOES.md` item 3.
- **Confirm mnemonics** — done for 24 of the 25 variables (22 mapped
  directly plus 2 calculated); only gross capital stock confirmed
  unavailable in this API. Some old (never-verified) mnemonics turned
  out to be incorrect — see `docs/LIMITACOES.md` item 3.
- ~~Map SDMX chapter per variable~~ — done (see above).
- ~~Eurostat alternative~~ — **done**: `src/eurostat_sdmx.jl` uses
  `NAMA_10_A64`/`_E`/`_P5` for VAB/compensation/CCF/employment/GFCF,
  `NAMA_10_NFA_ST` for capital stock, and `NAIO_10_CP1700` (the real
  symmetric IOT table — see item 3.9 and `docs/LIMITACOES.md` item 4-bis
  for the dataflow fix) for the matrix `A`.

### 4.4 Real sectoral calibration (done for 19, 10, and 3 sectors; real A on both paths)

- ~~Replace fixed weights with real sectoral national-accounts
  data~~ — done, `src/eurostat_sdmx.jl` (VAB, compensation, CCF,
  employment, GFCF, capital stock via
  `NAMA_10_A64`/`NAMA_10_A64_E`/`NAMA_10_A64_P5`/`NAMA_10_NFA_ST`),
  opt-in on both paths (`fonte_dados=:eurostat` for INE,
  `dados_setoriais=:eurostat` for AMECO).
- ~~Build the matrix `A` from Eurostat tables~~ — done for both paths.
  INE: 19 sectors, `construir_matriz_io_eurostat` via `NAIO_10_CP1700`
  (the real symmetric IOT table, `stk_flow=DOM` — a later fix replaced
  `NAIO_10_CP1620`, which turned out to be a margins satellite table,
  not the IOT itself; see `docs/LIMITACOES.md` item 4-bis). AMECO (3
  macro sectors): aggregating the already-clean 19-sector matrix (not
  raw flows) by the standard Leontief aggregation formula
  (`agregar_matriz_io`) gives a real, non-negative matrix, without the
  Tertiary-row caveat that used to appear here before the dataflow fix —
  verified with exact reconciliation against the output published by
  the table itself.
- ~~Estimate capital stock per sector by the perpetual-inventory
  method~~ — done (optional, `inventário_perpétuo=true`;
  `calcular_stock_capital_pim`, `src/eurostat_sdmx.jl`). Uses a single
  depreciation rate per sector (estimated, not fixed) — an
  asset-type-differentiated PIM would also require depreciation profiles
  by asset type, which Eurostat does not publish directly; left undone
  (see `docs/LIMITACOES.md` item 7).
- ~~Actually implement the `:média` and `:macro` aggregations in the
  INE path~~ — done, `agregar_setores` (`src/calibracao_pt.jl`).

### 4.5 Tests and continuous integration — done

- ~~Run locally~~ — done, `julia install_deps.jl` followed by
  `julia --project=. test/runtests.jl`, 111 tests passing.
- ~~Headless execution~~ — done, via `GKSwstype=100` (environment
  variable, not a per-function argument) before loading `Plots`; used
  both locally and in CI.
- ~~Add a CI workflow~~ — done, `.github/workflows/test.yml` (GitHub
  Actions, Julia 1.10/1 matrix, package cache, headless mode), on every
  push to `main`.

Not covered by CI (network needed, opt-in by design — see
`docs/LIMITACOES.md`): `método=:sdmx`, `fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`. Checked manually via
`verificar_sdmx_ameco()`/`verificar_eurostat_setorial()`.

### 4.6 Medium-term directions

Extensions already sketched in earlier sessions, as a roadmap once the
core has stabilized:

- **Financialization:** a credit and fictitious-capital layer, with an
  interest rate separating enterprise profit from financial income.
- **Ecology:** accounting for energy and material flows, and a
  biophysical limit on accumulation.
- **Imperialism and unequal exchange:** value transfers between
  economies with different organic compositions, linking to the
  international-comparison module.
- **Heterogeneous agents:** intra-sectoral dispersion of productivities
  and competition, instead of representative sectors.

---

## 5. Suggested roadmap

Proposed sequence, from most structural to most exploratory:

1. ~~Run the suite locally and fix whatever compilation reveals. Add
   headless CI.~~ — done.
2. ~~Fix the shock's `R_max`~~ — done.
3. ~~Couple `A` to the N-dept dynamics with capital mobility~~ — done
   (optional, `acoplado=true`), plus aggregate realization pressure
   (`realização=true`) and exact per-sector quantity rationing
   (`racionamento=true`, fixed point, no DAE); dispersion convergence
   and damping validated by test.
4. ~~Strengthen AMECO access~~ — done (official SDMX API, 26 series
   obtained — 24 mapped directly + 2 calculated; 1 confirmed
   unavailable).
5. ~~Wire up real sectoral data (Eurostat)~~ — done, opt-in, with a
   real matrix `A` on both paths (INE 19/10/3 sectors; AMECO 3 sectors,
   see §4.4). Default behavior remains synthetic/fixed-weight.
6. ~~Estimate capital stock via perpetual inventory~~ — done, optional
   (`inventário_perpétuo=true`).
7. ~~Fix the technical matrix A's wrong dataflow~~ — done
   (`NAIO_10_CP1700`, `stk_flow=DOM` — see §3.9).
8. ~~Reconstruct genuine gross output in the dynamical model~~ — done,
   with no new state (see §3.10).
9. ~~Exact conservation of the capital-mobility term~~ — done (`r̄`
   weighted by `C` — see §3.1).
10. ~~Write the academic paper (methodology + empirical
    application)~~ — done, `paper/main.tex`, reproducible from real data
    (`paper/gerar_resultados.jl`, `paper/monte_carlo.jl`,
    `paper/matrix_audit.jl`).
11. Medium-term extensions (financialization, ecology, unequal exchange,
    heterogeneous agents) — still to do.

---

## 6. Checklist

- [x] Tests run locally with no errors
- [x] Headless CI configured
- [x] Shock `R_max` computed with real A and l
- [x] `sistema_Ndept_io!` with coupling via A and capital mobility (optional, `acoplado=true`)
- [x] Optional aggregate realization pressure (`realização=true`) and `verificar_equilibrio_Ndept` (after-the-fact check)
- [x] Exact per-sector quantity rationing (`racionamento=true`, fixed point, no DAE or `NonlinearSolve.jl`)
- [x] AMECO download via the official SDMX API (replaces the discontinued TXT file)
- [x] SDMX API validated with a known value (`verificar_sdmx_ameco()`)
- [x] AMECO mnemonics confirmed (26 series obtained; 1 confirmed unavailable)
- [x] Matrix A from real supply-and-use tables (INE 19/10/3 sectors; AMECO 3 sectors, aggregated — see LIMITACOES item 4-bis)
- [x] Sectoral calibration with real national accounts by branch (both paths, opt-in)
- [x] Capital stock via perpetual inventory (optional, `inventário_perpétuo=true`; single depreciation rate per sector, not differentiated by asset type)
- [x] `:média` and `:macro` INE aggregations implemented
- [x] Technical matrix A fixed for the real dataflow (`NAIO_10_CP1700`, `stk_flow=DOM`, zero negative cells, exact reconciliation against P1)
- [x] Genuine gross output reconstructed in the dynamical model (no new state); investment demand in output scale (`Δx`), not expenditure
- [x] Reconstruction admissibility condition checked and fixed once per simulation (`_garantir_admissibilidade_output`), not reclaimed at every evaluation
- [x] Mobility term conserves aggregate constant capital exactly (`r̄` weighted by `C`)
- [x] AMECO time series uses real CCF (not a flat 10% deduction); `e` invariant under a common deflator, verified
- [x] `e=0.1` floor in the sectoral calibration explicitly reported (count of saturated sectors)
- [x] Academic paper (`paper/main.tex`) — methodology + empirical application to Portugal, reproducible
