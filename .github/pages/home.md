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
prices.

<div class="fig-banner"><img src="assets/figures/fig1_time_series.png" alt="Rate of exploitation, organic composition and profit rate, Portugal, over time"></div>

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

Worked examples, rendered with their outputs. They run offline on the
synthetic defaults.

@@GALLERY@@

## Cite

<div class="cite" markdown="1">
@@AUTHORS@@ (@@YEAR@@). *@@TITLE@@* (version @@VERSION@@).
Zenodo. [https://doi.org/@@DOI@@](https://doi.org/@@DOI@@)

The accompanying paper has its own DOI:
[@@PAPER_DOI@@](https://doi.org/@@PAPER_DOI@@).
[`CITATION.cff`](https://github.com/randsley/MarxKapital/blob/main/CITATION.cff)
</div>
