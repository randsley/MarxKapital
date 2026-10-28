# ============================================================================
# Exact (automatic-differentiation) Jacobian of the rationing map, bifurcation
# analysis of the damped iteration and of the TSSI price map (fixed lag τ),
# and the TSSI vs. simultaneist profit rate along simulated trajectories.
#
# Run with:  julia --project=. paper/jacobiana_bifurcacao.jl
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
registar!(nome, valor) = (push!(macros, nome => valor); println("    \\$nome = $valor"))

println("\n" * "="^70)
println("Jacobian, bifurcation and TSSI analysis...")
println("="^70)

# ----------------------------------------------------------------------------
# 1 — Exact Jacobian of the rationing map across the Monte Carlo design of
#     paper/monte_carlo.jl (same seeds, same economies)
# ----------------------------------------------------------------------------

println("\n[1/3] Rationing-map Jacobian sweep...")

Ns = [6, 12, 19]
densidades = [0.2, 0.4, 0.6]
trials_por_combinação = 30
tol_iter = 1e-8   # default tolerance of _resolver_racionamento

resultados = NamedTuple[]
for N in Ns, densidade in densidades, trial in 1:trials_por_combinação
    seed = 1000 * N + round(Int, 1000 * densidade) + trial
    Random.seed!(seed)
    A = criar_matriz_tecnica(N, densidade = densidade, seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    escala_O = 0.1 + rand() * 0.8
    O = escala_O .* (0.5 .+ rand(N))
    dg = _resolver_racionamento(A, σ_c, S, O; devolver_diagnóstico = true)
    dg05 = _resolver_racionamento(A, σ_c, S, O; relaxação = 0.5, devolver_diagnóstico = true)
    jr = jacobiana_racionamento(A, σ_c, S, O)
    λs = jr.valores_próprios
    k = argmin(jr.ρ)
    # Triangularity: ordering sectors by ρ* ascending, J_ik ≠ 0 only if ρ_k ≤ ρ_i.
    ordem = sortperm(jr.ρ)
    Jo = jr.J[ordem, ordem]
    triangular = maximum(abs.([Jo[i, j] for i in 1:N, j in 1:N if j > i]); init = 0.0) < 1e-10
    diagonal = sort(real.(λs)) ≈ sort(diag(jr.J))
    push!(resultados, (N = N, racionado = any(jr.ρ .< 1 - 1e-9),
                       triangular = triangular, diagonal = diagonal,
                       tem_zero = minimum(abs.(λs)) < 1e-8,
                       antítona = jr.antítona,
                       tem_menos_um = minimum(abs.(λs .+ 1)) < 1e-8,
                       linha_k = maximum(abs.(jr.J[k, :] .+ [i == k ? 1.0 : 0.0 for i in 1:N])) < 1e-8,
                       λ_min = minimum(real.(λs)), imag_max = maximum(abs.(imag.(λs))),
                       α_max = jr.α_max, α_ótimo = jr.α_ótimo,
                       raio_padrão = jr.raio_espectral,
                       raio_05 = raio_espectral_amortecido(λs, 0.5),
                       raio_ótimo = raio_espectral_amortecido(λs, jr.α_ótimo),
                       iterações = dg.iterações, convergiu = dg.convergiu,
                       iterações_05 = dg05.iterações, convergiu_05 = dg05.convergiu))
end

rac = filter(r -> r.racionado, resultados)
n_total, n_rac = length(resultados), length(rac)
registar!("JacNTrials", string(n_total))
registar!("JacNRationed", string(n_rac))
registar!("JacNAntitone", string(count(r -> r.antítona, rac)))
registar!("JacNMinusOne", string(count(r -> r.tem_menos_um && r.linha_k, rac)))
registar!("JacNComplex", string(count(r -> r.imag_max > 1e-8, rac)))
registar!("JacLambdaMin", fmt(minimum(r.λ_min for r in rac); d = 3))
registar!("JacNAlphaMaxOne", string(count(r -> abs(r.α_max - 1) < 1e-8, rac)))
registar!("JacAlphaMaxMin", fmt(minimum(r.α_max for r in rac); d = 3))
registar!("JacNDefaultStable", string(count(r -> r.raio_padrão < 1, rac)))
registar!("JacRadiusDefaultMax", fmt(maximum(r.raio_padrão for r in rac); d = 3))
registar!("JacRadiusHalfMax", fmt(maximum(r.raio_05 for r in rac); d = 3))
registar!("JacAlphaOptMean", fmt(mean(r.α_ótimo for r in rac); d = 3))
registar!("JacAlphaOptMin", fmt(minimum(r.α_ótimo for r in rac); d = 3))
registar!("JacAlphaOptMax", fmt(maximum(r.α_ótimo for r in rac); d = 3))

registar!("JacNTriangular", string(count(r -> r.triangular && r.diagonal, rac)))
registar!("JacNZero", string(count(r -> r.tem_zero, rac)))

# Linear-convergence prediction: the error contracts by the spectral radius
# per step, so reaching the step tolerance takes ≈ log(tol)/log(raio)
# iterations from an O(1) initial error. Checked at the default relaxation
# (2/3, radius 1/3) and at the previous default 0.5 (radius 1/2).
conv = filter(r -> r.convergiu && r.convergiu_05, rac)
observadas = [r.iterações for r in conv]
observadas_05 = [r.iterações_05 for r in conv]
previstas_padrão = log(tol_iter) / log(maximum(r.raio_padrão for r in conv))
previstas_05 = log(tol_iter) / log(maximum(r.raio_05 for r in conv))
registar!("JacItersObsMean", fmt(mean(observadas); d = 1))
registar!("JacItersObsMax", string(maximum(observadas)))
registar!("JacItersPredDefault", fmt(previstas_padrão; d = 1))
registar!("JacItersObsHalfMean", fmt(mean(observadas_05); d = 1))
registar!("JacItersObsHalfMax", string(maximum(observadas_05)))
registar!("JacItersPredHalf", fmt(previstas_05; d = 1))
registar!("JacItersSavingPct", string(round(Int, 100 * (1 - mean(observadas) / mean(observadas_05)))))

fig7a = histogram([r.λ_min for r in rac], bins = 30, xlabel = "Most negative eigenvalue of ∂F/∂ρ at ρ*",
                  ylabel = "Count", title = "Spectrum of the rationing map",
                  legend = false, color = :steelblue, size = (650, 420), margin = 5Plots.mm)
vline!(fig7a, [-1.0], ls = :dash, color = :black)
savefig(fig7a, joinpath(FIG_DIR, "fig7a_rationing_spectrum.pdf"))

bins_it = 0.5:1:(max(maximum(observadas), maximum(observadas_05)) + 0.5)   # shared integer bins
fig7b = histogram(observadas_05, bins = bins_it, xlabel = "Iterations to converge (tol = 1e-8)",
                  ylabel = "Count", title = "Observed vs. predicted iterations",
                  label = "observed, α = 0.5", color = :steelblue, alpha = 0.6,
                  size = (650, 420), margin = 5Plots.mm)
histogram!(fig7b, observadas, bins = bins_it, label = "observed, α = 2/3 (default)",
           color = :firebrick, alpha = 0.6)
vline!(fig7b, [previstas_05], lw = 2.5, ls = :dash, color = :steelblue,
       label = "log(tol)/log(1/2)")
vline!(fig7b, [previstas_padrão], lw = 2.5, ls = :dash, color = :firebrick,
       label = "log(tol)/log(1/3)")
savefig(fig7b, joinpath(FIG_DIR, "fig7b_predicted_iterations.pdf"))

# ----------------------------------------------------------------------------
# 1b — Choice of the default relaxation: convergence and speed across α, on
#      the sweep above, from random initial ρ, and under much scarcer supply
# ----------------------------------------------------------------------------

println("\n[1b/3] Relaxation comparison...")

casos = NamedTuple[]
for N in Ns, densidade in densidades, trial in 1:trials_por_combinação
    seed = 1000 * N + round(Int, 1000 * densidade) + trial
    Random.seed!(seed)
    A = criar_matriz_tecnica(N, densidade = densidade, seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    O = (0.1 + rand() * 0.8) .* (0.5 .+ rand(N))
    push!(casos, (A = A, σ_c = σ_c, S = S, O = O))
end
escassos = NamedTuple[]
for k in 1:200
    seed = 50_000 + k
    Random.seed!(seed)
    N = rand([6, 12, 19, 30])
    A = criar_matriz_tecnica(N, densidade = rand([0.2, 0.4, 0.6, 0.8]), seed = seed)
    σ_c = 0.3 .+ rand(N) * 0.4
    S = 5.0 .+ 15 * rand(N)
    O = (0.01 + rand() * 0.2) .* (0.5 .+ rand(N))   # far scarcer supply than the sweep
    push!(escassos, (A = A, σ_c = σ_c, S = S, O = O))
end

function correr(cs, iniciais, α)
    its = Int[]; n = 0
    for c in cs, ρ0 in iniciais(length(c.S))
        n += 1
        d = _resolver_racionamento(c.A, c.σ_c, c.S, c.O; relaxação = α, ρ_inicial = ρ0,
                                   max_iter = 2000, devolver_diagnóstico = true)
        d.convergiu && push!(its, d.iterações)
    end
    return (conv = length(its), total = n, média = mean(its), máx = maximum(its))
end

αs = [0.4, 0.5, 0.6, 2 / 3, 0.75, 0.85, 0.95]
n_inícios = 20
linhas = String[]
n_execuções = 0
falhas = 0
for α in αs
    Random.seed!(1)
    a = correr(casos, N -> [nothing], α)
    b = correr(casos, N -> [0.01 .+ 0.99 .* rand(N) for _ in 1:n_inícios], α)
    c = correr(escassos, N -> [nothing; [0.01 .+ 0.99 .* rand(N) for _ in 1:5]], α)
    global n_execuções = a.total + b.total + c.total
    global falhas += (a.total - a.conv) + (b.total - b.conv) + (c.total - c.conv)
    rótulo = α ≈ 2 / 3 ? "\\textbf{2/3} (default)" : α == 0.5 ? "0.5 (previous)" : string(α)
    push!(linhas, "$rótulo & $(fmt(a.média; d = 1)) & $(a.máx) & $(fmt(b.média; d = 1)) & $(b.máx) & " *
                  "$(fmt(c.média; d = 1)) & $(c.máx) \\\\")
    println("    α=$(round(α, digits = 3)): sweep $(a.conv)/$(a.total) mean $(fmt(a.média; d = 1)); ",
            "random ρ0 $(b.conv)/$(b.total); scarce $(c.conv)/$(c.total)")
end
# The fixed point does not depend on α: rationing factors along the Figure 4
# trajectory (paper/gerar_resultados.jl: N=6, seed 5, μ=0.5, racionamento)
# computed with the new and previous defaults.
Random.seed!(5)
sol4, _, p4 = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5, racionamento = true)
dif_κ = 0.0
for X in sol4.u
    C, V = X[1:6], X[7:12]
    S4 = p4.e .* V
    x4 = (p4.δ .* C .+ V .+ S4) ./ (1 .- vec(sum(p4.A, dims = 1)))
    Δx4 = p4.σ_c .* S4 .* x4 ./ C
    global dif_κ = max(dif_κ, maximum(abs.(_resolver_racionamento(p4.A, ones(6), Δx4, x4) .-
                                          _resolver_racionamento(p4.A, ones(6), Δx4, x4; relaxação = 0.5))))
end
registar!("RelaxFigFourDiff", sci(dif_κ))
registar!("RelaxNRuns", string(n_execuções))
registar!("RelaxNFailures", string(falhas))
registar!("RelaxNScarce", string(length(escassos)))
registar!("RelaxNStarts", string(n_inícios))

open(joinpath(FIG_DIR, "table2_relaxation.tex"), "w") do io
    println(io, "% Generated by paper/jacobiana_bifurcacao.jl — do not edit by hand.")
    println(io, "\\begin{tabular}{lrrrrrr}")
    println(io, "\\toprule")
    println(io, " & \\multicolumn{2}{c}{Sweep (\\(\\rho_0=1\\))} & \\multicolumn{2}{c}{Random \\(\\rho_0\\)} & \\multicolumn{2}{c}{Scarce supply} \\\\")
    println(io, "\\(\\alpha\\) & mean & max & mean & max & mean & max \\\\")
    println(io, "\\midrule")
    foreach(l -> println(io, l), linhas)
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end

# ----------------------------------------------------------------------------
# 2 — Bifurcation diagram of the damped iteration in the demand scale s
# ----------------------------------------------------------------------------

println("\n[2/3] Bifurcation diagram of the damped rationing iteration...")

Random.seed!(11)
N = 12
A = criar_matriz_tecnica(N, densidade = 0.5)
σ_c = fill(0.5, N)
S = 5.0 .+ 10 * rand(N)
O = 0.3 .+ rand(N) * 0.5
s_c = minimum(O ./ (A * (σ_c .* S)))
br = bifurcacao_racionamento(A, σ_c, S, O; escala = (0.005, 2.0))   # default α = 2/3
br_flip = bifurcacao_racionamento(A, σ_c, S, O; escala = (0.005, 2.0), relaxação = 1.1)
registar!("BifSc", fmt(s_c; d = 3))
registar!("BifNPointsDefault", string(length(br.pontos)))
registar!("BifFlipS", fmt(br_flip.pontos[1].θ; d = 3))
registar!("BifFlipType", string(br_flip.pontos[1].tipo))

# α_max and the rationed fraction are piecewise constant in s and jump at the
# border-collision point s_c; draw them as steps with the jump placed at the
# analytic s_c rather than interpolated between continuation steps.
antes = br.θ .< s_c
xs = [br.θ[antes]; s_c; s_c; br.θ[.!antes]]
α_plot = [br.α_max[antes]; br.α_max[findlast(antes)]; br.α_max[findfirst(.!antes)]; br.α_max[.!antes]]
frac_plot = [br.fração_racionada[antes]; 0.0; br.fração_racionada[findfirst(.!antes)];
             br.fração_racionada[.!antes]]
fig8 = plot(xs, α_plot, lw = 2.5, color = :black, label = "α_max(s): flip boundary",
            seriestype = :steppost, xlabel = "Demand scale s", ylabel = "Relaxation α",
            title = "Local stability of the damped rationing iteration",
            ylims = (0, 2.2), size = (700, 450), margin = 5Plots.mm, legend = :topright)
plot!(fig8, xs, α_plot, seriestype = :steppost, fillrange = 0, fillalpha = 0.12, lw = 0,
      color = :seagreen, label = "convergent")
hline!(fig8, [RELAXAÇÃO_PADRÃO], ls = :dash, color = :steelblue, label = "default α = 2/3")
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
sol, _, p = simular_Ndept(6, T = 100.0, seed = 5, acoplado = true, μ = 0.5, realização = true)
τs = [0.5, 1.0, 2.0, 5.0]
fig9a = plot(xlabel = "Time", ylabel = "r_TSSI − r_simultaneist (p.p.)",
             title = "TSSI vs. simultaneist profit rate", size = (700, 450), margin = 5Plots.mm)
erros = Float64[]
gap_final = Float64[]
for τ in τs
    v = valorizar_tssi(sol, p; τ = τ, h = 0.5)
    push!(erros, v.erro_invariantes)
    push!(gap_final, 100 * (v.r_tssi[end] - v.r_simultâneo[end]))
    plot!(fig9a, v.t, 100 .* (v.r_tssi .- v.r_simultâneo), lw = 2, label = "τ = $τ")
end
hline!(fig9a, [0.0], color = :black, ls = :dash, label = "")
savefig(fig9a, joinpath(FIG_DIR, "fig9a_tssi_gap.pdf"))
registar!("TssiInvErr", sci(maximum(erros)))
registar!("TssiGapTauOne", fmt(gap_final[2]; d = 3))
registar!("TssiGapTauFive", fmt(gap_final[4]; d = 3))

n_econ = 50
raios = Float64[]
raios_max_θ = Float64[]
n_pontos_tssi = 0
for seed in 1:n_econ
    Random.seed!(seed)
    sol_s, _, p_s = simular_Ndept(6, T = 60.0, seed = seed, acoplado = true, μ = 0.5,
                                  realização = true)
    push!(raios, estabilidade_tssi(dados_tssi(sol_s.u[end], p_s)).raio_espectral)
    bt = bifurcacao_tssi(sol_s.u[end], p_s; τ = 1.0, escala = (0.05, 10.0))
    push!(raios_max_θ, maximum(bt.raio))
    global n_pontos_tssi += length(bt.pontos)
end
registar!("TssiNEcon", string(n_econ))
registar!("TssiRadiusMean", fmt(mean(raios); d = 3))
registar!("TssiRadiusMax", fmt(maximum(raios); d = 3))
registar!("TssiRadiusThetaMax", fmt(maximum(raios_max_θ); d = 3))
registar!("TssiNBifPoints", string(n_pontos_tssi))
registar!("TssiHalfLifeTauOne", fmt(log(2) / -log(mean(raios)); d = 2))

fig9b = histogram(raios, bins = 15, xlabel = "Spectral radius of ∂p(t)/∂p(t−τ) at p*",
                  ylabel = "Count", title = "TSSI price map: local stability ($n_econ economies)",
                  legend = false, color = :seagreen, size = (650, 420), margin = 5Plots.mm)
savefig(fig9b, joinpath(FIG_DIR, "fig9b_tssi_stability.pdf"))

open(joinpath(FIG_DIR, "jacobian_stats.tex"), "w") do io
    println(io, "% Generated by paper/jacobiana_bifurcacao.jl — do not edit by hand.")
    for (nome, valor) in macros
        println(io, "\\newcommand{\\$nome}{$valor}")
    end
end

println("\n" * "="^70)
println("Concluído. Figuras fig7a/b, fig8, fig9a/b e jacobian_stats.tex em paper/figures/.")
println("="^70)
