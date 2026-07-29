# ============================================================================
# ESTRUTURAS DE DADOS E CONSTANTES
# ============================================================================
# Carregado em primeiro lugar: define os tipos e os dicionários de
# constantes usados por todos os restantes ficheiros do pacote.
# ============================================================================

# ----------------------------------------------------------------------------
# Departamento produtivo
# ----------------------------------------------------------------------------

"""
    Departamento

Representa um departamento produtivo na economia marxiana.

# Campos Básicos
- `nome::String`: Identificador do departamento
- `c::Float64`: Capital constante (meios de produção)
- `v::Float64`: Capital variável (força de trabalho / salários)
- `e::Float64`: Taxa de exploração / mais-valia (s/v)
- `k::Float64`: Composição orgânica do capital (c/v)

# Parâmetros Comportamentais
- `σ_c::Float64`: Fração da mais-valia reinvestida em capital constante
- `σ_v::Float64`: Fração da mais-valia reinvestida em capital variável
- `γ::Float64`: Fração da mais-valia consumida pelos capitalistas
- `δ::Float64`: Taxa de depreciação do capital constante

# Invariantes
- σ_c + σ_v + γ = 1.0 (toda a mais-valia é alocada)
- e > 0 (exploração positiva)
- k = c/v (consistência)
"""
struct Departamento
    nome::String
    c::Float64
    v::Float64
    e::Float64
    k::Float64
    σ_c::Float64
    σ_v::Float64
    γ::Float64
    δ::Float64

    function Departamento(nome, c, v, e, k, σ_c, σ_v, γ, δ)
        @assert c > 0 "Capital constante deve ser positivo"
        @assert v > 0 "Capital variável deve ser positivo"
        @assert e > 0 "Taxa de exploração deve ser positiva"
        @assert 0 ≤ σ_c ≤ 1 "σ_c deve estar em [0,1]"
        @assert 0 ≤ σ_v ≤ 1 "σ_v deve estar em [0,1]"
        @assert 0 ≤ γ ≤ 1 "γ deve estar em [0,1]"
        @assert abs(σ_c + σ_v + γ - 1.0) < 1e-6 "σ_c + σ_v + γ deve somar 1"
        @assert abs(k - c / v) < 1e-6 "k deve ser igual a c/v"
        @assert δ ≥ 0 "Taxa de depreciação não pode ser negativa"
        new(nome, c, v, e, k, σ_c, σ_v, γ, δ)
    end
end

"""Constructor externo simplificado com valores por omissão."""
function Departamento(nome::String; c = 100.0, v = 50.0, e = 1.5,
                      σ_c = 0.5, σ_v = 0.2, δ = 0.05)
    γ = 1.0 - σ_c - σ_v
    k = c / v
    return Departamento(nome, c, v, e, k, σ_c, σ_v, γ, δ)
end

# Métodos auxiliares
"""Taxa de lucro r = e/(k+1)."""
taxa_lucro(d::Departamento) = d.e / (d.k + 1)

"""Mais-valia s = e·v."""
mais_valia(d::Departamento) = d.e * d.v

"""Capital total K = c + v."""
capital_total(d::Departamento) = d.c + d.v

"""Valor do produto W = c + v + s."""
valor_produto(d::Departamento) = d.c + d.v + mais_valia(d)

function Base.show(io::IO, d::Departamento)
    print(io, "Departamento(\"$(d.nome)\": ")
    print(io, "K=$(round(capital_total(d), digits=1)), ")
    print(io, "k=$(round(d.k, digits=2)), ")
    print(io, "e=$(round(d.e, digits=2)), ")
    print(io, "r=$(round(taxa_lucro(d), digits=3)))")
end

# ----------------------------------------------------------------------------
# Parâmetros calibrados
# ----------------------------------------------------------------------------

"""
    ParâmetrosCalibrados

Armazena o resultado de uma calibração (INE ou AMECO) pronto a alimentar
uma simulação.
"""
struct ParâmetrosCalibrados
    N::Int
    nomes_setores::Vector{String}
    códigos_cae::Vector{String}

    C::Vector{Float64}
    V::Vector{Float64}

    e::Vector{Float64}
    k::Vector{Float64}
    r::Vector{Float64}

    A::Matrix{Float64}
    l::Vector{Float64}

    σ_c::Vector{Float64}
    σ_v::Vector{Float64}
    δ::Vector{Float64}

    fonte::String
    ano_base::Int
    data_calibração::DateTime
    qualidade_ajuste::Float64
end

# ----------------------------------------------------------------------------
# Dados do INE (fonte nacional portuguesa)
# ----------------------------------------------------------------------------

"""
    DadosINE

Contentor para dados do Instituto Nacional de Estatística.
"""
struct DadosINE
    ano::Int
    qre::DataFrame
    contas_setor::DataFrame
    emprego::DataFrame
    fbcf::DataFrame
    metadados::Dict{String, Any}
end

# ----------------------------------------------------------------------------
# Dados da AMECO (Comissão Europeia)
# ----------------------------------------------------------------------------

"""
    DadosAMECO

Séries temporais macroeconómicas de um país, provenientes da base AMECO
(Annual Macro-Economic Database) da Comissão Europeia.
"""
struct DadosAMECO
    país::String
    código_país::String
    anos::Vector{Int}

    # Contas Nacionais
    PIB::Vector{Float64}
    PIB_real::Vector{Float64}
    consumo_privado::Vector{Float64}
    consumo_público::Vector{Float64}
    FBCF::Vector{Float64}
    exportações::Vector{Float64}
    importações::Vector{Float64}

    # Mercado de Trabalho
    emprego::Vector{Float64}
    emprego_assalariado::Vector{Float64}
    desemprego::Vector{Float64}
    população_ativa::Vector{Float64}

    # Remunerações e Produtividade
    remunerações::Vector{Float64}
    produtividade::Vector{Float64}
    custos_unitários_trabalho::Vector{Float64}

    # Preços
    deflator_PIB::Vector{Float64}
    deflator_FBCF::Vector{Float64}
    IPC::Vector{Float64}

    # Finanças Públicas
    receitas_governo::Vector{Float64}
    despesas_governo::Vector{Float64}
    saldo_orçamental::Vector{Float64}
    dívida_pública::Vector{Float64}

    # Setor Externo
    balança_corrente::Vector{Float64}
    balança_comercial::Vector{Float64}

    # Stock de Capital
    stock_capital_total::Vector{Float64}

    # Metadados
    fonte::String
    data_download::DateTime
    notas::Dict{String, String}
end

# ----------------------------------------------------------------------------
# Códigos de países AMECO
# ----------------------------------------------------------------------------

const CÓDIGOS_PAÍSES_AMECO = Dict(
    "Áustria" => "AT", "Bélgica" => "BE", "Bulgária" => "BG",
    "Croácia" => "HR", "Chipre" => "CY", "República Checa" => "CZ",
    "Dinamarca" => "DK", "Estónia" => "EE", "Finlândia" => "FI",
    "França" => "FR", "Alemanha" => "DE", "Grécia" => "EL",
    "Hungria" => "HU", "Irlanda" => "IE", "Itália" => "IT",
    "Letónia" => "LV", "Lituânia" => "LT", "Luxemburgo" => "LU",
    "Malta" => "MT", "Países Baixos" => "NL", "Polónia" => "PL",
    "Portugal" => "PT", "Roménia" => "RO", "Eslováquia" => "SK",
    "Eslovénia" => "SI", "Espanha" => "ES", "Suécia" => "SE",
    "Área do Euro" => "EA", "Área do Euro (19)" => "EA19",
    "Reino Unido" => "UK", "Noruega" => "NO", "Suíça" => "CH",
    "Islândia" => "IS", "Turquia" => "TR",
    "União Europeia (27)" => "EU27", "União Europeia (28)" => "EU28",
    "Estados Unidos" => "US", "Japão" => "JP",
)

# ----------------------------------------------------------------------------
# Códigos de variáveis AMECO
# ----------------------------------------------------------------------------
# NOTA: usados apenas pelo parser TXT legado (`ler_ficheiro_ameco_txt`,
# `src/ameco_download.jl`), hoje sem caminho automático (ver
# docs/LIMITACOES.md item 3). Corrigidos contra a API SDMX real onde foi
# possível verificar (`receitas_governo`/`despesas_governo` estavam
# trocados; `consumo_privado`/`exportações`/`importações`/
# `custos_unit_trabalho`/`produtividade_trabalho` usavam mnemónicos que já
# não existem, ou nunca existiram, na API). `deflator_PIB` e
# `stock_capital_bruto` continuam por confirmar — não têm equivalente direto
# na API SDMX (o deflator calcula-se, o stock bruto não é publicado; ver
# `docs/LIMITACOES.md` item 3) — mantidos como estavam, sem correção
# fabricada. Para a fonte de verdade atual (API SDMX), ver `MAPA_AMECO_SDMX`
# em `src/ameco_sdmx.jl`.

const CÓDIGOS_AMECO_VARIÁVEIS = Dict(
    "PIB_corrente" => "UVGD",
    "PIB_constante" => "OVGD",
    "consumo_privado" => "UCPH",
    "consumo_público" => "UCTG",
    "FBCF" => "UIGT",
    "exportações" => "UXGS",
    "importações" => "UMGS",
    "emprego_total" => "NETD",
    "emprego_assalariado" => "NWTD",
    "taxa_desemprego" => "ZUTN",
    "população_ativa" => "NLTN",
    "remunerações" => "UWCD",
    "remunerações_por_assalariado" => "HWCDW",
    "produtividade_trabalho" => "ZVGDE",
    "custos_unit_trabalho" => "PLCD",
    "deflator_PIB" => "PVGD",
    "IPC" => "ZCPIH",
    "receitas_governo" => "URTG",
    "despesas_governo" => "UUTG",
    "saldo_orçamental" => "UBLG",
    "dívida_pública" => "UDGGL",
    "balança_corrente" => "UBCA",
    "balança_comercial" => "UBTB",
    "stock_capital_líquido" => "OKND",
    "stock_capital_bruto" => "OKCD",
)
