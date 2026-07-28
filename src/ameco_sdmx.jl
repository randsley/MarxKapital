# ============================================================================
# API SDMX OFICIAL DA AMECO
# ============================================================================
# A Comissão Europeia retirou a distribuição do ficheiro TXT estático usado
# por `ameco_download.jl` (URLs em URLS_AMECO_TENTAR devolvem 404 ou
# redirecionam para a página HTML do portal, não para dados). Em alternativa,
# a AMECO passou a expor uma API REST SDMX oficial, na mesma plataforma da
# nova ferramenta de dados do Eurostat:
#
#     https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1
#
# Cada grupo de variáveis da AMECO vive num "capítulo" (dataflow) próprio
# (ex.: AMECO_CHAPTER06-01 = "Gross domestic product"); não existe um único
# dataflow monolítico. Os mnemónicos já usados em CÓDIGOS_AMECO_VARIÁVEIS
# (estruturas.jl) continuam válidos como código ITEM nesta API — não foi
# necessário remapeá-los. Os códigos de país são maioritariamente ISO3, mas
# com irregularidades reais (GRC em vez de EL, GBR em vez de UK, ROM em vez
# de ROU) e códigos agregados próprios (EU27, EA21, D_W); por isso não são
# compatíveis com CÓDIGOS_PAÍSES_AMECO (códigos do antigo ficheiro TXT) e
# precisam de um mapeamento próprio.
# ============================================================================

const URL_BASE_SDMX_AMECO =
    "https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1"

"""
País (nome em português, mesmas chaves de `CÓDIGOS_PAÍSES_AMECO`) → código
REF_AREA usado pela API SDMX da AMECO. Construído a partir do codelist
`CL_AMECO_AREA` (verificado em julho de 2026). "União Europeia (28)" não tem
equivalente na base atual (código retirado após o Brexit) e foi omitido —
resolver esse país cai no código antigo de 2 letras, que a API SDMX
simplesmente não reconhece (devolve série vazia, sem erro).
"""
const CÓDIGOS_PAÍSES_AMECO_SDMX = Dict(
    "Áustria" => "AUT", "Bélgica" => "BEL", "Bulgária" => "BGR",
    "Croácia" => "HRV", "Chipre" => "CYP", "República Checa" => "CZE",
    "Dinamarca" => "DNK", "Estónia" => "EST", "Finlândia" => "FIN",
    "França" => "FRA", "Alemanha" => "DEU", "Grécia" => "GRC",
    "Hungria" => "HUN", "Irlanda" => "IRL", "Itália" => "ITA",
    "Letónia" => "LVA", "Lituânia" => "LTU", "Luxemburgo" => "LUX",
    "Malta" => "MLT", "Países Baixos" => "NLD", "Polónia" => "POL",
    "Portugal" => "PRT", "Roménia" => "ROM", "Eslováquia" => "SVK",
    "Eslovénia" => "SVN", "Espanha" => "ESP", "Suécia" => "SWE",
    "Área do Euro" => "EA21", "Área do Euro (19)" => "EA19",
    "Reino Unido" => "GBR", "Noruega" => "NOR", "Suíça" => "CHE",
    "Islândia" => "ISL", "Turquia" => "TUR",
    "União Europeia (27)" => "EU27",
    "Estados Unidos" => "USA", "Japão" => "JPN",
)

"""
Nome interno da variável (mesmas chaves de `CÓDIGOS_AMECO_VARIÁVEIS`) →
`(dataflow do capítulo, código ITEM, fator de escala, TRANSFORMATION)` na
API SDMX. Todas as entradas foram confirmadas com uma chamada real durante o
desenvolvimento (2026-07). Note-se que vários mnemónicos aqui **diferem**
dos que estavam (nunca verificados) em `CÓDIGOS_AMECO_VARIÁVEIS`
(`estruturas.jl`) — por exemplo `receitas_governo`/`despesas_governo`
tinham os códigos trocados (`UUTG` era a despesa, não a receita), e
`consumo_privado`/`exportações`/`importações` usavam mnemónicos que já não
existem na API atual (`UNCT`/`UXTG`/`UMTG` → `UCPH`/`UXGS`/`UMGS`). As
variáveis ainda por confirmar (custos unitários de trabalho indexados,
deflator do PIB, dívida pública, balança comercial, stock de capital bruto)
ficam por preencher aqui; `descarregar_ameco_sdmx` simplesmente não as
inclui no resultado, sem erro (ver `docs/LIMITACOES.md` item 3).

O fator de escala converte a unidade devolvida pela API (confirmada via a
coluna COMMENT/UNIT_MULT de cada resposta) para a convenção já usada no resto
do código (dados sintéticos, `calibrar_com_dados_ameco`): milhões de euros
para variáveis monetárias, milhares de pessoas para emprego, sem escala para
índices/percentagens/valores per capita. As variáveis monetárias verificadas
vêm em "Mrd EURO" (mil milhões) — escala 1000 para milhões (incluindo as do
capítulo 16, rotuladas "National currency" mas na mesma ordem de grandeza —
confirmado pela magnitude: ~107 bate com receita/despesa pública de ~44% de
um PIB de ~244 mil M€, não com 107% do PIB).
"""
const MAPA_AMECO_SDMX = Dict(
    "PIB_corrente"                 => ("AMECO_CHAPTER06-01", "UVGD",  1000.0, 1),
    "PIB_constante"                => ("AMECO_CHAPTER06-01", "OVGD",  1000.0, 1),
    "emprego_total"                => ("AMECO_CHAPTER01-04", "NETD",  1.0,    1),
    "remunerações"                 => ("AMECO_CHAPTER07-01", "UWCD",  1000.0, 1),
    "FBCF"                         => ("AMECO_CHAPTER03-01", "UIGT",  1000.0, 1),
    "stock_capital_líquido"        => ("AMECO_CHAPTER08-01", "OKND",  1000.0, 1),
    "consumo_privado"              => ("AMECO_CHAPTER02-01", "UCPH",  1000.0, 1),
    "consumo_público"              => ("AMECO_CHAPTER02-05", "UCTG",  1000.0, 1),
    "exportações"                  => ("AMECO_CHAPTER09-01", "UXGS",  1000.0, 1),
    "importações"                  => ("AMECO_CHAPTER09-02", "UMGS",  1000.0, 1),
    "emprego_assalariado"          => ("AMECO_CHAPTER01-07", "NWTD",  1.0,    1),
    "taxa_desemprego"              => ("AMECO_CHAPTER01-03", "ZUTN",  1.0,    1),
    "população_ativa"              => ("AMECO_CHAPTER01-02", "NLTN",  1.0,    1),
    "remunerações_por_assalariado" => ("AMECO_CHAPTER07-04", "HWCDW", 1.0,    1),
    "produtividade_trabalho"       => ("AMECO_CHAPTER08-02", "ZVGDE", 1.0,    3),
    "IPC"                          => ("AMECO_CHAPTER02-04", "ZCPIH", 1.0,    1),
    "receitas_governo"             => ("AMECO_CHAPTER16-01", "URTG",  1000.0, 1),
    "despesas_governo"             => ("AMECO_CHAPTER16-02", "UUTG",  1000.0, 1),
    "saldo_orçamental"             => ("AMECO_CHAPTER16-03", "UBLG",  1000.0, 1),
    "balança_corrente"             => ("AMECO_CHAPTER10-01", "UBCA",  1000.0, 1),
)

"""
Chama a API SDMX para um (dataflow, item, área) e devolve Dict{Int,Float64}
ano→valor. A chave SDMX fixa TRANSFORMATION (1 por omissão), UNIT=0 e
REFERENCE=0 e deixa AGG_METHOD por preencher (`.`): sem isto, a API devolve
várias séries por ano para o mesmo item (ex.: UVGD sem UNIT fixo devolve
preços correntes, PPS e ECU/EUR em simultâneo) e o dicionário ano→valor
ficaria dependente da ordem de chegada das linhas. A maioria dos capítulos
usa TRANSFORMATION=1; alguns (ex. capítulo 07-07/08-02, custos unitários e
produtividade) usam TRANSFORMATION=3 — passar explicitamente quando
necessário (confirmado por tentativa: a API devolve "número de filtros
incorreto" se o valor errado for wildcardeado em vez de fixo).
"""
function _obter_série_sdmx(dataflow::String, código_área::String, item::String;
                           transformação::Int = 1)
    url = "$URL_BASE_SDMX_AMECO/data/ECFIN,$dataflow,1.0/A.$código_área.$transformação..0.0.$item" *
          "?format=SDMX-CSV"
    try
        resp = HTTP.get(url, retry = true, readtimeout = 30, status_exception = false)
        resp.status == 200 || return Dict{Int, Float64}()
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        (nrow(df) == 0 || !("TIME_PERIOD" in names(df)) || !("OBS_VALUE" in names(df))) &&
            return Dict{Int, Float64}()
        return Dict(Int(row.TIME_PERIOD) => Float64(row.OBS_VALUE) for row in eachrow(df))
    catch
        return Dict{Int, Float64}()
    end
end

"""
    descarregar_ameco_sdmx(código_área, anos)

Descarrega, via a API SDMX oficial da AMECO, as séries mapeadas em
`MAPA_AMECO_SDMX` para o código de área dado (ver `CÓDIGOS_PAÍSES_AMECO_SDMX`
para resolver a partir do nome do país), devolvendo um
`Dict{String,Vector{Float64}}` pronto para `construir_dados_ameco`
(`src/ameco.jl`). Variáveis sem mapeamento, ou cuja chamada falhe, ficam
simplesmente ausentes do dicionário — `construir_dados_ameco` preenche por
omissão (0.0 ou NaN), pelo que uma falha parcial nunca lança erro.
"""
function descarregar_ameco_sdmx(código_área::String, anos)
    println("\n🌐 A obter dados AMECO via API SDMX oficial ($código_área)...")
    anos_vec = collect(anos)
    resultado = Dict{String, Vector{Float64}}()
    for (nome, (dataflow, item, escala, transformação)) in MAPA_AMECO_SDMX
        série = _obter_série_sdmx(dataflow, código_área, item; transformação = transformação)
        if isempty(série)
            @warn "Sem dados AMECO SDMX para '$nome' ($dataflow, $item, $código_área)."
            continue
        end
        resultado[nome] = [get(série, a, NaN) * escala for a in anos_vec]
    end
    isempty(resultado) && error("Nenhuma série obtida da API SDMX para '$código_área'.")
    println("  ✓ $(length(resultado))/$(length(MAPA_AMECO_SDMX)) séries obtidas.")
    return resultado
end

"""
    verificar_sdmx_ameco()

Verificação manual (não corre nos testes automáticos — ver
`docs/LIMITACOES.md` item 3): confirma que a API SDMX está acessível e que o
PIB de Portugal vem numa ordem de grandeza plausível para um ano recente.
Não compara um valor exato porque a AMECO revê os dados periodicamente.
Corra com:  `include("src/MarxKapital.jl"); verificar_sdmx_ameco()`
"""
function verificar_sdmx_ameco()
    println("\n" * "="^70)
    println("VERIFICAÇÃO MANUAL — API SDMX DA AMECO")
    println("="^70)
    série = _obter_série_sdmx("AMECO_CHAPTER06-01", "PRT", "UVGD")
    if isempty(série)
        println("✗ FALHOU: sem resposta da API para o PIB de Portugal.")
        return false
    end
    ano_recente = maximum(k for k in keys(série) if !isnan(série[k]))
    valor = série[ano_recente]
    plausível = 50.0 < valor < 500.0
    println(plausível ? "✓" : "✗", " PIB de Portugal ($ano_recente): ",
            round(valor, digits = 1), " mil M€ ",
            plausível ? "(plausível)" : "(fora do intervalo esperado 50-500)")
    println("="^70 * "\n")
    return plausível
end
