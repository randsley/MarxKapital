# ============================================================================
# Instalação de dependências do MarxKapital
# ----------------------------------------------------------------------------
# Executar uma vez, de preferência dentro do projeto:
#     julia --project=. install_deps.jl
# ou simplesmente:
#     julia install_deps.jl
# Com --notebooks, instala também o necessário para os notebooks.
# ============================================================================

using Pkg

deps = [
    "DifferentialEquations",  # solver de EDOs (Tsit5, ODEProblem)
    "Plots",                  # visualização
    "StatsPlots",             # boxplots/violinos (opcional, usado nalguns gráficos)
    "DataFrames",             # tabelas
    "CSV",                    # leitura de CSV AMECO
    "HTTP",                   # download automático AMECO
    "ForwardDiff",            # diferenciação automática (jacobianas, hessianas)
    "BifurcationKit",         # continuação numérica e análise de bifurcações
]

# Standard library — não precisam de add, mas listadas para referência:
#   LinearAlgebra, Statistics, Dates, Random

# Opcional, para os notebooks (notebooks/README.md):  julia install_deps.jl --notebooks
if "--notebooks" in ARGS
    append!(deps, [
        "IJulia",                 # kernel Julia para o Jupyter
        "Pluto",                  # notebooks reativos
        "PlutoUI",                # controlos (sliders) dos notebooks Pluto
        "JSON",                   # leitura dos .ipynb em test/notebooks.jl
    ])
end

println("A instalar dependências do MarxKapital...")
for d in deps
    println("  → $d")
    Pkg.add(d)
end
println("\nConcluído. Carregue o modelo com:  include(\"src/MarxKapital.jl\")")
