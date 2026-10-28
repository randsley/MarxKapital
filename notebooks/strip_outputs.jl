# ============================================================================
# Limpeza das saídas dos notebooks Jupyter executados (notebooks/jupyter/).
# O Plots grava cada gráfico três vezes (PNG, SVG e uma cópia HTML do PNG):
# fica só o PNG. Também se retira o ruído de pré-compilação.
#
#     julia notebooks/limpar_saidas.jl
# ============================================================================

import JSON

const RUÍDO = r"Precompiling|Waiting for another process|precompiled in|IJuliaExt"

for f in sort(filter(endswith(".ipynb"), readdir(joinpath(@__DIR__, "jupyter"), join = true)))
    nb = JSON.parsefile(f)
    for c in nb["cells"]
        c["cell_type"] == "code" || continue
        saídas = Any[]
        for o in c["outputs"]
            o["output_type"] == "stream" && occursin(RUÍDO, join(o["text"])) && continue
            d = get(o, "data", nothing)
            if d !== nothing && haskey(d, "image/png")
                for k in collect(keys(d))
                    k in ("image/png", "text/plain") || delete!(d, k)
                end
            end
            push!(saídas, o)
        end
        c["outputs"] = saídas
    end
    open(f, "w") do io
        JSON.print(io, nb, 1)
        println(io)
    end
    println(basename(f), ": ", round(filesize(f) / 1e6, digits = 2), " MB")
end
