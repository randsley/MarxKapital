# ============================================================================
# ANÁLISE DISTRIBUTIVA E VALIDAÇÃO DE CALIBRAÇÃO
# ============================================================================

"""
    curva_salario_lucro(A, l; n_pontos=100, plotar=true)

Fronteira de possibilidades distributivas (curva w-r): o trade-off entre
salário real e taxa de lucro determinado pela tecnologia. O bem 1 é
numerário (p₁ = 1).
"""
function curva_salario_lucro(A, l; n_pontos = 100, plotar = true)
    println("\n" * "="^70)
    println("FRONTEIRA DE POSSIBILIDADES DISTRIBUTIVAS")
    println("="^70)

    N = size(A, 1)
    R_max = calcular_taxa_lucro_maxima(A, l)
    println("\nTaxa máxima de lucro (w=0): $(round(R_max*100, digits=2))%")

    r_valores = range(0, R_max * 0.99, length = n_pontos)
    w_valores = zeros(n_pontos)
    p_matriz = zeros(N, n_pontos)

    for (i, r) in enumerate(r_valores)
        p_temp = calcular_precos_producao(A, l, 1.0, r)
        w_valores[i] = 1.0 / p_temp[1]
        p_matriz[:, i] = p_temp / p_temp[1]
    end

    w_max = w_valores[1]
    println("Salário máximo (r=0): $(round(w_max, digits=4))")

    dw_dr = diff(w_valores) ./ diff(r_valores)
    r_mid = (r_valores[1:end-1] + r_valores[2:end]) / 2
    w_mid = (w_valores[1:end-1] + w_valores[2:end]) / 2
    elasticidade = dw_dr .* (r_mid ./ w_mid)
    elasticidade_média = mean(elasticidade)
    println("Elasticidade média ε(w,r): $(round(elasticidade_média, digits=3))")

    if plotar
        p1 = plot(r_valores * 100, w_valores, xlabel = "Taxa de Lucro r (%)",
                  ylabel = "Salário Real w", title = "Fronteira Distributiva w-r",
                  label = "Curva w(r)", lw = 3, color = :blue, legend = :topright)
        scatter!([0, R_max * 100 * 0.99], [w_max, w_valores[end]],
                 label = "", markersize = 6, color = :red)

        p2 = plot(r_mid * 100, elasticidade, xlabel = "Taxa de Lucro r (%)",
                  ylabel = "Elasticidade ε(w,r)", title = "Elasticidade",
                  label = "ε = (dw/dr)·(r/w)", lw = 2, color = :purple)
        hline!([elasticidade_média], linestyle = :dash, color = :red, label = "Média")

        p3 = plot(xlabel = "Taxa de Lucro r (%)", ylabel = "Preço Relativo",
                  title = "Evolução dos Preços", legend = :outertopright)
        for i in 1:min(N, 5)
            plot!(r_valores * 100, p_matriz[i, :], label = "Bem $i", lw = 2, alpha = 0.7)
        end

        p4 = plot(w_valores, r_valores * 100, xlabel = "Salário Real w",
                  ylabel = "Taxa de Lucro r (%)", title = "Espaço de Fase",
                  label = "", lw = 2, color = :green)

        plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000))
        display(plt)
    end

    return (r = r_valores, w = w_valores, R_max = R_max, w_max = w_max,
            elasticidade_média = elasticidade_média, elasticidade = elasticidade,
            preços = p_matriz)
end

"""
    validar_taxas_lucro_calibradas(params)

Verifica se as taxas de lucro calibradas são teoricamente viáveis (dentro da
restrição tecnológica R_max), avalia dispersão, consistência e posição na
fronteira, e devolve uma pontuação de qualidade em [0, 100].
"""
function validar_taxas_lucro_calibradas(params::ParâmetrosCalibrados)
    println("\n" * "="^70)
    println("VALIDAÇÃO DE TAXAS DE LUCRO")
    println("="^70)
    println("\nAno base: $(params.ano_base)  |  Setores: $(params.N)")

    R_max = calcular_taxa_lucro_maxima(params.A, params.l)

    r_média   = mean(params.r)
    r_mediana = median(params.r)
    r_std     = std(params.r)

    println("\n📊 ESTATÍSTICAS")
    println("-"^70)
    println("  Média:   $(round(r_média*100, digits=2))%")
    println("  Mediana: $(round(r_mediana*100, digits=2))%")
    println("  Mín/Máx: $(round(minimum(params.r)*100, digits=2))% / $(round(maximum(params.r)*100, digits=2))%")
    println("  Desvio-padrão: $(round(r_std*100, digits=2))pp")
    println("  Coef. variação: $(round(r_std/r_média, digits=3))")
    println("\n⚙️  Taxa máxima teórica (R_max): $(round(R_max*100, digits=2))%")

    # Teste 1 — viabilidade da média
    viável_média = r_média < R_max
    margem_média = (R_max - r_média) / R_max * 100
    println("\n🔍 TESTE 1: Viabilidade da Taxa Média")
    if viável_média
        println("  ✓ Viável — margem: $(round(margem_média, digits=1))%")
        margem_média < 10 && println("  ⚠️  Margem pequena — próximo do limite")
    else
        println("  ✗ Excede o máximo (possível renda/monopólio ou A subestimada)")
    end

    # Teste 2 — viabilidade setorial
    setores_problemáticos = findall(params.r .>= R_max)
    println("\n🔍 TESTE 2: Viabilidade Setorial")
    if isempty(setores_problemáticos)
        println("  ✓ Todos os setores dentro do limite")
    else
        println("  ✗ $(length(setores_problemáticos)) setores excedem R_max")
        for idx in setores_problemáticos
            println("    • $(params.nomes_setores[idx]): $(round(params.r[idx]*100, digits=1))%")
        end
    end

    # Teste 3 — dispersão
    cv = r_std / r_média
    println("\n🔍 TESTE 3: Dispersão (CV = $(round(cv, digits=2)))")
    println(cv < 0.3 ? "  ✓ Baixa" : cv < 0.6 ? "  ⚠️  Moderada" : "  ✗ Alta")
    z = (params.r .- r_média) / r_std
    outliers_altos = findall(z .> 2)
    if !isempty(outliers_altos)
        println("  Lucros anormalmente altos (>2σ):")
        for idx in outliers_altos
            println("    • $(params.nomes_setores[idx]): $(round(params.r[idx]*100, digits=1))%")
        end
    end

    # Teste 4 — consistência
    k_média = mean(params.k)
    e_implícita = r_média * (k_média + 1)
    println("\n🔍 TESTE 4: Consistência")
    println("  k médio = $(round(k_média, digits=2))  →  e implícita = $(round(e_implícita, digits=2))")
    println(0.5 < e_implícita < 3.0 ? "  ✓ Razoável" : "  ⚠️  Fora do esperado")

    # Teste 5 — posição na fronteira
    posição_r = r_média / R_max * 100
    println("\n🔍 TESTE 5: Posição na Fronteira: $(round(posição_r, digits=1))% de R_max")
    println(posição_r < 30 ? "  → Baixa taxa de lucro" :
            posição_r < 70 ? "  → Zona intermédia" : "  → Alta taxa de lucro")

    # Visualização (sem boxplot: robusto sem StatsPlots)
    p1 = histogram(params.r * 100, bins = 15, xlabel = "Taxa de Lucro (%)",
                   ylabel = "Frequência", title = "Distribuição", label = "",
                   alpha = 0.7, color = :steelblue)
    vline!([r_média * 100], color = :red, lw = 2, linestyle = :dash, label = "Média")
    vline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max")

    p2 = scatter(params.k, params.r * 100, xlabel = "Composição Orgânica k",
                 ylabel = "Taxa de Lucro r (%)", title = "Relação r-k",
                 label = "", markersize = 6, alpha = 0.7)
    k_range = range(minimum(params.k), maximum(params.k), length = 100)
    plot!(k_range, e_implícita ./ (k_range .+ 1) * 100, color = :red, lw = 2,
          linestyle = :dash, label = "Teórico")

    ordem = sortperm(params.r, rev = true)
    top5 = ordem[1:min(5, params.N)]
    bottom5 = ordem[max(1, params.N - 4):params.N]
    nomes = [params.nomes_setores[top5]; params.nomes_setores[bottom5]]
    valores = [params.r[top5]; params.r[bottom5]] * 100
    p3 = bar(nomes, valores, xlabel = "Setor", ylabel = "Taxa de Lucro (%)",
             title = "Top/Bottom 5", legend = false, orientation = :horizontal,
             color = [fill(:green, length(top5)); fill(:red, length(bottom5))], alpha = 0.7)
    hline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot)

    p4 = histogram(params.r * 100, bins = 20, xlabel = "Taxa de Lucro (%)",
                   ylabel = "Frequência", title = "Distribuição Detalhada",
                   legend = :topright, orientation = :horizontal, alpha = 0.7,
                   color = :steelblue, label = "")
    vline!([r_média * 100], color = :red, lw = 2, label = "Média")
    vline!([r_mediana * 100], color = :green, lw = 2, linestyle = :dash, label = "Mediana")
    vline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max")
    q25 = quantile(params.r, 0.25) * 100
    q75 = quantile(params.r, 0.75) * 100
    vline!([q25, q75], color = :gray, lw = 1, linestyle = :dot, alpha = 0.5, label = "Q1/Q3")

    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "Diagnóstico de Validação")
    display(plt)

    # Pontuação
    pontuação = 0.0
    viável_média && (pontuação += 1.0)
    if isempty(setores_problemáticos)
        pontuação += 1.0
    else
        pontuação += max(0, 1.0 - length(setores_problemáticos) / params.N)
    end
    cv < 0.5 && (pontuação += 1.0)
    (0.5 < e_implícita < 3.0) && (pontuação += 1.0)
    (20 < posição_r < 80) && (pontuação += 1.0)
    pontuação_final = pontuação / 5 * 100

    println("\n" * "-"^70)
    println("  PONTUAÇÃO FINAL: $(round(pontuação_final, digits=1))%  " *
            (pontuação_final >= 80 ? "✅ ALTA QUALIDADE" :
             pontuação_final >= 60 ? "⚠️  ACEITÁVEL" : "❌ PROBLEMÁTICA"))
    println("="^70 * "\n")

    return (R_max = R_max, r_média = r_média, r_mediana = r_mediana,
            dispersão = r_std, cv = cv, viável_média = viável_média,
            margem = viável_média ? margem_média : missing,
            setores_problemáticos = setores_problemáticos,
            e_implícita = e_implícita, posição_fronteira = posição_r,
            pontuação = pontuação_final, plot = plt)
end
