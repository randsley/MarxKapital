# ============================================================================
# CALIBRAÇÃO COM DADOS PORTUGUESES (INE)
# ============================================================================
# Gera dados sintéticos com a estrutura setorial (CAE Rev.3) da economia
# portuguesa e calibra o modelo. Os valores são aproximações para
# demonstração — NÃO usar em análise oficial. Ver `obter_dados_portugal_eurostat`
# para o caminho com dados reais (opt-in, `fonte_dados=:eurostat`).
# ============================================================================

"""19 setores CAE Rev.3 (código, nome), usados tanto no caminho sintético como no real."""
const SETORES_CAE_PT = [
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

"""Gera dados sintéticos baseados na estrutura setorial portuguesa (19 setores CAE)."""
function gerar_dados_sintéticos_portugal(ano::Int)
    println("\n🔬 Gerando dados sintéticos para Portugal ($ano)...")

    setores = SETORES_CAE_PT
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

"""
    obter_dados_portugal_eurostat(ano)

Constrói o mesmo formato de `DadosINE` que `gerar_dados_sintéticos_portugal`,
mas com dados setoriais reais do Eurostat (`src/eurostat_sdmx.jl`): VAB,
remunerações e consumo de capital fixo (NAMA_10_A64), emprego
(NAMA_10_A64_E), FBCF (NAMA_10_A64_P5) e stock de capital líquido
(NAMA_10_NFA_ST), para as 19 secções NACE. Usa apenas as secções com dados
completos nas 6 séries; lança erro se restarem poucas (menos de 10 de 19) —
sinal de falha de rede ou indisponibilidade, não um caso normal a degradar
silenciosamente.
"""
function obter_dados_portugal_eurostat(ano::Int)
    println("\n🌐 A obter dados setoriais reais (Eurostat) para Portugal ($ano)...")

    vab, remun, ccf = obter_vab_remuneracoes_ccf_eurostat("PT", ano)
    emprego = obter_emprego_setorial_eurostat("PT", ano)
    fbcf = obter_fbcf_setorial_eurostat("PT", ano)
    stock = obter_stock_capital_setorial_eurostat("PT", ano)

    secções_completas = filter(s -> haskey(vab, s) && haskey(remun, s) && haskey(ccf, s) &&
                                    haskey(emprego, s) && haskey(fbcf, s) && haskey(stock, s),
                               [s[1] for s in SETORES_CAE_PT])
    length(secções_completas) < 10 &&
        error("Dados Eurostat incompletos para Portugal/$ano: só $(length(secções_completas))/19 " *
              "secções com as 6 séries completas.")

    nomes_por_código = Dict(s[1] => s[2] for s in SETORES_CAE_PT)
    códigos = secções_completas
    nomes = [nomes_por_código[c] for c in códigos]

    VAB = [vab[c] for c in códigos]
    remunerações = [remun[c] for c in códigos]
    CCF = [ccf[c] for c in códigos]
    EBE = VAB .- remunerações
    rendimento_empresarial = EBE .- CCF
    emprego_v = [emprego[c] for c in códigos]
    FBCF = [fbcf[c] for c in códigos]
    stock_capital = [stock[c] for c in códigos]

    df = DataFrame(código_cae = códigos, setor = nomes, VAB = VAB,
                   remunerações = remunerações, EBE = EBE, CCF = CCF,
                   rendimento_empresarial = rendimento_empresarial,
                   emprego = emprego_v, FBCF = FBCF, stock_capital = stock_capital)

    println("  ✓ $(length(códigos))/19 secções com dados reais completos.")

    metadados = Dict{String, Any}(
        "fonte" => "Eurostat (dados reais)",
        "ano" => ano, "PIB_total" => sum(VAB), "emprego_total" => sum(emprego_v))

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

"""Nomes em português para os 10 grupos de `GRUPOS_MEDIO_NACE` (mesma ordem)."""
const NOMES_GRUPOS_MEDIO = [
    "Agricultura, floresta e pesca", "Indústria (incl. energia)", "Construção",
    "Comércio, transportes, alojamento e restauração", "Informação e comunicação",
    "Atividades financeiras e de seguros", "Atividades imobiliárias",
    "Atividades profissionais, científicas e administrativas",
    "Administração pública, educação e saúde", "Atividades artísticas e outros serviços",
]
const CÓDIGOS_GRUPOS_MEDIO = ["A", "BCDE", "F", "GHI", "J", "K", "L", "MN", "OPQ", "RS"]

"""
    agregar_setores(df, A, grupos, códigos_grupos, nomes_grupos)

Agrega um DataFrame de setores (colunas `código_cae, setor, VAB,
remunerações, EBE, CCF, rendimento_empresarial, emprego, FBCF,
stock_capital` — o formato produzido por `gerar_dados_sintéticos_portugal`/
`obter_dados_portugal_eurostat`) e a matriz técnica `A` correspondente para
um número menor de grupos (cada elemento de `grupos` é uma lista de
`código_cae` de 1 letra a juntar). Devolve `(df_agregado, A_agregada)`.

Funciona tanto com `A` real (`construir_matriz_io_eurostat`) como aleatória
(`criar_matriz_tecnica`) — reusa `agregar_matriz_io` (`src/eurostat_sdmx.jl`),
que só assume `A ≥ 0` e pesos (VAB) `≥ 0`, sem depender da origem dos dados.
"""
function agregar_setores(df::DataFrame, A::Matrix{Float64}, grupos::Vector{Vector{String}},
                         códigos_grupos::Vector{String}, nomes_grupos::Vector{String})
    vab_por_secção = Dict(zip(df.código_cae, df.VAB))
    A_agregada = agregar_matriz_io(A, df.código_cae, grupos, vab_por_secção)

    soma(col) = [sum(df[in.(df.código_cae, Ref(secções)), col]) for secções in grupos]

    df_agregado = DataFrame(
        código_cae = códigos_grupos, setor = nomes_grupos,
        VAB = soma(:VAB), remunerações = soma(:remunerações), EBE = soma(:EBE),
        CCF = soma(:CCF), rendimento_empresarial = soma(:rendimento_empresarial),
        emprego = soma(:emprego), FBCF = soma(:FBCF), stock_capital = soma(:stock_capital))

    return df_agregado, A_agregada
end

"""
    calibrar_modelo_portugal(; ano=2022, agregação=:detalhada, fonte_dados=:sintético)

Pipeline de calibração com dados INE. `agregação`:
- `:detalhada` (omissão) — 19 setores CAE, sem agregação.
- `:macro` — 3 setores (Primário/Secundário/Terciário, `GRUPOS_MACRO_NACE`,
  `src/eurostat_sdmx.jl`), mesma agregação usada no caminho AMECO.
- `:média` — 10 setores (nível padrão NACE Rev.2 "A10", `GRUPOS_MEDIO_NACE`).

Em ambos os modos agregados, a matriz técnica `A` é agregada pela fórmula de
Leontief (`agregar_matriz_io`) — funciona com `A` sintética (aleatória) ou
real (`fonte_dados=:eurostat`), sem distinção de código entre os dois casos.

`fonte_dados`:
- `:sintético` (omissão) — estrutura sintética, `A` aleatória (comportamento
  histórico, inalterado).
- `:eurostat` — dados setoriais reais (`obter_dados_portugal_eurostat`) e
  matriz técnica `A` real, construída a partir do IOT simétrico do Eurostat
  (`construir_matriz_io_eurostat`). Requer rede; lança erro se indisponível
  (sem fallback silencioso — pedido explícito de dados reais).
"""
function calibrar_modelo_portugal(; ano = 2022, agregação = :detalhada,
                                  fonte_dados = :sintético)
    println("\n" * "="^70)
    println("CALIBRAÇÃO PARA PORTUGAL (INE)  |  Ano: $ano  |  Agregação: $agregação  |  Fonte: $fonte_dados")
    println("="^70)

    dados = fonte_dados == :eurostat ? obter_dados_portugal_eurostat(ano) :
                                       gerar_dados_sintéticos_portugal(ano)
    df19 = processar_qre(dados)
    N19 = nrow(df19)
    A19 = fonte_dados == :eurostat ?
        construir_matriz_io_eurostat("PT", ano, [[c] for c in df19.código_cae],
                                     Dict(zip(df19.código_cae, df19.VAB))) :
        criar_matriz_tecnica(N19, densidade = 0.4)

    df, A = if agregação == :detalhada
        df19, A19
    elseif agregação == :macro
        agregar_setores(df19, A19, GRUPOS_MACRO_NACE, ["PRIM", "SEC", "TER"],
                        ["Primário", "Secundário", "Terciário"])
    elseif agregação == :média
        agregar_setores(df19, A19, GRUPOS_MEDIO_NACE, CÓDIGOS_GRUPOS_MEDIO, NOMES_GRUPOS_MEDIO)
    else
        error("agregação '$agregação' desconhecida (use :detalhada, :macro ou :média)")
    end
    agregação == :detalhada || (df = processar_qre(DadosINE(dados.ano, df, df, df, df, dados.metadados)))
    N = nrow(df)
    p = estimar_parametros_setoriais(df, A)

    fonte = fonte_dados == :eurostat ? "INE/Eurostat (dados reais)" : "INE (sintético)"
    resultado = ParâmetrosCalibrados(N, df.setor, df.código_cae,
        p.C, p.V, p.e, p.k, p.r, A, p.l, p.σ_c, p.σ_v, p.δ,
        fonte, ano, now(), 0.85)

    println("\n✅ CALIBRAÇÃO CONCLUÍDA — $N setores | PIB: $(round(sum(df.VAB)/1000, digits=1)) mil M€")
    return resultado
end
