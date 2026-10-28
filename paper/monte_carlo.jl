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
densities = [0.2, 0.4, 0.6]
trials_per_combination = 30

results = NamedTuple[]
for N in Ns, density in densities, trial in 1:trials_per_combination
    seed = 1000 * N + round(Int, 1000 * density) + trial
    Random.seed!(seed)
    A = create_technical_matrix(N, density = density, seed = seed)
    _, rescaled = _ensure_output_admissibility(A)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    # O deliberately scarce relative to planned demand, to force genuine
    # rationing in most trials rather than trivial κ=1 everywhere.
    scale_O = 0.1 + rand() * 0.8
    O = scale_O .* (0.5 .+ rand(N))
    diag = _solve_rationing(A, σ_c, S, O; return_diagnostics = true)
    push!(results, (N = N, density = density, seed = seed,
                       converged = diag.converged, iterations = diag.iterations,
                       rationed_fraction = diag.rationed_fraction, ρA = maximum(abs.(eigvals(A))),
                       rescaled = rescaled))
end

n_total = length(results)
n_converged = count(r -> r.converged, results)
n_rationed = count(r -> r.rationed_fraction > 0, results)
converged_iterations = [r.iterations for r in results if r.converged]

println("  ✓ $n_total trials ($(length(Ns))×$(length(densities))×$trials_per_combination): ",
        "$n_converged/$n_total converged ($(round(100n_converged/n_total, digits=1))%), ",
        "$n_rationed/$n_total had genuine rationing (rationed_fraction>0)")
println("  ✓ iterations to converge: mean=$(round(mean(converged_iterations), digits=1)) ",
        "median=$(round(median(converged_iterations), digits=1)) ",
        "max=$(maximum(converged_iterations)) (cap=200)")

# Admissibility of the gross-output reconstruction (Equation 2 of the paper,
# _ensure_output_admissibility): how often do the same class of random
# synthetic matrices used throughout this sweep need column-sum rescaling,
# and does rescaling itself measurably change convergence/rationing behavior?
rescaled_runs = filter(r -> r.rescaled, results)
unrescaled_runs = filter(r -> !r.rescaled, results)
n_rescaled = length(rescaled_runs)
println("  ✓ output-bruto admissibility (Equation 2): $n_rescaled/$n_total matrices " *
        "needed column-sum rescaling ($(round(100n_rescaled/n_total,digits=1))%)")

it_resc = [r.iterations for r in rescaled_runs if r.converged]
it_unresc  = [r.iterations for r in unrescaled_runs if r.converged]
frac_resc = [r.rationed_fraction for r in rescaled_runs]
frac_unresc  = [r.rationed_fraction for r in unrescaled_runs]
println("  ✓ rescaled vs. non-rescaled matrices — convergence: ",
        "$(count(r->r.converged,rescaled_runs))/$n_rescaled vs. ",
        "$(count(r->r.converged,unrescaled_runs))/$(length(unrescaled_runs))")
println("    iterations to converge: mean=$(round(mean(it_resc),digits=1)) (rescaled) vs. ",
        "mean=$(round(mean(it_unresc),digits=1)) (non-rescaled)")
println("    fraction rationed: mean=$(round(mean(frac_resc),digits=3)) (rescaled) vs. ",
        "mean=$(round(mean(frac_unresc),digits=3)) (non-rescaled)")

# Convergence rate broken down by N and density
println("  ✓ convergence rate by (N, densidade):")
for N in Ns, density in densities
    subset = filter(r -> r.N == N && r.density == density, results)
    rate = count(r -> r.converged, subset) / length(subset)
    println("      N=$N densidade=$density: $(round(100rate, digits=1))% ",
            "($(count(r->r.converged, subset))/$(length(subset)))")
end

fig6a = histogram(converged_iterations, bins = 20, xlabel = "Iterations to converge",
                  ylabel = "Count", title = "Convergence speed",
                  legend = false, color = :steelblue, size = (650, 420), margin = 5Plots.mm)
savefig(fig6a, joinpath(FIG_DIR, "fig6a_convergence_iterations.pdf"))

fractions = [r.rationed_fraction for r in results]
fig6b = histogram(fractions, bins = 20, xlabel = "Fraction of sectors rationed (κ<0.999)",
                  ylabel = "Count", title = "Rationing incidence",
                  legend = false, color = :firebrick, size = (650, 420), margin = 5Plots.mm)
savefig(fig6b, joinpath(FIG_DIR, "fig6b_rationing_incidence.pdf"))

# ----------------------------------------------------------------------------
# Sweep 2 — dynamic coupling comparison across many seeds (replaces the
# single-seed Figure 5 illustration)
# ----------------------------------------------------------------------------

println("\n[2/2] Coupling-mechanism comparison across many seeds...")

n_seeds = 50
final_dispersion = Dict(:mobility => Float64[], :realization => Float64[], :rationing => Float64[])

for seed in 1:n_seeds
    Random.seed!(seed)
    sol_mob, _, p_mob = simulate_Ndept(6, T = 200.0, seed = seed, coupled = true, μ = 0.5)
    Random.seed!(seed)
    sol_real, _, p_real = simulate_Ndept(6, T = 200.0, seed = seed, coupled = true, μ = 0.5,
                                        realization = true)
    Random.seed!(seed)
    sol_rat, _, p_rat = simulate_Ndept(6, T = 200.0, seed = seed, coupled = true, μ = 0.5,
                                      rationing = true)

    r_mob = compute_price_profit_rates(sol_mob, p_mob)
    r_real = compute_price_profit_rates(sol_real, p_real)
    r_rat = compute_price_profit_rates(sol_rat, p_rat)

    push!(final_dispersion[:mobility], std(r_mob[:, end]))
    push!(final_dispersion[:realization], std(r_real[:, end]))
    push!(final_dispersion[:rationing], std(r_rat[:, end]))
end

for (mechanism, vals) in final_dispersion
    println("  ✓ $mechanism: mean=$(round(mean(vals), digits=4)) ",
            "median=$(round(median(vals), digits=4)) ",
            "std=$(round(std(vals), digits=4)) ",
            "[$(round(minimum(vals), digits=4)), $(round(maximum(vals), digits=4))]")
end
n_rat_larger = count(final_dispersion[:rationing] .> final_dispersion[:mobility])
println("  ✓ rationing > mobility-only dispersion in $n_rat_larger/$n_seeds seeds ",
        "($(round(100n_rat_larger/n_seeds, digits=1))%)")

# Dependency-free stand-in for a boxplot (no StatsPlots — see src/distribution.jl
# for the same convention): jittered per-seed points plus mean±std/median bars.
mechanisms = [:mobility, :realization, :rationing]
labels = ["mobility only", "+ realization", "+ rationing"]
colors = [:steelblue, :seagreen, :firebrick]
fig6c = plot(xlabel = "", ylabel = "Final profit-rate dispersion (std, t=200)",
             title = "Coupling mechanisms across $n_seeds random synthetic economies",
             xticks = (1:3, labels), legend = false, size = (700, 450), margin = 5Plots.mm)
for (i, (mechanism, cor)) in enumerate(zip(mechanisms, colors))
    vals = final_dispersion[mechanism]
    xs = fill(i, length(vals)) .+ (rand(length(vals)) .- 0.5) .* 0.25
    scatter!(fig6c, xs, vals, color = cor, alpha = 0.35, markersize = 3, label = "")
    scatter!(fig6c, [i], [mean(vals)], color = cor, markersize = 9, markershape = :diamond,
             markerstrokewidth = 1.5, markerstrokecolor = :black, label = "")
    plot!(fig6c, [i - 0.15, i + 0.15], [median(vals), median(vals)], color = :black, lw = 2, label = "")
end
savefig(fig6c, joinpath(FIG_DIR, "fig6c_dispersion_distribution.pdf"))

println("\n" * "="^70)
println("Done. Figures in paper/figures/ (fig6a/b/c).")
println("="^70)
