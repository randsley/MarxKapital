# ============================================================================
# Estimating the accumulation parameters on the EU sectoral panel (Section 5.8
# of paper/main.tex): capital mobility with a common reinvestment share, the
# investment function in its linear form (reinvestment elasticity η, mobility
# μ, margin λ), the exit of unprofitable capital, the investment floor θ, the
# mobility of variable capital μ_v and its own-surplus share σ_v; then
# Portugal's market sectors in the cross-dual model at those estimates
# (balanced growth, the Hopf point in μ_v, accumulation at historical cost).
#
# Run with:  julia --project=. paper/estimation.jl
# No network access required: reads the static extract
# data/eurostat_eu_sectors.csv (built by data/build_eurostat_sectors.jl),
# the same data as notebooks 10–14. Writes Table 5, Figure 12 and every
# number quoted in Section 5.8 to paper/figures/estimation_stats.tex (as
# \newcommand macros), so none is typed by hand.
# ============================================================================

ENV["GKSwstype"] = "100"
include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

macros = Pair{String,String}[]
fmt(x; d = 2) = d == 0 ? string(round(Int, x)) : @sprintf("%.*f", d, x)
record!(name, amount) = (push!(macros, name => amount); println("    \\$name = $amount"))

println("\n" * "="^70)
println("Estimating the accumulation parameters on the EU sectoral panel...")
println("="^70)

eu = CSV.read(joinpath(@__DIR__, "..", "data", "eurostat_eu_sectors.csv"), DataFrame)
MARKET = setdiff(sort(String.(unique(eu.section))), NON_MARKET_SECTIONS)
record!("EstSectors", string(length(MARKET)))
record!("EstCountries", string(length(unique(eu.geo))))

# ----------------------------------------------------------------------------
# Samples: baseline and the four robustness variants of notebooks 10–14
# ----------------------------------------------------------------------------
drop_geo(df, g) = df[.!in.(df.geo, Ref(g)), :]
cases = [("Baseline", eu, :excluded, y -> true),
         ("Self-employed imputed", eu, :imputed, y -> true),
         ("Without IE and LU", drop_geo(eu, ["IE", "LU"]), :excluded, y -> true),
         ("Up to 2008", eu, :excluded, y -> y <= 2008),
         ("2009 on", eu, :excluded, y -> y >= 2009)]

rows = map(cases) do (lab, data, se_mode, keep)
    P = compute_mobility_panel(data; sections = MARKET, self_employed = se_mode)
    P = P[keep.(P.year), :]
    m = estimate_mobility(P)
    IP = compute_investment_panel(data; sections = MARKET, self_employed = se_mode)
    IP = IP[keep.(IP.year), :]
    lin = estimate_investment_function(IP; form = :linear)
    fl = estimate_investment_floor(IP)
    LP = compute_labor_panel(data; sections = MARKET, self_employed = se_mode)
    LP = LP[keep.(LP.year), :]
    vg = estimate_variable_mobility(LP; dependent = :vg)
    eg = estimate_variable_mobility(LP; dependent = :eg)
    println("  ✓ $lab")
    (label = lab, m = m, IP = IP, lin = lin, fl = fl, vg = vg, eg = eg)
end
base = rows[1]
u = base.lin.unrestricted
years_used = base.IP.year[base.IP.valid_linear]
record!("EstYearFrom", string(minimum(years_used)))
record!("EstYearTo", string(maximum(years_used)))

# Common reinvestment share (notebook 10)
record!("EstMuCommon", fmt(base.m.μ))
record!("EstMuCommonSe", fmt(base.m.se_cluster))
record!("EstObsCommon", string(base.m.n))

# Linear investment function on every row, losses included (notebook 13)
record!("EstRowsLinear", string(base.lin.n))
record!("EstRowsLoss", string(count(base.IP.valid_linear .& (base.IP.r .<= 0))))
record!("EstLambda", fmt(u.λ; d = 3))
record!("EstLambdaSe", fmt(u.se_λ; d = 3))
record!("EstEta", fmt(u.η))
record!("EstEtaSe", fmt(u.se_η))
record!("EstMu", fmt(u.μ; d = 3))
record!("EstMuSe", fmt(u.se_μ; d = 3))
prof = base.lin.profile
record!("EstMuAtEtaZero", fmt(prof.μ[1]; d = 3))
record!("EstMuAtEtaOne", fmt(prof.μ[end]; d = 3))
record!("EstSsrEtaOne", fmt(100 * (prof.ssr[end] / minimum(prof.ssr) - 1); d = 1))

# Exit of unprofitable capital (losses only) and the investment floor
ex = estimate_investment_function(base.IP; form = :linear, exit_hurdle = 0.0).unrestricted
record!("EstExitPhi", fmt(ex.φ))
record!("EstExitPhiSe", fmt(ex.se_φ))
record!("EstFloor", fmt(base.fl.θ))
record!("EstFloorSe", fmt(base.fl.se))
record!("EstFloorMedian", fmt(base.fl.median_ratio))
θs = [r.fl.θ for r in rows]
record!("EstFloorMin", fmt(minimum(θs)))
record!("EstFloorMax", fmt(maximum(θs)))

# Mobility of variable capital and the own-surplus share σ_v (notebook 14)
record!("EstMuV", fmt(base.vg.μ_v; d = 3))
record!("EstMuVSe", fmt(base.vg.se_cluster; d = 3))
record!("EstMuVEmp", fmt(base.eg.μ_v; d = 3))
record!("EstMuVEmpSe", fmt(base.eg.se_cluster; d = 3))
σvs = [r.vg.λ_v for r in rows]
record!("EstSigmaVMin", fmt(minimum(σvs); d = 3))
record!("EstSigmaVMax", fmt(maximum(σvs); d = 3))
μvs_all = [x for r in rows for x in (r.vg.μ_v, r.eg.μ_v)]
record!("EstMuVMin", fmt(minimum(μvs_all); d = 3))
record!("EstMuVMax", fmt(maximum(μvs_all); d = 3))
μv_upper = maximum(r.vg.μ_v + 2r.vg.se_cluster for r in rows)
record!("EstMuVUpper", fmt(μv_upper))

# Average or incremental rates of profit (Shaikh 2016, ch. 7; notebook 12)
println("\nIncremental rates of profit...")
"""Rows whose incremental gap is inside its 1st–99th percentiles."""
trim_I(P) = (b = quantile(P.gap_I, [0.01, 0.99]); P[b[1] .<= P.gap_I .<= b[2], :])
"""Dispersion of the country × sector long-run mean gaps, net of sampling noise."""
function permanent_sd(P, col)
    m = combine(groupby(P, [:geo, :section]), col => mean => :m, col => var => :v, nrow => :T)
    m = m[m.T .>= 2, :]
    sqrt(max(var(m.m) - mean(m.v ./ m.T), 0.0))
end
P1 = compute_incremental_panel(eu; sections = MARKET).panel
P3 = compute_incremental_panel(eu; sections = MARKET, window = 3).panel
pers = [(estimate_persistence(Q, :gap), estimate_persistence(Q, :gap_I), Q)
        for P in (P1, P3) for Q in (P, trim_I(P))]
rng(v; d = 2) = fmt(minimum(v); d = d) * "--" * fmt(maximum(v); d = d)
record!("IncBetweenAvg", rng([a.between_share for (a, _, _) in pers]))
record!("IncBetweenInc", rng([b.between_share for (_, b, _) in pers]))
record!("IncRhoOneYear", fmt(pers[1][2].ρ))
trimmed = pers[[2, 4]]
record!("IncPermAvg", rng([permanent_sd(Q, :gap) for (_, _, Q) in trimmed]; d = 0))
record!("IncPermInc", rng([permanent_sd(Q, :gap_I) for (_, _, Q) in trimmed]; d = 0))
# horse race in the investment function at η = 1, on notebook 11's sample (r/r̄ ∈ [1/3, 3])
J = innerjoin(trim_I(P3), select(base.IP, :geo, :section, :year, :gk, :sk, :rbar, :σbar, :valid);
              on = [:geo, :section, :year])
J = J[J.valid .& (1/3 .<= J.r ./ J.rbar .<= 3), :]
own = J.σbar .* (J.rbar ./ J.r) .* J.sk
fa = estimate_fe_ols(J, J.gk, hcat(own, J.gap))
fb = estimate_fe_ols(J, J.gk, hcat(own, J.gap, J.gap_I))
record!("IncRows", string(nrow(J)))
record!("IncMuAvg", fmt(fa.β[2]; d = 3))
record!("IncMuAvgSe", fmt(fa.se_cluster[2]; d = 3))
record!("IncBothAvg", fmt(fb.β[2]; d = 3))
record!("IncBothInc", fmt(fb.β[3]; d = 4))
record!("IncBothIncSe", fmt(fb.se_cluster[3]; d = 4))

# Table 5
cell(b, se; d = 3) = @sprintf("\\(%.*f\\) (%.*f)", d, b, d, se)   # math mode: a real minus sign
open(joinpath(FIG_DIR, "table5_estimates.tex"), "w") do io
    println(io, "\\begin{tabular}{lrrrrrrr}")
    println(io, "\\toprule")
    println(io, " & \\multicolumn{1}{c}{common \\(\\sigma\\)} & \\multicolumn{3}{c}{investment function, linear form} & " *
                "floor & \\multicolumn{2}{c}{variable capital} \\\\")
    println(io, "\\cmidrule(lr){2-2}\\cmidrule(lr){3-5}\\cmidrule(lr){6-6}\\cmidrule(lr){7-8}")
    println(io, "Sample & \\(\\mu\\) & \\(\\lambda\\) & \\(\\eta\\) & \\(\\mu\\) & \\(\\theta\\) & " *
                "\\(\\mu_v\\) (wages) & \\(\\mu_v\\) (empl.) \\\\")
    println(io, "\\midrule")
    for r in rows
        v = r.lin.unrestricted
        println(io, join([r.label, cell(r.m.μ, r.m.se_cluster), cell(v.λ, v.se_λ), cell(v.η, v.se_η; d = 2),
                          cell(v.μ, v.se_μ), cell(r.fl.θ, r.fl.se; d = 2), cell(r.vg.μ_v, r.vg.se_cluster),
                          cell(r.eg.μ_v, r.eg.se_cluster)], " & "), " \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
println("  ✓ Table 5 written")

# ----------------------------------------------------------------------------
# Portugal's market sectors, 2019, in the cross-dual model at the estimates
# ----------------------------------------------------------------------------
println("\nPortugal's market sectors in the cross-dual model...")
P19 = eu[(eu.geo .== "PT") .& (eu.year .== 2019), :]
IPb = base.IP
σbar_pt = Dict(zip(IPb.section[IPb.geo .== "PT"], IPb.σbar[IPb.geo .== "PT"]))
depts = map(MARKET) do s
    row = P19[P19.section .== s, :][1, :]
    S = row.GVA - row.compensation - row.CFC
    Department(String(s); c = row.capital_stock, v = row.compensation, e = max(S / row.compensation, 0.1),
               σ_c = min(σbar_pt[s], 0.85), σ_v = 0.1, δ = row.CFC / row.capital_stock)
end
N = length(depts)
η̂, μ̂ = round(u.η, digits = 2), round(u.μ, digits = 2)
record!("EstPTYear", "2019")
record!("EstPTEta", fmt(η̂))
record!("EstPTMu", fmt(μ̂))
sol0, _, p = simulate_Ndept_custom(deepcopy(depts); T = 1.0, seed = 1, coupled = true, market_prices = true,
                                   reinvestment_form = :linear, η = η̂, μ = μ̂)

# Balanced growth continued in μ_v (each point from the previous one)
μv_grid = [0.0:0.05:0.5; 0.6:0.1:3.0]
Xstart = Ref(sol0.u[1])
sweep = map(enumerate(μv_grid)) do (k, m)
    q = with_parameter(p, :μ_v, m)
    eq = redirect_stdout(devnull) do
        balanced_growth(q, Xstart[]; T_warmup = k == 1 ? 400.0 : 0.0)
    end
    eq.converged || (eq = redirect_stdout(devnull) do
        balanced_growth(q, sol0.u[1])
    end)
    eq.converged && (Xstart[] = eq.X)
    dom = eq.eigenvalues[argmax(real.(eq.eigenvalues))]
    (μ_v = m, converged = eq.converged, max_re = real(dom), freq = abs(imag(dom)), g = eq.g)
end |> DataFrame
k = findfirst(i -> sweep.converged[i] && sweep.max_re[i] >= 0, 1:nrow(sweep))
isnothing(k) && error("no loss of stability on the μ_v grid; the text of Section 5.8 assumes one")
hopf = sweep.μ_v[k-1] - sweep.max_re[k-1] * (sweep.μ_v[k] - sweep.μ_v[k-1]) / (sweep.max_re[k] - sweep.max_re[k-1])
record!("EstHopfMuV", fmt(hopf))
record!("EstHopfRatio", fmt(hopf / base.vg.μ_v; d = 0))
record!("EstHopfPeriod", fmt(2π / sweep.freq[k]; d = 0))
# at the estimate: the nearest grid point at or above μ̂_v
i_est = findfirst(>=(base.vg.μ_v), sweep.μ_v)
record!("EstStableMaxRe", fmt(sweep.max_re[i_est]; d = 3))
record!("EstStableMaxReZero", fmt(sweep.max_re[1]; d = 3))
record!("EstStablePeriod", fmt(2π / sweep.freq[i_est]; d = 0))

ok = sweep.converged
plt = plot(sweep.μ_v[ok], sweep.max_re[ok]; lw = 2.5, marker = :circle, ms = 3, legend = :topleft,
           label = "largest real part of the eigenvalues", xlabel = "mobility of variable capital μᵥ",
           ylabel = "per year", size = (640, 380))
hline!(plt, [0]; color = :gray, label = "")
vspan!(plt, [base.vg.μ_v - 2base.vg.se_cluster, base.vg.μ_v + 2base.vg.se_cluster]; alpha = 0.25,
       color = :green, label = "estimated μᵥ ± 2 se")
vline!(plt, [hopf]; color = :red, ls = :dash, label = "Hopf point")
savefig(plt, joinpath(FIG_DIR, "fig12_mu_v_hopf.pdf"))
println("  ✓ Figure 12 written")

# Accumulation at historical cost (TSSI-driven dynamics) against current prices
function dispersion(X, q)
    C, V = X[1:N], X[N+1:2N]
    B = _tssi_on(q) ? _book(X, q) : nothing
    ec = cross_dual_state(C, V, X[2N+1:3N], q; B = B)
    K = isnothing(B) ? C .+ V : B .+ V
    r̄ = sum(ec.r .* K) / sum(K)
    sqrt(sum(K .* (ec.r .- r̄) .^ 2) / sum(K))
end
_, _, pt = simulate_Ndept_custom(deepcopy(depts); T = 1.0, seed = 1, coupled = true, market_prices = true,
                                 reinvestment_form = :linear, η = η̂, μ = μ̂, tssi_dynamics = true)
eq_cur = redirect_stdout(devnull) do
    balanced_growth(p, sol0.u[1])
end
eq_tssi = redirect_stdout(devnull) do
    balanced_growth(pt, [sol0.u[1]; sol0.u[1][1:N]])
end
(eq_cur.converged && eq_tssi.converged) || error("balanced growth did not converge")
record!("EstGrowthCurrent", fmt(100eq_cur.g))
record!("EstGrowthTSSI", fmt(100eq_tssi.g))
record!("EstMaxReCurrent", fmt(maximum(real.(eq_cur.eigenvalues)); d = 4))
record!("EstMaxReTSSI", fmt(maximum(real.(eq_tssi.eigenvalues)); d = 4))
record!("EstStableBoth", eq_cur.stable && eq_tssi.stable ? "stable" : "not stable")
record!("EstDispCurrent", fmt(dispersion(eq_cur.X, p); d = 3))
record!("EstDispTSSI", fmt(dispersion(eq_tssi.X, pt); d = 3))
bc = _book(eq_tssi.X, pt) ./ eq_tssi.X[1:N]
record!("EstBookMin", fmt(minimum(bc)))
record!("EstBookMinSector", MARKET[argmin(bc)])
record!("EstBookMax", fmt(maximum(bc)))
record!("EstBookMaxSector", MARKET[argmax(bc)])

open(joinpath(FIG_DIR, "estimation_stats.tex"), "w") do io
    println(io, "% Generated by paper/estimation.jl — do not edit by hand.")
    for (name, amount) in macros
        println(io, "\\newcommand{\\$name}{$amount}")
    end
end
println("\nDone: $(length(macros)) macros in paper/figures/estimation_stats.tex")
