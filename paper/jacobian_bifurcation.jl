# ============================================================================
# Exact (automatic-differentiation) Jacobian of the rationing map, bifurcation
# analysis of the damped iteration and of the TSSI price map (fixed lag τ),
# and the TSSI vs. simultaneist profit rate along simulated trajectories.
#
# Run with:  julia --project=. paper/jacobian_bifurcation.jl
# No network access required (all synthetic). Writes figures to
# paper/figures/ and every number quoted in the corresponding sections of
# paper/main.tex to paper/figures/jacobian_stats.tex (as \newcommand macros),
# so none is typed by hand.
# ============================================================================

ENV["GKSwstype"] = "100"
include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

macros = Pair{String,String}[]
fmt(x; d = 2) = string(round(x, digits = d))
# Scientific notation for LaTeX: 2.4e-9 → \ensuremath{2.4\times10^{-9}}
function sci(x)
    e = floor(Int, log10(abs(x)))
    return "\\ensuremath{$(round(x / 10.0^e, digits = 1))\\times10^{$e}}"
end
record!(name, amount) = (push!(macros, name => amount); println("    \\$name = $amount"))

println("\n" * "="^70)
println("Jacobian, bifurcation and TSSI analysis...")
println("="^70)

# ----------------------------------------------------------------------------
# 1 — Exact Jacobian of the rationing map across the Monte Carlo design of
#     paper/monte_carlo.jl (same seeds, same economies)
# ----------------------------------------------------------------------------

println("\n[1/3] Rationing-map Jacobian sweep...")

Ns = [6, 12, 19]
densities = [0.2, 0.4, 0.6]
trials_per_combination = 30
tol_iter = 1e-8   # default tolerance of _solve_rationing

results = NamedTuple[]
for N in Ns, density in densities, trial in 1:trials_per_combination
    seed = 1000 * N + round(Int, 1000 * density) + trial
    Random.seed!(seed)
    A = create_technical_matrix(N, density = density, seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    scale_O = 0.1 + rand() * 0.8
    O = scale_O .* (0.5 .+ rand(N))
    dg = _solve_rationing(A, σ_c, S, O; return_diagnostics = true)
    dg05 = _solve_rationing(A, σ_c, S, O; relaxation = 0.5, return_diagnostics = true)
    jr = rationing_jacobian(A, σ_c, S, O)
    λs = jr.eigenvalues
    k = argmin(jr.ρ)
    # Triangularity: ordering sectors by ρ* ascending, J_ik ≠ 0 only if ρ_k ≤ ρ_i.
    order = sortperm(jr.ρ)
    Jo = jr.J[order, order]
    triangular = maximum(abs.([Jo[i, j] for i in 1:N, j in 1:N if j > i]); init = 0.0) < 1e-10
    diagonal = sort(real.(λs)) ≈ sort(diag(jr.J))
    push!(results, (N = N, rationed = any(jr.ρ .< 1 - 1e-9),
                       triangular = triangular, diagonal = diagonal,
                       has_zero = minimum(abs.(λs)) < 1e-8,
                       antitone = jr.antitone,
                       has_minus_one = minimum(abs.(λs .+ 1)) < 1e-8,
                       row_k = maximum(abs.(jr.J[k, :] .+ [i == k ? 1.0 : 0.0 for i in 1:N])) < 1e-8,
                       λ_min = minimum(real.(λs)), imag_max = maximum(abs.(imag.(λs))),
                       α_max = jr.α_max, α_optimal = jr.α_optimal,
                       radius_default = jr.spectral_radius,
                       radius_05 = damped_spectral_radius(λs, 0.5),
                       radius_optimal = damped_spectral_radius(λs, jr.α_optimal),
                       iterations = dg.iterations, converged = dg.converged,
                       iterations_05 = dg05.iterations, converged_05 = dg05.converged))
end

ration = filter(r -> r.rationed, results)
n_total, n_rat = length(results), length(ration)
record!("JacNTrials", string(n_total))
record!("JacNRationed", string(n_rat))
record!("JacNAntitone", string(count(r -> r.antitone, ration)))
record!("JacNMinusOne", string(count(r -> r.has_minus_one && r.row_k, ration)))
record!("JacNComplex", string(count(r -> r.imag_max > 1e-8, ration)))
record!("JacLambdaMin", fmt(minimum(r.λ_min for r in ration); d = 3))
record!("JacNAlphaMaxOne", string(count(r -> abs(r.α_max - 1) < 1e-8, ration)))
record!("JacAlphaMaxMin", fmt(minimum(r.α_max for r in ration); d = 3))
record!("JacNDefaultStable", string(count(r -> r.radius_default < 1, ration)))
record!("JacRadiusDefaultMax", fmt(maximum(r.radius_default for r in ration); d = 3))
record!("JacRadiusHalfMax", fmt(maximum(r.radius_05 for r in ration); d = 3))
record!("JacAlphaOptMean", fmt(mean(r.α_optimal for r in ration); d = 3))
record!("JacAlphaOptMin", fmt(minimum(r.α_optimal for r in ration); d = 3))
record!("JacAlphaOptMax", fmt(maximum(r.α_optimal for r in ration); d = 3))

record!("JacNTriangular", string(count(r -> r.triangular && r.diagonal, ration)))
record!("JacNZero", string(count(r -> r.has_zero, ration)))

# Linear-convergence prediction: the error contracts by the spectral radius
# per step, so reaching the step tolerance takes ≈ log(tol)/log(raio)
# iterations from an O(1) initial error. Checked at the default relaxation
# (2/3, radius 1/3) and at the previous default 0.5 (radius 1/2).
conv = filter(r -> r.converged && r.converged_05, ration)
observed = [r.iterations for r in conv]
observed_05 = [r.iterations_05 for r in conv]
predicted_default = log(tol_iter) / log(maximum(r.radius_default for r in conv))
predicted_05 = log(tol_iter) / log(maximum(r.radius_05 for r in conv))
record!("JacItersObsMean", fmt(mean(observed); d = 1))
record!("JacItersObsMax", string(maximum(observed)))
record!("JacItersPredDefault", fmt(predicted_default; d = 1))
record!("JacItersObsHalfMean", fmt(mean(observed_05); d = 1))
record!("JacItersObsHalfMax", string(maximum(observed_05)))
record!("JacItersPredHalf", fmt(predicted_05; d = 1))
record!("JacItersSavingPct", string(round(Int, 100 * (1 - mean(observed) / mean(observed_05)))))

fig7a = histogram([r.λ_min for r in ration], bins = 30, xlabel = "Most negative eigenvalue of ∂F/∂ρ at ρ*",
                  ylabel = "Count", title = "Spectrum of the rationing map",
                  legend = false, color = :steelblue, size = (650, 420), margin = 5Plots.mm)
vline!(fig7a, [-1.0], ls = :dash, color = :black)
savefig(fig7a, joinpath(FIG_DIR, "fig7a_rationing_spectrum.pdf"))

bins_it = 0.5:1:(max(maximum(observed), maximum(observed_05)) + 0.5)   # shared integer bins
fig7b = histogram(observed_05, bins = bins_it, xlabel = "Iterations to converge (tol = 1e-8)",
                  ylabel = "Count", title = "Observed vs. predicted iterations",
                  label = "observed, α = 0.5", color = :steelblue, alpha = 0.6,
                  size = (650, 420), margin = 5Plots.mm)
histogram!(fig7b, observed, bins = bins_it, label = "observed, α = 2/3 (default)",
           color = :firebrick, alpha = 0.6)
vline!(fig7b, [predicted_05], lw = 2.5, ls = :dash, color = :steelblue,
       label = "log(tol)/log(1/2)")
vline!(fig7b, [predicted_default], lw = 2.5, ls = :dash, color = :firebrick,
       label = "log(tol)/log(1/3)")
savefig(fig7b, joinpath(FIG_DIR, "fig7b_predicted_iterations.pdf"))

# ----------------------------------------------------------------------------
# 1b — Choice of the default relaxation: convergence and speed across α, on
#      the sweep above, from random initial ρ, and under much scarcer supply
# ----------------------------------------------------------------------------

println("\n[1b/3] Relaxation comparison...")

cases = NamedTuple[]
for N in Ns, density in densities, trial in 1:trials_per_combination
    seed = 1000 * N + round(Int, 1000 * density) + trial
    Random.seed!(seed)
    A = create_technical_matrix(N, density = density, seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    O = (0.1 + rand() * 0.8) .* (0.5 .+ rand(N))
    push!(cases, (A = A, σ_c = σ_c, S = S, O = O))
end
scarce = NamedTuple[]
for k in 1:200
    seed = 50_000 + k
    Random.seed!(seed)
    N = rand([6, 12, 19, 30])
    A = create_technical_matrix(N, density = rand([0.2, 0.4, 0.6, 0.8]), seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    O = (0.01 + rand() * 0.2) .* (0.5 .+ rand(N))   # far scarcer supply than the sweep
    push!(scarce, (A = A, σ_c = σ_c, S = S, O = O))
end

function run_case(cs, initials, α)
    its = Int[]; n = 0
    for c in cs, ρ0 in initials(length(c.S))
        n += 1
        d = _solve_rationing(c.A, c.σ_c, c.S, c.O; relaxation = α, ρ_initial = ρ0,
                                   max_iter = 2000, return_diagnostics = true)
        d.converged && push!(its, d.iterations)
    end
    return (conv = length(its), total = n, avg = mean(its), peak = maximum(its))
end

αs = [0.4, 0.5, 0.6, 2 / 3, 0.75, 0.85, 0.95]
n_starts = 20
records = String[]
n_runs = 0
failures = 0
for α in αs
    Random.seed!(1)
    a = run_case(cases, N -> [nothing], α)
    b = run_case(cases, N -> [0.01 .+ 0.99 .* rand(N) for _ in 1:n_starts], α)
    c = run_case(scarce, N -> [nothing; [0.01 .+ 0.99 .* rand(N) for _ in 1:5]], α)
    global n_runs = a.total + b.total + c.total
    global failures += (a.total - a.conv) + (b.total - b.conv) + (c.total - c.conv)
    label_ = α ≈ 2 / 3 ? "\\textbf{2/3} (default)" : α == 0.5 ? "0.5 (previous)" : string(α)
    push!(records, "$label_ & $(fmt(a.avg; d = 1)) & $(a.peak) & $(fmt(b.avg; d = 1)) & $(b.peak) & " *
                  "$(fmt(c.avg; d = 1)) & $(c.peak) \\\\")
    println("    α=$(round(α, digits = 3)): sweep $(a.conv)/$(a.total) mean $(fmt(a.avg; d = 1)); ",
            "random ρ0 $(b.conv)/$(b.total); scarce $(c.conv)/$(c.total)")
end
# The fixed point does not depend on α: rationing factors along the Figure 4
# trajectory (paper/generate_results.jl: N=6, seed 5, μ=0.5, racionamento)
# computed with the new and previous defaults.
Random.seed!(5)
sol4, _, p4 = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5, rationing = true)
diff_κ = 0.0
for X in sol4.u
    C, V = X[1:6], X[7:12]
    S4 = p4.e .* V
    x4 = (p4.δ .* C .+ V .+ S4) ./ (1 .- vec(sum(p4.A, dims = 1)))
    Δx4 = p4.σ_c .* S4 .* x4 ./ C
    global diff_κ = max(diff_κ, maximum(abs.(_solve_rationing(p4.A, ones(6), Δx4, x4) .-
                                          _solve_rationing(p4.A, ones(6), Δx4, x4; relaxation = 0.5))))
end
record!("RelaxFigFourDiff", sci(diff_κ))
record!("RelaxNRuns", string(n_runs))
record!("RelaxNFailures", string(failures))
record!("RelaxNScarce", string(length(scarce)))
record!("RelaxNStarts", string(n_starts))

open(joinpath(FIG_DIR, "table2_relaxation.tex"), "w") do io
    println(io, "% Generated by paper/jacobian_bifurcation.jl — do not edit by hand.")
    println(io, "\\begin{tabular}{lrrrrrr}")
    println(io, "\\toprule")
    println(io, " & \\multicolumn{2}{c}{Sweep (\\(\\rho_0=1\\))} & \\multicolumn{2}{c}{Random \\(\\rho_0\\)} & \\multicolumn{2}{c}{Scarce supply} \\\\")
    println(io, "\\(\\alpha\\) & mean & max & mean & max & mean & max \\\\")
    println(io, "\\midrule")
    foreach(l -> println(io, l), records)
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end

# ----------------------------------------------------------------------------
# 2 — Bifurcation diagram of the damped iteration in the demand scale s
# ----------------------------------------------------------------------------

println("\n[2/3] Bifurcation diagram of the damped rationing iteration...")

Random.seed!(11)
N = 12
A = create_technical_matrix(N, density = 0.5)
σ_c = fill(0.5, N)
S = 5.0 .+ 10 * rand(N)
O = 0.3 .+ rand(N) * 0.5
s_c = minimum(O ./ (A * (σ_c .* S)))
br = rationing_bifurcation(A, σ_c, S, O; scale = (0.005, 2.0))   # default α = 2/3
br_flip = rationing_bifurcation(A, σ_c, S, O; scale = (0.005, 2.0), relaxation = 1.1)
record!("BifSc", fmt(s_c; d = 3))
record!("BifNPointsDefault", string(length(br.points)))
record!("BifFlipS", fmt(br_flip.points[1].θ; d = 3))
record!("BifFlipType", string(br_flip.points[1].kind))

# α_max and the rationed fraction are piecewise constant in s and jump at the
# border-collision point s_c; draw them as steps with the jump placed at the
# analytic s_c rather than interpolated between continuation steps.
before = br.θ .< s_c
xs = [br.θ[before]; s_c; s_c; br.θ[.!before]]
α_plot = [br.α_max[before]; br.α_max[findlast(before)]; br.α_max[findfirst(.!before)]; br.α_max[.!before]]
frac_plot = [br.rationed_fraction[before]; 0.0; br.rationed_fraction[findfirst(.!before)];
             br.rationed_fraction[.!before]]
fig8 = plot(xs, α_plot, lw = 2.5, color = :black, label = "α_max(s): flip boundary",
            seriestype = :steppost, xlabel = "Demand scale s", ylabel = "Relaxation α",
            title = "Local stability of the damped rationing iteration",
            ylims = (0, 2.2), size = (700, 450), margin = 5Plots.mm, legend = :topright)
plot!(fig8, xs, α_plot, seriestype = :steppost, fillrange = 0, fillalpha = 0.12, lw = 0,
      color = :seagreen, label = "convergent")
hline!(fig8, [DEFAULT_RELAXATION], ls = :dash, color = :steelblue, label = "default α = 2/3")
hline!(fig8, [1.0], ls = :dot, color = :firebrick, label = "undamped α = 1")
vline!(fig8, [s_c], ls = :dashdot, color = :gray, label = "rationing onset s_c")
plot!(fig8, xs, frac_plot, seriestype = :steppost, lw = 1.5, color = :orange,
      label = "fraction of sectors rationed")
savefig(fig8, joinpath(FIG_DIR, "fig8_rationing_bifurcation.pdf"))

# ----------------------------------------------------------------------------
# 3 — TSSI: profit rates along trajectories (fixed lag τ) and stability of
#     the TSSI price map under frozen data, across random economies
# ----------------------------------------------------------------------------

println("\n[3/3] TSSI valuation and price-map stability...")

Random.seed!(5)
sol, _, p = simulate_Ndept(6, T = 100.0, seed = 5, coupled = true, μ = 0.5, realization = true)
τs = [0.5, 1.0, 2.0, 5.0]
fig9a = plot(xlabel = "Time", ylabel = "r_TSSI − r_simultaneist (p.p.)",
             title = "TSSI vs. simultaneist profit rate", size = (700, 450), margin = 5Plots.mm)
errors = Float64[]
final_gap = Float64[]
for τ in τs
    v = tssi_valuation(sol, p; τ = τ, h = 0.5)
    push!(errors, v.invariance_error)
    push!(final_gap, 100 * (v.r_tssi[end] - v.r_simultaneous[end]))
    plot!(fig9a, v.t, 100 .* (v.r_tssi .- v.r_simultaneous), lw = 2, label = "τ = $τ")
end
hline!(fig9a, [0.0], color = :black, ls = :dash, label = "")
savefig(fig9a, joinpath(FIG_DIR, "fig9a_tssi_gap.pdf"))
record!("TssiInvErr", sci(maximum(errors)))
record!("TssiGapTauOne", fmt(final_gap[2]; d = 3))
record!("TssiGapTauFive", fmt(final_gap[4]; d = 3))

n_economies = 50
radii = Float64[]
radii_max_θ = Float64[]
n_tssi_points = 0
for seed in 1:n_economies
    Random.seed!(seed)
    sol_s, _, p_s = simulate_Ndept(6, T = 60.0, seed = seed, coupled = true, μ = 0.5,
                                  realization = true)
    push!(radii, tssi_stability(tssi_data(sol_s.u[end], p_s)).spectral_radius)
    bt = tssi_bifurcation(sol_s.u[end], p_s; τ = 1.0, scale = (0.05, 10.0))
    push!(radii_max_θ, maximum(bt.radius))
    global n_tssi_points += length(bt.points)
end
record!("TssiNEcon", string(n_economies))
record!("TssiRadiusMean", fmt(mean(radii); d = 3))
record!("TssiRadiusMax", fmt(maximum(radii); d = 3))
record!("TssiRadiusThetaMax", fmt(maximum(radii_max_θ); d = 3))
record!("TssiNBifPoints", string(n_tssi_points))
record!("TssiHalfLifeTauOne", fmt(log(2) / -log(mean(radii)); d = 2))

fig9b = histogram(radii, bins = 15, xlabel = "Spectral radius of ∂p(t)/∂p(t−τ) at p*",
                  ylabel = "Count", title = "TSSI price map: local stability ($n_economies economies)",
                  legend = false, color = :seagreen, size = (650, 420), margin = 5Plots.mm)
savefig(fig9b, joinpath(FIG_DIR, "fig9b_tssi_stability.pdf"))

open(joinpath(FIG_DIR, "jacobian_stats.tex"), "w") do io
    println(io, "% Generated by paper/jacobian_bifurcation.jl — do not edit by hand.")
    for (name, amount) in macros
        println(io, "\\newcommand{\\$name}{$amount}")
    end
end

println("\n" * "="^70)
println("Done. Figures fig7a/b, fig8, fig9a/b and jacobian_stats.tex in paper/figures/.")
println("="^70)
