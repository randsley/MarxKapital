# ============================================================================
# CALIBRAÇÃO COM DADOS PORTUGUESES (INE)
# ============================================================================
# Gera dados sintéticos com a estrutura setorial (CAE Rev.3) da economia
# portuguesa e calibra o modelo. Os valores são aproximações para
# demonstração — NÃO usar em análise oficial.
# ============================================================================

"""Gera dados sintéticos baseados na estrutura setorial portuguesa (19 setores CAE)."""
function gerar_dados_sintéticos_portugal(ano::Int)
    println("\n🔬 Gerando dados sintéticos para Portugal ($ano)...")

    setores = [
        ("A", "Agricultura, produção animal, caça, floresta e pesca"),
        ("B", "Indústrias extrativas"),
        ("C", "Indústrias transformadoras"),
        ("D", "Eletricidade, gás, vapor"),
        ("E", "Captação, tratamento e distribuição de água"),
        ("F", "Construção"),
        ("G", "Comércio por grosso e a retalho"),
        ("H", "Transportes e armazenagem"),
        ("I", "Alojamento, restauração"),
        ("J", "Atividades de informação e comunicação"),
        ("K", "Atividades financeiras e de seguros"),
        ("L", "Atividades imobiliárias"),
        ("M", "Atividades de consultoria, científicas"),
        ("N", "Atividades administrativas"),
        ("O", "Administração Pública"),
        ("P", "Educação"),
        ("Q", "Saúde humana e apoio social"),
        ("R", "Atividades artísticas"),
        ("S", "Outras atividades"),
    ]
    N = length(setores)
    códigos = [s[1] for s in setores]
    nomes = [s[2] for s in setores]

    VAB = Float64[2_800, 800, 18_500, 3_200, 1_200, 8_500, 19_000, 7_800,
                  7_200, 8_500, 11_500, 19_000, 12_000, 9_500, 17_000,
                  13_500, 15_000, 2_200, 3_800]

    pct_remunerações = [0.35, 0.40, 0.52, 0.35, 0.45, 0.60, 0.48, 0.50,
                        0.58, 0.55, 0.38, 0.15, 0.62, 0.65, 0.72, 0.75,
                        0.70, 0.60, 0.55]
    remunerações = VAB .* pct_remunerações
    EBE = VAB .- remunerações

    pct_depreciação = [0.08, 0.12, 0.10, 0.15, 0.10, 0.06, 0.08, 0.12,
                       0.08, 0.15, 0.05, 0.02, 0.10, 0.08, 0.06, 0.05,
                       0.08, 0.10, 0.08]
    CCF = VAB .* pct_depreciação
    rendimento_empresarial = EBE .- CCF

    emprego = Float64[180, 15, 650, 35, 45, 380, 850, 240, 380, 150,
                      110, 35, 320, 420, 680, 430, 520, 85, 180]

    pct_investimento = [0.18, 0.25, 0.20, 0.30, 0.22, 0.15, 0.18, 0.22,
                        0.16, 0.25, 0.12, 0.35, 0.20, 0.18, 0.15, 0.12,
                        0.18, 0.20, 0.18]
    FBCF = VAB .* pct_investimento

    múltiplo_capital = [2.5, 5.0, 1.8, 8.0, 6.0, 1.5, 1.2, 3.5, 1.8, 2.0,
                        1.5, 15.0, 1.0, 1.2, 2.5, 2.0, 2.5, 2.0, 1.5]
    stock_capital = VAB .* múltiplo_capital

    df = DataFrame(código_cae = códigos, setor = nomes, VAB = VAB,
                   remunerações = remunerações, EBE = EBE, CCF = CCF,
                   rendimento_empresarial = rendimento_empresarial,
                   emprego = emprego, FBCF = FBCF, stock_capital = stock_capital)

    metadados = Dict{String, Any}(
        "fonte" => "Dados sintéticos (estrutura baseada em INE)",
        "ano" => ano, "PIB_total" => sum(VAB), "emprego_total" => sum(emprego))

    return DadosINE(ano, df, df, df, df, metadados)
end

"""Processa os Quadros de Recursos e Empregos, adicionando indicadores marxianos."""
function processar_qre(dados::DadosINE)
    println("\n🔄 Processando QRE...")
    df = dados.qre
    df.salário_médio        = df.remunerações ./ df.emprego
    df.produtividade        = df.VAB ./ df.emprego
    df.intensidade_capital  = df.stock_capital ./ df.emprego
    df.taxa_mais_valia      = df.rendimento_empresarial ./ df.remunerações
    df.composição_orgânica  = df.stock_capital ./ df.remunerações
    df.taxa_lucro           = df.rendimento_empresarial ./ (df.stock_capital .+ df.remunerações)
    return df
end

"""Estima os parâmetros marxianos por setor a partir do QRE processado."""
function estimar_parametros_setoriais(df::DataFrame, A::Matrix{Float64})
    println("\n📐 Estimando parâmetros...")
    N = nrow(df)
    C = df.stock_capital
    V = df.remunerações
    e = max.(0.1, df.taxa_mais_valia)
    k = C ./ V
    r = e ./ (k .+ 1)

    l = df.emprego ./ df.VAB .* 1800
    l = l ./ maximum(l)

    σ_c = clamp.(df.FBCF ./ df.rendimento_empresarial, 0.1, 0.7)
    σ_v = fill(0.15, N)
    δ = df.CCF ./ df.stock_capital

    γ = 1.0 .- σ_c .- σ_v
    for i in 1:N
        if γ[i] < 0
            σ_c[i] = 0.6; σ_v[i] = 0.2; γ[i] = 0.2
        end
    end

    println("  ✓ e médio: $(round(mean(e), digits=2)) | k médio: $(round(mean(k), digits=2)) | r médio: $(round(mean(r)*100, digits=1))%")
    return (C = C, V = V, e = e, k = k, r = r, l = l, σ_c = σ_c, σ_v = σ_v, δ = δ)
end

"""
    calibrar_modelo_portugal(; ano=2022, agregação=:detalhada)

Pipeline de calibração com dados INE sintéticos. `agregação` é aceite por
compatibilidade mas apenas `:detalhada` (19 setores) está totalmente ligada.
"""
function calibrar_modelo_portugal(; ano = 2022, agregação = :detalhada)
    println("\n" * "="^70)
    println("CALIBRAÇÃO PARA PORTUGAL (INE)  |  Ano: $ano  |  Agregação: $agregação")
    println("="^70)

    dados = gerar_dados_sintéticos_portugal(ano)
    df = processar_qre(dados)
    N = nrow(df)
    A = criar_matriz_tecnica(N, densidade = 0.4)
    p = estimar_parametros_setoriais(df, A)

    resultado = ParâmetrosCalibrados(N, df.setor, df.código_cae,
        p.C, p.V, p.e, p.k, p.r, A, p.l, p.σ_c, p.σ_v, p.δ,
        "INE (sintético)", ano, now(), 0.85)

    println("\n✅ CALIBRAÇÃO CONCLUÍDA — $N setores | PIB: $(round(sum(df.VAB)/1000, digits=1)) mil M€")
    return resultado
end
