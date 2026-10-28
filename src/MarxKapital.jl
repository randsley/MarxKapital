# ============================================================================
# MarxKapital — Modelo Marxiano de N Departamentos
# ----------------------------------------------------------------------------
# Carregador principal. Faz os `using` necessários e inclui os módulos pela
# ordem correta (estruturas primeiro). Uso:
#
#     include("src/MarxKapital.jl")
#     ajuda_modelo()
#
# Este projeto é carregado por `include` (estilo script), não como pacote
# registado, de modo a não depender de UUIDs fixos no Project.toml.
# Instale as dependências uma vez com:  julia install_deps.jl
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
# Importado com prefixo (BK.continuation, BK.@optic, ...) para não poluir o
# espaço de nomes com os exports genéricos do BifurcationKit.
import BifurcationKit as BK

# Import explícito para evitar ambiguidades com StatsBase/Distributions se
# carregados noutro ponto da sessão.
import Statistics: mean, std, median, var, cor, quantile
import LinearAlgebra: eigvals, norm, diagm

const _MK_SRC = @__DIR__

# Ordem importa: estruturas e constantes primeiro.
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

println("MarxKapital carregado. Escreva  ajuda_modelo()  para começar.")
