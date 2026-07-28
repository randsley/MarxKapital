# ============================================================================
# INTEGRAÇÃO COM AMECO — NÚCLEO
# ============================================================================
# Dados sintéticos, calibração, comparação internacional e séries temporais.
# O download real está em ameco_download.jl.
# ============================================================================

"""Lista, por categoria, todos os países disponíveis na AMECO."""
function listar_países_ameco()
    println("\n" * "="^70)
    println("PAÍSES DISPONÍVEIS NA BASE AMECO")
    println("="^70)
    categorias = Dict(
        "União Europeia (27)" => ["Alemanha", "Áustria", "Bélgica", "Bulgária",
            "Chipre", "Croácia", "Dinamarca", "Eslováquia", "Eslovénia", "Espanha",
            "Estónia", "Finlândia", "França", "Grécia", "Hungria", "Irlanda",
            "Itália", "Letónia", "Lituânia", "Luxemburgo", "Malta", "Países Baixos",
            "Polónia", "Portugal", "República Checa", "Roménia", "Suécia"],
        "Área do Euro" => ["Área do Euro", "Área do Euro (19)"],
        "Outros europeus" => ["Reino Unido", "Noruega", "Suíça", "Islândia"],
        "Candidatos" => ["Turquia"],
        "Comparação internacional" => ["Estados Unidos", "Japão"],
        "Agregados" => ["União Europeia (27)", "União Europeia (28)"],
    )
    for (cat, países) in sort(collect(categorias))
        println("\n📍 $cat"); println("-"^70)
        for p in sort(países)
            println("  $p ($(CÓDIGOS_PAÍSES_AMECO[p]))")
        end
    end
    println("\n💡 Uso: obter_dados_ameco(\"Portugal\"); calibrar_com_ameco_v2(\"Portugal\")")
    println("="^70 * "\n")
end

"""Resolve nome ou código de país para o código ISO AMECO."""
function _resolver_código_país(país::String)
    haskey(CÓDIGOS_PAÍSES_AMECO, país) && return CÓDIGOS_PAÍSES_AMECO[país]
    país in values(CÓDIGOS_PAÍSES_AMECO) && return país
    error("País '$país' não encontrado. Use listar_países_ameco().")
end

"""
    gerar_dados_sintéticos_ameco(código_país, anos)

Séries temporais sintéticas mas plausíveis (tendência + ciclo) calibradas
por parâmetros base de cada país. Para demonstração — não usar oficialmente.
"""
function gerar_dados_sintéticos_ameco(código_país::String, anos::Vector{Int})
    println("\n🔬 Gerando dados sintéticos AMECO para $código_país...")
    n = length(anos)

    params_país = Dict(
        "PT" => (PIB_base = 234_000, emprego_base = 4_900),
        "ES" => (PIB_base = 1_400_000, emprego_base = 20_500),
        "DE" => (PIB_base = 3_900_000, emprego_base = 44_900),
        "FR" => (PIB_base = 2_800_000, emprego_base = 29_600),
        "IT" => (PIB_base = 2_000_000, emprego_base = 25_600),
        "NL" => (PIB_base = 1_000_000, emprego_base = 9_700),
        "BE" => (PIB_base = 580_000, emprego_base = 5_000),
        "EL" => (PIB_base = 215_000, emprego_base = 4_100),
        "IE" => (PIB_base = 500_000, emprego_base = 2_500),
        "EA19" => (PIB_base = 14_000_000, emprego_base = 165_000),
        "US" => (PIB_base = 25_000_000, emprego_base = 160_000),
    )
    if !haskey(params_país, código_país)
        @warn "País $código_país sem parâmetros específicos; a usar perfil PT."
    end
    base = get(params_país, código_país, params_país["PT"])

    g_nom, g_real, infl = 0.015, 0.012, 0.02
    t = 1:n
    ciclo = sin.(2π * t / 8) * 0.02

    PIB       = base.PIB_base .* (1 + g_nom).^(t .- n) .* (1 .+ ciclo)
    PIB_real  = base.PIB_base .* (1 + g_real).^(t .- n) .* (1 .+ ciclo * 0.8)
    deflator  = PIB ./ PIB_real * 100
    IPC       = 100 .* (1 + infl).^(t .- 1) .* (1 .+ rand(n) * 0.005 .- 0.0025)

    consumo_privado = PIB * 0.65
    consumo_público = PIB * 0.18
    FBCF            = PIB * 0.20
    exportações     = PIB * 0.45
    importações     = PIB * 0.43

    emprego = base.emprego_base .* (1 + 0.005).^(t .- n) .* (1 .+ ciclo * 0.3)
    emprego_assalariado = emprego * 0.85

    desemp_base = código_país == "PT" ? 7.0 : código_país == "DE" ? 3.5 :
                  código_país == "ES" ? 13.0 : código_país == "EL" ? 12.0 : 6.0
    desemprego = max.(desemp_base .+ ciclo * (-20) .+ rand(n) * 2 .- 1, 2.0)
    população_ativa = emprego ./ (1 .- desemprego / 100)

    remunerações = PIB * 0.52
    produtividade = PIB_real ./ emprego
    custos_unit = (remunerações ./ emprego) ./ produtividade * 100

    receitas = PIB * 0.43
    despesas = PIB * 0.46
    saldo = (receitas .- despesas) ./ PIB * 100
    dívida_base = código_país == "PT" ? 120.0 : código_país == "EL" ? 180.0 :
                  código_país == "IT" ? 140.0 : código_país == "DE" ? 60.0 : 80.0
    dívida = dívida_base .+ cumsum(saldo) * 0.1

    bal_comercial = (exportações .- importações) ./ PIB * 100
    bal_corrente = bal_comercial .+ rand(n) * 2 .- 1

    stock_capital = PIB * 3.0 .+ cumsum(FBCF) * 0.1

    println("  ✓ $n anos ($(anos[1])-$(anos[end])) | PIB médio $(round(mean(PIB)/1000, digits=1)) mil M | desemprego médio $(round(mean(desemprego), digits=1))%")

    nome_país = something(findfirst(==(código_país), CÓDIGOS_PAÍSES_AMECO), código_país)
    notas = Dict("tipo" => "Dados sintéticos", "baseado_em" => "Padrões AMECO reais",
                 "advertência" => "Demonstração — não usar em análise oficial")

    return DadosAMECO(nome_país, código_país, anos,
        PIB, PIB_real, consumo_privado, consumo_público, FBCF, exportações, importações,
        emprego, emprego_assalariado, desemprego, população_ativa,
        remunerações, produtividade, custos_unit, deflator, IPC,
        receitas, despesas, saldo, dívida, bal_corrente, bal_comercial,
        stock_capital, "AMECO (sintético)", now(), notas)
end

"""Constrói DadosAMECO a partir de séries extraídas (dicionário nome → vetor)."""
function construir_dados_ameco(código_país, anos, dados::Dict, fonte)
    nome_país = something(findfirst(==(código_país), CÓDIGOS_PAÍSES_AMECO), código_país)
    g(key, d = 0.0) = get(dados, key, fill(d, length(anos)))
    return DadosAMECO(nome_país, código_país, anos,
        g("PIB_corrente"), g("PIB_constante"), g("consumo_privado"), g("consumo_público"),
        g("FBCF"), g("exportações"), g("importações"), g("emprego_total"),
        g("emprego_assalariado"), g("taxa_desemprego"), g("população_ativa"),
        g("remunerações"), g("produtividade_trabalho"), g("custos_unit_trabalho"),
        g("deflator_PIB"), g("IPC"), g("receitas_governo"), g("despesas_governo"),
        g("saldo_orçamental"), g("dívida_pública"), g("balança_corrente"),
        g("balança_comercial", NaN), g("stock_capital_líquido"),
        fonte, now(), Dict{String, String}())
end

# ----------------------------------------------------------------------------
# Calibração a partir de dados AMECO
# ----------------------------------------------------------------------------

"""Distribuição setorial (macro: 3 setores) do VAB por país."""
function _dist_setorial_vab(código_país)
    código_país == "PT" ? [0.02, 0.22, 0.76] :
    código_país == "DE" ? [0.01, 0.30, 0.69] :
    código_país == "EL" ? [0.04, 0.16, 0.80] : [0.02, 0.25, 0.73]
end

"""Distribuição setorial (macro: 3 setores) do emprego por país."""
function _dist_setorial_emprego(código_país)
    código_país == "PT" ? [0.04, 0.24, 0.72] : [0.03, 0.26, 0.71]
end

"""
    calibrar_com_dados_ameco(dados::DadosAMECO, ano, agregação)

Calibra o modelo a partir de uma estrutura DadosAMECO já carregada.
Atualmente só a agregação `:macro` (Primário/Secundário/Terciário) está
implementada. Se o ano pedido não tiver PIB válido, usa o ano válido mais
próximo.
"""
function calibrar_com_dados_ameco(dados::DadosAMECO, ano::Int, agregação::Symbol)
    println("\n" * "="^70)
    println("CALIBRAÇÃO COM DADOS AMECO — $(dados.país) | Ano: $ano")
    println("Fonte: $(dados.fonte)")
    println("="^70)

    agregação == :macro || error("Apenas agregação :macro implementada")

    idx = findfirst(==(ano), dados.anos)
    isnothing(idx) && error("Ano $ano indisponível. Anos: $(dados.anos[1])-$(dados.anos[end])")

    if isnan(dados.PIB[idx]) || dados.PIB[idx] <= 0
        válidos = findall(x -> !isnan(x) && x > 0, dados.PIB)
        isempty(válidos) && error("Nenhum PIB válido nos dados")
        idx = válidos[argmin(abs.(dados.anos[válidos] .- ano))]
        ano = dados.anos[idx]
        @warn "PIB indisponível; a usar ano $ano (mais próximo com dados)."
    end

    setores = ["Primário", "Secundário", "Terciário"]
    códigos = ["PRIM", "SEC", "TER"]
    N = 3
    dist_VAB = _dist_setorial_vab(dados.código_país)
    dist_emp = _dist_setorial_emprego(dados.código_país)

    PIB_total    = dados.PIB[idx]
    emprego_tot  = dados.emprego[idx]
    remun_tot    = dados.remunerações[idx]
    FBCF_total   = dados.FBCF[idx]
    stock_tot    = dados.stock_capital_total[idx]

    println("\n📊 Dados ($ano): PIB $(round(PIB_total/1000, digits=1)) mil M | " *
            "Emprego $(round(emprego_tot/1000, digits=2)) M | " *
            "Stock K $(round(stock_tot/1000, digits=1)) mil M")

    VAB           = PIB_total * dist_VAB
    emprego       = emprego_tot * dist_emp
    remunerações  = remun_tot * dist_VAB
    stock_capital = stock_tot * [0.10, 0.35, 0.55]
    FBCF_setorial = FBCF_total * dist_VAB

    V = remunerações
    C = stock_capital
    EBE = VAB .- remunerações
    CCF = stock_capital * 0.10
    rendimento = EBE .- CCF

    e = max.(rendimento ./ remunerações, 0.1)
    k = C ./ V
    r = rendimento ./ (C .+ V)

    println("\n📐 Parâmetros marxianos:")
    for i in 1:N
        println("  $(setores[i]): e=$(round(e[i], digits=2)) k=$(round(k[i], digits=2)) r=$(round(r[i]*100, digits=2))%")
    end

    A = criar_matriz_tecnica(N, densidade = 0.3)
    l = emprego ./ VAB; l = l / maximum(l)
    σ_c = clamp.(FBCF_setorial ./ rendimento, 0.2, 0.7)
    σ_v = fill(0.15, N)
    δ = CCF ./ stock_capital

    resultado = ParâmetrosCalibrados(N, setores, códigos, C, V, e, k, r, A, l,
        σ_c, σ_v, δ, "AMECO — $(dados.fonte)", ano, now(), 0.80)

    println("\n✅ CALIBRAÇÃO CONCLUÍDA — e médio $(round(mean(e), digits=2)) | r médio $(round(mean(r)*100, digits=2))%")
    println("="^70 * "\n")
    return resultado, dados
end

"""
    calibrar_com_ameco_v2(país; ano=2022, método=:auto)

Obtém dados AMECO (ver `obter_dados_ameco`) e calibra o modelo.
`método` ∈ (:auto, :download, :local, :sintético, :manual).
"""
function calibrar_com_ameco_v2(país::String; ano = 2022, método = :auto,
                               agregação_setorial = :macro)
    dados = obter_dados_ameco(país, anos = 1995:ano, método = método)
    return calibrar_com_dados_ameco(dados, ano, agregação_setorial)
end

# ----------------------------------------------------------------------------
# Comparação internacional
# ----------------------------------------------------------------------------

"""
    comparar_países_ameco(países; ano=2022, método=:sintético)

Calibra vários países e produz tabela + gráficos comparativos dos indicadores
marxianos.
"""
function comparar_países_ameco(países::Vector{String}; ano = 2022, método = :sintético)
    println("\n" * "="^70)
    println("COMPARAÇÃO INTERNACIONAL — AMECO | Ano: $ano")
    println("Países: $(join(países, ", "))")
    println("="^70)

    resultados = []
    for país in países
        println("\n🌍 $país...")
        params, dados = calibrar_com_ameco_v2(país, ano = ano, método = método)
        push!(resultados, (país = país, params = params, dados = dados))
    end

    df = DataFrame(
        País = [r.país for r in resultados],
        PIB = [round(sum(r.params.C .+ r.params.V) / 1000, digits = 1) for r in resultados],
        Taxa_Exploração = [round(mean(r.params.e), digits = 2) for r in resultados],
        Comp_Orgânica = [round(mean(r.params.k), digits = 2) for r in resultados],
        Taxa_Lucro = [round(mean(r.params.r) * 100, digits = 2) for r in resultados],
        Quota_Salarial = [round(sum(r.params.V) / sum(r.params.C .+ r.params.V) * 100, digits = 1) for r in resultados],
    )
    println("\n", df)

    p1 = bar(df.País, df.Taxa_Exploração, title = "Taxa de Exploração (e)",
             legend = false, color = :steelblue, alpha = 0.7)
    p2 = bar(df.País, df.Comp_Orgânica, title = "Composição Orgânica (k)",
             legend = false, color = :coral, alpha = 0.7)
    p3 = bar(df.País, df.Taxa_Lucro, title = "Taxa de Lucro (%)",
             legend = false, color = :green, alpha = 0.7)
    p4 = bar(df.País, df.Quota_Salarial, title = "Quota Salarial (% PIB)",
             legend = false, color = :purple, alpha = 0.7)
    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "Comparação Internacional ($ano)")
    display(plt)

    return (resultados = resultados, tabela = df, plot = plt)
end

# ----------------------------------------------------------------------------
# Séries temporais
# ----------------------------------------------------------------------------

"""Calcula indicadores marxianos ano a ano a partir de DadosAMECO."""
function analisar_série_temporal_com_dados(dados::DadosAMECO)
    n = length(dados.anos)
    e_t = fill(NaN, n); k_t = fill(NaN, n); r_t = fill(NaN, n); q_t = fill(NaN, n)
    for i in 1:n
        V, C, VAB = dados.remunerações[i], dados.stock_capital_total[i], dados.PIB[i]
        if !isnan(V) && !isnan(C) && !isnan(VAB) && V > 0 && C > 0
            rend = VAB - V - C * 0.10
            e_t[i] = rend / V
            k_t[i] = C / V
            r_t[i] = rend / (C + V)
            q_t[i] = V / VAB
        end
    end
    return (anos = dados.anos, e = e_t, k = k_t, r = r_t, quota_salarial = q_t)
end

"""
    analisar_série_temporal_ameco(país; anos=1995:2023, método=:sintético)

Obtém dados e produz a análise temporal (4 painéis) dos indicadores marxianos.
"""
function analisar_série_temporal_ameco(país::String; anos = 1995:2023,
                                       método = :sintético, ficheiro = nothing)
    println("\n" * "="^70)
    println("ANÁLISE DE SÉRIE TEMPORAL — $país | $(first(anos))-$(last(anos))")
    println("="^70)

    dados = obter_dados_ameco(país, anos = anos, método = método,
                              ficheiro = ficheiro)
    st = analisar_série_temporal_com_dados(dados)

    p1 = plot(st.anos, st.e, xlabel = "Ano", ylabel = "e",
              title = "Taxa de Exploração", lw = 2, label = "", color = :blue)
    p2 = plot(st.anos, st.k, xlabel = "Ano", ylabel = "k",
              title = "Composição Orgânica", lw = 2, label = "", color = :red)
    p3 = plot(st.anos, st.r * 100, xlabel = "Ano", ylabel = "r (%)",
              title = "Taxa de Lucro", lw = 2, label = "", color = :green)
    p4 = plot(st.anos, st.quota_salarial * 100, xlabel = "Ano", ylabel = "% PIB",
              title = "Quota Salarial", lw = 2, label = "", color = :purple)
    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "Análise Temporal: $país")
    display(plt)

    v(x) = filter(!isnan, x)
    println("\n📈 MÉDIAS DO PERÍODO:")
    println("  e: $(round(mean(v(st.e)), digits=2)) | k: $(round(mean(v(st.k)), digits=2)) | " *
            "r: $(round(mean(v(st.r))*100, digits=2))% | quota salarial: $(round(mean(v(st.quota_salarial))*100, digits=1))%")
    println("="^70 * "\n")

    return (dados = dados, e = st.e, k = st.k, r = st.r,
            quota_salarial = st.quota_salarial, plot = plt)
end

"""Cria um vetor de Departamento a partir de ParâmetrosCalibrados."""
function criar_departamentos_de_params(params::ParâmetrosCalibrados)
    depts = Departamento[]
    for i in 1:params.N
        push!(depts, Departamento(params.nomes_setores[i], c = params.C[i],
                                  v = params.V[i], e = params.e[i], σ_c = params.σ_c[i],
                                  σ_v = params.σ_v[i], δ = params.δ[i]))
    end
    return depts
end
