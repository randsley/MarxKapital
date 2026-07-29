# ============================================================================
# Generates every figure and table used in paper/main.tex, from real data.
#
# Run with:  julia --project=. paper/gerar_resultados.jl
#
# Requires network access (Eurostat + AMECO SDMX APIs). No numbers in the
# paper are hand-entered — this script is the single source of truth for
# every reported figure/table.
# ============================================================================

ENV["GKSwstype"] = "100"

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

println("\n" * "="^70)
println("A gerar resultados para paper/main.tex...")
println("="^70)

# ----------------------------------------------------------------------------
# Figure 1 — aggregate profit-rate trend, Portugal, 1996-2022 (real AMECO data)
# ----------------------------------------------------------------------------

println("\n[1/5] Time series (e, k, r), Portugal 1996-2022, two valuation conventions...")
anos = 1996:2022
dados_pt = obter_dados_ameco("Portugal", anos = anos, método = :sdmx)
st_corrente    = analisar_série_temporal_com_dados(dados_pt; valorização = :corrente)
st_consistente = analisar_série_temporal_com_dados(dados_pt; valorização = :consistente)

p1 = plot(anos, st_corrente.e, xlabel = "Year", ylabel = "e", title = "Rate of exploitation",
          label = "current-price V, VAB", lw = 2, color = :steelblue)
plot!(p1, anos, st_consistente.e, label = "deflated V, VAB", lw = 2, color = :steelblue,
      linestyle = :dash)
p2 = plot(anos, st_corrente.k, xlabel = "Year", ylabel = "k", title = "Organic composition",
          label = "current-price V, VAB", lw = 2, color = :firebrick)
plot!(p2, anos, st_consistente.k, label = "deflated V, VAB", lw = 2, color = :firebrick,
      linestyle = :dash)
p3 = plot(anos, st_corrente.r .* 100, xlabel = "Year", ylabel = "r (%)", title = "Profit rate",
          label = "current-price V, VAB", lw = 2, color = :seagreen)
plot!(p3, anos, st_consistente.r .* 100, label = "deflated V, VAB", lw = 2, color = :seagreen,
      linestyle = :dash)
fig1 = plot(p1, p2, p3, layout = (1, 3), size = (1350, 380), margin = 6Plots.mm,
            legend = :outerbottom, legendcolumns = 2)
savefig(fig1, joinpath(FIG_DIR, "fig1_time_series.pdf"))
println("  ✓ [corrente]    e: $(round(st_corrente.e[1],digits=3)) -> $(round(st_corrente.e[end],digits=3))  ",
        "k: $(round(st_corrente.k[1],digits=2)) -> $(round(st_corrente.k[end],digits=2))  ",
        "r: $(round(st_corrente.r[1]*100,digits=2))% -> $(round(st_corrente.r[end]*100,digits=2))%")
println("  ✓ [consistente] e: $(round(st_consistente.e[1],digits=3)) -> $(round(st_consistente.e[end],digits=3))  ",
        "k: $(round(st_consistente.k[1],digits=2)) -> $(round(st_consistente.k[end],digits=2))  ",
        "r: $(round(st_consistente.r[1]*100,digits=2))% -> $(round(st_consistente.r[end]*100,digits=2))%")

println("\n[1b/5] Portugal vs. Spain, consistent valuation...")
dados_es = obter_dados_ameco("Espanha", anos = anos, método = :sdmx)
st_es = analisar_série_temporal_com_dados(dados_es; valorização = :consistente)
fig1b = plot(anos, st_consistente.r .* 100, xlabel = "Year", ylabel = "r (%)",
             title = "Profit rate, consistent valuation: Portugal vs. Spain",
             label = "Portugal", lw = 2, color = :seagreen, size = (700, 420), margin = 5Plots.mm)
plot!(fig1b, anos, st_es.r .* 100, label = "Spain", lw = 2, color = :darkorange)
savefig(fig1b, joinpath(FIG_DIR, "fig1b_pt_vs_es.pdf"))
println("  ✓ Spain [consistente] e: $(round(st_es.e[1],digits=3)) -> $(round(st_es.e[end],digits=3))  ",
        "k: $(round(st_es.k[1],digits=2)) -> $(round(st_es.k[end],digits=2))  ",
        "r: $(round(st_es.r[1]*100,digits=2))% -> $(round(st_es.r[end]*100,digits=2))%")

println("\n[1c/5] Robustness: GDP deflator vs. investment-goods deflator, Portugal...")
st_fbcf = analisar_série_temporal_com_dados(dados_pt; valorização = :consistente_fbcf)
println("  ✓ [consistente_fbcf] e: $(round(st_fbcf.e[1],digits=3)) -> $(round(st_fbcf.e[end],digits=3))  ",
        "k: $(round(st_fbcf.k[1],digits=2)) -> $(round(st_fbcf.k[end],digits=2))  ",
        "r: $(round(st_fbcf.r[1]*100,digits=2))% -> $(round(st_fbcf.r[end]*100,digits=2))%")

# ----------------------------------------------------------------------------
# Table 1 — 19-sector calibration profile, Portugal 2022 (real Eurostat data)
# ----------------------------------------------------------------------------

println("\n[2/5] 19-sector calibration, Portugal 2022...")
params = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat)

const NACE_EN = Dict(
    "A" => "Agriculture, forestry and fishing", "B" => "Mining and quarrying",
    "C" => "Manufacturing", "D" => "Electricity, gas, steam",
    "E" => "Water supply, sewerage, waste", "F" => "Construction",
    "G" => "Wholesale and retail trade", "H" => "Transportation and storage",
    "I" => "Accommodation and food service", "J" => "Information and communication",
    "K" => "Financial and insurance activities", "L" => "Real estate activities",
    "M" => "Professional, scientific and technical", "N" => "Administrative and support",
    "O" => "Public administration", "P" => "Education",
    "Q" => "Human health and social work", "R" => "Arts, entertainment and recreation",
    "S" => "Other service activities",
)

open(joinpath(FIG_DIR, "table1_sectors.tex"), "w") do io
    println(io, "\\begin{tabular}{llrrrr}")
    println(io, "\\toprule")
    println(io, "Code & Sector & VAB (M\\texteuro) & \$e\$ & \$k\$ & \$r\$ (\\%) \\\\")
    println(io, "\\midrule")
    ord = sortperm(params.r, rev = true)
    for i in ord
        nome = NACE_EN[params.códigos_cae[i]]
        vab_i = round((params.C[i] + params.V[i] + params.e[i] * params.V[i]) / 1000, digits = 1)
        println(io, "$(params.códigos_cae[i]) & $nome & $vab_i & " *
                    "$(round(params.e[i], digits = 2)) & $(round(params.k[i], digits = 2)) & " *
                    "$(round(params.r[i] * 100, digits = 2)) \\\\")
    end
    println(io, "\\bottomrule")
    println(io, "\\end{tabular}")
end
println("  ✓ $(params.N) sectors, mean e=$(round(mean(params.e),digits=2)) ",
        "mean k=$(round(mean(params.k),digits=2)) mean r=$(round(mean(params.r)*100,digits=2))%")

# ----------------------------------------------------------------------------
# Figure 2 — real 19x19 technical matrix A (heatmap)
# ----------------------------------------------------------------------------

println("\n[3/5] Real technical matrix A (heatmap)...")
fig2 = heatmap(params.códigos_cae, params.códigos_cae, params.A,
               xlabel = "buying sector j", ylabel = "supplying sector i",
               title = "Real technical matrix A (Portugal, 2022)",
               color = :viridis, size = (650, 550), margin = 5Plots.mm)
savefig(fig2, joinpath(FIG_DIR, "fig2_matrix_A.pdf"))
ρ_A = maximum(abs.(eigvals(params.A)))
println("  ✓ ρ(A) = $(round(ρ_A, digits = 3))")

# ----------------------------------------------------------------------------
# Figure 3 — transformation problem on the real calibrated economy
# ----------------------------------------------------------------------------

println("\n[4/5] Transformation problem (real A, real l)...")
A, l = params.A, params.l
λ = calcular_valores_trabalho(A, l)
λ_norm = λ ./ sum(λ)
R_max = calcular_taxa_lucro_maxima(A, l)

r̄_vals = [0.0, 0.3 * R_max, 0.6 * R_max]
fig3_series = []
for r̄ in r̄_vals
    p = calcular_precos_producao(A, l, 1.0, r̄)
    p_norm = p ./ sum(p)
    desvio = (p_norm .- λ_norm) ./ λ_norm .* 100
    push!(fig3_series, (r̄ = r̄, desvio = desvio))
end
fig3 = plot(xlabel = "Sector (ranked by labor value)", ylabel = "Price deviation from value (%)",
            title = "Values vs. Sraffa production prices (real economy)", size = (750, 450),
            legend = :outertopright, margin = 5Plots.mm)
ord = sortperm(λ_norm)
for (i, s) in enumerate(fig3_series)
    plot!(fig3, 1:length(ord), s.desvio[ord], label = "r̄ = $(round(s.r̄*100, digits=1))%",
          lw = 2, marker = :circle, markersize = 3)
end
hline!(fig3, [0], color = :black, linestyle = :dash, label = "")
savefig(fig3, joinpath(FIG_DIR, "fig3_transformation.pdf"))
println("  ✓ R_max = $(round(R_max*100, digits=1))%")

# ----------------------------------------------------------------------------
# Figure 4 — illustrative N-dept coupling comparison (synthetic, labeled as such)
# ----------------------------------------------------------------------------

println("\n[5/5] Illustrative N-dept coupling comparison (synthetic)...")
Random.seed!(5)
sol_mob, _, p_mob = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5)
Random.seed!(5)
sol_real, _, p_real = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5, realização = true)
Random.seed!(5)
sol_rac, _, p_rac = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5, racionamento = true)

r_mob = calcular_taxas_lucro_precos(sol_mob, p_mob)
r_real = calcular_taxas_lucro_precos(sol_real, p_real)
r_rac = calcular_taxas_lucro_precos(sol_rac, p_rac)

fig4 = plot(sol_mob.t, [std(r_mob[:, t]) for t in 1:length(sol_mob.t)],
            label = "mobility only", lw = 2, xlabel = "Time", ylabel = "Std. dev. of sectoral profit rates",
            title = "Illustrative comparison of coupling mechanisms (synthetic)", size = (750, 450))
plot!(fig4, sol_real.t, [std(r_real[:, t]) for t in 1:length(sol_real.t)],
      label = "+ realization pressure", lw = 2)
plot!(fig4, sol_rac.t, [std(r_rac[:, t]) for t in 1:length(sol_rac.t)],
      label = "+ quantity rationing", lw = 2)
savefig(fig4, joinpath(FIG_DIR, "fig4_coupling_comparison.pdf"))
println("  ✓ final dispersion: mobility=$(round(std(r_mob[:,end]),digits=4)) ",
        "realization=$(round(std(r_real[:,end]),digits=4)) rationing=$(round(std(r_rac[:,end]),digits=4))")

println("\n" * "="^70)
println("Concluído. Figuras/tabelas em paper/figures/.")
println("="^70)
