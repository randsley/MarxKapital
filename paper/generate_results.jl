# ============================================================================
# Generates every figure and table used in paper/main.tex, from real data.
#
# Run with:  julia --project=. paper/generate_results.jl
#
# Requires network access (Eurostat + AMECO SDMX APIs). No numbers in the
# paper are hand-entered — this script is the single source of truth for
# every reported figure/table.
# ============================================================================

ENV["GKSwstype"] = "100"

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf, Statistics

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

println("\n" * "="^70)
println("Generating results for paper/main.tex...")
println("="^70)

# ----------------------------------------------------------------------------
# Figure 1 — aggregate profit-rate trend, Portugal, 1996-2022 (real AMECO data)
# ----------------------------------------------------------------------------

println("\n[1/6] Time series (e, k, r), Portugal 1996-2022, two valuation conventions...")
years = 1996:2022
data_pt = fetch_ameco_data("Portugal", years = years, method = :sdmx)
st_current    = analyze_time_series_with_data(data_pt; valuation = :current)
st_consistent = analyze_time_series_with_data(data_pt; valuation = :consistent)

p1 = plot(years, st_current.e, xlabel = "Year", ylabel = "e", title = "Rate of exploitation",
          label = "current-price V, GVA", lw = 2, color = :steelblue)
plot!(p1, years, st_consistent.e, label = "deflated V, GVA", lw = 2, color = :steelblue,
      linestyle = :dash)
p2 = plot(years, st_current.k, xlabel = "Year", ylabel = "k", title = "Organic composition",
          label = "current-price V, GVA", lw = 2, color = :firebrick)
plot!(p2, years, st_consistent.k, label = "deflated V, GVA", lw = 2, color = :firebrick,
      linestyle = :dash)
p3 = plot(years, st_current.r .* 100, xlabel = "Year", ylabel = "r (%)", title = "Profit rate",
          label = "current-price V, GVA", lw = 2, color = :seagreen)
plot!(p3, years, st_consistent.r .* 100, label = "deflated V, GVA", lw = 2, color = :seagreen,
      linestyle = :dash)
fig1 = plot(p1, p2, p3, layout = (1, 3), size = (1350, 380), margin = 6Plots.mm,
            legend = :outerbottom, legendcolumns = 2)
savefig(fig1, joinpath(FIG_DIR, "fig1_time_series.pdf"))
println("  ✓ [corrente]    e: $(round(st_current.e[1],digits=3)) -> $(round(st_current.e[end],digits=3))  ",
        "k: $(round(st_current.k[1],digits=2)) -> $(round(st_current.k[end],digits=2))  ",
        "r: $(round(st_current.r[1]*100,digits=2))% -> $(round(st_current.r[end]*100,digits=2))%")
println("  ✓ [consistent] e: $(round(st_consistent.e[1],digits=3)) -> $(round(st_consistent.e[end],digits=3))  ",
        "k: $(round(st_consistent.k[1],digits=2)) -> $(round(st_consistent.k[end],digits=2))  ",
        "r: $(round(st_consistent.r[1]*100,digits=2))% -> $(round(st_consistent.r[end]*100,digits=2))%")

println("\n[1b/6] Portugal vs. Spain, consistent valuation...")
data_es = fetch_ameco_data("Spain", years = years, method = :sdmx)
st_es = analyze_time_series_with_data(data_es; valuation = :consistent)
fig1b = plot(years, st_consistent.r .* 100, xlabel = "Year", ylabel = "r (%)",
             title = "Profit rate, consistent valuation: Portugal vs. Spain",
             label = "Portugal", lw = 2, color = :seagreen, size = (700, 420), margin = 5Plots.mm)
plot!(fig1b, years, st_es.r .* 100, label = "Spain", lw = 2, color = :darkorange)
savefig(fig1b, joinpath(FIG_DIR, "fig1b_pt_vs_es.pdf"))
println("  ✓ Spain [consistent] e: $(round(st_es.e[1],digits=3)) -> $(round(st_es.e[end],digits=3))  ",
        "k: $(round(st_es.k[1],digits=2)) -> $(round(st_es.k[end],digits=2))  ",
        "r: $(round(st_es.r[1]*100,digits=2))% -> $(round(st_es.r[end]*100,digits=2))%")

println("\n[1c/6] Robustness: GDP deflator vs. investment-goods deflator, Portugal...")
st_gfcf = analyze_time_series_with_data(data_pt; valuation = :consistent_gfcf)
println("  ✓ [consistente_fbcf] e: $(round(st_gfcf.e[1],digits=3)) -> $(round(st_gfcf.e[end],digits=3))  ",
        "k: $(round(st_gfcf.k[1],digits=2)) -> $(round(st_gfcf.k[end],digits=2))  ",
        "r: $(round(st_gfcf.r[1]*100,digits=2))% -> $(round(st_gfcf.r[end]*100,digits=2))%")

# ----------------------------------------------------------------------------
# Table 1 — 19-sector calibration profile, Portugal 2022 (real Eurostat data)
# ----------------------------------------------------------------------------

println("\n[2/6] 19-sector calibration, Portugal 2022...")
params = calibrate_portugal_model(year = 2022, data_source = :eurostat)

open(joinpath(FIG_DIR, "table1_sectors.tex"), "w") do io
    println(io, "\\begin{tabular}{llrrrr}")
    println(io, "\\toprule")
    println(io, "Code & Sector & GVA (\\texteuro bn) & \$e\$ & \$k\$ & \$r\$ (\\%) \\\\")
    println(io, "\\midrule")
    ord = sortperm(params.r, rev = true)
    for i in ord
        name = params.sector_names[i]
        gva_i = round(params.GVA[i] / 1000, digits = 1)
        println(io, "$(params.nace_codes[i]) & $name & $gva_i & " *
                    "$(round(params.e[i], digits = 2)) & $(round(params.k[i], digits = 2)) & " *
                    "$(round(params.r[i] * 100, digits = 2)) \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
w = params.GVA ./ sum(params.GVA)
S_sectoral = params.e .* params.V
r_aggregate = sum(S_sectoral) / sum(params.C .+ params.V)

# Table 3 — sectors at the e = 0.1 floor: raw (business income after CFC over
# compensation) vs. imposed values, and the floor's effect on the aggregate rate
floored = findall(params.e_raw .< params.e)
r_aggregate_raw = sum(params.e_raw .* params.V) / sum(params.C .+ params.V)
open(joinpath(FIG_DIR, "table3_floor.tex"), "w") do io
    println(io, "\\begin{tabular}{llrrrr}")
    println(io, "\\toprule")
    println(io, "Code & Sector & raw \$e\$ & imposed \$e\$ & raw \$r\$ (\\%) & imposed \$r\$ (\\%) \\\\")
    println(io, "\\midrule")
    for i in floored[sortperm(params.e_raw[floored])]
        @printf(io, "%s & %s & %.3f & %.2f & %.2f & %.2f \\\\\n", params.nace_codes[i],
                params.sector_names[i], params.e_raw[i], params.e[i],
                params.e_raw[i] / (params.k[i] + 1) * 100, params.r[i] * 100)
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
open(joinpath(FIG_DIR, "floor_stats.tex"), "w") do io
    println(io, "% Generated by paper/generate_results.jl — do not edit by hand.")
    println(io, "\\newcommand{\\FloorN}{$(length(floored))}")
    println(io, "\\newcommand{\\FloorSectors}{$(params.N)}")
    @printf(io, "\\newcommand{\\FloorAggR}{%.2f}\n", r_aggregate * 100)
    @printf(io, "\\newcommand{\\FloorAggRRaw}{%.2f}\n", r_aggregate_raw * 100)
end
println("  ✓ $(length(floored))/$(params.N) sectors at the e floor; aggregate r ",
        "$(round(r_aggregate*100, digits=2))% with the floor, $(round(r_aggregate_raw*100, digits=2))% without")
println("  ✓ $(params.N) sectors, GVA-weighted mean e=$(round(sum(w.*params.e),digits=2)) ",
        "k=$(round(sum(w.*params.k),digits=2)) r=$(round(sum(w.*params.r)*100,digits=2))%  ",
        "| aggregate r=ΣS/Σ(C+V)=$(round(r_aggregate*100,digits=2))%")

# ----------------------------------------------------------------------------
# Figure 2 — real 19x19 technical matrix A (heatmap)
# ----------------------------------------------------------------------------

# NAIO_10_CP1700 (the real symmetric IOT) is a benchmark table, not annual
# (Portugal: 2010/2013/2015/2017/2020) — requesting 2022 silently falls back
# to 2020, mixing a 2020-vintage matrix with 2022 labor coefficients. Rather
# than accept that mismatch, Figures 2-3 use a fully coherent 2020
# calibration (matrix AND labor coefficients both 2020); Table 1 and the
# aggregate AMECO series stay 2022/1996-2022 (neither depends on A).
println("\n[3/6] Real technical matrix A (heatmap, coherent 2020 calibration)...")
params2020 = calibrate_portugal_model(year = 2020, data_source = :eurostat)
fig2 = heatmap(params2020.nace_codes, params2020.nace_codes, params2020.A,
               xlabel = "buying sector j", ylabel = "supplying sector i",
               title = "Real technical matrix A (Portugal, 2020)",
               color = :viridis, size = (650, 550), margin = 5Plots.mm)
savefig(fig2, joinpath(FIG_DIR, "fig2_matrix_A.pdf"))
ρ_A = maximum(abs.(eigvals(params2020.A)))
println("  ✓ ρ(A) = $(round(ρ_A, digits = 3)) (2020 calibration, N=$(params2020.N))")

# ----------------------------------------------------------------------------
# Figure 3 — transformation problem on the real calibrated economy
# ----------------------------------------------------------------------------

println("\n[4/6] Transformation problem (real A, real l, coherent 2020 calibration)...")
A, l = params2020.A, params2020.l
λ = compute_labor_values(A, l)
λ_norm = λ ./ sum(λ)
R_max = compute_max_profit_rate(A, l)

# Plausible empirical profit rates for the main figure (R_max≈691% for this
# economy is not itself a plausible rate to plot against — flagged as a
# separate concern about the matrix's scale, see paper Section 6.2).
r̄_vals = [0.05, 0.10, 0.15]
fig3_series = []
for r̄ in r̄_vals
    p = compute_production_prices(A, l, 1.0, r̄)
    p_norm = p ./ sum(p)
    deviation = (p_norm .- λ_norm) ./ λ_norm .* 100
    push!(fig3_series, (r̄ = r̄, deviation = deviation))
end
fig3 = plot(xlabel = "Sector (ranked by labor value)", ylabel = "Price deviation from value (%)",
            title = "Values vs. Sraffa production prices (real economy)", size = (750, 450),
            legend = :outertopright, margin = 5Plots.mm)
ord = sortperm(λ_norm)
for (i, s) in enumerate(fig3_series)
    plot!(fig3, 1:length(ord), s.deviation[ord], label = "r̄ = $(round(s.r̄*100, digits=1))%",
          lw = 2, marker = :circle, markersize = 3)
end
hline!(fig3, [0], color = :black, linestyle = :dash, label = "")
savefig(fig3, joinpath(FIG_DIR, "fig3_transformation.pdf"))
println("  ✓ R_max = $(round(R_max*100, digits=1))%")

# ----------------------------------------------------------------------------
# Figure 4 — illustrative N-dept coupling comparison (synthetic, labeled as such)
# ----------------------------------------------------------------------------

println("\n[5/6] Illustrative N-dept coupling comparison (synthetic)...")
Random.seed!(5)
sol_mob, _, p_mob = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5)
Random.seed!(5)
sol_real, _, p_real = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5, realization = true)
Random.seed!(5)
sol_rat, _, p_rat = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5, rationing = true)

r_mob = compute_price_profit_rates(sol_mob, p_mob)
r_real = compute_price_profit_rates(sol_real, p_real)
r_rat = compute_price_profit_rates(sol_rat, p_rat)

fig4 = plot(sol_mob.t, [std(r_mob[:, t]) for t in 1:length(sol_mob.t)],
            label = "mobility only", lw = 2, xlabel = "Time", ylabel = "Std. dev. of sectoral profit rates",
            title = "Illustrative comparison of coupling mechanisms (synthetic)", size = (750, 450))
plot!(fig4, sol_real.t, [std(r_real[:, t]) for t in 1:length(sol_real.t)],
      label = "+ realization pressure", lw = 2)
plot!(fig4, sol_rat.t, [std(r_rat[:, t]) for t in 1:length(sol_rat.t)],
      label = "+ quantity rationing", lw = 2)
savefig(fig4, joinpath(FIG_DIR, "fig4_coupling_comparison.pdf"))
println("  ✓ final dispersion: mobility=$(round(std(r_mob[:,end]),digits=4)) ",
        "realization=$(round(std(r_real[:,end]),digits=4)) rationing=$(round(std(r_rat[:,end]),digits=4))")

# ----------------------------------------------------------------------------
# Table 4 — real final demand (NAIO_10_CP1700 final-use columns) in the
# dynamics: rationing net of final consumption and exports, and the cross-dual
# balanced-growth ray with a real household consumption basket
# ----------------------------------------------------------------------------

println("\n[6/6] Real final demand in the dynamics (Portugal 2022, real A)...")
fd_rows = String[]
φ19 = Float64[]
fd19_sections = String[]
for agg in (:macro, :medium, :detailed)
    pa = redirect_stdout(devnull) do
        calibrate_portugal_model(year = 2022, data_source = :eurostat, aggregation = agg)
    end
    fd = pa.final_demand
    N = pa.N
    φ = exogenous_demand_share(fd)
    agg == :detailed && (append!(φ19, φ); append!(fd19_sections, fd.sections))
    depts = departments_from_params(pa)
    # share of sectors rationed (mean along the trajectory) and growth of ΣC, without and with φ
    function rationing_run(φarg)
        sol, _, p = simulate_Ndept_custom(depts; T = 30.0, coupled = true, rationing = true,
                                          A = pa.A, final_demand_share = φarg)
        colsum = vec(sum(p.A, dims = 1))
        shares = map(sol.u) do X
            C, V = X[1:N], X[N+1:2N]
            S = p.e .* V
            x = (p.δ .* C .+ V .+ S) ./ (1 .- colsum)
            O = isnothing(φarg) ? x : (1 .- φarg) .* x
            count(_solve_rationing(p.A, ones(N), p.σ_c .* S .* x ./ C, O) .< 0.999) / N
        end
        return mean(shares), sum(sol.u[end][1:N]) / sum(sol.u[1][1:N])
    end
    inc0, growth0 = rationing_run(nothing)
    inc1, growth1 = rationing_run(φ)
    # balanced growth of the cross-dual model, net-output vs. real basket
    g = map((nothing, consumption_basket(fd))) do basket
        sol, _, p = simulate_Ndept_custom(depts; T = 1.0, coupled = true, μ = 0.5,
                                          market_prices = true, A = pa.A, basket = basket)
        eq = redirect_stdout(devnull) do
            balanced_growth(p, sol.u[1])
        end
        eq.converged || @warn "Balanced growth did not converge ($agg)."
        (eq.g, eq.stable)
    end
    push!(fd_rows, @sprintf("%d & %.2f & %.2f & \\(\\times\\)%.1f & \\(\\times\\)%.1f & %.3f & %.3f & %s \\\\",
                            N, inc0, inc1, growth0, growth1, g[1][1], g[2][1],
                            g[1][2] && g[2][2] ? "both" : (g[1][2] || g[2][2] ? "one" : "neither")))
    println("  ✓ N=$N: rationed $(round(inc0, digits = 3)) → $(round(inc1, digits = 3)), ",
            "ΣC ×$(round(growth0, digits = 1)) → ×$(round(growth1, digits = 1)), ",
            "g★ $(round(g[1][1], digits = 4)) → $(round(g[2][1], digits = 4))")
end
open(joinpath(FIG_DIR, "table4_final_demand.tex"), "w") do io
    println(io, "\\begin{tabular}{rrrrrrrl}")
    println(io, "\\toprule")
    println(io, " & \\multicolumn{2}{c}{Rationed share} & \\multicolumn{2}{c}{Growth of \\(\\sum C\\)} & " *
                "\\multicolumn{2}{c}{\\(g^\\star\\), cross-dual} & \\\\")
    println(io, "\\(N\\) & \\(O=x\\) & \\(O=(1-\\varphi)x\\) & \\(O=x\\) & \\(O=(1-\\varphi)x\\) & " *
                "net-output basket & real basket & stable \\\\")
    println(io, "\\midrule")
    foreach(r -> println(io, r), fd_rows)
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
open(joinpath(FIG_DIR, "final_demand_stats.tex"), "w") do io
    println(io, "% Generated by paper/generate_results.jl — do not edit by hand.")
    i_min, i_max = argmin(φ19), argmax(φ19)
    @printf(io, "\\newcommand{\\FDPhiMin}{%.2f}\n", φ19[i_min])
    println(io, "\\newcommand{\\FDPhiMinSector}{$(fd19_sections[i_min])}")
    @printf(io, "\\newcommand{\\FDPhiMax}{%.2f}\n", φ19[i_max])
    println(io, "\\newcommand{\\FDPhiMaxSector}{$(fd19_sections[i_max])}")
    println(io, "\\newcommand{\\FDPhiCapped}{$(count(φ19 .>= 0.95))}")
end

println("\n" * "="^70)
println("Done. Figures/tables in paper/figures/.")
println("="^70)
