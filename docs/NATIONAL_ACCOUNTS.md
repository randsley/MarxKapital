# From national accounts to C, V and S

*[🇵🇹 Ler em português](NATIONAL_ACCOUNTS.pt.md)*

How the real-data calibration (`calibrate_portugal_model(data_source = :eurostat)`,
`src/calibration_pt.jl`; the data layer in `src/eurostat_sdmx.jl`) turns
Eurostat's national accounts (ESA 2010) into the model's departments. Every
series is by NACE Rev. 2 section (A–S), in million euros at current prices
unless stated. Notebooks 9–12 use the same series, from the static extract
`data/eurostat_eu_sectors.csv`.

## 1. Accounting items → model quantities

| Model | Meaning | ESA 2010 item | Eurostat dataflow and key | Notes |
|---|---|---|---|---|
| `V` | variable capital (wages) | D1, compensation of employees | `NAMA_10_A64`, `A.CP_MEUR..D1.PT` | Optionally plus the self-employed's labor income (§3) |
| `S` | surplus value | B1G − D1 − P51C | GVA: `NAMA_10_A64`, `…B1G…`; CFC: `…P51C…` | Net operating surplus and net mixed income, plus other net taxes on production (D29 − D39), which are in GVA at basic prices |
| `e = S/V` | rate of exploitation | | | Floored at `e_floor` (§4); `e_raw` keeps the ratio before the floor |
| `C` | constant capital (stock) | N11N, net fixed assets | `NAMA_10_NFA_ST`, `A.CRC_MEUR..N11N.PT` (current replacement cost) | Or own perpetual-inventory series (`perpetual_inventory = true`, `docs/LIMITATIONS.md` item 7). Inventories are not included |
| `k = C/V` | organic composition | | | |
| `δ` | depreciation rate | P51C / N11N | | |
| `σ_c` | share of surplus reinvested in `C` | P51G / S | GFCF: `NAMA_10_A64_P5`, `A.CP_MEUR..N11G.P51G.PT` | Clamped to [0.1, 0.7]; `σ_v` = 0.15 is assumed |
| `l` | direct labor per unit of output | EMP_DC / B1G | `NAMA_10_A64_E`, `A.THS_PER..EMP_DC.PT` | Normalized to max 1 |
| `A` | technical coefficients | intermediate use of domestic output | `NAIO_10_CP1700`, `stk_flow = DOM` (product × industry) | Benchmark years only (PT: 2010, 2013, 2015, 2017, 2020); spectral radius kept < 1 |
| final demand | | P3_S13, P3_S14 + P3_S15, P5, P6 | same IOT | `params.final_demand` |
| import coefficients | | imported intermediate inputs / P1 | same IOT, `IMP` row | `params.import_coefficients` |
| real flows (notebook 12) | | B1G and P51G in chain-linked volumes | `NAMA_10_A64`, `NAMA_10_A64_P5`, unit `CLV15_MEUR` | Ratios within one sector only, since chain-linked volumes are not additive |

## 2. NACE sections → the model's treatment

The model treats every department it keeps as a capitalist producer of surplus value. It does not separate productive from unproductive labor *within* the sectors it keeps. That distinction matters for the level of the rate of profit (below).

| Section | | `sectors = :market` | Raw `e`, PT 2022: excluded | imputed (persons) | imputed (hours) |
|---|---|---|---|---|---|
| A | Agriculture, forestry, fishing | kept | 1.39 | −0.20 | 0.07 |
| B | Mining and quarrying | kept | 0.65 | 0.47 | 0.49 |
| C | Manufacturing | kept | 0.53 | 0.45 | 0.45 |
| D | Electricity, gas, steam | kept | −0.53 | −0.53 | −0.53 |
| E | Water, sewerage, waste | kept | 0.34 | 0.33 | 0.33 |
| F | Construction | kept | 0.33 | 0.14 | 0.12 |
| G | Wholesale and retail trade | kept | 0.53 | 0.33 | 0.34 |
| H | Transportation and storage | kept | 0.23 | 0.14 | 0.13 |
| I | Accommodation and food | kept | 0.86 | 0.54 | 0.51 |
| J | Information and communication | kept | 0.22 | 0.14 | 0.14 |
| K | Finance and insurance | kept | 1.51 | 1.37 | 1.39 |
| **L** | **Real estate** | **left out** | 8.52 | 5.04 | |
| M | Professional, scientific, technical | kept | 0.34 | 0.05 | 0.05 |
| N | Administrative and support | kept | 0.33 | −0.04 | 0.04 |
| **O** | **Public administration** | **left out** | −0.03 | −0.03 | |
| **P** | **Education** | **left out** | −0.01 | −0.07 | |
| **Q** | **Health and social work** | **left out** | 0.09 | 0.02 | |
| R | Arts, entertainment, recreation | kept | 0.12 | −0.18 | −0.15 |
| S | Other services | kept | 0.62 | −0.12 | −0.04 |

**Why L, O, P and Q are left out** (`NON_MARKET_SECTIONS`, the same 15 market sectors as notebooks 9–12):

- **O, P and Q are mostly non-market.** The accounts value non-market output at its cost, so their operating surplus is, by convention, only the depreciation of public capital. Their `e` is ≈ 0 by construction, not by measurement. Official accounts treat government activity as production "at a zero profit" (Shaikh 2016, ch. 4, p. 129, n. 11).
- **L is dominated by imputed rents.** The rent that owner-occupiers are deemed to pay themselves is counted as output, and dwellings as capital. Shaikh (2016, ch. 7) removes these "fictitious" profits and capital for the same reason (Shaikh and Tonak 1994, pp. 253–254). In Portugal L's capital stock is about 15 times its GVA.

What happens to the links with the dropped sections:
- What the market sectors buy from L, O, P and Q (rents, for example) comes from outside the modelled economy, like imports. It is added to the import coefficients (`outside_input_coefficients`), so that gross output is still rebuilt correctly from value added (`_gross_output`, `src/core.jl`).
- What L, O, P and Q buy from the market sectors becomes exogenous demand and is added to government final demand (`outside_purchases_from_iot`). In Portugal, 2020 IOT, this is €10.4 bn.

**Productive and unproductive labor.** The classical and Marxian tradition counts wholesale and retail trade, financial services, legal services, advertising, the military and the civil service as non-production activities. Their costs are paid out of the surplus value produced elsewhere, not added to it (Shaikh 2016, ch. 4, pp. 129–130; Shaikh and Tonak 1994; Mohun 2005). On that accounting the rate of profit measured from conventional operating surplus is a stable fraction of the classical one (Shaikh 2016, p. 130). `sectors = :market` goes only part of the way: it drops the non-market sections, but keeps G and K as departments that produce surplus value. That is a limitation of the model, not a claim about them.

## 3. The self-employed

Gross operating surplus includes the mixed income of the self-employed, which is partly a wage. `self_employed` controls how it is treated:

- `:excluded` (default): `V` = D1 as published. The self-employed's whole income counts as surplus value, which overstates `e` where self-employment is common (A: 1.39).
- `:imputed`: each self-employed person earns the average employee's compensation of their section, `V × EMP_DC / SAL_DC` in persons. This is the method of Shaikh and Tonak (1994, pp. 110–113), used in AMECO's adjusted wage share (Shaikh 2016, ch. 7, n. 31).
- `:imputed_hours`: the same per hour worked (`THS_HW`, `fetch_eurostat_sector_hours`). A farmer who works part of the year counts for less. It lifts agriculture from −0.20 to 0.07, but barely moves M, N, R and S, where imputing a wage at the average employee's rate leaves almost no surplus.

## 4. The floor on `e`

`Department` requires `e > 0`, so the calibration sets `e = max(e_floor, e_raw)` (`e_floor = 0.1` by default; `docs/LIMITATIONS.md` item 8). The floor stands for three different things, which the options separate:

| Portugal, 2022 | Sectors floored | Aggregate `r`, with the floor (raw) |
|---|---|---|
| 19 sections, excluded (default) | 4 of 19: D, O, P, Q | 6.12% (5.80%) |
| 19 sections, imputed | 9 of 19: A, D, M, N, O, P, Q, R, S | 4.65% (3.70%) |
| `sectors = :market`, excluded | 1 of 15: D | 11.27% (11.18%) |
| `:market`, `e_years = 5`, excluded | 1 of 15: R | 11.09% (11.03%) |
| `:market`, `e_years = 5`, imputed | 5 of 15: A, M, N, R, S | 7.79% (6.59%) |
| `:market`, `e_years = 5`, `:imputed_hours` | 5 of 15: A, M, N, R, S | 7.66% (6.98%) |

- **Non-market sections** account for O, P and Q. `sectors = :market` removes them, and with them L, whose huge capital stock is what keeps the aggregate rate of profit near 6%.
- **One-off years:** electricity's −0.53 in 2022 is the energy crisis (5.4–6.8 in 2015–2019). `e_years` computes `e` from sums over several years; five years (2018–2022) give D 3.70. A three-year window (2020–2022) is dominated by the pandemic, which pushes transport (H) and the arts (R) below the floor, so the window should be long enough to cover a whole cycle.
- **The imputation:** with the self-employed counted at a wage, A, M, N, R and S are left with `e` at or below zero. Their thin net margin is in the accounts, not in the method. The floor then sets their `e` at 0.1, which is a modeling choice; `e_raw` keeps the measured value.

## References

- Mohun, S. (2005). On measuring the wealth of nations: the US economy, 1964–2001. *Cambridge Journal of Economics*, 29(5), 799–815.
- Shaikh, A. (2016). *Capitalism: Competition, Conflict, Crises*. Oxford University Press.
- Shaikh, A. and Tonak, E. A. (1994). *Measuring the Wealth of Nations: The Political Economy of National Accounts*. Cambridge University Press.
