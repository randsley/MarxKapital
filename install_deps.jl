# ============================================================================
# MarxKapital dependency installation
# ----------------------------------------------------------------------------
# Run once, preferably inside the project:
#     julia --project=. install_deps.jl
# or simply:
#     julia install_deps.jl
# With --notebooks, also installs what the notebooks need; with
# --notebook-test, only what test/notebooks.jl needs to run them (CI).
# ============================================================================

using Pkg

# SpatialEconometrics.jl is not registered: notebook 8 uses it, pinned to a
# commit so that the notebook's results do not move with the package. It is
# a notebook-only dependency; src/ never loads it.
const SPATIALECONOMETRICS = (url = "https://github.com/randsley/SpatialEconometrics.jl",
                             rev = "350df9fdc2f1f71e99eba88283196b050897a56e")

deps = [
    "DifferentialEquations",  # ODE solvers (Tsit5, ODEProblem)
    "Plots",                  # plotting
    "StatsPlots",             # boxplots/violins (optional, used in some plots)
    "DataFrames",             # tables
    "CSV",                    # reading AMECO CSV
    "HTTP",                   # automatic AMECO download
    "ForwardDiff",            # automatic differentiation (Jacobians, Hessians)
    "BifurcationKit",         # numerical continuation and bifurcation analysis
]

# Standard library: no add needed, listed for reference:
#   LinearAlgebra, Statistics, Dates, Random

# Optional, for the notebooks (notebooks/README.md):  julia install_deps.jl --notebooks
notebooks = "--notebooks" in ARGS
notebook_test = "--notebook-test" in ARGS
if notebooks || notebook_test
    # --notebook-test installs only these, on top of nothing else (CI runs the
    # model's dependencies in an earlier step)
    notebook_test && !notebooks && empty!(deps)
    append!(deps, [
        "PlutoUI",                # controls (sliders) of the Pluto notebooks
        "JSON",                   # reading the .ipynb files in test/notebooks.jl
    ])
    notebooks && append!(deps, [
        "IJulia",                 # Julia kernel for Jupyter
        "Pluto",                  # reactive notebooks
    ])
end

println("Installing MarxKapital dependencies...")
for d in deps
    println("  → $d")
    Pkg.add(d)
end
if notebooks || notebook_test
    println("  → SpatialEconometrics (notebook 8; $(SPATIALECONOMETRICS.rev[1:7]))")
    Pkg.add(url = SPATIALECONOMETRICS.url, rev = SPATIALECONOMETRICS.rev)
end
println("\nDone. Load the model with:  include(\"src/MarxKapital.jl\")")
