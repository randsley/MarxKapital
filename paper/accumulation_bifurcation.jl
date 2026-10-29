# ============================================================================
# Balanced growth and accumulation cycles in the cross-dual model: Hopf
# bifurcation in the mobility of variable capital μ_v, continuation of the
# limit cycles (collocation, Floquet multipliers) checked against direct
# simulation, wage-share sweep, Hopf boundary in (ω, μ_v) and in β,
# robustness across random economies, and TSSI on the balanced-growth ray.
#
# Run with:  julia --project=. paper/accumulation_bifurcation.jl
# No network access required (all synthetic). Writes figures to
# paper/figures/ and every number quoted in the corresponding sections of
# paper/main.tex to paper/figures/accumulation_stats.tex (as \newcommand
# macros), so none is typed by hand.
# ============================================================================

ENV["GKSwstype"] = "100"
include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

macros = Pair{String,String}[]
fmt(x; d = 2) = d == 0 ? string(round(Int, x)) : string(round(x, digits = d))
function sci(x)
    e = floor(Int, log10(abs(x)))
    return "\\ensuremath{$(round(x / 10.0^e, digits = 1))\\times10^{$e}}"
end
record!(name, amount) = (push!(macros, name => amount); println("    \\$name = $amount"))

println("\n" * "="^70)
println("Balanced growth, Hopf bifurcation and accumulation cycles...")
println("="^70)

# Reference economy: six sectors, capital mobility μ = 0.5, market prices.
Random.seed!(5)
sol_ref, _, p_ref = simulate_Ndept(6, T = 1.0, seed = 5, coupled = true, μ = 0.5,
                                  market_prices = true)
X0 = sol_ref.u[1]
record!("AccN", "6")
record!("AccMu", fmt(p_ref.μ; d = 1))
record!("AccBetaDefault", fmt(p_ref.β; d = 1))

# ----------------------------------------------------------------------------
# 1 — Identities of the cross-dual system
# ----------------------------------------------------------------------------

println("\n[1/6] Cross-dual identities...")
walras_error, profit_error = 0.0, 0.0
for k in 1:200
    X = X0 .* (0.5 .+ rand(length(X0))) .+ [zeros(12); randn(6)]
    ec = cross_dual_state(X[1:6], X[7:12], X[13:18], p_ref)
    global walras_error = max(walras_error, abs(sum(ec.P .* ec.demand) - sum(ec.P .* ec.x)) / sum(ec.P .* ec.x))
    global profit_error = max(profit_error, abs(sum(ec.Π) - sum(p_ref.e .* X[7:12])) / sum(p_ref.e .* X[7:12]))
end
record!("AccWalrasErr", sci(max(walras_error, 1e-16)))
record!("AccProfitErr", sci(max(profit_error, 1e-16)))

# ----------------------------------------------------------------------------
# 2 — Hopf bifurcation in μ_v and the branch of limit cycles
# ----------------------------------------------------------------------------

println("\n[2/6] Hopf bifurcation and limit cycles in μ_v (β = 0.1)...")
β_hopf = 0.1
p = merge(p_ref, (β = β_hopf,))
record!("AccBetaHopf", fmt(β_hopf; d = 1))
μv_max = 2.5
res = accumulation_bifurcation(p, X0, :μ_v; interval = (0.0, μv_max), orbit_interval = (0.0, μv_max))
H = res.hopf[1]
record!("AccMuvH", fmt(H.θ; d = 3))
record!("AccHopfPeriod", fmt(H.period; d = 1))
record!("AccHopfOmega", fmt(abs(H.ω); d = 3))
record!("AccHopfLyap", fmt(H.l1; d = 3))
record!("AccHopfTransv", fmt(H.transversality; d = 3))
record!("AccNHopf", string(length(res.hopf)))
record!("AccHopfLast", fmt(res.hopf[end].θ; d = 2))
record!("AccRealPartStart", fmt(res.max_real_part[1]; d = 3))

o = res.orbits
points_po(kind) = sort([pt.θ for pt in o.points if pt.kind == kind])
ns, folds, pds = points_po(:ns), points_po(:bp), points_po(:pd)
println("    cycle bifurcations: ", o.points)
record!("AccNSFirst", fmt(ns[1]; d = 3))
record!("AccNSFurther", join(fmt.(ns[2:end]; d = 2), ", "))
record!("AccFoldList", isempty(folds) ? "none" : join(fmt.(folds; d = 2), " and "))
# upper turning point of the cycle branch (first decrease of θ along the
# outward leg): a fold of cycles whether or not the step-dependent detector flags it
θ_out = o.branches[2].branch.param
k_back = findfirst(k -> θ_out[k+1] < θ_out[k], 1:length(θ_out)-1)
record!("AccFoldUpper", isnothing(k_back) ? "none" : fmt(θ_out[k_back]; d = 2))
record!("AccPDFirst", isempty(pds) ? "none" : fmt(pds[1]; d = 2))
record!("AccCycleQminEnd", sci(o.min_share[end]))
record!("AccCycleAmpEnd", fmt(o.amplitude[end]; d = 2))
record!("AccCyclePeriodEnd", fmt(o.period[end]; d = 1))

# Direct simulation on a grid of μ_v: equilibrium, periodic cycle, or
# quasi-periodic / irregular motion (Poincaré-section spread).
grid_pts = [0.9, 0.95, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45, 1.5, 1.55, 1.6, 1.7, 1.8,
          1.9, 2.0, 2.2, 2.4]
class(c) = c.n < 2 || c.amplitude < 1e-4 ? :equilibrium :
            c.section_dispersion < 0.01 * c.amplitude ? :periodic : :irregular
sims = [simulated_cycle(p, :μ_v, θ, X0; T = 6000.0) for θ in grid_pts]
classes = class.(sims)
for (θ, c, k) in zip(grid_pts, sims, classes)
    println("    μ_v = $θ: $k, amplitude $(round(c.amplitude, sigdigits = 3)), return times $(c.T_min)–$(c.T_max)")
end
# agreement of simulated periodic cycles with the stable part of the branch
deviations_T, deviations_A = Float64[], Float64[]
for (θ, c, k) in zip(grid_pts, sims, classes)
    k === :periodic || continue
    cand = findall(i -> o.stable[i], eachindex(o.θ))
    i = cand[argmin(abs.(o.θ[cand] .- θ))]
    abs(o.θ[i] - θ) < 0.02 || continue
    push!(deviations_T, abs(c.T_min - o.period[i]) / o.period[i])
    push!(deviations_A, abs(c.amplitude - o.amplitude[i]) / o.amplitude[i])
end
# periodic simulations with no stable continued cycle nearby (e.g. phase
# locking on the torus beyond a Neimark–Sacker point)
no_branch = [θ for (θ, k) in zip(grid_pts, classes) if k === :periodic &&
            !any(i -> o.stable[i] && abs(o.θ[i] - θ) < 0.02, eachindex(o.θ))]
record!("AccSimUnmatched", isempty(no_branch) ? "none" : join(fmt.(no_branch; d = 2), ", "))
k_sm = isempty(no_branch) ? nothing : findfirst(==(no_branch[1]), grid_pts)
record!("AccSimUnmatchedPeriod", isnothing(k_sm) ? "none" : fmt(sims[k_sm].T_min; d = 1))
record!("AccSimNGrid", string(length(grid_pts)))
record!("AccSimNPeriodic", string(count(==(:periodic), classes)))
record!("AccSimNIrregular", string(count(==(:irregular), classes)))
record!("AccSimNMatched", string(length(deviations_T)))
record!("AccSimPeriodDev", fmt(100 * maximum(deviations_T); d = 1))
record!("AccSimAmpDev", fmt(100 * maximum(deviations_A); d = 1))
record!("AccSimIrregularFrom", fmt(minimum(θ for (θ, k) in zip(grid_pts, classes) if k === :irregular); d = 2))
i11 = findfirst(==(1.1), grid_pts)
record!("AccSimPeriodOneOne", fmt(sims[i11].T_min; d = 1))

fig10a = plot(res.θ, res.max_real_part, lw = 2, color = :black, label = "max Re λ (balanced growth)",
              xlabel = "Mobility of variable capital μ_v", ylabel = "max Re λ",
              title = "Stability of the balanced-growth ray", size = (700, 450), margin = 5Plots.mm,
              legend = :topleft)
hline!(fig10a, [0.0], ls = :dash, color = :gray, label = "")
vline!(fig10a, [h.θ for h in res.hopf], ls = :dot, color = :firebrick, label = "Hopf points")
savefig(fig10a, joinpath(FIG_DIR, "fig10a_balanced_growth_stability.pdf"))

# amplitude diagram: stable (solid) and unstable (dashed) cycles, simulations on top
fig10b = plot(xlabel = "Mobility of variable capital μ_v", ylabel = "Cycle amplitude (max share swing)",
              title = "Accumulation cycles: continuation vs. simulation", size = (700, 450),
              margin = 5Plots.mm, legend = :bottomright)
plot!(fig10b, [0.0, H.θ], [0.0, 0.0], lw = 2.5, color = :black, label = "stable balanced growth")
plot!(fig10b, [H.θ, μv_max], [0.0, 0.0], lw = 1.5, ls = :dash, color = :black, label = "")
# contiguous runs of equal stability, so the dash pattern is visible
for branch in o.branches
    b = branch.branch
    θb, Ab, eb = b.param, b.amplitude, b.stable
    i = 1
    while i < length(θb)
        j = i
        while j < length(θb) && eb[j+1] == eb[i]
            j += 1
        end
        stop = min(j + 1, length(θb))
        plot!(fig10b, θb[i:stop], Ab[i:stop], lw = eb[i] ? 2.5 : 1.5, ls = eb[i] ? :solid : :dash,
              color = :steelblue, label = "")
        i = j + 1
    end
end
plot!(fig10b, [NaN], [NaN], lw = 2.5, color = :steelblue, label = "limit cycle (stable / unstable)")
for (kind, cor, label_) in ((:ns, :darkorange, "Neimark–Sacker"), (:bp, :purple, "fold of cycles"),
                            (:pd, :firebrick, "period doubling"))
    pts = [pt.θ for pt in o.points if pt.kind == kind]
    isempty(pts) && continue
    ks = [argmin(abs.(o.θ .- θ)) for θ in pts]
    scatter!(fig10b, pts, o.amplitude[ks], color = cor, ms = 6, label = label_)
end
for (k, cor, label_) in ((:periodic, :seagreen, "simulation: periodic"),
                         (:irregular, :gray, "simulation: quasi-periodic / irregular"),
                         (:equilibrium, :black, "simulation: equilibrium"))
    ii = findall(==(k), classes)
    isempty(ii) && continue
    scatter!(fig10b, grid_pts[ii], [sims[i].amplitude for i in ii], marker = :diamond, ms = 5,
             color = cor, label = label_)
end
savefig(fig10b, joinpath(FIG_DIR, "fig10b_accumulation_cycles.pdf"))

# ----------------------------------------------------------------------------
# 2b — Lyapunov exponents (chaos test) and hysteresis by simulation
# ----------------------------------------------------------------------------

println("\n[2b/6] Lyapunov exponents and up/down parameter sweeps...")
T_lyap = 30000.0
record!("AccLyapT", fmt(T_lyap; d = 0))
θ_lyap = [1.1, 1.3, 1.9, 2.0, 2.1, 2.2, 2.3, 2.4]
lyap = Dict(θ => lyapunov_exponents(p, :μ_v, θ, X0; T = T_lyap) for θ in θ_lyap)
for θ in θ_lyap
    println("    μ_v = $θ: λ = $(round.(lyap[θ].λ, sigdigits = 3)), at T/2: $(round.(lyap[θ].λ_mid, sigdigits = 3))")
end
# second, randomly perturbed initial condition at every point with λ₁ > 0
Random.seed!(107)
chaotic = [θ for θ in θ_lyap if lyap[θ].λ[1] > 0.01]
z_alt(θ) = _to_free(X0, with_parameter(p, :μ_v, θ)) .+ 5e-3 .* randn(length(_to_free(X0, p)))
lyap_alt = Dict(θ => lyapunov_exponents(p, :μ_v, θ, X0; T = T_lyap, z0 = z_alt(θ)) for θ in chaotic)
for θ in chaotic
    println("    μ_v = $θ (alt. IC): λ = $(round.(lyap_alt[θ].λ, sigdigits = 3))")
end
λ1_all = [x for θ in chaotic for x in (lyap[θ].λ[1], lyap_alt[θ].λ[1])]
λ2_all(θ) = (lyap[θ].λ[2], lyap_alt[θ].λ[2])
hyper = [θ for θ in chaotic if all(>(5e-3), λ2_all(θ))]
record!("AccLyapCycle", sci(abs(lyap[1.1].λ[1])))
record!("AccLyapCycleTwo", fmt(lyap[1.1].λ[2]; d = 4))
record!("AccLyapTorusOne", sci(abs(lyap[1.3].λ[1])))
record!("AccLyapTorusTwo", sci(abs(lyap[1.3].λ[2])))
record!("AccLyapTorusThree", fmt(lyap[1.3].λ[3]; d = 4))
record!("AccLyapNChaos", string(length(chaotic)))
record!("AccLyapChaosList", join(fmt.(chaotic; d = 1), ", "))
record!("AccLyapOneMin", fmt(minimum(λ1_all); d = 3))
record!("AccLyapOneMax", fmt(maximum(λ1_all); d = 3))
record!("AccLyapICDev", fmt(100 * maximum(abs(lyap[θ].λ[1] - lyap_alt[θ].λ[1]) / lyap[θ].λ[1] for θ in chaotic); d = 0))
record!("AccLyapWindowMuv", join(fmt.([θ for θ in θ_lyap if θ > 1.5 && lyap[θ].λ[1] < 0.01]; d = 1), ", "))
record!("AccLyapWindowOne", sci(maximum(abs(lyap[θ].λ[1]) for θ in θ_lyap if θ > 1.5 && lyap[θ].λ[1] < 0.01)))
record!("AccHyperList", isempty(hyper) ? "none" : join(fmt.(hyper; d = 1), ", "))
record!("AccHyperTwoMin", isempty(hyper) ? "none" : fmt(minimum(minimum(λ2_all(θ)) for θ in hyper); d = 3))
record!("AccHyperTwoMax", isempty(hyper) ? "none" : fmt(maximum(maximum(λ2_all(θ)) for θ in hyper); d = 3))
record!("AccLyapQuotaMin", sci(minimum(lyap[θ].min_share for θ in chaotic)))

step_h = 0.01
hs = simulated_hysteresis(p, :μ_v, 1.30:step_h:1.56, X0)
coex = hs.coexistence
println("    coexistence at μ_v = ", coex)
record!("AccHystStep", fmt(step_h; d = 2))
record!("AccHystLo", fmt(minimum(coex); d = 2))
record!("AccHystHi", fmt(maximum(coex); d = 2))
record!("AccHystNext", fmt(maximum(coex) + step_h; d = 2))
ic = findall(θ -> θ in coex, hs.θ)
record!("AccHystCyclePeriodHi", fmt(maximum(hs.down.mean_return[ic]); d = 1))
record!("AccHystCyclePeriodLo", fmt(minimum(hs.down.mean_return[ic]); d = 1))
record!("AccHystTorusAmp", fmt(mean(hs.up.amplitude[ic]); d = 2))
record!("AccHystCycleAmp", fmt(mean(hs.down.amplitude[ic]); d = 2))
record!("AccHystAllSame", string(all(hs.up.class[ic] .== :irregular) && all(hs.down.class[ic] .== :cycle)))

λs_plot = [lyap[θ].λ for θ in θ_lyap]
fig10c = scatter(θ_lyap, getindex.(λs_plot, 1), ms = 6, color = :firebrick, label = "λ₁",
                 xlabel = "Mobility of variable capital μ_v", ylabel = "Lyapunov exponent",
                 title = "Largest Lyapunov exponents", size = (700, 450), margin = 5Plots.mm,
                 legend = :topleft)
scatter!(fig10c, θ_lyap, getindex.(λs_plot, 2), ms = 5, marker = :square, color = :steelblue, label = "λ₂")
scatter!(fig10c, θ_lyap, getindex.(λs_plot, 3), ms = 5, marker = :utriangle, color = :gray, label = "λ₃")
scatter!(fig10c, chaotic, [lyap_alt[θ].λ[1] for θ in chaotic], ms = 4, marker = :x,
         color = :black, label = "λ₁, second initial condition")
hline!(fig10c, [0.0], ls = :dash, color = :black, label = "")
savefig(fig10c, joinpath(FIG_DIR, "fig10c_lyapunov.pdf"))

fig10d = plot(hs.θ, hs.up.mean_return, lw = 2, marker = :circle, ms = 3, color = :darkorange,
              label = "sweeping up (from the torus)", xlabel = "Mobility of variable capital μ_v",
              ylabel = "Mean return time to the Poincaré section",
              title = "Coexisting attractors (hysteresis)", size = (700, 450), margin = 5Plots.mm)
plot!(fig10d, hs.θ, hs.down.mean_return, lw = 2, marker = :diamond, ms = 3, color = :steelblue,
      label = "sweeping down (from the cycle)")
vspan!(fig10d, [minimum(coex) - step_h / 2, maximum(coex) + step_h / 2], alpha = 0.12,
       color = :seagreen, label = "torus and stable cycle coexist")
savefig(fig10d, joinpath(FIG_DIR, "fig10d_hysteresis.pdf"))

# ----------------------------------------------------------------------------
# 3 — Wage-share sweep: uniform ω and proportional exploration scale
# ----------------------------------------------------------------------------

println("\n[3/6] Wage-share sweep...")
vu = wage_sweep(p_ref, X0; variant = :uniform)
vp = wage_sweep(p_ref, X0; variant = :proportional)
record!("AccWageOmegaMin", fmt(first(vu.ω); d = 2))
record!("AccWageOmegaMax", fmt(last(vu.ω); d = 2))
record!("AccWageAllStable", string(all(vu.stable) && all(vp.stable)))
record!("AccWageNPoints", string(length(vu.θ) + length(vp.θ)))
record!("AccWageGMax", fmt(100 * first(vu.g); d = 0))
record!("AccWageGMin", fmt(100 * last(vu.g); d = 1))
record!("AccWageRMax", fmt(100 * first(vu.r); d = 0))
record!("AccWageRMin", fmt(100 * last(vu.r); d = 1))
record!("AccWageKMax", fmt(first(vu.k); d = 2))
record!("AccWageKMin", fmt(last(vu.k); d = 2))
record!("AccWageReMin", fmt(minimum(vu.max_real_part); d = 3))
record!("AccWageReMax", fmt(maximum(vu.max_real_part); d = 3))
i_mon = findfirst(!, vu.oscillatory)
record!("AccWageMonotoneFrom", isnothing(i_mon) ? "none" : fmt(vu.ω[i_mon]; d = 2))
record!("AccPropOmegaMin", fmt(minimum(vp.ω); d = 2))
record!("AccPropOmegaMax", fmt(maximum(vp.ω); d = 2))
# g/r ratio: a Cambridge-type relation g ≈ s·r − δ̄ holds along both sweeps
record!("AccWageGoverRHi", fmt(first(vu.g) / first(vu.r); d = 2))
record!("AccWageGoverRLo", fmt(last(vu.g) / last(vu.r); d = 2))

fig11a = plot(vu.ω, 100 .* vu.g, lw = 2.5, color = :steelblue, label = "g★, uniform ω",
              xlabel = "Aggregate wage share ω", ylabel = "Rate (%)",
              title = "Balanced growth and distribution", size = (700, 450), margin = 5Plots.mm,
              yscale = :log10, legend = :topright)
plot!(fig11a, vu.ω, 100 .* vu.r, lw = 2.5, color = :firebrick, label = "r★, uniform ω")
plot!(fig11a, vp.ω, 100 .* vp.g, lw = 0, marker = :circle, ms = 3, color = :steelblue,
      label = "g★, proportional e")
plot!(fig11a, vp.ω, 100 .* vp.r, lw = 0, marker = :circle, ms = 3, color = :firebrick,
      label = "r★, proportional e")
savefig(fig11a, joinpath(FIG_DIR, "fig11a_wage_share_growth.pdf"))

# ----------------------------------------------------------------------------
# 4 — Hopf boundary in (ω, μ_v) and its dependence on β
# ----------------------------------------------------------------------------

println("\n[4/6] Hopf boundary in (ω, μ_v) and in β...")
ch = hopf_curve(p, X0; ω_values = 0.2:0.05:0.65)
record!("AccHopfCurveOmegaMin", fmt(first(ch.ω); d = 2))
record!("AccHopfCurveOmegaMax", fmt(last(ch.ω); d = 2))
record!("AccHopfCurveMuvMin", fmt(first(ch.μ_v_H); d = 2))
record!("AccHopfCurveMuvMax", fmt(last(ch.μ_v_H); d = 2))
record!("AccHopfCurveMonotone", string(issorted(ch.μ_v_H)))
record!("AccHopfCurveAllSuper", string(all(ch.supercritical)))
jumps = abs.(diff(ch.frequency))
j = argmax(jumps)
record!("AccHopfFreqJumpLo", fmt(ch.ω[j]; d = 2))
record!("AccHopfFreqJumpHi", fmt(ch.ω[j+1]; d = 2))
record!("AccHopfFreqBefore", fmt(ch.frequency[j]; d = 2))
record!("AccHopfFreqAfter", fmt(ch.frequency[j+1]; d = 2))

βs = [0.05, 0.1, 0.2, 0.3, 0.5, 1.0]
μvH_β = map(βs) do β
    r = accumulation_bifurcation(merge(p_ref, (β = β,)), X0, :μ_v; interval = (0.0, 4.0), orbits = false)
    isempty(r.hopf) ? NaN : r.hopf[1].θ
end
println("    μ_v,H(β): ", collect(zip(βs, μvH_β)))
record!("AccBetaList", join(fmt.(βs; d = 2), ", "))
record!("AccBetaMuvHList", join([isnan(x) ? "none" : fmt(x; d = 2) for x in μvH_β], ", "))
record!("AccBetaMuvHDefault", isnan(μvH_β[findfirst(==(p_ref.β), βs)]) ? "none" :
                                fmt(μvH_β[findfirst(==(p_ref.β), βs)]; d = 2))

fig11b = plot(ch.ω, ch.μ_v_H, lw = 2.5, color = :black, marker = :circle, ms = 4,
              label = "Hopf boundary μ_v,H(ω), β = $β_hopf",
              xlabel = "Aggregate wage share ω", ylabel = "Mobility of variable capital μ_v",
              title = "Where balanced growth gives way to cycles", size = (700, 450),
              margin = 5Plots.mm, legend = :topleft, ylims = (0, 1.15 * maximum(ch.μ_v_H)))
plot!(fig11b, ch.ω, ch.μ_v_H, fillrange = 0, fillalpha = 0.12, lw = 0, color = :seagreen,
      label = "stable balanced growth")
annotate!(fig11b, ch.ω[end-2], 1.07 * maximum(ch.μ_v_H), text("limit cycles", 9, :firebrick))
savefig(fig11b, joinpath(FIG_DIR, "fig11b_hopf_boundary.pdf"))

# ----------------------------------------------------------------------------
# 5 — Robustness across random economies; TSSI on the balanced-growth ray
# ----------------------------------------------------------------------------

println("\n[5/6] Robustness across random economies and TSSI check...")
n_economies = 30
rob = map(1:n_economies) do seed
    Random.seed!(seed)
    N = 3 + seed % 6
    sol_s, _, p_s = simulate_Ndept(N, T = 1.0, seed = seed, coupled = true, μ = 0.5,
                                  market_prices = true)
    r = accumulation_bifurcation(merge(p_s, (β = β_hopf,)), sol_s.u[1], :μ_v; interval = (0.0, 4.0),
                              orbits = false)
    (N = N, stable0 = r.max_real_part[1] < 0, has_hopf = !isempty(r.hopf),
     μ_v_H = isempty(r.hopf) ? NaN : r.hopf[1].θ,
     super = !isempty(r.hopf) && r.hopf[1].supercritical,
     period = isempty(r.hopf) ? NaN : r.hopf[1].period, share = minimum(r.min_share))
end
μs_H = filter(!isnan, [r.μ_v_H for r in rob])
periods = filter(!isnan, [r.period for r in rob])
record!("AccRobN", string(n_economies))
record!("AccRobNMin", string(minimum(r.N for r in rob)))
record!("AccRobNMax", string(maximum(r.N for r in rob)))
record!("AccRobNStable", string(count(r -> r.stable0, rob)))
record!("AccRobNHopf", string(count(r -> r.has_hopf, rob)))
record!("AccRobNSuper", string(count(r -> r.super, rob)))
record!("AccRobMuvHMin", fmt(minimum(μs_H); d = 2))
record!("AccRobMuvHMax", fmt(maximum(μs_H); d = 2))
record!("AccRobMuvHMedian", fmt(median(μs_H); d = 2))
record!("AccRobPeriodMin", fmt(minimum(periods); d = 1))
record!("AccRobPeriodMax", fmt(maximum(periods); d = 1))
record!("AccRobQuotaMin", fmt(minimum(r.share for r in rob); d = 3))

eq = balanced_growth(p_ref, X0)
s_eq = solve(ODEProblem(cross_dual_system!, eq.X, (0.0, 30.0), p_ref), Tsit5(),
             abstol = 1e-11, reltol = 1e-11)
v = tssi_valuation(s_eq, p_ref; τ = 1.0, h = 0.5)
record!("AccTssiGap", sci(maximum(abs.(v.r_tssi[3:end] .- v.r_simultaneous[3:end]))))
record!("AccGrowthRef", fmt(100 * eq.g; d = 1))
record!("AccGrowthSimErr", sci(abs(log(sum(s_eq.u[end][1:12]) / sum(s_eq.u[1][1:12])) / 30 - eq.g) / eq.g))

# ----------------------------------------------------------------------------
# 6 — Exit friction: outflows damped as a sector's share shrinks
# ----------------------------------------------------------------------------

println("\n[6/6] Exit friction...")
εs = [0.0, 0.01, 0.05]
μvs_exit = [1.2, 1.6, 2.0, 2.4]
exit_sims = Dict((ε, θ) => simulated_cycle(merge(p, (exit_friction = ε,)), :μ_v, θ, X0; T = 6000.0)
                 for ε in εs, θ in μvs_exit)
for ε in εs, θ in μvs_exit
    c = exit_sims[(ε, θ)]
    println("    ε = $ε, μ_v = $θ: $(class(c)), min share $(round(c.min_share, sigdigits = 3))")
end
label(k) = k === :equilibrium ? "eq." : k === :periodic ? "cycle" : "irreg."
open(joinpath(FIG_DIR, "table_exit_friction.tex"), "w") do io
    println(io, "% Generated by paper/accumulation_bifurcation.jl — do not edit by hand.")
    println(io, "\\begin{tabular}{l" * "r"^length(μvs_exit) * "}")
    println(io, "\\toprule")
    println(io, "\\multicolumn{1}{c}{} & \\multicolumn{$(length(μvs_exit))}{c}{\\(\\mu_v\\)} \\\\")
    println(io, "\\(\\varepsilon\\) & " * join(fmt.(μvs_exit; d = 1), " & ") * " \\\\")
    println(io, "\\midrule")
    for ε in εs
        cells = [sci(exit_sims[(ε, θ)].min_share) * " (" * label(class(exit_sims[(ε, θ)])) * ")"
                 for θ in μvs_exit]
        println(io, fmt(ε; d = 2) * " & " * join(cells, " & ") * " \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
record!("AccExitEpsMax", fmt(εs[end]; d = 2))
record!("AccExitMuvMax", fmt(μvs_exit[end]; d = 1))
record!("AccExitShareOff", sci(exit_sims[(0.0, μvs_exit[end])].min_share))
record!("AccExitShareOn", sci(exit_sims[(εs[end], μvs_exit[end])].min_share))
record!("AccExitAmpOffLow", fmt(exit_sims[(0.0, μvs_exit[1])].amplitude; d = 2))
record!("AccExitAmpOnLow", sci(exit_sims[(εs[end], μvs_exit[1])].amplitude))

open(joinpath(FIG_DIR, "accumulation_stats.tex"), "w") do io
    println(io, "% Generated by paper/accumulation_bifurcation.jl — do not edit by hand.")
    for (name, amount) in macros
        println(io, "\\newcommand{\\$name}{$amount}")
    end
end

println("\n" * "="^70)
println("Done. Figures fig10a/b, fig11a/b and accumulation_stats.tex in paper/figures/.")
println("="^70)
