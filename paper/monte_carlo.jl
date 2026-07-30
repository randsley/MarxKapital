# ============================================================================
# Monte Carlo robustness sweep, replacing the single-seed illustrations of
# an earlier draft (Figure 5's coupling comparison, and the rationing
# fixed point's convergence claim) with distributions across many random
# economies, per external review.
#
# Run with:  julia --project=. paper/monte_carlo.jl
# No network access required (all synthetic).
# ============================================================================

ENV["GKSwstype"] = "100"
include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

println("\n" * "="^70)
println("Monte Carlo sweep...")
println("="^70)

# ----------------------------------------------------------------------------
# Sweep 1 — rationing fixed-point convergence, many matrices/densities/N
# ----------------------------------------------------------------------------

println("\n[1/2] Rationing fixed-point convergence sweep...")

Ns = [6, 12, 19]
densidades = [0.2, 0.4, 0.6]
trials_por_combinação = 30

resultados = NamedTuple[]
for N in Ns, densidade in densidades, trial in 1:trials_por_combinação
    seed = 1000 * N + round(Int, 1000 * densidade) + trial
    Random.seed!(seed)
    A = criar_matriz_tecnica(N, densidade = densidade, seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    # O deliberately scarce relative to planned demand, to force genuine
    # rationing in most trials rather than trivial κ=1 everywhere.
    escala_O = 0.1 + rand() * 0.8
    O = escala_O .* (0.5 .+ rand(N))
    diag = _resolver_racionamento(A, σ_c, S, O; devolver_diagnóstico = true)
    push!(resultados, (N = N, densidade = densidade, seed = seed,
                       convergiu = diag.convergiu, iterações = diag.iterações,
                       fração_racionada = diag.fração_racionada, ρA = maximum(abs.(eigvals(A)))))
end

n_total = length(resultados)
n_convergiu = count(r -> r.convergiu, resultados)
n_racionado = count(r -> r.fração_racionada > 0, resultados)
iterações_convergidas = [r.iterações for r in resultados if r.convergiu]

println("  ✓ $n_total trials ($(length(Ns))×$(length(densidades))×$trials_por_combinação): ",
        "$n_convergiu/$n_total converged ($(round(100n_convergiu/n_total, digits=1))%), ",
        "$n_racionado/$n_total had genuine rationing (fração_racionada>0)")
println("  ✓ iterations to converge: mean=$(round(mean(iterações_convergidas), digits=1)) ",
        "median=$(round(median(iterações_convergidas), digits=1)) ",
        "max=$(maximum(iterações_convergidas)) (cap=200)")

# Convergence rate broken down by N and density
println("  ✓ convergence rate by (N, densidade):")
for N in Ns, densidade in densidades
    subset = filter(r -> r.N == N && r.densidade == densidade, resultados)
    taxa = count(r -> r.convergiu, subset) / length(subset)
    println("      N=$N densidade=$densidade: $(round(100taxa, digits=1))% ",
            "($(count(r->r.convergiu, subset))/$(length(subset)))")
end

fig6a = histogram(iterações_convergidas, bins = 20, xlabel = "Iterations to converge",
                  ylabel = "Count", title = "Convergence speed",
                  legend = false, color = :steelblue, size = (650, 420), margin = 5Plots.mm)
savefig(fig6a, joinpath(FIG_DIR, "fig6a_convergence_iterations.pdf"))

frações = [r.fração_racionada for r in resultados]
fig6b = histogram(frações, bins = 20, xlabel = "Fraction of sectors rationed (κ<0.999)",
                  ylabel = "Count", title = "Rationing incidence",
                  legend = false, color = :firebrick, size = (650, 420), margin = 5Plots.mm)
savefig(fig6b, joinpath(FIG_DIR, "fig6b_rationing_incidence.pdf"))

# ----------------------------------------------------------------------------
# Sweep 2 — dynamic coupling comparison across many seeds (replaces the
# single-seed Figure 5 illustration)
# ----------------------------------------------------------------------------

println("\n[2/2] Coupling-mechanism comparison across many seeds...")

n_seeds = 50
dispersão_final = Dict(:mobilidade => Float64[], :realização => Float64[], :racionamento => Float64[])

for seed in 1:n_seeds
    Random.seed!(seed)
    sol_mob, _, p_mob = simular_Ndept(6, T = 200.0, seed = seed, acoplado = true, μ = 0.5)
    Random.seed!(seed)
    sol_real, _, p_real = simular_Ndept(6, T = 200.0, seed = seed, acoplado = true, μ = 0.5,
                                        realização = true)
    Random.seed!(seed)
    sol_rac, _, p_rac = simular_Ndept(6, T = 200.0, seed = seed, acoplado = true, μ = 0.5,
                                      racionamento = true)

    r_mob = calcular_taxas_lucro_precos(sol_mob, p_mob)
    r_real = calcular_taxas_lucro_precos(sol_real, p_real)
    r_rac = calcular_taxas_lucro_precos(sol_rac, p_rac)

    push!(dispersão_final[:mobilidade], std(r_mob[:, end]))
    push!(dispersão_final[:realização], std(r_real[:, end]))
    push!(dispersão_final[:racionamento], std(r_rac[:, end]))
end

for (mecanismo, vals) in dispersão_final
    println("  ✓ $mecanismo: mean=$(round(mean(vals), digits=4)) ",
            "median=$(round(median(vals), digits=4)) ",
            "std=$(round(std(vals), digits=4)) ",
            "[$(round(minimum(vals), digits=4)), $(round(maximum(vals), digits=4))]")
end
n_rac_maior = count(dispersão_final[:racionamento] .> dispersão_final[:mobilidade])
println("  ✓ rationing > mobility-only dispersion in $n_rac_maior/$n_seeds seeds ",
        "($(round(100n_rac_maior/n_seeds, digits=1))%)")

# Dependency-free stand-in for a boxplot (no StatsPlots — see src/distributiva.jl
# for the same convention): jittered per-seed points plus mean±std/median bars.
mecanismos = [:mobilidade, :realização, :racionamento]
rótulos = ["mobility only", "+ realization", "+ rationing"]
cores = [:steelblue, :seagreen, :firebrick]
fig6c = plot(xlabel = "", ylabel = "Final profit-rate dispersion (std, t=200)",
             title = "Coupling mechanisms across $n_seeds random synthetic economies",
             xticks = (1:3, rótulos), legend = false, size = (700, 450), margin = 5Plots.mm)
for (i, (mecanismo, cor)) in enumerate(zip(mecanismos, cores))
    vals = dispersão_final[mecanismo]
    xs = fill(i, length(vals)) .+ (rand(length(vals)) .- 0.5) .* 0.25
    scatter!(fig6c, xs, vals, color = cor, alpha = 0.35, markersize = 3, label = "")
    scatter!(fig6c, [i], [mean(vals)], color = cor, markersize = 9, markershape = :diamond,
             markerstrokewidth = 1.5, markerstrokecolor = :black, label = "")
    plot!(fig6c, [i - 0.15, i + 0.15], [median(vals), median(vals)], color = :black, lw = 2, label = "")
end
savefig(fig6c, joinpath(FIG_DIR, "fig6c_dispersion_distribution.pdf"))

println("\n" * "="^70)
println("Concluído. Figuras em paper/figures/ (fig6a/b/c).")
println("="^70)
