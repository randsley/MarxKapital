# ============================================================================
# Smoke test of the notebooks (notebooks/): runs the code cells of every
# Jupyter notebook and every Pluto notebook, offline, each in a fresh module.
# Needs PlutoUI and JSON (`julia install_deps.jl --notebooks`).
#
#     julia test/notebooks.jl          # without the cells tagged "slow" (CI)
#     julia test/notebooks.jl --all    # every cell
# ============================================================================

using Test, JSON
import REPL

const ROOT = dirname(@__DIR__)
const RUN_ALL = "--all" in ARGS
ENV["GKSwstype"] = "100"

"""Isolated module with its own `include`/`eval`, like the Main of a session."""
function new_module()
    m = Module(gensym("notebook"))
    Core.eval(m, :(include(p) = Base.include($m, p)))
    Core.eval(m, :(eval(x) = Core.eval($m, x)))
    return m
end

"""Exercises the rendering of a result that would be displayed (e.g. a plot)."""
function render(x)
    showable(MIME("image/png"), x) && show(IOBuffer(), MIME("image/png"), x)
    return nothing
end

"""Runs the code cells of an `.ipynb` in order, with IJulia's soft scope."""
function run_ipynb(path)
    nb = JSON.parsefile(path)
    m = new_module()
    cd(dirname(path)) do
        for (k, c) in enumerate(nb["cells"])
            c["cell_type"] == "code" || continue
            tags = get(get(c, "metadata", Dict()), "tags", String[])
            ("slow" in tags && !RUN_ALL) && continue
            # as in IJulia, relative `include`s start from the notebook's folder
            r = task_local_storage(:SOURCE_PATH, path) do
                Base.include_string(REPL.softscope, m, join(c["source"]), "$path[$k]")
            end
            render(r)
        end
    end
end

"""Runs a Pluto notebook as a script: the cells are saved in topological
order, and the file's fallback `@bind` gives each control its initial
value."""
run_pluto(path) = cd(() -> Base.include(new_module(), path), dirname(path))

@testset "Notebooks" begin
    for (folder, run_case) in (("jupyter", run_ipynb), ("pluto", run_pluto))
        dir = joinpath(ROOT, "notebooks", folder)
        for f in sort(filter(f -> endswith(f, folder == "jupyter" ? ".ipynb" : ".jl"), readdir(dir)))
            @testset "$folder/$f" begin
                t = @elapsed run_case(joinpath(dir, f))
                println("  ✓ $folder/$f ($(round(t, digits = 1)) s)")
                @test true
            end
        end
    end
end
