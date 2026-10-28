# Changelog

*[🇵🇹 Ler em português](CHANGELOG.md)*

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705369.svg)](https://doi.org/10.5281/zenodo.21705369)

Format based on Keep a Changelog. Semantic versioning.

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
  `docs/LIMITACOES.md` item 4-bis, `paper/matrix_audit.jl`.
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
  "independent sectors" version by default. See `docs/LIMITACOES.md`
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
  remain available. See `docs/LIMITACOES.md` item 3.
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
  `docs/LIMITACOES.md` item 2.

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
- `docs/LIMITACOES.md` documenting known limitations.

### Fixed
- `Statistics` explicitly imported (mean/std/median/var/cor/quantile).
- ODE parameters passed as a `NamedTuple` (type-stable) instead of a `Dict`.
- `matriz_identidade(N)` replaces incorrect uses of LinearAlgebra's `I` constant.
- Calibration validation uses robust histograms (no hard dependency on boxplots).
- Fixed the undefined-`match_obj` bug in the AMECO update flow (the update function was removed/rewritten).
- Optional, shared `seed` across simulations for reproducibility and base-vs-shock comparability.

### Known (see docs/LIMITACOES.md)
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
