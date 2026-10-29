# Known limitations and pending work

*[🇵🇹 Ler em português](LIMITATIONS.pt.md)*

This file documents, plainly, what is not yet correct or complete.
None of these points prevent the code from running, but all of them
affect how the results should be interpreted.

## 1. The technical matrix A did not feed back into the N-department dynamics

In `system_Ndept!` (file `src/core.jl`), each department's
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

**Fixed:** `system_Ndept_io!` (`src/core.jl`), selectable
with `coupled=true` in `simulate_Ndept`/`simulate_Ndept_custom`,
couples A to the dynamics through a capital-mobility term
`μ·(rᵢ − r̄)·Cᵢ`, with `rᵢ` computed on capital valued at Sraffian prices
of production (which depend on A), rather than the bare `e/(k+1)`.
`system_Ndept!` remains the default ("independent sectors") version,
unchanged, for compatibility.
`r̄` is the mean of `r` weighted by `C` (not the aggregate ratio
`ΣS/Σ(C+V)`, used until a later fix) — the only choice for which
`Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exactly, guaranteeing that the mobility term
reallocates aggregate constant capital between sectors rather than
creating or destroying it. Verified by test (`test/runtests.jl`,
"Capital mobility — exact conservation").

**Fixed (second mechanism, optional):** `system_Ndept_io!`
now accepts `realization=true` (passed via `p.realization`, a keyword of
`simulate_Ndept`/`simulate_Ndept_custom`), which adds a realization
pressure that scales planned reinvestment by
`ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1), damping accumulation
whenever the technical structure cannot sustain current output levels.
`xᵢ` is **genuine** gross output, not the value-added-type flow
`Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (constant capital *transferred*, not the stock `Cᵢ`) used
in an earlier fix: `Wᵢ` omits the circulating intermediate consumption
that the matrix `A` actually prices. `xᵢ` is reconstructed from the
model's own cost-output identity — see further below, "Fixed (genuine
gross output...)". Verified by test
(`test/runtests.jl`, "N-dept simulation with realization pressure") and by
robustness across 20 seed/μ combinations with no solver failures.

**Fixed (third mechanism, exact per sector, optional):**
`system_Ndept_io!` now accepts `rationing=true` (takes precedence
over `realization`), which solves **per-sector quantity rationing** — not
just an aggregate pressure. Each sector `j`'s *desired* output
expansion, `Δxⱼ=σ_c,ⱼ·Sⱼ·xⱼ/Cⱼ` (planned investment converted to output
scale via the current capital-output ratio, not the expenditure
`σ_c,ⱼSⱼ` directly — a later fix, see below), requires inputs from
suppliers in the proportions `A[:,j]` (Leontief technology, no
substitution between inputs), so realized reinvestment is bounded by the
scarcest input — and the rationing a sector suffers reduces its
effective demand for ALL its inputs, in turn affecting the rationing
faced by its own suppliers. Solved by fixed-point iteration
(`_solve_rationing`, `src/core.jl`):

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
(`test/runtests.jl`, "Market rationing (fixed point)": `ρ₁=√0.8`,
verified by hand) and by robustness across 20 seed/μ combinations (N=8)
and at N=19, with no convergence failures nor ODE-solver failures.

`check_equilibrium_Ndept(sol, p)` (`src/analysis.jl`) generalizes
`check_equilibrium_2dept` to N sectors: it returns the *intermediate-use
residual* `xᵢ−(A·x)ᵢ` per sector and `ρ_real` (the aggregate version) at
a given point, after the fact — this is not a disequilibrium or market
measure (a positive residual is the normal case in input-output
accounting: output available for consumption, exports, etc., which this
diagnostic does not model), and it does not use the per-sector rationing
(that is already embedded in `κ` inside `system_Ndept_io!` when
`rationing=true`).

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
simulation is assembled (`_ensure_output_admissibility`,
`src/core.jl`), rescaling `A` uniformly if needed, with a warning — not
a silent clamp reapplied at every evaluation. Verified by test
(`test/runtests.jl`, "Reconstructed gross output..." and "Admissibility of the gross output reconstruction").

**Fixed (investment demand in output scale, not expenditure):**
the `Δxⱼ` in the rationing formula above replaces an earlier version
that applied `A[i,j]` directly to planned investment expenditure
`σ_c,ⱼSⱼ`, as if a unit of expenditure required the same input
composition as a unit of physical output — a dimensional problem
identified in external review. `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` converts expenditure
into an output expansion via the sector's current capital-output ratio,
before `A` is applied. By default the entire reconstructed `xᵢ` is
treated as available for investment demand `Dᵢ`, without netting out the
replacement of intermediate inputs (already counted in `zᵢ`) or other
final demand.

**Partly fixed (optional):** the final-use columns of the same IOT
(`NAIO_10_CP1700`, domestic use) give final demand by product
(`final_demand_from_iot`, `fetch_eurostat_final_demand`), now stored in
`params.final_demand` on the Eurostat paths. With
`final_demand_share = exogenous_demand_share(params.final_demand)` in
`simulate_Ndept_custom` (and `A = params.A`), rationing compares `Dᵢ` with
`(1 − φᵢ)·xᵢ`, where `φᵢ` is the share of output going to final
consumption and exports. For Portugal 2022 (paper, Section 5.7, Table 4)
this leaves the share of rationed sectors unchanged and lowers
accumulation by about a fifth at 10 and 19 sectors. Still open:
intermediate replacement is not netted, so `Dᵢ≤(1−φᵢ)xᵢ` remains an upper
bound on investable supply, not a fully netted reproduction balance. And
Eurostat's matrix covers domestic inputs only, so the `xᵢ` reconstructed
from it leaves out imported intermediate inputs.

## 2. R_max in the wage shock used an auxiliary matrix (fixed)

In `simulate_wage_shock` (`src/shocks.jl`), the reported `R_max` was
computed with an `A_ref` matrix generated only to give a feasibility
reference, and with `l = ones(N)` — not the simulation's matrix nor the
departments' real labor coefficients.

**Fixed:** `R_max` now uses `p_base.A` (the technical matrix actually
returned by `simulate_Ndept_custom` for the base scenario) and
`l = [d.v for d in depts]` (labor coefficients proportional to V, the
same convention used in `system_Ndept_io!`). The reported feasibility
value now corresponds to the simulated scenario, not an auxiliary
reference.

Mitigation already applied (kept): the same `seed` is passed to both
scenarios (base and shock), so the two simulations' technical matrices
are identical and the base-vs-shock comparison is reproducible.

## 3. AMECO download (fixed: the official SDMX API replaces the TXT file)

**Historical context:** this section used to describe the old static TXT
file's heuristic URLs (`AMECO_URLS_TO_TRY`, `src/ameco_download.jl`) and
its fixed-width parser (`read_ameco_txt_file`). Confirmed in 2026-07
that this distribution was **discontinued by the European Commission** —
every URL returns a 404 or redirects to the portal's HTML page, never
data.

**Fixed:** AMECO now exposes an **official SDMX REST API**
(`src/ameco_sdmx.jl`, `webgate.ec.europa.eu/ecfin/redisstat`, the same
platform as Eurostat's newer data tool). `fetch_ameco_data`
(methods `:auto`/`:sdmx`/`:download`) uses it as the default automatic
path. Verified with real calls (2026-07): Portugal's GDP, employment,
compensation, GFCF, and net capital stock, correctly returned back to
1960. The mnemonics in `AMECO_VARIABLE_CODES` (UVGD, OVGD, etc.) were
confirmed valid as `ITEM` codes in this API, with no need to remap.
Country codes needed their own mapping (`AMECO_SDMX_COUNTRY_CODES`),
mostly ISO3 but with real irregularities (GRC not EL, GBR not UK, ROM
not ROU).

**Resolved (almost entirely):** `AMECO_SDMX_MAP` now maps 22 of the 25
variables in `AMECO_VARIABLE_CODES`, plus 2 series calculated from
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
`GDP_current/GDP_constant×100`, not requested from the API), and trade
balance (calculated, exports minus imports of **goods** only — chapter
11-01, items `DXGT`/`DMGT`, `UNIT=99`; distinct from
`exports`/`imports`, which cover goods and services). The values
obtained for Portugal match known real figures (2022 deficit ≈ -0.3% of
GDP, 2022 unemployment ≈ 6.2%, 2022 public debt ≈ 111% of GDP).

**Confirmed unavailable (not "pending"):** gross capital stock. Only the
net-stock chapter (`AMECO_CHAPTER08-01`) exists in this API, with no
published gross equivalent — verified by a full wildcard of the
chapter's items, not just by failing to find it on the first attempt.

**Important note:** several mnemonics that were in
`AMECO_VARIABLE_CODES` (never previously verified) turned out to be
**incorrect** against the real API — for example `UUTG` was assigned to
`government_revenue` (government revenue) but is actually
`government_expenditure` (government expenditure) — the two were swapped —
and `private_consumption`/`exports`/`imports` used mnemonics
(`UNCT`/`UXTG`/`UMTG`) that no longer exist in the current API (the
correct ones are `UCPH`/`UXGS`/`UMGS`). `AMECO_SDMX_MAP` uses the
corrected codes; `AMECO_VARIABLE_CODES` (`types.jl`, used only by
the legacy TXT parser) was not changed — it remains heuristic, as always
warned.

Only gross capital stock (confirmed unavailable, see above) is missing
from the result (filled with 0.0 by `build_ameco_data`, without an
error). Run `check_ameco_sdmx()` manually (not part of the automated
tests, so as not to depend on network access in CI) before trusting the
data in a real analysis.

The old TXT/CSV path (`read_ameco_txt_file`, `parse_ameco_csv`,
methods `:local`/`:csv`) remains available for anyone who already has a
manually downloaded file, but it is no longer the automatic path.

If every path fails, `fetch_ameco_data(..., method=:auto)` silently
falls back to **synthetic data** (with a warning). Always check the
result's `source` (source) field.

## 4. AMECO calibration is macro (3 sectors), with fixed weights by default (fixed)

`calibrate_with_ameco_data` only implements the `:macro` aggregation
(Primary/Secondary/Tertiary). By default (`sector_data=:fixed`), the
sectoral split of GDP, employment, and capital stock uses **fixed
per-country weights** hard-coded in `_sector_gva_shares`,
`_sector_employment_shares`, and `_sector_stock_shares`. These are
approximations; countries without a specific profile fall back to the EU
average profile. Since value added, compensation and CCF are split by the
same weights, `e` comes out equal in all three sectors; only `k` differs.

**Fixed (fixed weights):** this path deducted 10% of each sector's capital
stock as depreciation, instead of AMECO's real CCF (the same error as item
9), and split the stock by `[0.10, 0.35, 0.55]`, which gave the Primary
sector 12–17 times its value added in capital. Together these made net
income negative in the Primary sector (and, with synthetic data, in the
Secondary too): `e` sat at the 0.1 floor while `r` was negative,
inconsistent with `r = e/(k+1)`. The path now uses AMECO's CCF series
(`UKCT`), split like value added (real sectoral CCF shares track value-added
shares closely), and Eurostat capital-stock shares for Portugal,
`[0.02, 0.16, 0.82]` (`NAMA_10_NFA_ST`, 2019/2022: 0.016 / 0.16 / 0.82; the
Tertiary sector includes dwellings). `r` is computed as `e/(k+1)` from the
floored `e`, and sectors hitting the floor are reported, as in the INE path
(item 8). In `compare_ameco_countries`, the `GDP` and `Wage_Share` columns
actually measured capital advanced `Σ(C+V)` and `ΣV/Σ(C+V)`; they now
measure value added and `ΣV/ΣVAB`.

**Fixed (optional):** `sector_data=:eurostat` uses **real** VAB,
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
(`aggregate_io_matrix`, `src/eurostat_sdmx.jl`):
`A₃[gi,gj] = Σ A₁₉[i,j]·GVA[j] / Σ GVA[j]` (VAB-weighted sum within group
`j`). The caveat about the Tertiary row that used to appear here in an
earlier version described a symptom of the wrong table used at the time
(see item 4-bis) — resolved, not worked around, by the dataflow fix.

## 4-bis. Real technical matrix A — wrong dataflow, found and fixed

**Bug history (2026-07/08):** an audit requested during external review
(meant to quantify the effect of a margin-clipping step, reconcile
published totals, document the CPA↔NACE correspondence, and resolve the
domestic-vs-total-use question) revealed something more fundamental than
any of those individual questions: `build_eurostat_io_matrix`
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

**Fixed:** `build_eurostat_io_matrix` now uses `NAIO_10_CP1700`
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
falls back to the nearest reference year (`_nearest_iot_year`), with
a warning — so the matrix `A` for a request for, say, 2022, in practice
has a 2020 vintage (see `paper/main.tex`, Section 4.2, for how the paper
explicitly separates the 2020 and 2022 results rather than mixing them).

Used by `calibrate_portugal_model(..., data_source=:eurostat)` (19 CAE
sectors — see item 5) and, aggregated via `aggregate_io_matrix`, by
`calibrate_with_ameco_v2(..., sector_data=:eurostat)` (3 macro sectors
— see item 4). Full verification (admissibility-rescaling frequency,
reconciliation, domestic/imported question) in `paper/matrix_audit.jl`,
run manually against the live API.

## 5. `aggregation` in the INE calibration was not fully wired up (fixed)

`calibrate_portugal_model` accepted the `aggregation` (aggregation)
argument but only ran `:detailed` (19 sectors); the `:medium` and
`:macro` modes were silently ignored.

**Fixed:** `:macro` aggregates to the same 3 sectors used in the AMECO
path (`NACE_MACRO_GROUPS`); `:medium` aggregates to 10 sectors, the
standard NACE Rev.2 "A10" level (`NACE_MEDIUM_GROUPS`,
`src/eurostat_sdmx.jl`) — a recognized aggregation, not an invented one.
`aggregate_sectors` (`src/calibration_pt.jl`) sums the flow variables by
group and aggregates `A` by the same Leontief formula from item 4 —
works with both `data_source=:synthetic` (random A) and `:eurostat`
(real A), with no code distinction between the two cases. Verified: all
6 combinations (`:detailed`/`:macro`/`:medium` ×
`:synthetic`/`:eurostat`) produce non-negative matrices with ρ(A)<1.

## 6. All default data are SYNTHETIC (real data now optional)

Both the INE and AMECO paths use, **by default**, **generated** data
with plausible patterns. They serve demonstration, testing, and
methodological development — **not publishable empirical analysis** in
that mode.

**Real data available (opt-in):**
- INE: `calibrate_portugal_model(data_source=:eurostat, aggregation=:detailed|:macro|:medium)`
  — 19, 3, or 10 sectors, real data and real technical matrix `A` (see
  items 4-bis and 5).
- AMECO: `calibrate_with_ameco_v2(..., sector_data=:eurostat)` — 3
  macro sectors, real data and matrix `A` (see item 4).

Explicitly requesting these modes is still required — the default
behavior on both paths remains synthetic/fixed-weight, for compatibility
with historical behavior and to keep the test suite fully offline (see
`check_eurostat_sectoral()` for a manual check, outside the
automated tests).

## 7. Capital stock and depreciation are approximated (fixed, with caveat)

Constant capital is approximated by capital stock. Depreciation comes
from data wherever data exist: the real-data paths and the AMECO
fixed-weights path use the reported consumption of fixed capital (CFC),
and the synthetic INE data set CFC as a share of value added. No path
still uses a flat 10% of the stock. By default, the
`:eurostat` path uses the net stock directly reported by Eurostat for
the requested year.

**Fixed (optional):** `perpetual_inventory=true`
(`calibrate_portugal_model`/`calibrate_with_ameco_v2`, with
`data_source`/`sector_data=:eurostat`) replaces this direct reading
with its own series computed via the perpetual-inventory method (PIM —
`compute_pim_capital_stock`, `src/eurostat_sdmx.jl`):
`Kₜ = (1-δ)·Kₜ₋₁ + GFCFₜ`, with `δ` estimated (`CFC/stock` in the
reference year, not a fixed value) and seeded from the earliest year with
reported stock and GFCF. Checked with real Portuguese data (2026-10):
the PIM series runs below the reported stock, by 15% in aggregate in
2010 and 28% in 2022. By sector, the 2022 gap ranges from +11%
(agriculture, A) to −36% (real estate, L); manufacturing (C) is at −10%.
The largest gaps are in sectors dominated by buildings and structures
(L, O, G, K, Q), which fits the main simplification: the PIM here uses a
single depreciation rate per sector, estimated from CFC/stock, not one
per asset type (structures,
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

The test suite (`test/runtests.jl`, 254 tests) runs locally and in CI
(GitHub Actions, Julia 1.10 and 1, on every push to `main`) — see
`.github/workflows/test.yml`. It covers the default synthetic/opt-in
paths; the real-data paths (`data_source=:eurostat`,
`sector_data=:eurostat`, `method=:sdmx`) require network access and
do not run in CI — check them manually with `check_ameco_sdmx()`,
`check_eurostat_sectoral()`, and `paper/matrix_audit.jl` before using
them in a real analysis.

## 8. Imposed floor on `e` (rate of exploitation) in the sectoral calibration (documented)

`estimate_sector_parameters` (`src/calibration_pt.jl`) imposes `e =
max(0.1, surplus_value_rate)`: sectors whose business income (net of CCF)
is close to zero or negative relative to compensation would produce a
zero or negative `e`, which the model does not accept (`Department`
requires `e>0`). This is an imposed value, not a purely empirical
observation — the function now explicitly reports how many sectors hit
the floor (e.g., 4/19 for Portugal 2022), rather than doing so silently.

**Documented:** `CalibratedParameters` now also carries `e_raw`, the ratio
before the floor (on both the INE and AMECO paths), and the paper prints
the raw and imposed values side by side (`paper/main.tex`, Section 5.1,
Table 3, generated by `paper/generate_results.jl`). For Portugal 2022 the
four floored sectors are electricity (raw `e` ≈ −0.53), public
administration, education (both slightly negative) and health (≈ 0.09).
The floor barely moves the aggregate: `r = ΣS/Σ(C+V)` is 6.12% with it and
5.80% with the raw ratios. The floor itself stays, because `Department`
requires `e > 0`.

## 9. AMECO exploitation/depreciation series format (fixed)

`analyze_time_series_with_data` (`src/ameco.jl`) used, in an earlier
version, a flat 10% deduction from the (constant-price) capital stock as
"depreciation" when computing the surplus, instead of real consumption
of fixed capital (CCF) — this broke the algebraic invariance that
`e=(Y-V-CFC)/V` should have under a common deflator applied to `Y`, `V`,
and CCF together, since the flat 10% term did not scale with the
deflator. **Fixed:** the real AMECO CCF series is now used (item `UKCT`,
chapter 03-05), deflated consistently with `V` and `Y` in each valuation
convention (`valuation=:current`, `:consistent`, or
`:consistent_gfcf`, the last of which uses the investment deflator
instead of the GDP deflator, to test sensitivity to the choice of
deflator). Verified directly: `e` is now identical across conventions
for every year, for both Portugal and Spain — not merely asserted
algebraically.

## 10. Automatic differentiation, TSSI and bifurcations — scope

- **Rationing convergence: local proved, global not.** The exact
  Jacobian (`rationing_jacobian`) is triangular with sectors ordered
  by ρ*, with spectrum in `[−1, 0]` (`paper/main.tex`, Proposition 1):
  damped iteration converges locally for every `α ∈ (0, 1)`. Uniqueness
  of the fixed point and global convergence from any initial ρ remain
  open. The Proposition assumes the generic case (no ties in the minimum
  defining κⱼ, no exact `xᵢ/Dᵢ = 1`); at ties, automatic differentiation
  returns the derivative of the branch `minimum` selects.
- **Default relaxation (fixed: 0.5 → 2/3).** With eigenvalues 0 and −1
  both present (every case in the sweep), the radius-minimizing `α` is
  2/3 (radius 1/3). It is now the default (`DEFAULT_RELAXATION`): ≈30% fewer
  iterations, with convergence far from the fixed point checked
  empirically (6870 runs per `α`, from 0.4 to 0.95, no failures —
  `paper/main.tex`, Table 2), since Proposition 1 only guarantees local
  convergence.
- **Hessians through rationing are not supported.** The implicit-function
  derivative of the fixed point is first-order only; `system_hessian`
  works without `rationing=true`.
- **TSSI is a valuation layer only.** The capital-mobility term still
  uses simultaneist (Sraffian) profit rates; there is no TSSI-driven
  variant of the dynamics. The lag τ is a single fixed constant (not a
  distribution of turnover times by sector).
- **Depreciation at historical cost (fixed, optional).** By default
  depreciation `d = δC/x` is valued at base prices.
  `tssi_valuation(...; depreciation = :historical)` instead keeps a book
  value of fixed capital per sector: gross investment is bought at the
  previous step's TSSI price of the sector's capital good (the
  `A`-column-weighted price), depreciation removes `δh` of the book value,
  and disposals leave at average book cost. `d` is then the book value
  used up per unit of output. The invariants still hold to machine
  precision; on a 6-sector coupled run, book value/`C` stays between 0.95
  and 1.16 and the TSSI profit rate moves by under 0.2 points.
- **Bifurcations of the accumulation ODE: only in the cross-dual model
  (partly fixed).** `system_Ndept!` and `system_Ndept_io!` grow without
  bound and have no equilibria in levels; their steady states are
  balanced-growth rays, fixed points of the normalized system
  (`src/growth.jl`). But without market prices a sector's profit
  rate does not depend on its relative size: there is no interior
  balanced growth (capital concentrates in one sector), even with
  `μ_v`, `realization` or `rationing`. Only the optional cross-dual
  dynamics (`market_prices=true`, `src/cross_dual.jl`) have interior rays,
  and that is where `accumulation_bifurcation` detects Hopf points and
  continues the limit cycles. For the maps (rationing, TSSI), the
  fold/flip/Neimark–Sacker classification is done on the multipliers in
  `continue_fixed_point`, because BifurcationKit's detection assumes ODEs;
  for rationing, the loss of stability at `s_c` is a border collision
  (piecewise-smooth map), located only to the resolution of the
  continuation step.
- **No bifurcation of the TSSI price map in the cases tested** (50 random
  economies, surplus-value scale in [0.05, 10]). This is an empirical
  check, not a stability proof for every `A`.

## 11. Cross-dual dynamics (market prices) and accumulation cycles — scope

- **Assumptions of the cross-dual model.** Market prices respond to
  relative excess demand with a single speed `β`; capital goods are
  bought in the composition of A's columns and all consumption in a fixed
  basket `basket`: by default initial net-output shares, an assumption;
  on a real-data calibration, `consumption_basket(params.final_demand)`
  gives real household consumption shares (with `A = params.A`). For
  Portugal 2022 the real basket raises the balanced-growth rate from about
  0.14 to 0.19 at 10 and 19 sectors and leaves stability unchanged (paper,
  Section 5.7). Prices are normalized so that
  total profit equals total surplus value. It cannot be combined with
  `realization` or `rationing`.
- **`μ_v` (mobility of variable capital) is off by default.** Accumulation
  cycles appear from `μ_v ≈ 0.5–1.3` (supercritical Hopf in all 30 random
  economies tested, with `β = 0.1`); the empirical value of `μ_v` is not
  calibrated.
- **The cycles approach the boundary of the simplex (partly fixed:
  optional exit friction).** Away from the Hopf point, sector shares fall
  to 10⁻³–10⁻⁴ (10⁻⁵ at `μ_v = 2.4`): the oscillations nearly wipe out
  sectors, which is economically implausible. `exit_friction = ε > 0`
  (`simulate_Ndept`, `simulate_Ndept_custom`, or `p.exit_friction`;
  continuation parameter `:exit_friction` in `with_parameter`) damps each
  outflow of the mobility terms by `sᵢ/(sᵢ + ε)`, `sᵢ` the sector's share,
  and scales inflows by a common factor so the term still sums to exactly
  0 (`_mobility_flow`). In the paper's
  reference economy (β = 0.1), `ε = 0.05` raises the smallest share at
  `μ_v = 2.4` from 9.5·10⁻⁶ to 4.3·10⁻³ (from 5.8·10⁻⁴ to 5.8·10⁻³ at
  `μ_v = 2.0`), moves the first Hopf point up (stability is lost near
  `μ_v ≈ 1.2` instead of 1.05) and changes which regime prevails at a
  given `μ_v`, but the cycles remain (paper, Section 5.6). The default is `ε = 0`, so the
  paper's other results are unchanged. The functional form and `ε` are
  assumptions, not estimates, and entry of new capital is not modeled.
- **Bifurcation detection.** Two Hopf points in the same continuation
  step escape detection (`dsmax = 0.01` by default; `accumulation_bifurcation`
  warns when its count of unstable eigenvalues disagrees). Bifurcations
  of the cycles (fold, period doubling, Neimark–Sacker) depend on the step
  and count as confirmed only where direct simulation (`simulated_cycle`)
  agrees. BifurcationKit's automatic branch switching at the Hopf point
  fails (singular Jacobian); the branch is seeded from the normal-form
  predictor instead.
- **Chaos: numerical evidence, not proof.** In the irregular regime the
  largest Lyapunov exponent (`lyapunov_exponents`) is positive and robust
  to the initial condition, the integration tolerance and the run length
  (and two exponents are positive at high `μ_v`: hyperchaos), but these
  are finite-time estimates, not a computer-assisted proof. Coexistence of
  a stable cycle and the torus was verified by sweeping the parameter in
  both directions (`simulated_hysteresis`), not by mapping the full basins
  of attraction.
- **Cost.** Collocation continuation of cycles is slow for N = 6 (≈100 s),
  and each Lyapunov-exponent estimate takes ≈100 s; the tests use short
  horizons.

## 12. AMECO forecast years (fixed)

AMECO publishes the Commission's forecasts for the release year and the
next one in the same series as the observed data, and nothing in the
SDMX response marks them: `OBS_STATUS` is `A` for every year. Requesting
years up to 2027 from the spring 2026 release silently returned the 2026
and 2027 forecasts, so a calibration for 2026, or a time series ending
there, used forecasts as if they were data.

**Fixed:** the release year is read from the `LAST UPDATE` column of the
SDMX response (`_release_year`), and on the SDMX path `fetch_ameco_data`
drops the years from the release year on, with a warning
(`_drop_forecast_years`). The last actual year is recorded in
`data.notes["last_actual_year"]`. A calibration year beyond it falls back
to that year with a warning. `include_forecasts=true` (in
`fetch_ameco_data`, `calibrate_with_ameco_v2` and
`analyze_ameco_time_series`) keeps the forecasts. Tested offline
(`test/runtests.jl`, "AMECO forecast years").

**Caveat:** the legacy TXT/CSV files carry no release date, so no years
are dropped on those paths. The rule assumes AMECO's usual calendar
(spring and autumn releases, each forecasting the current and the next
year). The most recent actual year is itself provisional and may be
revised in later releases.
