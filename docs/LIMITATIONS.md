# Known limitations and pending work

*[🇵🇹 Ler em português](LIMITATIONS.pt.md)*

This file documents, plainly, what is not yet correct or complete.
None of these points prevent the code from running, but all of them
affect how the results should be interpreted.

Each section starts with a short summary of where things stand now;
the rest is the detail and the history of each fix.

## At a glance

| § | Topic | Status | Still open |
|---|---|---|---|
| 1 | Sectoral coupling through `A` | Fixed (opt-in): capital mobility, realization pressure and per-sector rationing, on genuine gross output with imported inputs and final demand | Netting intermediate replacement (`net_intermediate`) holds only briefly with real tables: nothing keeps sectoral proportions in line with `A` |
| 2 | `R_max` in the wage shock | Fixed | — |
| 3 | AMECO download | Fixed: official SDMX API | Gross capital stock is not published; `method = :auto` falls back to synthetic data, with a warning |
| 4 | AMECO calibration (3 macro sectors) | Fixed: real depreciation, capital at current cost; real sector data and the self-employed adjustment are opt-in | The default sector weights are fixed approximations |
| 4-bis | Real technical matrix `A` | Fixed: the right Eurostat table | Input-output tables exist only for benchmark years; the nearest one is used |
| 5 | `aggregation` in the INE calibration | Fixed | — |
| 6 | Synthetic default data | By design: real data are opt-in | — |
| 7 | Capital stock and depreciation | Fixed; perpetual inventory by asset type is opt-in | Construction and finance keep large gaps against the reported stock |
| 8 | Floor on `e` | Mitigated (opt-in): market sectors, multi-year `e`, imputation per hour | A department with `e ≤ 0` is not allowed, so some sectors stay floored |
| 9 | Deflating the AMECO series | Fixed; `:consistent_gfcf` deprecated | — |
| 10 | Automatic differentiation, TSSI, bifurcations | Scope | Global convergence of rationing is not proved; bifurcations exist only in the cross-dual model |
| 11 | Cross-dual dynamics and cycles | Scope: parameters estimated on the EU panel | The cycles lie outside the estimated range; chaos is numerical evidence, not proof |
| 12 | AMECO forecast years | Fixed | Legacy TXT/CSV files carry no release date, so forecasts are not dropped there |

**Testing.** The test suite (`test/runtests.jl`, 639 tests) runs locally and in CI
(GitHub Actions, Julia 1.10 and 1, on every push to `main`) — see
`.github/workflows/test.yml`. It covers the default synthetic/opt-in
paths; the real-data paths (`data_source=:eurostat`,
`sector_data=:eurostat`, `method=:sdmx`) require network access and
do not run in CI — check them manually with `check_ameco_sdmx()`,
`check_eurostat_sectoral()`, and `paper/matrix_audit.jl` before using
them in a real analysis.


## 1. Sectoral coupling through the technical matrix A

**In short:** by default the sectors accumulate independently and `A`
only enters values and prices. `coupled = true` couples them through
`A` by capital mobility, optionally with realization pressure or exact
per-sector quantity rationing, on gross output reconstructed from the
model's own state (with imported inputs and final demand as options).
Still open: netting the replacement of intermediate inputs out of
investable supply works with real tables only for a few years, because
nothing in the coupled system keeps sectoral proportions in line with
`A`.

### Default model: independent sectors

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

In this model the cycles and (non-)convergence of profit rates reflect
only heterogeneity in initial parameters, not sectoral
interdependence. The coupled system below fixes that.

### Capital mobility (`coupled = true`)

`system_Ndept_io!` (`src/core.jl`), selectable
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

### Realization pressure (`realization = true`)

`system_Ndept_io!` accepts `realization=true` (passed via `p.realization`, a keyword of
`simulate_Ndept`/`simulate_Ndept_custom`), which adds a realization
pressure that scales planned reinvestment by
`ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1), damping accumulation
whenever the technical structure cannot sustain current output levels.
`xᵢ` is **genuine** gross output, not the value-added-type flow
`Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (constant capital *transferred*, not the stock `Cᵢ`) used
in an earlier fix: `Wᵢ` omits the circulating intermediate consumption
that the matrix `A` actually prices. `xᵢ` is reconstructed from the
model's own cost-output identity (see "Gross output, not value added"
below). Verified by test
(`test/runtests.jl`, "N-dept simulation with realization pressure") and by
robustness across 20 seed/μ combinations with no solver failures.

### Per-sector quantity rationing (`rationing = true`)

`system_Ndept_io!` accepts `rationing=true` (takes precedence
over `realization`), which solves **per-sector quantity rationing** — not
just an aggregate pressure. Each sector `j`'s *desired* output
expansion, `Δxⱼ=σ_c,ⱼ·Sⱼ·xⱼ/Cⱼ` (planned investment converted to output
scale via the current capital-output ratio, not the expenditure
`σ_c,ⱼSⱼ` directly; see "Investment demand in output units" below), requires inputs from
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

### Gross output, not value added

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
in these simulations; the real Eurostat domestic-use matrix omits imports
by definition, which the optional import coefficients put back, see the
end of this item). The admissibility condition `Σᵢ A[i,j]<1` (needed for the denominator to
be positive) is not guaranteed by `ρ(A)<1` (which bounds the spectral
radius, not any individual column sum); checked and fixed once, when the
simulation is assembled (`_ensure_output_admissibility`,
`src/core.jl`), rescaling `A` uniformly if needed, with a warning — not
a silent clamp reapplied at every evaluation. Verified by test
(`test/runtests.jl`, "Reconstructed gross output..." and "Admissibility of the gross output reconstruction").

### Investment demand in output units

The `Δxⱼ` in the rationing formula above replaces an earlier version
that applied `A[i,j]` directly to planned investment expenditure
`σ_c,ⱼSⱼ`, as if a unit of expenditure required the same input
composition as a unit of physical output — a dimensional problem
identified in external review. `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` converts expenditure
into an output expansion via the sector's current capital-output ratio,
before `A` is applied. By default the entire reconstructed `xᵢ` is
treated as available for investment demand `Dᵢ`, without netting out the
replacement of intermediate inputs (already counted in `zᵢ`) or other
final demand.

### Final demand (`final_demand_share`, opt-in)

The final-use columns of the same IOT
(`NAIO_10_CP1700`, domestic use) give final demand by product
(`final_demand_from_iot`, `fetch_eurostat_final_demand`), now stored in
`params.final_demand` on the Eurostat paths. With
`final_demand_share = exogenous_demand_share(params.final_demand)` in
`simulate_Ndept_custom` (and `A = params.A`), rationing compares `Dᵢ` with
`(1 − φᵢ)·xᵢ`, where `φᵢ` is the share of output going to final
consumption and exports. For Portugal 2022 (paper, Section 5.7, Table 4)
this leaves the share of rationed sectors unchanged and lowers
accumulation by about a fifth at 10 and 19 sectors.

### Netting intermediate replacement (`net_intermediate`, opt-in; partly open)

`net_intermediate = true` (with `rationing = true`) also nets
the replacement of the period's intermediate inputs, comparing `Dᵢ` with
`max(xᵢ − (A·x)ᵢ − φᵢxᵢ, 0)` (`_investable_supply`, `src/core.jl`).

- **On its own it is not usable with the real IOT.** With Portugal's 2022
  IOT accumulation collapses (ΣC ×0.3 over 30 years at 10 and 19 sectors,
  against ×56.6–×200.6 without it), because two things don't match.
  - *What investment buys.* In the table the row residual
    `x − A·x − φ·x` is gross capital formation (plus small items), which a
    handful of sectors produce: construction F (65% of its output), J
    (18%), M (15%), L (12%), A (8%), G (5%), R (2%). But the model's
    investment demand, `A·Δx`, has the composition of the circulating
    inputs of expanding output, which every sector supplies. The minimum
    in `κⱼ = minᵢ ρᵢ` binds at a sector with no residual.
  - *The model's `x`.* It is 0.5–2.0 times the IOT output by section in
    2022 (0.7–1.3 in 2020, the table's benchmark year), and the residual
    is 0–6% of output in most sectors, so a few percent of error decides
    which sectors can supply investment.
- **Fixed for the first, opt-in:** `capital_goods = b` makes gross
  investment buy capital goods, in the shares `b` (or the columns of an
  `N×N` matrix). `capital_goods_composition(params.final_demand; A =
  params.A)` gives them from the table's row residual, dropping goods
  below 0.1% of capital formation, which would otherwise decide the
  minimum.
- **Fixed for the second, opt-in:** `benchmark_output =
  params.final_demand.output` rescales `x` sector by sector, with factors
  fixed at `t = 0`, to the table's composition and the same total.
- **With both, the netted balance holds at the start but not for long**
  (Portugal, 15 market sectors, 2022 and 2019; 19 sections, 2022). At
  `t = 0` no sector is rationed (model investment is about 1/1.24 of the
  table's gross capital formation). How long it holds depends on how fast
  the sectoral composition drifts away from the table's, and the drift is
  mostly unrationed variable capital (`dV = σ_v·S`, growing at `σ_v·eᵢ`,
  2–23% a year by sector).
  - At the calibrated `σ_v` = 0.15, the composition drifts by a factor of
    e¹·⁴–e¹⁰ in 10 years, and investment stops within about 3 years.
  - At `σ_v` = 0.01, the order of the estimates of notebook 14, κ averages
    0.74–0.80 over the first 10 years and falls to 0 by year 30.
  - At `σ_v` = 0, it averages 0.85–0.89, then about 0.5, and is 0.42–0.45
    at year 30.

  The supply-side reproduction balance binds in about 90% of the
  periods. The coupled system has no mechanism keeping sectoral
  proportions in line with `A`. Proportionality is exactly what a netted
  balance tests, and it fails as sectors grow at their own rates.
- **Still open:** a mechanism that restores proportions, such as market
  prices (the cross-dual system, which cannot be combined with rationing)
  or demand-led variable capital.

A related observation for the default model: at `σ_v` = 0.01, ΣC grows
×0.9–1.4 over 30 years even without netting (×1.4 at 19 sections with
imports, against ×73.7 at the calibrated 0.15). The ×56–×200 of the
paper's Table 4 come from variable capital growing at `σ_v` = 0.15.

### Imported inputs (`import_coefficients`, opt-in)

Eurostat's matrix covers domestic
inputs only, so the `xᵢ` reconstructed from it left out imported
intermediate inputs. The IOT's own `IMP` row gives them per buying
industry, and `fetch_eurostat_import_coefficients` turns them into
coefficients `mⱼ = IMPⱼ/P1ⱼ`, stored in `params.import_coefficients` on the
Eurostat paths (aggregated with the same GVA weights as A's columns). With
`import_coefficients` in `simulate_Ndept_custom` (and `A = params.A`),
gross output is `xⱼ = Wⱼ/(1 − Σᵢ A[i,j] − mⱼ)` (`_gross_output`), and the
admissibility check covers `Σᵢ A[i,j] + mⱼ`. For Portugal (IOT 2020),
manufacturing imports 35% of its output in inputs, and the
reconstructed `x` is 2.3 times what the domestic matrix alone implies; in
the other sections, 1.01 to 1.38 times. With rationing (paper, Table 4)
the share of rationed sectors does not change, but accumulation over 30
years rises by 8% at 10 sectors (×200.6 → ×215.9) and by 31% at 19
(×72.4 → ×94.7). Opt-in, so the paper's numbers are unchanged. Not
available in the cross-dual model (`market_prices`), whose profits would
also need a price of imports, nor in the TSSI layer.

## 2. R_max in the wage shock (fixed)

**In short:** `R_max` now uses the simulated scenario's own matrix and
labor coefficients, not an auxiliary reference matrix.

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

## 3. AMECO download: the official SDMX API (fixed)

**In short:** data come from AMECO's official SDMX API, which maps 24 of
25 variables; the old TXT distribution was discontinued. Gross capital
stock is not published. If every path fails, `method = :auto` falls back
to synthetic data with a warning, so check the result's `source`.

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

## 4. AMECO calibration (3 macro sectors)

**In short:** the calibration uses AMECO's real depreciation and values
the capital stock at current replacement cost. By default the split into
3 macro sectors uses fixed weights; `sector_data = :eurostat` uses real
sector data and the real matrix `A`, and `self_employed = :imputed`
counts the self-employed at the average wage.

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

**Fixed (capital valuation):** this path divided AMECO's net capital stock
(`OKND`, at constant 2020 prices) by compensation at current prices, so `k`
fell with every year of inflation after 2020: for 2024 it was 17–25% too
low in Germany, Portugal and Poland. The stock is now revalued to current
replacement cost with the GFCF deflator (`PIGT`, 2020 = 100), the price
basis of Eurostat's stock on the `:eurostat` path, and the calibrated `k`
equals `analyze_time_series_with_data(...; valuation = :current_cost)`
exactly. **Self-employment (optional):** compensation of employees leaves
out the self-employed, whose income then counts as surplus value and
overstates `e` (in 2024 by a factor of about 1.8 in Greece and Italy).
`self_employed = :imputed` counts each of them at the average employee's
compensation, as AMECO's adjusted wage share does. It is opt-in, and
available on every real-data path: on `:fixed` with AMECO's aggregate
ratio; on `sector_data = :eurostat` and in `calibrate_portugal_model(...;
data_source = :eurostat)` per NACE section, from Eurostat's employees
(`SAL_DC`) and employment (`EMP_DC`), imputed at the 19 sections before any
aggregation (`impute_self_employed`). Self-employment is very uneven: in
Portugal, 2022, the factor is 2.98 in agriculture, 1.84 in other services
and 1.58 in real estate, but 1.05 in manufacturing. Imputing lowers the
aggregate `e` from 0.45 to 0.26 and `r` from 5.8% to 3.7%. The imputation
assumes the self-employed earn what employees in their section do; where
mixed income falls short of that (agriculture: raw `e` −0.20), `e` turns
negative, and more sectors hit the floor of item 8. Persons are counted,
not hours worked.

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

## 4-bis. Real technical matrix A (fixed: wrong dataflow)

**In short:** `A` is built from Eurostat's symmetric input-output table
(`NAIO_10_CP1700`, domestic use), after an audit found an earlier version
reading a trade-margins satellite table. The table exists only for
benchmark years (Portugal: 2010, 2013, 2015, 2017, 2020); other years use
the nearest one, with a warning.

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

## 5. `aggregation` in the INE calibration (fixed)

**In short:** `:detailed` (19), `:medium` (10, NACE A10) and `:macro` (3)
all work, on synthetic and real data.

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

## 6. Default data are synthetic; real data are opt-in

**In short:** without options, both calibration paths use generated
data, for demonstration and offline tests. Real data must be requested
explicitly.

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

## 7. Capital stock and depreciation

**In short:** constant capital is proxied by the net capital stock, and
depreciation comes from reported consumption of fixed capital on every
real-data path. An optional perpetual inventory by asset type tracks the
reported stock closely (2022 aggregate gap −1.9%); construction and
finance keep the largest gaps.

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
machinery, ICT, etc. have very different useful lives in practice).

**Fixed (optional): by asset type.** `perpetual_inventory=:by_asset`
(`true` is `:single`, the version above) runs the inventory asset by
asset (`compute_pim_capital_stock_by_asset`). Eurostat publishes no
depreciation by asset, but it does publish GFCF (`NAMA_10_A64_P5`) and
the net stock (`NAMA_10_NFA_ST`) by asset type and section in chain-linked
volumes, so each asset's rate can be backed out of the stock identity
without revaluation effects (`estimate_asset_depreciation`, the median over
years of `(Kₜ₋₁ + Iₜ − Kₜ)/Kₜ₋₁`). The six asset types (`PIM_ASSETS`:
dwellings, other buildings and structures, transport equipment, other
machinery, cultivated biological resources, intellectual property) add up
to the net total in every Portuguese section, within 1%. The recursion runs
in volumes and each asset is revalued by its own GFCF deflator; a holding
the section never buys (dwellings in construction, say) takes the deflator
of the section's total investment, and one whose series give no rate takes
the asset type's median rate in the other sections. The implied rates are
3–9% for buildings and structures, 25–28% for transport equipment,
12–25% for other machinery and 27–46% for intellectual property.

Against the stock Eurostat reports for Portugal, the aggregate gap falls
from −15.4% to −3.3% in 2010 and from −28.2% to −1.9% in 2022. By section
the mean absolute gap falls from 12.1% to 10.0% (2010) and from 19.9% to
7.9% (2022); in 2022, 14 of 19 sections are within 10% (4 with one rate).
The structure-heavy sections improve most (L from −36% to −2%, O from
−34% to −5%, G from −30% to +9%). What is left is not the depreciation
profile but the treatment of particular flows: construction (F, +26% in
2022) and finance (K, −21%, with net disposals of buildings, i.e.
negative GFCF, in many years since 2011) keep the largest gaps. The
by-asset version removes two simplifications of the single-rate one at
once, one rate for long- and short-lived assets and no revaluation of the
stock at current prices; this check does not separate their contributions.

Degrades per sector, not globally: if a sector's historical GFCF does
not reach the requested year, or the estimated `δ` is not valid, that
sector individually falls back to the value reported by Eurostat,
without affecting the others.

## 8. The floor on `e` in the sectoral calibration (mitigated)

**In short:** the model needs `e > 0`, so the calibration floors `e`
(at 0.1 by default) and reports the raw value in `e_raw`. Options separate
the causes: non-market sectors (`sectors = :market`), one-off years
(`e_years`) and the imputation of the self-employed. With the market
sectors, a five-year `e` and the self-employed imputed, the floor still
binds in 5 of 15 sectors.

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
requires `e > 0`. With the self-employed imputed (`self_employed =
:imputed`, item 4) the floor binds in 9 of 19 sectors instead of 4:
agriculture (A), professional (M) and administrative services (N), arts
(R) and other services (S) join the four above, so the floor matters more
on that path.

**Mitigated (opt-in):** the floor covers three different things, which
`calibrate_portugal_model` can now separate (`docs/NATIONAL_ACCOUNTS.md`
§4; the defaults are unchanged, so the paper's Table 3 is too):
- *Non-market sections.* O, P and Q have `e` ≈ 0 by construction, because
  the accounts value non-market output at cost. `sectors = :market` leaves
  them out together with real estate (L, imputed rents), the 15 market
  sectors of notebooks 9–12. Inputs bought from them are treated like
  imports, and their purchases become government demand. The floor then
  binds only in electricity (1 of 15), and `r` is 11.3% instead of 6.1%,
  because L's capital stock is gone.
- *One-off years.* Electricity's −0.53 is the 2022 energy crisis.
  `e_years` computes `e` over several years; over 2018–2022 D has 3.70.
  A three-year window, 2020–2022, is dominated by the pandemic (transport
  and the arts drop below the floor), so the window should span a cycle.
- *The imputation of the self-employed.* `self_employed = :imputed_hours`
  imputes per hour worked. It lifts agriculture from −0.20 to 0.07 but not
  M, N, R and S, whose `e` stays at or below zero with the self-employed
  counted at a wage. That is in the accounts. With the market sectors, a
  five-year window and either imputation, the floor binds in 5 of 15
  sectors (A, M, N, R, S).

`e_floor` makes the floor a keyword (it must stay positive). What remains
open is a department with `e ≤ 0`, which the model does not allow: the
floored value in those five sectors is a modeling choice, and `e_raw`
keeps the measured one.

## 9. Deflating the AMECO time series (fixed)

**In short:** the series use AMECO's real depreciation, and the rate of
exploitation is identical under every consistent valuation. Current cost
is the reference valuation; `:consistent_gfcf`, which mixed deflators, is
deprecated.

`analyze_time_series_with_data` (`src/ameco.jl`) used, in an earlier
version, a flat 10% deduction from the (constant-price) capital stock as
"depreciation" when computing the surplus, instead of real consumption
of fixed capital (CCF) — this broke the algebraic invariance that
`e=(Y-V-CFC)/V` should have under a common deflator applied to `Y`, `V`,
and CCF together, since the flat 10% term did not scale with the
deflator. **Fixed:** the real AMECO CCF series is now used (item `UKCT`,
chapter 03-05), deflated consistently with `V` and `Y` in each valuation
convention (`valuation=:current`, `:consistent` or `:current_cost`, the
last of which revalues the stock with the investment deflator instead of
deflating the flows by the GDP deflator). Verified directly: `e` is now
identical across conventions for every year, for both Portugal and Spain
— not merely asserted algebraically. **Fixed (mixed deflators):** a
fourth convention, `:consistent_gfcf`, deflated `V` and CCF by the
investment deflator but output by the GDP deflator, so its `e` was not
the current-price one (1.02 against 0.785 for Portugal in 1996) and its
profit rate was too high. Deflating output by the investment deflator as
well gives exactly the `e`, `k` and `r` of `:current_cost`, so
`:consistent_gfcf` is now a deprecated alias of it, with a warning.

## 10. Automatic differentiation, TSSI and bifurcations — scope

**In short:** rationing converges locally (proved) but global
convergence is not proved; Jacobians and Hessians through rationing are
exact; TSSI can drive the dynamics (opt-in); balanced growth and its
bifurcations exist only in the cross-dual model.

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
- **Hessians through rationing (fixed).** The implicit-function derivative
  of the fixed point used to be first-order only, so `system_hessian`
  failed with `rationing=true`. `_rationing_fixed_point` (`src/core.jl`) now
  applies the implicit function theorem once per level of `Dual`: the inner
  level returns ρ* with its first derivative, and differentiating the
  first-order formula at that point gives the exact second derivative (any
  order, in fact). Checked against finite differences of the exact Jacobian
  (agreement to about 10⁻⁸ in three random 6–8-sector economies with
  rationing binding) and against the closed form of the 2-sector example.
  It is the Hessian of the active branch: the map is piecewise smooth, so
  it is undefined at ties in κ or at `ρᵢ = 1`, like the Jacobian.
- **TSSI-driven dynamics (fixed, optional).** By default TSSI is a
  valuation layer only, and the capital-mobility term uses profit rates
  with constant capital at current (simultaneist or market) prices.
  `tssi_dynamics = true` (`simulate_Ndept_custom`, coupled systems) makes
  the rate that drives accumulation the rate on capital advanced at
  historical cost, `Sᵢ/(Bᵢ + Vᵢ)` (`Πᵢ/(Bᵢ + Vᵢ)` with market prices): the
  state gains the book value `B` of each sector's fixed capital, bought at
  the price of its capital good, depreciated at `δ`, with scrapping and net
  disposals leaving at average book cost (`src/tssi.jl`). With market
  prices capital is bought at market prices; without them, at TSSI
  temporal prices that follow the TSSI map with a continuous lag `τ`. The
  variant keeps homogeneity of degree 1, so balanced growth, its stability
  and the Jacobian tools apply. The lag τ is still a single fixed constant
  (not a distribution of turnover times by sector), and the TSSI prices
  leave out imported inputs, so `import_coefficients` is not accepted. In
  Portugal's calibrated cross-dual economy (notebook 14) historical-cost
  valuation barely changes balanced growth (7.23% against 7.24%, the same
  stability), the dispersion of profit rates (0.077 against 0.072) or the
  response to a price shock; book values stay within 0.76–1.17 times `C`.
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

**In short:** the accumulation parameters are now estimated on the EU
sectoral panel (μ, η, the investment floor θ, μ_v and σ_v). The cycles
appear only at a mobility of variable capital far above the estimate
(33 times in Portugal's calibrated economy). Chaos rests on numerical
evidence, not proof, and the cross-dual model cannot be combined with
rationing.

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
- **`μ` is constant; the data say it is not.** Notebook 8 estimates the
  capital-mobility coefficient from EU27 capital flows (net foreign
  financing against the lagged profit-rate gap, 1996–2024). Between
  countries, over the whole period, `μ̂` ≈ 0.33 without the financial
  centres, close to the default of 0.3. Year to year within countries it is
  zero on average: 0.15 before 2008 and −0.27 after. The model's constant
  `μ` matches the long-run pattern, not the response in a credit crisis.
  Between the model's own departments, sectors, notebook 9 finds `μ`
  unidentified (Portugal, 15 market sectors, 2002–2023). Sectors have no
  record of capital transferred, so it is built as net investment beyond a
  common share of own surplus. Within sectors, with sector and year
  effects, `μ̂` ≈ 0.11 (Driscoll–Kraay se 0.05) with the self-employed's
  income counted as surplus value, but −0.19 to −0.35 with it imputed as
  wages: the surplus enters both sides of the equation. Persistent
  sectoral gaps attract no capital (`μ̂` = −0.31 between sectors).
  Notebook 10 repeats the estimate on the 15 market sectors of 26 EU
  countries, with country × year effects that absorb each national credit
  cycle (`compute_mobility_panel`, `estimate_mobility`). There `μ̂` ≈ −0.14
  (clustered se 0.05), with any fixed effects, with the gap instrumented by
  its lag (−0.12), and negative in 21 of 26 countries; Portugal's 0.11 is
  the exception. It is not mainly measurement error: net investment does
  rise with the gap (0.08), but less than a common reinvestment share of
  the sector's surplus would (0.21). What the data reject is the model's
  common `σ_c` for every department, which forces all of the response of
  investment to profitability through `μ`. A reinvestment share that
  differs between departments, or falls with the profit rate, would let
  `μ` be estimated net of it. The apparent break at 2008 (`μ̂` −0.16
  before, −0.06 after, with common effects) has the same source: the
  response of net investment to the gap is stable, and the share
  reinvested net of depreciation halved (0.19 to 0.10); the gross share,
  the model's `σ_c`, did not change (depreciation rose; notebook 11). So
  `μ` constant over time is not what the data reject. Notebook 11 estimates
  the model's investment function with a reinvestment share that falls
  with relative profitability, `σ_c·(r̄/rᵢ)^η`: `μ̂` is then positive for
  every `η` (0.05 to 0.13), but the panel does not identify `η`; investment
  follows own surplus at about a tenth of the average share, which
  calibrates `η` ≈ 1 and gives `μ̂` = 0.13 (se 0.04). In the model, `η` = 1
  with that `μ` lets unprofitable sectors accumulate until their profit
  rate reaches zero. Notebook 13 estimates the linear reinvestment form
  (below) on every row, the loss years included: `η̂` = 0.15 (se 0.18;
  0.09–0.45 across variants) and `μ̂` = 0.063 (se 0.011), so own surplus
  matters more than notebook 11's calibration assumed. Capital does not
  leave unprofitable sectors through investment (the exit coefficient has
  the wrong sign at every hurdle); instead gross investment has a floor
  near replacement, `θ̂` = 0.69 (se 0.18) of depreciation in the loss
  years. With market prices, Portugal's market sectors then have a stable
  interior balanced growth path for every `η` ≤ 0.9; only `η` = 1 has none.
- **The mobility term uses the average rate of profit, and the data agree.**
  Shaikh (2016, ch. 7) argues that competition equalizes the incremental
  rate, the return on new investment, so average rates may differ forever.
  Notebook 12 measures it on the EU panel (`compute_incremental_panel`,
  `estimate_persistence`): incremental-rate gaps are mostly transitory
  (4–14% of their variance is between country × sector units, against
  74–78% for average-rate gaps), but they are not equalized (a permanent
  dispersion of 6–8 pp net of noise, half the 14–15 pp of average rates),
  and they are very noisy, with a mechanical bias from past investment in
  the denominator. Capital follows the average-rate gap: in the investment
  function at `η` = 1, `μ̂` = 0.14 (se 0.03), while the incremental gap
  moves investment a third as much per standard deviation and adds nothing
  once both are in. Inside a department of the model, constant returns make
  the marginal and average rates equal, so the model is unchanged; the
  persistent average gaps of the data (vintages, what the accounts count as
  capital) belong in each department's calibrated technique, and the
  estimates of `μ` absorb them in country × sector effects.
- **Reinvestment share (optional).** `simulate_Ndept_custom(...; η, σ_schedule)`
  replaces each department's fixed `σ_c` by `σ_c,ᵢ·m(t)·(r̄/rᵢ)^η`: an
  elasticity `η` of the share to relative profitability (0 = fixed share,
  the default) and a piecewise-constant multiplier `m(t)` (`σ_schedule`).
  Notebooks 10–11 motivate `η`: under a fixed share the EU panel gives a
  negative `μ̂`. The gross reinvestment share did not change after 2008,
  so the data do not call for a schedule; it is there for scenarios. In the
  cross-dual system profits at market prices can be ≤ 0, so `(r̄/rᵢ)^η` is
  undefined there; it needs `reinvestment_form = :linear`,
  `σ_c,ᵢ·m(t)·[(1−η)Πᵢ + η·r̄·Kᵢ]` with `r̄ = ΣΠ/ΣK`, which is defined
  for losses and estimated in notebook 13. Two further options cover what
  happens when profits collapse: `investment_floor = θ` (gross investment
  ≥ `θ·δ·C`, supported by the data) and `exit_rate`/`exit_hurdle`
  (scrapping below a hurdle; not supported by the investment data, kept
  for scenarios). A schedule makes the system non-autonomous, so the
  balanced-growth and bifurcation tools reject it.
- **`μ_v` (mobility of variable capital) is off by default (now
  estimated).** Accumulation cycles appear from `μ_v ≈ 0.5–1.3`
  (supercritical Hopf in all 30 random economies tested, with `β = 0.1`).
  Notebook 14 estimates `μ_v` on the EU panel (`compute_labor_panel`,
  `estimate_variable_mobility`): 0.037 (se 0.016) on wage-bill growth and
  0.024 (se 0.009) on employment growth, 0.016–0.074 across variants. In
  Portugal's calibrated cross-dual economy (notebook 13's estimates)
  stability is lost at `μ_v` ≈ 1.22, 33 times the estimate, so the cycles
  lie outside the empirical range; at the estimate, balanced growth is
  stable with damped oscillations of 18–19 years. The data's `σ_v`, the
  share of surplus spent on hiring, is 0.005–0.012, far below the
  0.1–0.15 the calibrations assume.
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

**In short:** AMECO's forecast years are dropped on the SDMX path, with
a warning (`include_forecasts = true` keeps them). Legacy TXT/CSV files
carry no release date, so nothing is dropped there.

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
revised in later releases. If no release year can be read from
`LAST UPDATE` (the column is missing or in an unknown format), no year is
dropped and `fetch_ameco_data` warns that forecasts cannot be identified,
rather than keeping them silently (`_apply_forecast_rule`).
