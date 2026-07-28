# ============================================================================
# API SDMX DO EUROSTAT — DADOS SETORIAIS REAIS
# ============================================================================
# Fornece dados setoriais reais (VAB, remunerações, emprego, FBCF, stock de
# capital, e fluxos intersetoriais para a matriz técnica A) para substituir
# os pesos fixos/dados sintéticos em `calibracao_pt.jl` e `ameco.jl`. Usa a
# API REST SDMX do Eurostat (ec.europa.eu/eurostat/api/dissemination/sdmx),
# plataforma distinta da API AMECO (ameco_sdmx.jl) mas com o mesmo formato
# de pedido/resposta (SDMX-CSV).
#
# Verificado com dados reais de Portugal (2026-07):
#   VAB (B1G), remunerações (D1), CCF (P51C)   → dataflow NAMA_10_A64
#   Emprego (EMP_DC)                            → dataflow NAMA_10_A64_E
#   FBCF (P51G, asset10=N11G)                   → dataflow NAMA_10_A64_P5
#   Stock de capital líquido (asset10=N11N)      → dataflow NAMA_10_NFA_ST
#   Fluxos intersetoriais (IOT simétrico)        → dataflow NAIO_10_CP1620
#
# A dimensão `nace_r2` aceita códigos de secção NACE de 1 letra (A-U)
# diretamente — as mesmas 19 letras (A-S) já usadas como `código_cae` em
# `calibracao_pt.jl`. Um único pedido com `nace_r2` por preencher devolve
# todas as secções de uma vez (confirmado). O IOT simétrico não aceita
# secções diretamente — usa códigos mais finos (nível A64, ex. "A01",
# "CPA_C10-12"); a secção correspondente é sempre a primeira letra do
# código (depois de remover o prefixo "CPA_", quando presente).
#
# Cobertura: o Eurostat só cobre países da UE/EEE/candidatos. Países fora
# dessa cobertura (ex. Estados Unidos, Japão) devolvem séries vazias — quem
# chama estas funções deve prever um caminho de reserva (ver `ameco.jl`,
# `dados_setoriais=:fixo`).
# ============================================================================

const URL_BASE_EUROSTAT_SDMX = "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1"

"""As 19 secções NACE Rev.2 usadas como `código_cae` em `calibracao_pt.jl`."""
const SECÇÕES_NACE = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                      "L", "M", "N", "O", "P", "Q", "R", "S"]

"""Agregação macro (3 setores: Primário/Secundário/Terciário), usada pelo
caminho AMECO (`src/ameco.jl`) e por `agregação=:macro` no caminho INE
(`src/calibracao_pt.jl`)."""
const GRUPOS_MACRO_NACE = [["A"], ["B", "C", "D", "E", "F"],
                           ["G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S"]]

"""Agregação intermédia — nível padrão NACE Rev.2 "A10" (10 grupos), restrito
às secções A-S já usadas neste projeto (sem T/U, atividades das famílias e
extraterritoriais, irrelevantes aqui). Usada por `agregação=:média` no
caminho INE (`src/calibracao_pt.jl`)."""
const GRUPOS_MEDIO_NACE = [
    ["A"],                  # Agricultura, floresta e pesca
    ["B", "C", "D", "E"],   # Indústria, incl. energia
    ["F"],                  # Construção
    ["G", "H", "I"],        # Comércio, transportes, alojamento e restauração
    ["J"],                  # Informação e comunicação
    ["K"],                  # Atividades financeiras e de seguros
    ["L"],                  # Atividades imobiliárias
    ["M", "N"],             # Atividades profissionais, científicas, administrativas
    ["O", "P", "Q"],        # Administração pública, educação, saúde
    ["R", "S"],             # Artísticas, outras atividades de serviços
]

"""
Chama a API SDMX do Eurostat para `dataflow`/`chave` e devolve
Dict{String,Dict{Int,Float64}} secção NACE → (ano → valor). Filtra a
resposta às linhas cujo `nace_r2` é uma secção de 1 letra (A-S); ignora
subdivisões A64 mais finas e as secções T/U (atividades das famílias e
extraterritoriais, irrelevantes aqui). Falha (rede, formato, sem dados)
devolve um dicionário vazio — nunca lança erro.
"""
function _obter_secções_eurostat(dataflow::String, chave::String)
    url = "$URL_BASE_EUROSTAT_SDMX/data/ESTAT,$dataflow,1.0/$chave?format=SDMX-CSV"
    try
        resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                        retry = true, readtimeout = 30, status_exception = false)
        resp.status == 200 || return Dict{String, Dict{Int, Float64}}()
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        (nrow(df) == 0 || !("nace_r2" in names(df)) ||
         !("TIME_PERIOD" in names(df)) || !("OBS_VALUE" in names(df))) &&
            return Dict{String, Dict{Int, Float64}}()

        resultado = Dict{String, Dict{Int, Float64}}()
        for row in eachrow(df)
            secção = String(row.nace_r2)
            (length(secção) == 1 && secção in SECÇÕES_NACE) || continue
            ismissing(row.OBS_VALUE) && continue
            d = get!(resultado, secção, Dict{Int, Float64}())
            d[Int(row.TIME_PERIOD)] = Float64(row.OBS_VALUE)
        end
        return resultado
    catch
        return Dict{String, Dict{Int, Float64}}()
    end
end

"""Como `_obter_secções_eurostat`, mas já reduzido a um único ano (Dict{String,Float64})."""
function _valores_setoriais_eurostat(dataflow::String, chave::String, ano::Int)
    secções = _obter_secções_eurostat(dataflow, chave)
    Dict(s => v[ano] for (s, v) in secções if haskey(v, ano))
end

"""VAB, remunerações e consumo de capital fixo por secção (milhões de euros)."""
function obter_vab_remuneracoes_ccf_eurostat(código_país::String, ano::Int)
    vab   = _valores_setoriais_eurostat("NAMA_10_A64", "A.CP_MEUR..B1G.$código_país", ano)
    remun = _valores_setoriais_eurostat("NAMA_10_A64", "A.CP_MEUR..D1.$código_país", ano)
    ccf   = _valores_setoriais_eurostat("NAMA_10_A64", "A.CP_MEUR..P51C.$código_país", ano)
    return vab, remun, ccf
end

"""Emprego por secção (milhares de pessoas, conceito doméstico)."""
function obter_emprego_setorial_eurostat(código_país::String, ano::Int)
    _valores_setoriais_eurostat("NAMA_10_A64_E", "A.THS_PER..EMP_DC.$código_país", ano)
end

"""FBCF (formação bruta de capital fixo) por secção, todos os tipos de ativo (milhões de euros)."""
function obter_fbcf_setorial_eurostat(código_país::String, ano::Int)
    _valores_setoriais_eurostat("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$código_país", ano)
end

"""Stock de capital líquido por secção, todos os tipos de ativo (milhões de euros, preço de substituição)."""
function obter_stock_capital_setorial_eurostat(código_país::String, ano::Int)
    _valores_setoriais_eurostat("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$código_país", ano)
end

"""Série completa (todos os anos disponíveis) de FBCF por secção — usada pelo inventário perpétuo (`calcular_stock_capital_pim`)."""
function obter_série_fbcf_setorial_eurostat(código_país::String)
    _obter_secções_eurostat("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$código_país")
end

"""Série completa (todos os anos disponíveis) de stock de capital líquido por secção — usada como referência (benchmark) pelo inventário perpétuo."""
function obter_série_stock_capital_setorial_eurostat(código_país::String)
    _obter_secções_eurostat("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$código_país")
end

"""Série completa (todos os anos disponíveis) de CCF por secção — usada para estimar δ no inventário perpétuo."""
function obter_série_ccf_setorial_eurostat(código_país::String)
    _obter_secções_eurostat("NAMA_10_A64", "A.CP_MEUR..P51C.$código_país")
end

"""
    calcular_stock_capital_pim(fbcf_série, δ, benchmark_ano, benchmark_valor, anos)

Constrói uma série de stock de capital pelo método do inventário perpétuo
(PIM — Perpetual Inventory Method): `Kₜ = (1-δ)·Kₜ₋₁ + FBCFₜ`, a partir de
um ano de referência (`benchmark_ano`, `benchmark_valor` — tipicamente o
stock líquido reportado pelo Eurostat no ano mais antigo disponível) e uma
série de FBCF (`fbcf_série`, `Dict{Int,Float64}` ano→valor). `δ` é uma taxa
de depreciação única (não diferenciada por tipo de ativo — essa seria uma
extensão de maior fidelidade, ver `docs/LIMITACOES.md` item 7), tipicamente
estimada como `CCF/stock` no ano de referência, não um valor fixo ~10%.

Devolve `Dict{Int,Float64}` ano→stock, só para os anos em que a recursão
consegue avançar sem interrupção (para se faltar FBCF nalgum ano
intermédio — a série fica truncada nesse ponto, não extrapolada).
"""
function calcular_stock_capital_pim(fbcf_série::Dict{Int, Float64}, δ::Float64,
                                    benchmark_ano::Int, benchmark_valor::Float64,
                                    anos::Vector{Int})
    K = Dict{Int, Float64}(benchmark_ano => benchmark_valor)
    for a in (benchmark_ano + 1):maximum(anos)
        (haskey(fbcf_série, a) && haskey(K, a - 1)) || continue
        K[a] = (1 - δ) * K[a - 1] + fbcf_série[a]
    end
    return K
end

"""Secção NACE (1 letra) correspondente a um código A64 do IOT (ex. "A01"→"A", "CPA_C10-12"→"C")."""
function _secção_do_código_a64(código::String)
    s = startswith(código, "CPA_") ? código[5:end] : código
    isempty(s) && return ""
    return string(uppercase(s[1]))
end

"""
    construir_matriz_io_eurostat(código_país, ano, grupos, vab_por_secção)

Constrói uma matriz técnica G×G a partir do IOT simétrico real do Eurostat
(NAIO_10_CP1620) para `código_país`/`ano`, agregando os códigos A64 em
`grupos` (cada elemento é uma lista de secções NACE — `[["A"],["B"],...]`
para 19 setores, ou `[["A"],["B","C","D","E","F"],[...]]` para 3 setores
macro). `vab_por_secção` (de `obter_vab_remuneracoes_ccf_eurostat`) fornece
o VAB para completar a identidade oferta-uso.

Coeficiente técnico: `A[i,j] = fluxo(i→j) / output_bruto(j)`, com
`output_bruto(j) = Σᵢ fluxo(i→j) + VAB(j)`. Reforça produtividade (ρ(A)<1)
com a mesma regra de `criar_matriz_tecnica` (`src/nucleo.jl`).

Lança erro se o IOT não tiver dados para o país/ano — ao contrário das
séries setoriais (que degradam secção a secção), sem o IOT não há matriz
real possível; quem chama deve tratar isto como falha da via `:eurostat`
e cair para o caminho de reserva (`criar_matriz_tecnica`).
"""
function construir_matriz_io_eurostat(código_país::String, ano::Int,
                                      grupos::Vector{Vector{String}},
                                      vab_por_secção::Dict{String, Float64})
    G = length(grupos)
    secção_para_grupo = Dict{String, Int}()
    for (gi, secções) in enumerate(grupos), s in secções
        secção_para_grupo[s] = gi
    end

    url = "$URL_BASE_EUROSTAT_SDMX/data/ESTAT,NAIO_10_CP1620,1.0/A.MIO_EUR.TOTAL...$código_país" *
          "?format=SDMX-CSV&startPeriod=$ano&endPeriod=$ano"
    resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                    retry = true, readtimeout = 60, status_exception = false)
    resp.status == 200 || error("IOT Eurostat indisponível para $código_país/$ano (status $(resp.status)).")
    df = CSV.read(IOBuffer(resp.body), DataFrame)
    nrow(df) == 0 && error("IOT Eurostat sem dados para $código_país/$ano.")

    # `ind_use` (colunas) inclui não só indústrias mas categorias de procura
    # final (P3_S14 consumo, P51G FBCF, P6 exportações, ...) cujo código
    # colide por primeira letra com secções reais (ex. "P3_S14" → "P",
    # confundido com a secção P "Educação"). Restringe-se `ind_use` ao
    # conjunto de códigos que também aparecem como produto (`cpa2_1`) — só
    # esses são indústrias reais no IOT simétrico.
    códigos_indústria = Set(replace(String(c), "CPA_" => "")
                            for c in df.cpa2_1 if c != "CPA_TOTAL")

    # O IOT simétrico a preços base regista as margens de comércio/transporte
    # (produtos CPA_G45-47/H49-53) como fluxos por vezes negativos — a
    # realocação da margem para o produto realmente comprado é uma célula
    # negativa na própria linha do produto de comércio/transporte, uma
    # convenção normal de contabilidade nacional nestas tabelas, não um erro.
    # Confirmado nos dados reais: as 317 células negativas de PT/2022 estão
    # TODAS confinadas a essas duas secções como fornecedoras — nenhuma outra
    # célula é negativa. Um coeficiente técnico negativo não é interpretável
    # no sentido de Leontief usado no resto do código (calcular_valores_trabalho,
    # calcular_precos_producao assumem A ≥ 0), mas colapsar a MATRIZ AGREGADA
    # a zero apagaria também os fluxos genuínos de outras secções de serviços
    # somadas no mesmo grupo (ex. no agrupamento de 3 setores, isto zerava a
    # linha inteira do Terciário). Em vez disso, cada célula bruta é colapsada
    # a zero ANTES de somar por grupo, para que só a margem seja descartada.
    F = zeros(G, G)
    for row in eachrow(df)
        ismissing(row.OBS_VALUE) && continue
        String(row.ind_use) in códigos_indústria || continue
        si = _secção_do_código_a64(String(row.cpa2_1))
        sj = _secção_do_código_a64(String(row.ind_use))
        (haskey(secção_para_grupo, si) && haskey(secção_para_grupo, sj)) || continue
        F[secção_para_grupo[si], secção_para_grupo[sj]] += max(Float64(row.OBS_VALUE), 0.0)
    end

    VAB_grupo = [sum(get(vab_por_secção, s, 0.0) for s in secções) for secções in grupos]
    output_bruto = [sum(F[:, j]) + VAB_grupo[j] for j in 1:G]

    A = zeros(G, G)
    for i in 1:G, j in 1:G
        output_bruto[j] > 0 && (A[i, j] = F[i, j] / output_bruto[j])
    end

    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && (A = A / ρ_A * 0.8)
    return A
end

"""
    agregar_matriz_io(A_fina, secções_finas, grupos, pesos)

Agrega uma matriz técnica N×N (`A_fina`, cujas linhas/colunas correspondem,
por ordem, a `secções_finas`) num conjunto de G grupos (`grupos`, cada
elemento uma lista de identificadores de `secções_finas`), pela fórmula
padrão de agregação de matrizes de Leontief: cada coluna agregada é a média
das colunas finas do grupo, ponderada pelo peso de cada setor fino
(tipicamente VAB ou output bruto, em `pesos`), não uma média simples:

    A_grossa[gi,gj] = Σ_{i∈Gi} Σ_{j∈Gj} A_fina[i,j]·pesos[j]  /  Σ_{j∈Gj} pesos[j]

Preserva não-negatividade (soma/média ponderada de valores não-negativos) —
ao contrário de agregar os fluxos brutos do IOT diretamente (ver nota em
`construir_matriz_io_eurostat` sobre as margens de comércio/transporte),
agregar coeficientes já limpos evita reintroduzir esse problema. Não assume
nada sobre a origem de `A_fina` — funciona tanto para uma matriz real
(`construir_matriz_io_eurostat`) como para uma matriz aleatória
(`criar_matriz_tecnica`, `src/nucleo.jl`), útil para agregação setorial
independente da fonte de dados (`agregar_setores`, `src/calibracao_pt.jl`).
Setores de `secções_finas` sem grupo correspondente em `grupos` são
ignorados (permite `grupos` parcial).
"""
function agregar_matriz_io(A_fina::Matrix{Float64}, secções_finas::Vector{String},
                           grupos::Vector{Vector{String}}, pesos::Dict{String, Float64})
    N = length(secções_finas)
    G = length(grupos)
    idx = Dict(s => i for (i, s) in enumerate(secções_finas))
    grupo_de = Dict{Int, Int}()
    for (gi, secções) in enumerate(grupos), s in secções
        haskey(idx, s) && (grupo_de[idx[s]] = gi)
    end
    peso_fino = [get(pesos, s, 0.0) for s in secções_finas]

    A_grossa = zeros(G, G)
    denom = zeros(G)
    for j in 1:N
        haskey(grupo_de, j) || continue
        denom[grupo_de[j]] += peso_fino[j]
    end
    for i in 1:N, j in 1:N
        (haskey(grupo_de, i) && haskey(grupo_de, j)) || continue
        A_grossa[grupo_de[i], grupo_de[j]] += A_fina[i, j] * peso_fino[j]
    end
    for gj in 1:G
        denom[gj] > 0 && (A_grossa[:, gj] ./= denom[gj])
    end
    return A_grossa
end

"""
    verificar_eurostat_setorial()

Verificação manual (não corre nos testes automáticos): confirma acesso às
séries setoriais e ao IOT do Eurostat para Portugal, com valores plausíveis.
Corra com:  `include("src/MarxKapital.jl"); verificar_eurostat_setorial()`
"""
function verificar_eurostat_setorial()
    println("\n" * "="^70)
    println("VERIFICAÇÃO MANUAL — DADOS SETORIAIS EUROSTAT")
    println("="^70)
    ano = 2022
    ok = true

    vab, remun, ccf = obter_vab_remuneracoes_ccf_eurostat("PT", ano)
    n_vab = length(vab)
    println(n_vab >= 15 ? "✓" : "✗", " VAB: $n_vab/19 secções (esperado ≥15)")
    ok &= n_vab >= 15

    emprego = obter_emprego_setorial_eurostat("PT", ano)
    println(length(emprego) >= 15 ? "✓" : "✗", " Emprego: $(length(emprego))/19 secções")
    ok &= length(emprego) >= 15

    try
        A = construir_matriz_io_eurostat("PT", ano, [[s] for s in SECÇÕES_NACE], vab)
        ρ_A = maximum(abs.(eigvals(A)))
        plausível = size(A) == (19, 19) && ρ_A < 1.0
        println(plausível ? "✓" : "✗", " Matriz A real: $(size(A)), ρ(A)=$(round(ρ_A, digits=3))")
        ok &= plausível
    catch e
        println("✗ Matriz A real: falhou ($e)")
        ok = false
    end

    try
        stock_reportado = obter_stock_capital_setorial_eurostat("PT", ano)
        secções_pim = [s for s in SECÇÕES_NACE if haskey(stock_reportado, s)][1:min(3, end)]
        stock_pim = _stock_capital_pim_por_secção("PT", ano, secções_pim, stock_reportado)
        desvios = [abs(stock_pim[s] - stock_reportado[s]) / stock_reportado[s] for s in secções_pim]
        plausível = maximum(desvios) < 0.5   # mesma ordem de grandeza, não igual (metodologias diferentes)
        println(plausível ? "✓" : "✗", " Stock por inventário perpétuo vs. reportado (",
                join(secções_pim, ","), "): desvio máx. $(round(maximum(desvios)*100, digits=1))%")
        ok &= plausível
    catch e
        println("✗ Stock por inventário perpétuo: falhou ($e)")
        ok = false
    end

    println("="^70 * "\n")
    return ok
end
