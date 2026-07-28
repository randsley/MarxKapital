# ============================================================================
# SIMULAÇÃO DE CHOQUES DISTRIBUTIVOS
# ============================================================================

"""
    simular_choque_salarial(depts, Δw; T=50.0, plotar=true, seed=42)

Simula o impacto de um aumento salarial de fração `Δw` (ex.: 0.10 = +10%).
V sobe (1+Δw); e desce proporcionalmente (s constante no curto prazo);
r = e/(k+1) ajusta-se. Compara cenário base vs. choque.

R_max é calculado com a matriz técnica e os coeficientes de trabalho reais
da simulação (`p_base.A`, `l ∝ V`), não uma matriz auxiliar (ver
docs/LIMITACOES.md, item 2 — corrigido). Passa a mesma `seed` a ambos os
cenários para garantir comparabilidade das matrizes técnicas geradas.
"""
function simular_choque_salarial(depts, Δw::Float64; T = 50.0, plotar = true, seed = 42)
    println("\n" * "="^70)
    println("SIMULAÇÃO DE CHOQUE SALARIAL — Δw = +$(round(Δw*100, digits=1))%")
    println("="^70)

    N = length(depts)

    # Cenário base — mesma seed para reprodutibilidade/comparabilidade
    sol_base, _, p_base = simular_Ndept_customizado(depts, T = T, seed = seed)

    # R_max com a matriz e os coeficientes de trabalho reais da simulação base
    l = [d.v for d in depts]
    R_max = calcular_taxa_lucro_maxima(p_base.A, l)
    r_base_inicial = mean([taxa_lucro(d) for d in depts])
    r_base_final = mean(calcular_taxas_lucro(sol_base, p_base.e)[:, end])

    # Cenário com choque
    depts_choque = Departamento[]
    for d in depts
        push!(depts_choque, Departamento(d.nome, c = d.c, v = d.v * (1 + Δw),
                                         e = d.e / (1 + Δw), σ_c = d.σ_c,
                                         σ_v = d.σ_v, δ = d.δ))
    end
    sol_choque, _, p_choque = simular_Ndept_customizado(depts_choque, T = T, seed = seed)
    r_choque_inicial = mean([taxa_lucro(d) for d in depts_choque])
    r_choque_final = mean(calcular_taxas_lucro(sol_choque, p_choque.e)[:, end])

    impacto_inicial = (r_choque_inicial - r_base_inicial) * 100
    impacto_final   = (r_choque_final - r_base_final) * 100

    K_base_inicial   = sum(capital_total(d) for d in depts)
    K_choque_inicial = sum(capital_total(d) for d in depts_choque)
    K_base_final     = sum(sol_base[1:N, end]) + sum(sol_base[N+1:2N, end])
    K_choque_final   = sum(sol_choque[1:N, end]) + sum(sol_choque[N+1:2N, end])

    println("\n📈 TAXAS DE LUCRO")
    println("  Base:   inicial $(round(r_base_inicial*100, digits=2))%  →  final $(round(r_base_final*100, digits=2))%")
    println("  Choque: inicial $(round(r_choque_inicial*100, digits=2))%  →  final $(round(r_choque_final*100, digits=2))%")
    println("  Impacto: imediato $(round(impacto_inicial, digits=2))pp | longo prazo $(round(impacto_final, digits=2))pp")
    println("\n💰 ACUMULAÇÃO DE CAPITAL")
    println("  Base:   +$(round((K_base_final/K_base_inicial - 1)*100, digits=1))%")
    println("  Choque: +$(round((K_choque_final/K_choque_inicial - 1)*100, digits=1))%")

    if plotar
        r_base_traj   = vec(mean(calcular_taxas_lucro(sol_base, p_base.e), dims = 1))
        r_choque_traj = vec(mean(calcular_taxas_lucro(sol_choque, p_choque.e), dims = 1))

        p1 = plot(sol_base.t, r_base_traj * 100, label = "Base", xlabel = "Tempo",
                  ylabel = "Taxa Média de Lucro (%)", title = "Impacto do Choque", lw = 2)
        plot!(sol_choque.t, r_choque_traj * 100, label = "Choque", lw = 2, linestyle = :dash)
        hline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max (ref.)")

        K_base_traj   = vec(sum(sol_base[1:N, :], dims = 1) + sum(sol_base[N+1:2N, :], dims = 1))
        K_choque_traj = vec(sum(sol_choque[1:N, :], dims = 1) + sum(sol_choque[N+1:2N, :], dims = 1))
        p2 = plot(sol_base.t, K_base_traj, label = "Base", xlabel = "Tempo",
                  ylabel = "Capital Total", title = "Acumulação", lw = 2)
        plot!(sol_choque.t, K_choque_traj, label = "Choque", lw = 2, linestyle = :dash)

        p3 = plot(sol_base.t, (r_choque_traj - r_base_traj) * 100, xlabel = "Tempo",
                  ylabel = "Δr (pp)", title = "Efeito Líquido", lw = 2, label = "",
                  fill = (0, 0.3, :purple))
        hline!([0], color = :black, linestyle = :dash, label = "")

        display(plot(p1, p2, p3, layout = (1, 3), size = (1400, 400)))
    end

    return (r_base_final = r_base_final, r_choque_final = r_choque_final,
            impacto_r_inicial = impacto_inicial, impacto_r_final = impacto_final,
            R_max = R_max, viável = r_choque_final < R_max)
end

"""
    comparar_choques_salariais(depts, choques; T=50.0, seed=42)

Corre vários cenários de choque e devolve a taxa de lucro final de cada.
"""
function comparar_choques_salariais(depts, choques::Vector{Float64}; T = 50.0, seed = 42)
    println("\n🔬 Comparando $(length(choques)) cenários de choque...")
    resultados = []
    sol_base, _, p_base = simular_Ndept_customizado(depts, T = T, seed = seed)
    r_base = mean(calcular_taxas_lucro(sol_base, p_base.e)[:, end])
    push!(resultados, (choque = 0.0, r_final = r_base))
    for Δw in choques
        res = simular_choque_salarial(depts, Δw, T = T, plotar = false, seed = seed)
        push!(resultados, (choque = Δw, r_final = res.r_choque_final))
    end
    return resultados
end
