# ============================================================================
# MarxKapital — N-Department Marxian Model
# ----------------------------------------------------------------------------
# Main loader. Does the required `using`s and includes the source files in the
# right order (types first). Usage:
#
#     include("src/MarxKapital.jl")
#     model_help()
#
# The project is loaded with `include` (script style), not as a registered
# package, so that it does not depend on fixed UUIDs in Project.toml.
# Install the dependencies once with:  julia install_deps.jl
# ============================================================================

using LinearAlgebra
using DifferentialEquations
using Plots
using Statistics
using DataFrames
using Dates
using Random
using HTTP
using CSV
using ForwardDiff
# Imported with a prefix (BK.continuation, BK.@optic, ...) so as not to fill
# the namespace with BifurcationKit's generic exports.
import BifurcationKit as BK

# Explicit imports to avoid ambiguities with StatsBase/Distributions if they
# are loaded elsewhere in the session.
import Statistics: mean, std, median, var, cor, quantile
import LinearAlgebra: eigvals, norm, diagm

const _MK_SRC = @__DIR__

# Order matters: types and constants first.
include(joinpath(_MK_SRC, "types.jl"))
include(joinpath(_MK_SRC, "core.jl"))
include(joinpath(_MK_SRC, "analysis.jl"))
include(joinpath(_MK_SRC, "distribution.jl"))
include(joinpath(_MK_SRC, "shocks.jl"))
include(joinpath(_MK_SRC, "differentiation.jl"))
include(joinpath(_MK_SRC, "tssi.jl"))
include(joinpath(_MK_SRC, "cross_dual.jl"))
include(joinpath(_MK_SRC, "growth.jl"))
include(joinpath(_MK_SRC, "bifurcation.jl"))
include(joinpath(_MK_SRC, "eurostat_sdmx.jl"))
include(joinpath(_MK_SRC, "calibration_pt.jl"))
include(joinpath(_MK_SRC, "ameco_sdmx.jl"))
include(joinpath(_MK_SRC, "ameco.jl"))
include(joinpath(_MK_SRC, "ameco_download.jl"))
include(joinpath(_MK_SRC, "plotting.jl"))
include(joinpath(_MK_SRC, "examples.jl"))

println("MarxKapital loaded. Type  model_help()  to get started.")
