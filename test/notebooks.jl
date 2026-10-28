# ============================================================================
# Teste de fumo dos notebooks (notebooks/): corre as células de código de cada
# notebook Jupyter e cada notebook Pluto, offline, num módulo novo cada um.
# Precisa de PlutoUI e JSON (`julia install_deps.jl --notebooks`).
#
#     julia test/notebooks.jl          # sem as células marcadas "slow" (CI)
#     julia test/notebooks.jl --all    # todas as células
# ============================================================================

using Test, JSON
import REPL

const RAIZ = dirname(@__DIR__)
const TODAS = "--all" in ARGS
ENV["GKSwstype"] = "100"

"""Módulo isolado com `include`/`eval` próprios, como o Main de uma sessão."""
function módulo_novo()
    m = Module(gensym("notebook"))
    Core.eval(m, :(include(p) = Base.include($m, p)))
    Core.eval(m, :(eval(x) = Core.eval($m, x)))
    return m
end

"""Exercita a renderização de um resultado que seria mostrado (p. ex. um gráfico)."""
function renderizar(x)
    showable(MIME("image/png"), x) && show(IOBuffer(), MIME("image/png"), x)
    return nothing
end

"""Corre as células de código de um `.ipynb` por ordem, com o âmbito suave do IJulia."""
function correr_ipynb(caminho)
    nb = JSON.parsefile(caminho)
    m = módulo_novo()
    cd(dirname(caminho)) do
        for (k, c) in enumerate(nb["cells"])
            c["cell_type"] == "code" || continue
            etiquetas = get(get(c, "metadata", Dict()), "tags", String[])
            ("slow" in etiquetas && !TODAS) && continue
            # como no IJulia, os `include` relativos partem da pasta do notebook
            r = task_local_storage(:SOURCE_PATH, caminho) do
                Base.include_string(REPL.softscope, m, join(c["source"]), "$caminho[$k]")
            end
            renderizar(r)
        end
    end
end

"""Corre um notebook Pluto como script: as células estão gravadas por ordem
topológica, e o `@bind` de recurso do ficheiro dá a cada controlo o seu valor
inicial."""
correr_pluto(caminho) = cd(() -> Base.include(módulo_novo(), caminho), dirname(caminho))

@testset "Notebooks" begin
    for (pasta, correr) in (("jupyter", correr_ipynb), ("pluto", correr_pluto))
        dir = joinpath(RAIZ, "notebooks", pasta)
        for f in sort(filter(f -> endswith(f, pasta == "jupyter" ? ".ipynb" : ".jl"), readdir(dir)))
            @testset "$pasta/$f" begin
                t = @elapsed correr(joinpath(dir, f))
                println("  ✓ $pasta/$f ($(round(t, digits = 1)) s)")
                @test true
            end
        end
    end
end
