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

# Import explícito para evitar ambiguidades com StatsBase/Distributions se
# carregados noutro ponto da sessão.
import Statistics: mean, std, median, var, cor, quantile
import LinearAlgebra: eigvals, norm, diagm

const _MK_SRC = @__DIR__

# Ordem importa: estruturas e constantes primeiro.
include(joinpath(_MK_SRC, "estruturas.jl"))
include(joinpath(_MK_SRC, "nucleo.jl"))
include(joinpath(_MK_SRC, "analise.jl"))
include(joinpath(_MK_SRC, "distributiva.jl"))
include(joinpath(_MK_SRC, "choques.jl"))
include(joinpath(_MK_SRC, "calibracao_pt.jl"))
include(joinpath(_MK_SRC, "ameco.jl"))
include(joinpath(_MK_SRC, "ameco_download.jl"))
include(joinpath(_MK_SRC, "visualizacao.jl"))
include(joinpath(_MK_SRC, "exemplos.jl"))

println("MarxKapital carregado. Escreva  ajuda_modelo()  para começar.")
