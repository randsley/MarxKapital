# ============================================================================
# MarxKapital dependency installation
# ----------------------------------------------------------------------------
# Run once, preferably inside the project:
#     julia --project=. install_deps.jl
# or simply:
#     julia install_deps.jl
# With --notebooks, also installs what the notebooks need.
# ============================================================================

using Pkg

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
if "--notebooks" in ARGS
    append!(deps, [
        "IJulia",                 # Julia kernel for Jupyter
        "Pluto",                  # reactive notebooks
        "PlutoUI",                # controls (sliders) of the Pluto notebooks
        "JSON",                   # reading the .ipynb files in test/notebooks.jl
    ])
end

println("Installing MarxKapital dependencies...")
for d in deps
    println("  → $d")
    Pkg.add(d)
end
println("\nDone. Load the model with:  include(\"src/MarxKapital.jl\")")
