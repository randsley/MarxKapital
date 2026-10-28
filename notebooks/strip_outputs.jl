# ============================================================================
# Strips the outputs of the executed Jupyter notebooks (notebooks/jupyter/).
# Plots saves each plot three times (PNG, SVG and an HTML copy of the PNG):
# only the PNG is kept. Precompilation noise is removed as well.
#
#     julia notebooks/strip_outputs.jl
# ============================================================================

import JSON

const NOISE = r"Precompiling|Waiting for another process|precompiled in|IJuliaExt"

for f in sort(filter(endswith(".ipynb"), readdir(joinpath(@__DIR__, "jupyter"), join = true)))
    nb = JSON.parsefile(f)
    for c in nb["cells"]
        c["cell_type"] == "code" || continue
        outputs = Any[]
        for o in c["outputs"]
            o["output_type"] == "stream" && occursin(NOISE, join(o["text"])) && continue
            d = get(o, "data", nothing)
            if d !== nothing && haskey(d, "image/png")
                for k in collect(keys(d))
                    k in ("image/png", "text/plain") || delete!(d, k)
                end
            end
            push!(outputs, o)
        end
        c["outputs"] = outputs
    end
    open(f, "w") do io
        JSON.print(io, nb, 1)
        println(io)
    end
    println(basename(f), ": ", round(filesize(f) / 1e6, digits = 2), " MB")
end
