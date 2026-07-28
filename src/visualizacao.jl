# ============================================================================
# VISUALIZAÇÃO
# ============================================================================

"""Painéis do modelo de 2 departamentos: capital, composição, lucro, equilíbrio."""
function plotar_2dept(sol, depts, p)
    t = sol.t
    C1, V1, C2, V2 = (sol[i, :] for i in 1:4)
    e1, e2 = p[1], p[2]
    σ_c1, σ_c2 = p[3], p[5]

    K1 = C1 .+ V1; K2 = C2 .+ V2
    S1 = e1 .* V1; S2 = e2 .* V2
    k1 = C1 ./ V1; k2 = C2 ./ V2
    r1 = e1 ./ (k1 .+ 1); r2 = e2 ./ (k2 .+ 1)
    r_media = (S1 .+ S2) ./ (K1 .+ K2)

    p1 = plot(t, [K1 K2], label = ["Dept I" "Dept II"], xlabel = "Tempo",
              ylabel = "Capital Total", title = "Evolução do Capital", lw = 2)
    p2 = plot(t, [k1 k2], label = ["Dept I" "Dept II"], xlabel = "Tempo",
              ylabel = "k", title = "Composição Orgânica", lw = 2)
    p3 = plot(t, [r1 r2 r_media], label = ["Dept I" "Dept II" "Média"],
              xlabel = "Tempo", ylabel = "r", title = "Taxas de Lucro", lw = 2)
    deseq = (V1 .+ (1 .- σ_c1) .* S1) .- (C2 .+ σ_c2 .* S2)
    p4 = plot(t, deseq, label = "", xlabel = "Tempo", ylabel = "Desequilíbrio",
              title = "Equilíbrio Intersetorial", lw = 2, color = :red)
    hline!([0], color = :black, linestyle = :dash, label = "")

    plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 800))
end

"""Painéis do modelo de N departamentos: capital, composições, lucros, distribuição final."""
function plotar_Ndept(sol, depts, p; salvar = nothing)
    N = length(depts)
    t = sol.t
    r = calcular_taxas_lucro(sol, p.e)
    k = calcular_composicoes_organicas(sol)
    r_media = calcular_taxa_media_lucro(sol, p.e)

    K = zeros(N, length(t))
    for idx in 1:length(t)
        K[:, idx] = sol[1:N, idx] .+ sol[N+1:2N, idx]
    end

    p1 = plot(t, K', xlabel = "Tempo", ylabel = "Capital",
              title = "Evolução (N=$N)", legend = false, alpha = 0.6)
    p2 = plot(t, k', xlabel = "Tempo", ylabel = "k",
              title = "Composições Orgânicas", legend = false, alpha = 0.6)
    p3 = plot(t, r', xlabel = "Tempo", ylabel = "r", title = "Taxas de Lucro",
              legend = false, alpha = 0.6)
    plot!(t, r_media, lw = 3, color = :black, label = "Média")
    p4 = histogram(r[:, end], xlabel = "Taxa de Lucro", ylabel = "Frequência",
                   title = "Distribuição Final", legend = false, bins = 15)

    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 800))
    isnothing(salvar) || savefig(plt, salvar)
    display(plt)
    return plt
end
