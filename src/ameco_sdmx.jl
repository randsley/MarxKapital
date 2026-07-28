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
`(dataflow do capítulo, código ITEM, fator de escala)` na API SDMX. As
entradas marcadas "verificado" foram confirmadas com uma chamada real durante
o desenvolvimento (2026-07); as restantes ainda não têm capítulo confirmado —
ficam por preencher aqui e `descarregar_ameco_sdmx` simplesmente não as
inclui no resultado, sem erro (ver docstring dessa função e
`docs/LIMITACOES.md` item 3).

O fator de escala converte a unidade devolvida pela API (confirmada via a
coluna COMMENT/UNIT_MULT de cada resposta) para a convenção já usada no resto
do código (dados sintéticos, `calibrar_com_dados_ameco`): milhões de euros
para variáveis monetárias, milhares de pessoas para emprego. As variáveis
monetárias verificadas vêm em "Mrd EURO" (mil milhões) — escala 1000 para
milhões; o emprego já vem em milhares de pessoas — escala 1.
"""
const MAPA_AMECO_SDMX = Dict(
    "PIB_corrente"          => ("AMECO_CHAPTER06-01", "UVGD", 1000.0),  # verificado
    "PIB_constante"         => ("AMECO_CHAPTER06-01", "OVGD", 1000.0),  # verificado
    "emprego_total"         => ("AMECO_CHAPTER01-04", "NETD", 1.0),     # verificado
    "remunerações"          => ("AMECO_CHAPTER07-01", "UWCD", 1000.0),  # verificado
    "FBCF"                  => ("AMECO_CHAPTER03-01", "UIGT", 1000.0),  # verificado
    "stock_capital_líquido" => ("AMECO_CHAPTER08-01", "OKND", 1000.0),  # verificado
)

"""
Chama a API SDMX para um (dataflow, item, área) e devolve Dict{Int,Float64}
ano→valor. A chave SDMX fixa TRANSFORMATION=1, UNIT=0 e REFERENCE=0 e deixa
AGG_METHOD por preencher (`.`): sem isto, a API devolve várias séries por
ano para o mesmo item (ex.: UVGD sem UNIT fixo devolve preços correntes,
PPS e ECU/EUR em simultâneo) e o dicionário ano→valor ficaria dependente da
ordem de chegada das linhas. Verificado com UVGD, OVGD, NETD, UWCD, UIGT e
OKND (2026-07): cada um devolve exatamente uma linha por ano com esta chave.
"""
function _obter_série_sdmx(dataflow::String, código_área::String, item::String)
    url = "$URL_BASE_SDMX_AMECO/data/ECFIN,$dataflow,1.0/A.$código_área.1..0.0.$item" *
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
    for (nome, (dataflow, item, escala)) in MAPA_AMECO_SDMX
        série = _obter_série_sdmx(dataflow, código_área, item)
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
