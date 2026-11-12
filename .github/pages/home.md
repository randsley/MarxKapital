# MarxKapital
{: .fs-9 }

<p class="hero">A Julia model of Marxian economics: accumulation, exploitation,
organic composition, the rate of profit, the transformation of values into
prices of production and the wage–profit frontier. It is calibrated to
Portuguese national accounts and European (AMECO, Eurostat) data.</p>

[Get started](overview.html#installation){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Read the paper (PDF)](paper/main.pdf){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Notebooks](notebooks/index.html){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/randsley/MarxKapital){: .btn .fs-5 .mb-4 .mb-md-0 }

Version **@@VERSION@@** · [![DOI](https://zenodo.org/badge/DOI/@@DOI@@.svg)](https://doi.org/@@DOI@@)
· [![Tests](https://github.com/randsley/MarxKapital/actions/workflows/test.yml/badge.svg)](https://github.com/randsley/MarxKapital/actions/workflows/test.yml)

---

## Calibrated to real data

Rate of exploitation, organic composition and rate of profit for Portugal,
from national accounts, with variable capital at current and at deflated
prices. How the national accounts map onto constant capital, variable
capital and surplus value, and which sectors are left out, is set out in
[From national accounts to C, V and S](national-accounts.html).

<div class="fig-banner"><img src="assets/figures/fig1_time_series.png" alt="Rate of exploitation, organic composition and profit rate, Portugal, over time"></div>

## Empirical findings: capital mobility and reinvestment

The model's capital-mobility coefficient $$\mu$$ and its investment
function, estimated on Eurostat's accounts for the 15 market sectors of 26
EU countries (notebooks 9–13).

<div class="fig-grid">
<figure><img src="assets/figures/nb10_mobility.png" alt="Capital received beyond own surplus against the profit-rate gap, 26 EU countries">
<figcaption><strong>A fixed reinvestment share fails.</strong> If every
sector reinvests a fixed share of its own surplus, capital seems to flee
profit: \(\hat\mu = -0.14\), negative in 21 of 26 countries. The fault
is the fixed share (<a href="notebooks/jupyter/10_eu_sectoral_mobility.html">notebook 10</a>).</figcaption></figure>
<figure><img src="assets/figures/nb11_mobility_eta.png" alt="Estimated mu against the reinvestment elasticity eta">
<figcaption><strong>Mobility turns positive.</strong> Once the share
reinvested may fall with relative profitability (elasticity \(\eta\)),
\(\hat\mu\) is positive for every \(\eta\), 0.05 to 0.13
(<a href="notebooks/jupyter/11_reinvestment_and_mobility.html">notebook 11</a>).</figcaption></figure>
<figure><img src="assets/figures/nb13_eta_profile.png" alt="Fit of the investment function against eta">
<figcaption><strong>Own surplus comes first.</strong> On every row, loss
years included, \(\hat\eta = 0.15\) (se 0.18) and
\(\hat\mu = 0.06\). Investment does not stop when profits do: it has a
floor at about 0.7 of depreciation
(<a href="notebooks/jupyter/13_investment_floor_and_market_prices.html">notebook 13</a>).</figcaption></figure>
<figure><img src="assets/figures/nb13_balanced_growth.png" alt="Largest real part of the eigenvalues at balanced growth against eta">
<figcaption><strong>A stable economy at the estimates.</strong> With market
prices, Portugal's market sectors have a stable interior balanced growth
path for every \(\eta\) up to 0.9; only \(\eta = 1\) has none
(<a href="notebooks/jupyter/13_investment_floor_and_market_prices.html">notebook 13</a>).</figcaption></figure>
</div>

Notebook 12 tests Shaikh's claim that competition equalizes incremental,
not average, rates of profit: incremental-rate gaps are mostly transitory
but not equalized, and capital follows the average-rate gap. The
[known limitations](limitations.html) record what these results do and do
not settle.

## What the model does

<div class="fig-grid">
<figure><img src="assets/figures/fig2_matrix_A.png" alt="Heatmap of Portugal's real technical matrix A">
<figcaption><strong>Input–output structure.</strong> The real technical matrix
\(A\) of the Portuguese economy (Eurostat input–output tables, 19 sectors)
couples the sectors.</figcaption></figure>
<figure><img src="assets/figures/fig3_transformation.png" alt="Deviation of production prices from labor values by sector">
<figcaption><strong>Values and prices.</strong> Labor values
\(\lambda = (I-A)^{-1} l\) against Sraffian prices of production, sector by
sector, at three rates of profit.</figcaption></figure>
<figure><img src="assets/figures/fig10b_accumulation_cycles.png" alt="Bifurcation diagram of accumulation cycles against the mobility of variable capital">
<figcaption><strong>Accumulation cycles.</strong> With market prices,
balanced growth gives way to limit cycles at a Hopf bifurcation, then to
quasi-periodic and chaotic motion.</figcaption></figure>
<figure><img src="assets/figures/fig11b_hopf_boundary.png" alt="Hopf boundary against the aggregate wage share">
<figcaption><strong>Distribution and stability.</strong> A higher wage
share makes balanced growth more robust to capital mobility.</figcaption></figure>
</div>

- **Reproduction schemes:** the classical two-department model and $$N$$
  departments, optionally coupled through $$A$$ by capital mobility,
  realization pressure or per-sector quantity rationing.
- **Values, prices, distribution:** labor values, prices of production,
  the transformation problem, the wage–profit frontier and wage shocks.
- **Calibration:** Portuguese INE/Eurostat data (19, 10 or 3 sectors) and
  any country in AMECO, through the official SDMX APIs. Defaults are
  synthetic; real data are opt-in.
- **Estimation:** capital mobility and the investment function from
  sectoral panels, with fixed effects and clustered or Driscoll–Kraay
  errors.
- **Dynamics:** exact Jacobians by automatic differentiation, TSSI
  valuation, balanced growth, bifurcation continuation, Lyapunov exponents.

## Quick start

```bash
git clone https://github.com/randsley/MarxKapital.git marxkapital
cd marxkapital
julia install_deps.jl
```

```julia
include("src/MarxKapital.jl")
model_help()                                   # overview of the model
example_Ndept(10)                              # N-department example
simulate_Ndept(10, coupled = true, μ = 0.3)    # sectors coupled through A
example_transformation()                       # values → prices of production
params = calibrate_portugal_model(year = 2022, data_source = :eurostat)
```

The [overview](overview.html) covers the full API; read the
[known limitations](limitations.html) before any empirical use.

## Notebooks

Worked examples, rendered with their outputs. They run offline:
notebooks 1–6 on the synthetic defaults, 7–13 on static extracts of AMECO
and Eurostat data.

@@GALLERY@@

## Cite

<div class="cite" markdown="1">
@@AUTHORS@@ (@@YEAR@@). *@@TITLE@@* (version @@VERSION@@).
Zenodo. [https://doi.org/@@DOI@@](https://doi.org/@@DOI@@)

The accompanying paper has its own DOI:
[@@PAPER_DOI@@](https://doi.org/@@PAPER_DOI@@).
[`CITATION.cff`](https://github.com/randsley/MarxKapital/blob/main/CITATION.cff)
</div>
