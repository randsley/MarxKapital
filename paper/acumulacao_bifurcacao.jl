# ============================================================================
# Balanced growth and accumulation cycles in the cross-dual model: Hopf
# bifurcation in the mobility of variable capital μ_v, continuation of the
# limit cycles (collocation, Floquet multipliers) checked against direct
# simulation, wage-share sweep, Hopf boundary in (ω, μ_v) and in β,
# robustness across random economies, and TSSI on the balanced-growth ray.
#
# Run with:  julia --project=. paper/acumulacao_bifurcacao.jl
# No network access required (all synthetic). Writes figures to
# paper/figures/ and every number quoted in the corresponding sections of
# paper/main.tex to paper/figures/acumulacao_stats.tex (as \newcommand
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
registar!(nome, valor) = (push!(macros, nome => valor); println("    \\$nome = $valor"))

println("\n" * "="^70)
println("Balanced growth, Hopf bifurcation and accumulation cycles...")
println("="^70)

# Reference economy: six sectors, capital mobility μ = 0.5, market prices.
Random.seed!(5)
sol_ref, _, p_ref = simular_Ndept(6, T = 1.0, seed = 5, acoplado = true, μ = 0.5,
                                  preços_mercado = true)
X0 = sol_ref.u[1]
registar!("AccN", "6")
registar!("AccMu", fmt(p_ref.μ; d = 1))
registar!("AccBetaDefault", fmt(p_ref.β; d = 1))

# ----------------------------------------------------------------------------
# 1 — Identities of the cross-dual system
# ----------------------------------------------------------------------------

println("\n[1/5] Cross-dual identities...")
erro_walras, erro_lucro = 0.0, 0.0
for k in 1:200
    X = X0 .* (0.5 .+ rand(length(X0))) .+ [zeros(12); randn(6)]
    ec = estado_cruzado(X[1:6], X[7:12], X[13:18], p_ref)
    global erro_walras = max(erro_walras, abs(sum(ec.P .* ec.procura) - sum(ec.P .* ec.x)) / sum(ec.P .* ec.x))
    global erro_lucro = max(erro_lucro, abs(sum(ec.Π) - sum(p_ref.e .* X[7:12])) / sum(p_ref.e .* X[7:12]))
end
registar!("AccWalrasErr", sci(max(erro_walras, 1e-16)))
registar!("AccProfitErr", sci(max(erro_lucro, 1e-16)))

# ----------------------------------------------------------------------------
# 2 — Hopf bifurcation in μ_v and the branch of limit cycles
# ----------------------------------------------------------------------------

println("\n[2/5] Hopf bifurcation and limit cycles in μ_v (β = 0.1)...")
β_hopf = 0.1
p = merge(p_ref, (β = β_hopf,))
registar!("AccBetaHopf", fmt(β_hopf; d = 1))
μv_max = 2.5
res = bifurcacao_acumulação(p, X0, :μ_v; intervalo = (0.0, μv_max), intervalo_órbitas = (0.0, μv_max))
H = res.hopf[1]
registar!("AccMuvH", fmt(H.θ; d = 3))
registar!("AccHopfPeriod", fmt(H.período; d = 1))
registar!("AccHopfOmega", fmt(abs(H.ω); d = 3))
registar!("AccHopfLyap", fmt(H.l1; d = 3))
registar!("AccHopfTransv", fmt(H.transversalidade; d = 3))
registar!("AccNHopf", string(length(res.hopf)))
registar!("AccHopfLast", fmt(res.hopf[end].θ; d = 2))
registar!("AccRealPartStart", fmt(res.parte_real_máx[1]; d = 3))

o = res.órbitas
pontos_po(tipo) = sort([pt.θ for pt in o.pontos if pt.tipo == tipo])
ns, folds, pds = pontos_po(:ns), pontos_po(:bp), pontos_po(:pd)
println("    cycle bifurcations: ", o.pontos)
registar!("AccNSFirst", fmt(ns[1]; d = 3))
registar!("AccNSFurther", join(fmt.(ns[2:end]; d = 2), ", "))
registar!("AccFoldList", isempty(folds) ? "none" : join(fmt.(folds; d = 2), " and "))
# upper turning point of the cycle branch (first decrease of θ along the
# outward leg): a fold of cycles whether or not the step-dependent detector flags it
θ_fora = o.ramos[2].branch.param
k_volta = findfirst(k -> θ_fora[k+1] < θ_fora[k], 1:length(θ_fora)-1)
registar!("AccFoldUpper", isnothing(k_volta) ? "none" : fmt(θ_fora[k_volta]; d = 2))
registar!("AccPDFirst", isempty(pds) ? "none" : fmt(pds[1]; d = 2))
registar!("AccCycleQminEnd", sci(o.quota_mín[end]))
registar!("AccCycleAmpEnd", fmt(o.amplitude[end]; d = 2))
registar!("AccCyclePeriodEnd", fmt(o.período[end]; d = 1))

# Direct simulation on a grid of μ_v: equilibrium, periodic cycle, or
# quasi-periodic / irregular motion (Poincaré-section spread).
grelha = [0.9, 0.95, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45, 1.5, 1.55, 1.6, 1.7, 1.8,
          1.9, 2.0, 2.2, 2.4]
classe(c) = c.n < 2 || c.amplitude < 1e-4 ? :equilíbrio :
            c.dispersão_secção < 0.01 * c.amplitude ? :periódico : :irregular
sims = [ciclo_simulado(p, :μ_v, θ, X0; T = 6000.0) for θ in grelha]
classes = classe.(sims)
for (θ, c, k) in zip(grelha, sims, classes)
    println("    μ_v = $θ: $k, amplitude $(round(c.amplitude, sigdigits = 3)), return times $(c.T_min)–$(c.T_max)")
end
# agreement of simulated periodic cycles with the stable part of the branch
desvios_T, desvios_A = Float64[], Float64[]
for (θ, c, k) in zip(grelha, sims, classes)
    k === :periódico || continue
    cand = findall(i -> o.estável[i], eachindex(o.θ))
    i = cand[argmin(abs.(o.θ[cand] .- θ))]
    abs(o.θ[i] - θ) < 0.02 || continue
    push!(desvios_T, abs(c.T_min - o.período[i]) / o.período[i])
    push!(desvios_A, abs(c.amplitude - o.amplitude[i]) / o.amplitude[i])
end
# periodic simulations with no stable continued cycle nearby (e.g. phase
# locking on the torus beyond a Neimark–Sacker point)
sem_ramo = [θ for (θ, k) in zip(grelha, classes) if k === :periódico &&
            !any(i -> o.estável[i] && abs(o.θ[i] - θ) < 0.02, eachindex(o.θ))]
registar!("AccSimUnmatched", isempty(sem_ramo) ? "none" : join(fmt.(sem_ramo; d = 2), ", "))
k_sm = isempty(sem_ramo) ? nothing : findfirst(==(sem_ramo[1]), grelha)
registar!("AccSimUnmatchedPeriod", isnothing(k_sm) ? "none" : fmt(sims[k_sm].T_min; d = 1))
registar!("AccSimNGrid", string(length(grelha)))
registar!("AccSimNPeriodic", string(count(==(:periódico), classes)))
registar!("AccSimNIrregular", string(count(==(:irregular), classes)))
registar!("AccSimNMatched", string(length(desvios_T)))
registar!("AccSimPeriodDev", fmt(100 * maximum(desvios_T); d = 1))
registar!("AccSimAmpDev", fmt(100 * maximum(desvios_A); d = 1))
registar!("AccSimIrregularFrom", fmt(minimum(θ for (θ, k) in zip(grelha, classes) if k === :irregular); d = 2))
i11 = findfirst(==(1.1), grelha)
registar!("AccSimPeriodOneOne", fmt(sims[i11].T_min; d = 1))

fig10a = plot(res.θ, res.parte_real_máx, lw = 2, color = :black, label = "max Re λ (balanced growth)",
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
for ramo in o.ramos
    b = ramo.branch
    θb, Ab, eb = b.param, b.amplitude, b.stable
    i = 1
    while i < length(θb)
        j = i
        while j < length(θb) && eb[j+1] == eb[i]
            j += 1
        end
        fim = min(j + 1, length(θb))
        plot!(fig10b, θb[i:fim], Ab[i:fim], lw = eb[i] ? 2.5 : 1.5, ls = eb[i] ? :solid : :dash,
              color = :steelblue, label = "")
        i = j + 1
    end
end
plot!(fig10b, [NaN], [NaN], lw = 2.5, color = :steelblue, label = "limit cycle (stable / unstable)")
for (tipo, cor, rótulo) in ((:ns, :darkorange, "Neimark–Sacker"), (:bp, :purple, "fold of cycles"),
                            (:pd, :firebrick, "period doubling"))
    pts = [pt.θ for pt in o.pontos if pt.tipo == tipo]
    isempty(pts) && continue
    ks = [argmin(abs.(o.θ .- θ)) for θ in pts]
    scatter!(fig10b, pts, o.amplitude[ks], color = cor, ms = 6, label = rótulo)
end
for (k, cor, rótulo) in ((:periódico, :seagreen, "simulation: periodic"),
                         (:irregular, :gray, "simulation: quasi-periodic / irregular"),
                         (:equilíbrio, :black, "simulation: equilibrium"))
    ii = findall(==(k), classes)
    isempty(ii) && continue
    scatter!(fig10b, grelha[ii], [sims[i].amplitude for i in ii], marker = :diamond, ms = 5,
             color = cor, label = rótulo)
end
savefig(fig10b, joinpath(FIG_DIR, "fig10b_accumulation_cycles.pdf"))

# ----------------------------------------------------------------------------
# 3 — Wage-share sweep: uniform ω and proportional exploration scale
# ----------------------------------------------------------------------------

println("\n[3/5] Wage-share sweep...")
vu = varrimento_salarial(p_ref, X0; variante = :uniforme)
vp = varrimento_salarial(p_ref, X0; variante = :proporcional)
registar!("AccWageOmegaMin", fmt(first(vu.ω); d = 2))
registar!("AccWageOmegaMax", fmt(last(vu.ω); d = 2))
registar!("AccWageAllStable", string(all(vu.estável) && all(vp.estável)))
registar!("AccWageNPoints", string(length(vu.θ) + length(vp.θ)))
registar!("AccWageGMax", fmt(100 * first(vu.g); d = 0))
registar!("AccWageGMin", fmt(100 * last(vu.g); d = 1))
registar!("AccWageRMax", fmt(100 * first(vu.r); d = 0))
registar!("AccWageRMin", fmt(100 * last(vu.r); d = 1))
registar!("AccWageKMax", fmt(first(vu.k); d = 2))
registar!("AccWageKMin", fmt(last(vu.k); d = 2))
registar!("AccWageReMin", fmt(minimum(vu.parte_real_máx); d = 3))
registar!("AccWageReMax", fmt(maximum(vu.parte_real_máx); d = 3))
i_mon = findfirst(!, vu.oscilatório)
registar!("AccWageMonotoneFrom", isnothing(i_mon) ? "none" : fmt(vu.ω[i_mon]; d = 2))
registar!("AccPropOmegaMin", fmt(minimum(vp.ω); d = 2))
registar!("AccPropOmegaMax", fmt(maximum(vp.ω); d = 2))
# g/r ratio: a Cambridge-type relation g ≈ s·r − δ̄ holds along both sweeps
registar!("AccWageGoverRHi", fmt(first(vu.g) / first(vu.r); d = 2))
registar!("AccWageGoverRLo", fmt(last(vu.g) / last(vu.r); d = 2))

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

println("\n[4/5] Hopf boundary in (ω, μ_v) and in β...")
ch = curva_hopf(p, X0; ω_valores = 0.2:0.05:0.65)
registar!("AccHopfCurveOmegaMin", fmt(first(ch.ω); d = 2))
registar!("AccHopfCurveOmegaMax", fmt(last(ch.ω); d = 2))
registar!("AccHopfCurveMuvMin", fmt(first(ch.μ_v_H); d = 2))
registar!("AccHopfCurveMuvMax", fmt(last(ch.μ_v_H); d = 2))
registar!("AccHopfCurveMonotone", string(issorted(ch.μ_v_H)))
registar!("AccHopfCurveAllSuper", string(all(ch.supercrítico)))
saltos = abs.(diff(ch.frequência))
j = argmax(saltos)
registar!("AccHopfFreqJumpLo", fmt(ch.ω[j]; d = 2))
registar!("AccHopfFreqJumpHi", fmt(ch.ω[j+1]; d = 2))
registar!("AccHopfFreqBefore", fmt(ch.frequência[j]; d = 2))
registar!("AccHopfFreqAfter", fmt(ch.frequência[j+1]; d = 2))

βs = [0.05, 0.1, 0.2, 0.3, 0.5, 1.0]
μvH_β = map(βs) do β
    r = bifurcacao_acumulação(merge(p_ref, (β = β,)), X0, :μ_v; intervalo = (0.0, 4.0), órbitas = false)
    isempty(r.hopf) ? NaN : r.hopf[1].θ
end
println("    μ_v,H(β): ", collect(zip(βs, μvH_β)))
registar!("AccBetaList", join(fmt.(βs; d = 2), ", "))
registar!("AccBetaMuvHList", join([isnan(x) ? "none" : fmt(x; d = 2) for x in μvH_β], ", "))
registar!("AccBetaMuvHDefault", isnan(μvH_β[findfirst(==(p_ref.β), βs)]) ? "none" :
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

println("\n[5/5] Robustness across random economies and TSSI check...")
n_econ = 30
rob = map(1:n_econ) do seed
    Random.seed!(seed)
    N = 3 + seed % 6
    sol_s, _, p_s = simular_Ndept(N, T = 1.0, seed = seed, acoplado = true, μ = 0.5,
                                  preços_mercado = true)
    r = bifurcacao_acumulação(merge(p_s, (β = β_hopf,)), sol_s.u[1], :μ_v; intervalo = (0.0, 4.0),
                              órbitas = false)
    (N = N, estável0 = r.parte_real_máx[1] < 0, tem_hopf = !isempty(r.hopf),
     μ_v_H = isempty(r.hopf) ? NaN : r.hopf[1].θ,
     super = !isempty(r.hopf) && r.hopf[1].supercrítico,
     período = isempty(r.hopf) ? NaN : r.hopf[1].período, quota = minimum(r.quota_mín))
end
μs_H = filter(!isnan, [r.μ_v_H for r in rob])
períodos = filter(!isnan, [r.período for r in rob])
registar!("AccRobN", string(n_econ))
registar!("AccRobNMin", string(minimum(r.N for r in rob)))
registar!("AccRobNMax", string(maximum(r.N for r in rob)))
registar!("AccRobNStable", string(count(r -> r.estável0, rob)))
registar!("AccRobNHopf", string(count(r -> r.tem_hopf, rob)))
registar!("AccRobNSuper", string(count(r -> r.super, rob)))
registar!("AccRobMuvHMin", fmt(minimum(μs_H); d = 2))
registar!("AccRobMuvHMax", fmt(maximum(μs_H); d = 2))
registar!("AccRobMuvHMedian", fmt(median(μs_H); d = 2))
registar!("AccRobPeriodMin", fmt(minimum(períodos); d = 1))
registar!("AccRobPeriodMax", fmt(maximum(períodos); d = 1))
registar!("AccRobQuotaMin", fmt(minimum(r.quota for r in rob); d = 3))

eq = crescimento_equilibrado(p_ref, X0)
s_eq = solve(ODEProblem(sistema_cruzado!, eq.X, (0.0, 30.0), p_ref), Tsit5(),
             abstol = 1e-11, reltol = 1e-11)
v = valorizar_tssi(s_eq, p_ref; τ = 1.0, h = 0.5)
registar!("AccTssiGap", sci(maximum(abs.(v.r_tssi[3:end] .- v.r_simultâneo[3:end]))))
registar!("AccGrowthRef", fmt(100 * eq.g; d = 1))
registar!("AccGrowthSimErr", sci(abs(log(sum(s_eq.u[end][1:12]) / sum(s_eq.u[1][1:12])) / 30 - eq.g) / eq.g))

open(joinpath(FIG_DIR, "acumulacao_stats.tex"), "w") do io
    println(io, "% Generated by paper/acumulacao_bifurcacao.jl — do not edit by hand.")
    for (nome, valor) in macros
        println(io, "\\newcommand{\\$nome}{$valor}")
    end
end

println("\n" * "="^70)
println("Concluído. Figuras fig10a/b, fig11a/b e acumulacao_stats.tex em paper/figures/.")
println("="^70)
