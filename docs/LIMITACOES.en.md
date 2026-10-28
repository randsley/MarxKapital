# Known limitations and pending work

*[🇵🇹 Ler em português](LIMITACOES.md)*

This file documents, plainly, what is not yet correct or complete.
None of these points prevent the code from running, but all of them
affect how the results should be interpreted.

## 1. The technical matrix A did not feed back into the N-department dynamics

In `sistema_Ndept!` (file `src/nucleo.jl`), each department's
accumulation depends only on its own surplus value:

    dCᵢ/dt = σ_c,ᵢ · Sᵢ − δᵢ · Cᵢ
    dVᵢ/dt = σ_v,ᵢ · Sᵢ

The matrix `A` is computed and carried in `p.A`, but **does not enter the
equations**. In other words: the input-output structure exists for
computing labor values and prices of production (which use it
correctly), but the time simulation treats sectors as independent. This
contradicts the logic of expanded reproduction, where one sector's
constant-capital consumption is another sector's output.

**Consequence:** the cycles and (non-)convergence of profit rates in the
N-department simulation reflect only heterogeneity in initial
parameters, not genuine sectoral interdependence.

**Pending fix (historical):** couple accumulation through A — for
example, requiring that sector i's constant-capital demand (ΔCᵢ) be met
by the output of supplying sectors (columns/rows of A), and introduce a
capital-mobility mechanism that shifts investment toward sectors with
r > r̄.

**Fixed:** `sistema_Ndept_io!` (`src/nucleo.jl`), selectable
with `acoplado=true` in `simular_Ndept`/`simular_Ndept_customizado`,
couples A to the dynamics through a capital-mobility term
`μ·(rᵢ − r̄)·Cᵢ`, with `rᵢ` computed on capital valued at Sraffian prices
of production (which depend on A), rather than the bare `e/(k+1)`.
`sistema_Ndept!` remains the default ("independent sectors") version,
unchanged, for compatibility.
`r̄` is the mean of `r` weighted by `C` (not the aggregate ratio
`ΣS/Σ(C+V)`, used until a later fix) — the only choice for which
`Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exactly, guaranteeing that the mobility term
reallocates aggregate constant capital between sectors rather than
creating or destroying it. Verified by test (`test/runtests.jl`,
"Mobilidade de capital — conservação exata").

**Fixed (second mechanism, optional):** `sistema_Ndept_io!`
now accepts `realização=true` (passed via `p.realização`, a keyword of
`simular_Ndept`/`simular_Ndept_customizado`), which adds a realization
pressure that scales planned reinvestment by
`ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1), damping accumulation
whenever the technical structure cannot sustain current output levels.
`xᵢ` is **genuine** gross output, not the value-added-type flow
`Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (constant capital *transferred*, not the stock `Cᵢ`) used
in an earlier fix: `Wᵢ` omits the circulating intermediate consumption
that the matrix `A` actually prices. `xᵢ` is reconstructed from the
model's own cost-output identity — see further below, "Fixed (genuine
gross output...)". Verified by test
(`test/runtests.jl`, "Simulação N-dept com pressão de realização") and by
robustness across 20 seed/μ combinations with no solver failures.

**Fixed (third mechanism, exact per sector, optional):**
`sistema_Ndept_io!` now accepts `racionamento=true` (takes precedence
over `realização`), which solves **per-sector quantity rationing** — not
just an aggregate pressure. Each sector `j`'s *desired* output
expansion, `Δxⱼ=σ_c,ⱼ·Sⱼ·xⱼ/Cⱼ` (planned investment converted to output
scale via the current capital-output ratio, not the expenditure
`σ_c,ⱼSⱼ` directly — a later fix, see below), requires inputs from
suppliers in the proportions `A[:,j]` (Leontief technology, no
substitution between inputs), so realized reinvestment is bounded by the
scarcest input — and the rationing a sector suffers reduces its
effective demand for ALL its inputs, in turn affecting the rationing
faced by its own suppliers. Solved by fixed-point iteration
(`_resolver_racionamento`, `src/nucleo.jl`):

```
κⱼ = min_{i: A[i,j]>0} ρᵢ          (bounded by the scarcest input)
Dᵢ = Σⱼ A[i,j]·κⱼ·Δxⱼ               (effective demand, already consistent with rationing)
ρᵢ = min(1, xᵢ / Dᵢ)               (short-side rule)
```

A Bénassy/Barro-Grossman-style quantity-rationing mechanism
(disequilibrium macro), not an algebraic constraint managed by a DAE
solver: solved by fixed-point iteration inside the right-hand-side
calculation of the ODE itself (with under-relaxation, which is
necessary — the unrelaxed version oscillates indefinitely instead of
converging, confirmed in a two-sector example), the same way Sraffa
prices are already solved by a direct linear system in the same
function. Without convergence within 200 iterations, it falls back to
`κ=1` (no rationing) with a warning — the same graceful degradation used
elsewhere in the code. `NonlinearSolve.jl` was **not needed**, nor
turning the system into a formal DAE (mass-matrix/`DAEProblem`) — the
fixed point already gives an exact answer (within numerical tolerance)
to the rationing problem as formulated, without needing to expose
`(ρ,κ)` as solver-managed state. Verified with a closed-form example
(`test/runtests.jl`, "Racionamento de mercado (ponto fixo)": `ρ₁=√0.8`,
verified by hand) and by robustness across 20 seed/μ combinations (N=8)
and at N=19, with no convergence failures nor ODE-solver failures.

`verificar_equilibrio_Ndept(sol, p)` (`src/analise.jl`) generalizes
`verificar_equilibrio_2dept` to N sectors: it returns the *intermediate-use
residual* `xᵢ−(A·x)ᵢ` per sector and `ρ_real` (the aggregate version) at
a given point, after the fact — this is not a disequilibrium or market
measure (a positive residual is the normal case in input-output
accounting: output available for consumption, exports, etc., which this
diagnostic does not model), and it does not use the per-sector rationing
(that is already embedded in `κ` inside `sistema_Ndept_io!` when
`racionamento=true`).

**Fixed (genuine gross output, not a value-added-type flow):**
`Oᵢ`/`xᵢ` above is no longer `Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (which omits circulating
intermediate consumption — materials, energy, purchased services — and
is not gross output in the input-output sense used to build `A`). `xᵢ`
is reconstructed from the model's own cost-output identity: since
`A[i,j]` is defined as input `i` per unit of buyer `j`'s gross output,
`j`'s circulating consumption is `zⱼ=(Σᵢ A[i,j])·xⱼ`, giving
`xⱼ = Wⱼ/(1-Σᵢ A[i,j])` — without introducing new state, recomputed at
every evaluation of the ODE's right-hand side, just like Sraffa prices.
Valid only when `A` represents each sector's *complete* circulating-input
requirement (true by construction for the closed synthetic matrices used
in these simulations; not for the real Eurostat domestic-use matrix,
which omits imports by definition — never used in this reconstruction).
The admissibility condition `Σᵢ A[i,j]<1` (needed for the denominator to
be positive) is not guaranteed by `ρ(A)<1` (which bounds the spectral
radius, not any individual column sum); checked and fixed once, when the
simulation is assembled (`_garantir_admissibilidade_output`,
`src/nucleo.jl`), rescaling `A` uniformly if needed, with a warning — not
a silent clamp reapplied at every evaluation. Verified by test
(`test/runtests.jl`, "Output bruto reconstruído..." and "Admissibilidade
da reconstrução de output bruto").

**Fixed (investment demand in output scale, not expenditure):**
the `Δxⱼ` in the rationing formula above replaces an earlier version
that applied `A[i,j]` directly to planned investment expenditure
`σ_c,ⱼSⱼ`, as if a unit of expenditure required the same input
composition as a unit of physical output — a dimensional problem
identified in external review. `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` converts expenditure
into an output expansion via the sector's current capital-output ratio,
before `A` is applied. Still open: the entire reconstructed `xᵢ` is
treated as available for investment demand `Dᵢ`, without netting out the
replacement of intermediate inputs (already counted in `zᵢ`) or other
final demand — no data source in the current pipeline provides
sector-of-origin consumption allocation, so `Dᵢ≤xᵢ` should be read as an
upper bound on investable supply, not a fully netted reproduction
balance.

## 2. R_max in the wage shock used an auxiliary matrix (fixed)

In `simular_choque_salarial` (`src/choques.jl`), the reported `R_max` was
computed with an `A_ref` matrix generated only to give a feasibility
reference, and with `l = ones(N)` — not the simulation's matrix nor the
departments' real labor coefficients.

**Fixed:** `R_max` now uses `p_base.A` (the technical matrix actually
returned by `simular_Ndept_customizado` for the base scenario) and
`l = [d.v for d in depts]` (labor coefficients proportional to V, the
same convention used in `sistema_Ndept_io!`). The reported feasibility
value now corresponds to the simulated scenario, not an auxiliary
reference.

Mitigation already applied (kept): the same `seed` is passed to both
scenarios (base and shock), so the two simulations' technical matrices
are identical and the base-vs-shock comparison is reproducible.

## 3. AMECO download (fixed: the official SDMX API replaces the TXT file)

**Historical context:** this section used to describe the old static TXT
file's heuristic URLs (`URLS_AMECO_TENTAR`, `src/ameco_download.jl`) and
its fixed-width parser (`ler_ficheiro_ameco_txt`). Confirmed in 2026-07
that this distribution was **discontinued by the European Commission** —
every URL returns a 404 or redirects to the portal's HTML page, never
data.

**Fixed:** AMECO now exposes an **official SDMX REST API**
(`src/ameco_sdmx.jl`, `webgate.ec.europa.eu/ecfin/redisstat`, the same
platform as Eurostat's newer data tool). `obter_dados_ameco`
(methods `:auto`/`:sdmx`/`:download`) uses it as the default automatic
path. Verified with real calls (2026-07): Portugal's GDP, employment,
compensation, GFCF, and net capital stock, correctly returned back to
1960. The mnemonics in `CÓDIGOS_AMECO_VARIÁVEIS` (UVGD, OVGD, etc.) were
confirmed valid as `ITEM` codes in this API, with no need to remap.
Country codes needed their own mapping (`CÓDIGOS_PAÍSES_AMECO_SDMX`),
mostly ISO3 but with real irregularities (GRC not EL, GBR not UK, ROM
not ROU).

**Resolved (almost entirely):** `MAPA_AMECO_SDMX` now maps 22 of the 25
variables in `CÓDIGOS_AMECO_VARIÁVEIS`, plus 2 series calculated from
already-mapped series (GDP deflator, trade balance) — 24/25 in total,
all verified with real calls in 2026-07. Beyond the original 6 (current/
constant GDP, total employment, compensation, GFCF, net capital stock)
and the following 14 (private/public consumption, exports, imports,
paid employment, unemployment rate, labor force, compensation per
employee, labor productivity, CPI, government revenue/expenditure,
budget balance, and current-account balance), the following were added:
unit labor costs (chapter 07-07, item `PLCD`, `TRANSFORMATION=3`), public
debt (chapter 18-02, item `UDGGL` — the old, never-verified mnemonic
turned out to be correct this time), GDP deflator (calculated,
`PIB_corrente/PIB_constante×100`, not requested from the API), and trade
balance (calculated, exports minus imports of **goods** only — chapter
11-01, items `DXGT`/`DMGT`, `UNIT=99`; distinct from
`exportações`/`importações`, which cover goods and services). The values
obtained for Portugal match known real figures (2022 deficit ≈ -0.3% of
GDP, 2022 unemployment ≈ 6.2%, 2022 public debt ≈ 111% of GDP).

**Confirmed unavailable (not "pending"):** gross capital stock. Only the
net-stock chapter (`AMECO_CHAPTER08-01`) exists in this API, with no
published gross equivalent — verified by a full wildcard of the
chapter's items, not just by failing to find it on the first attempt.

**Important note:** several mnemonics that were in
`CÓDIGOS_AMECO_VARIÁVEIS` (never previously verified) turned out to be
**incorrect** against the real API — for example `UUTG` was assigned to
`receitas_governo` (government revenue) but is actually
`despesas_governo` (government expenditure) — the two were swapped —
and `consumo_privado`/`exportações`/`importações` used mnemonics
(`UNCT`/`UXTG`/`UMTG`) that no longer exist in the current API (the
correct ones are `UCPH`/`UXGS`/`UMGS`). `MAPA_AMECO_SDMX` uses the
corrected codes; `CÓDIGOS_AMECO_VARIÁVEIS` (`estruturas.jl`, used only by
the legacy TXT parser) was not changed — it remains heuristic, as always
warned.

Only gross capital stock (confirmed unavailable, see above) is missing
from the result (filled with 0.0 by `construir_dados_ameco`, without an
error). Run `verificar_sdmx_ameco()` manually (not part of the automated
tests, so as not to depend on network access in CI) before trusting the
data in a real analysis.

The old TXT/CSV path (`ler_ficheiro_ameco_txt`, `processar_csv_ameco`,
methods `:local`/`:csv`) remains available for anyone who already has a
manually downloaded file, but it is no longer the automatic path.

If every path fails, `obter_dados_ameco(..., método=:auto)` silently
falls back to **synthetic data** (with a warning). Always check the
result's `fonte` (source) field.

## 4. AMECO calibration is macro (3 sectors), with fixed weights by default (fixed)

`calibrar_com_dados_ameco` only implements the `:macro` aggregation
(Primary/Secondary/Tertiary). By default (`dados_setoriais=:fixo`), the
sectoral split of GDP, employment, and capital stock uses **fixed
per-country weights** hard-coded in `_dist_setorial_vab`,
`_dist_setorial_emprego`, and `[0.10, 0.35, 0.55]`. These are
approximations; countries without a specific profile fall back to the EU
average profile.

**Fixed (optional):** `dados_setoriais=:eurostat` uses **real** VAB,
compensation, consumption of fixed capital, employment, GFCF, and
capital stock from Eurostat (`src/eurostat_sdmx.jl`, dataflows
`NAMA_10_A64`, `NAMA_10_A64_E`, `NAMA_10_A64_P5`, `NAMA_10_NFA_ST`),
aggregated to the 3 macro sections. Only covers EU/EEA countries; outside
that coverage, or if the request (data or matrix A) fails, it silently
falls back (with a warning) to fixed weights and a random A — it never
raises an error.

**Real matrix A — fixed, with good reconciliation, not a known caveat:**
the real matrix is first built at the 19 fine sectors (see item 4-bis)
and that **coefficient** matrix (not raw flows) is aggregated to the 3
groups by the standard Leontief aggregation formula
(`agregar_matriz_io`, `src/eurostat_sdmx.jl`):
`A₃[gi,gj] = Σ A₁₉[i,j]·VAB[j] / Σ VAB[j]` (VAB-weighted sum within group
`j`). The caveat about the Tertiary row that used to appear here in an
earlier version described a symptom of the wrong table used at the time
(see item 4-bis) — resolved, not worked around, by the dataflow fix.

## 4-bis. Real technical matrix A — wrong dataflow, found and fixed

**Bug history (2026-07/08):** an audit requested during external review
(meant to quantify the effect of a margin-clipping step, reconcile
published totals, document the CPA↔NACE correspondence, and resolve the
domestic-vs-total-use question) revealed something more fundamental than
any of those individual questions: `construir_matriz_io_eurostat`
(`src/eurostat_sdmx.jl`) used `NAIO_10_CP1620`, which **is not** the
symmetric IOT table — its real Eurostat title is "Table of trade and
transport margins," a small satellite table used to decompose the use
table at purchasers' prices into its components (basic-price flows plus
margins plus taxes-subsidies), not the symmetric table itself. Building
`A` from it understated intersectoral flows by more than an order of
magnitude (implied total intermediate consumption ≈€8.8bn for Portugal
2020, against a true ≈€177.8bn computed as published output minus
published VAB, summed across all NACE sections) — and every negative
cell previously attributed to a margin-reallocation accounting
convention was simply that satellite table's mechanics, not a feature of
the real input-output structure. This directly explains the implausibly
low spectral radius (ρ(A)≈0.11-0.15) and the implausibly high `R_max`
(≈600-700%) reported in earlier versions of this file and of the paper
in `paper/`.

**Fixed:** `construir_matriz_io_eurostat` now uses `NAIO_10_CP1700`
("Symmetric input-output table at basic prices, product by product"),
the real table, with `stk_flow=DOM` (domestic-use flows only — the table
also publishes `IMP` and `TOTAL`, confirmed by a real query; `A` should
represent *domestic* productive interdependence, and an imported input
is not supplied by any domestic sector). Verified with real Portuguese
data: zero negative cells, exact reconciliation against the `P1` (gross
output) row published by the table itself for all 19 sections,
ρ(A)≈0.52-0.60 (depending on `stk_flow`), `R_max`≈68-91% — both
economically plausible. `NAIO_10_CP1700` is a benchmark table (not
annual — Portugal: 2010/2013/2015/2017/2020), unlike the rest of the
pipeline; a request for a year without a published table automatically
falls back to the nearest reference year (`_ano_iot_mais_próximo`), with
a warning — so the matrix `A` for a request for, say, 2022, in practice
has a 2020 vintage (see `paper/main.tex`, Section 4.2, for how the paper
explicitly separates the 2020 and 2022 results rather than mixing them).

Used by `calibrar_modelo_portugal(..., fonte_dados=:eurostat)` (19 CAE
sectors — see item 5) and, aggregated via `agregar_matriz_io`, by
`calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` (3 macro sectors
— see item 4). Full verification (admissibility-rescaling frequency,
reconciliation, domestic/imported question) in `paper/matrix_audit.jl`,
run manually against the live API.

## 5. `agregação` in the INE calibration was not fully wired up (fixed)

`calibrar_modelo_portugal` accepted the `agregação` (aggregation)
argument but only ran `:detalhada` (19 sectors); the `:média` and
`:macro` modes were silently ignored.

**Fixed:** `:macro` aggregates to the same 3 sectors used in the AMECO
path (`GRUPOS_MACRO_NACE`); `:média` aggregates to 10 sectors, the
standard NACE Rev.2 "A10" level (`GRUPOS_MEDIO_NACE`,
`src/eurostat_sdmx.jl`) — a recognized aggregation, not an invented one.
`agregar_setores` (`src/calibracao_pt.jl`) sums the flow variables by
group and aggregates `A` by the same Leontief formula from item 4 —
works with both `fonte_dados=:sintético` (random A) and `:eurostat`
(real A), with no code distinction between the two cases. Verified: all
6 combinations (`:detalhada`/`:macro`/`:média` ×
`:sintético`/`:eurostat`) produce non-negative matrices with ρ(A)<1.

## 6. All default data are SYNTHETIC (real data now optional)

Both the INE and AMECO paths use, **by default**, **generated** data
with plausible patterns. They serve demonstration, testing, and
methodological development — **not publishable empirical analysis** in
that mode.

**Real data available (opt-in):**
- INE: `calibrar_modelo_portugal(fonte_dados=:eurostat, agregação=:detalhada|:macro|:média)`
  — 19, 3, or 10 sectors, real data and real technical matrix `A` (see
  items 4-bis and 5).
- AMECO: `calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` — 3
  macro sectors, real data and matrix `A` (see item 4).

Explicitly requesting these modes is still required — the default
behavior on both paths remains synthetic/fixed-weight, for compatibility
with historical behavior and to keep the test suite fully offline (see
`verificar_eurostat_setorial()` for a manual check, outside the
automated tests).

## 7. Capital stock and depreciation are approximated (fixed, with caveat)

Constant capital is approximated by capital stock, and depreciation is
fixed at ~10% of the stock in several places (outside the real-data
paths, where real CCF/stock is already used). By default, the
`:eurostat` path uses the net stock directly reported by Eurostat for
the requested year.

**Fixed (optional):** `inventário_perpétuo=true`
(`calibrar_modelo_portugal`/`calibrar_com_ameco_v2`, with
`fonte_dados`/`dados_setoriais=:eurostat`) replaces this direct reading
with its own series computed via the perpetual-inventory method (PIM —
`calcular_stock_capital_pim`, `src/eurostat_sdmx.jl`):
`Kₜ = (1-δ)·Kₜ₋₁ + FBCFₜ`, with `δ` estimated (`CCF/stock` in the
reference year, not a fixed value) and seeded from the earliest year with
reported stock and GFCF. Verified with real Portuguese data: the PIM
series tracks the reported stock across 22 years (2000-2022), with a
growing but moderate deviation up to the most recent year (sector C:
~10% in 2022) — expected, since the PIM here uses a single depreciation
rate per sector, not differentiated by asset type (structures,
machinery, ICT, etc. have very different useful lives in practice — GFCF
data by asset type is already available in Eurostat, `NAMA_10_A64_P5`
has an `asset10` dimension, but building a multi-asset PIM would also
require depreciation profiles by asset type, which Eurostat does not
publish directly — left undone).

Degrades per sector, not globally: if a sector's historical GFCF does
not reach the requested year, or the estimated `δ` is not valid, that
sector individually falls back to the value reported by Eurostat,
without affecting the others.

---

The test suite (`test/runtests.jl`, 168 tests) runs locally and in CI
(GitHub Actions, Julia 1.10 and 1, on every push to `main`) — see
`.github/workflows/test.yml`. It covers the default synthetic/opt-in
paths; the real-data paths (`fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`, `método=:sdmx`) require network access and
do not run in CI — check them manually with `verificar_sdmx_ameco()`,
`verificar_eurostat_setorial()`, and `paper/matrix_audit.jl` before using
them in a real analysis.

## 8. Imposed floor on `e` (rate of exploitation) in the sectoral calibration

`estimar_parametros_setoriais` (`src/calibracao_pt.jl`) imposes `e =
max(0.1, taxa_mais_valia)`: sectors whose business income (net of CCF)
is close to zero or negative relative to compensation would produce a
zero or negative `e`, which the model does not accept (`Departamento`
requires `e>0`). This is an imposed value, not a purely empirical
observation — the function now explicitly reports how many sectors hit
the floor (e.g., 4/19 for Portugal 2022), rather than doing so silently.
There is not yet an appendix table showing the four raw (non-floored)
values alongside the imposed ones, which would strengthen transparency —
see `paper/main.tex`, Section 5.1, for the same caveat in the paper's
context.

## 9. AMECO exploitation/depreciation series format (fixed)

`analisar_série_temporal_com_dados` (`src/ameco.jl`) used, in an earlier
version, a flat 10% deduction from the (constant-price) capital stock as
"depreciation" when computing the surplus, instead of real consumption
of fixed capital (CCF) — this broke the algebraic invariance that
`e=(Y-V-CCF)/V` should have under a common deflator applied to `Y`, `V`,
and CCF together, since the flat 10% term did not scale with the
deflator. **Fixed:** the real AMECO CCF series is now used (item `UKCT`,
chapter 03-05), deflated consistently with `V` and `Y` in each valuation
convention (`valorização=:corrente`, `:consistente`, or
`:consistente_fbcf`, the last of which uses the investment deflator
instead of the GDP deflator, to test sensitivity to the choice of
deflator). Verified directly: `e` is now identical across conventions
for every year, for both Portugal and Spain — not merely asserted
algebraically.

## 10. Automatic differentiation, TSSI and bifurcations — scope

- **Rationing convergence: local proved, global not.** The exact
  Jacobian (`jacobiana_racionamento`) is triangular with sectors ordered
  by ρ*, with spectrum in `[−1, 0]` (`paper/main.tex`, Proposition 1):
  damped iteration converges locally for every `α ∈ (0, 1)`. Uniqueness
  of the fixed point and global convergence from any initial ρ remain
  open. The Proposition assumes the generic case (no ties in the minimum
  defining κⱼ, no exact `xᵢ/Dᵢ = 1`); at ties, automatic differentiation
  returns the derivative of the branch `minimum` selects.
- **Default relaxation (fixed: 0.5 → 2/3).** With eigenvalues 0 and −1
  both present (every case in the sweep), the radius-minimizing `α` is
  2/3 (radius 1/3). It is now the default (`RELAXAÇÃO_PADRÃO`): ≈30% fewer
  iterations, with convergence far from the fixed point checked
  empirically (6870 runs per `α`, from 0.4 to 0.95, no failures —
  `paper/main.tex`, Table 2), since Proposition 1 only guarantees local
  convergence.
- **Hessians through rationing are not supported.** The implicit-function
  derivative of the fixed point is first-order only; `hessiana_sistema`
  works without `racionamento=true`.
- **TSSI is a valuation layer only.** The capital-mobility term still
  uses simultaneist (Sraffian) profit rates; there is no TSSI-driven
  variant of the dynamics. The lag τ is a single fixed constant (not a
  distribution of turnover times by sector), and depreciation
  `d = δC/x` is valued at base prices, not historical acquisition prices.
- **The bifurcations are of maps, not of the ODE.** `sistema_Ndept!` and
  `sistema_Ndept_io!` grow without bound and have no equilibria in
  levels; analyzing bifurcations of the ODE itself would require
  rewriting it in normalized variables (capital shares, organic
  compositions). BifurcationKit's bifurcation detection assumes ODEs, so
  the classification (fold/flip/Neimark–Sacker) is done on the map's
  multipliers in `continuar_ponto_fixo`; for rationing, the loss of
  stability at `s_c` is a border collision (piecewise-smooth map),
  located only to the resolution of the continuation step.
- **No bifurcation of the TSSI price map in the cases tested** (50 random
  economies, surplus-value scale in [0.05, 10]). This is an empirical
  check, not a stability proof for every `A`.
