# ============================================================================
# DOWNLOAD AUTOMÁTICO AMECO (LEGADO) E PARSER DO FICHEIRO TXT
# ============================================================================
# LEGADO: a Comissão Europeia retirou a distribuição do ficheiro TXT estático
# que este ficheiro descarregava — as URLs abaixo já não devolvem dados reais
# (confirmado 2026-07: 404 ou redireccionamento para a página HTML do portal).
# O caminho automático por omissão passou a ser a API SDMX oficial, em
# `src/ameco_sdmx.jl` (ver `obter_dados_ameco`, métodos `:auto`/`:sdmx`).
# `ler_ficheiro_ameco_txt`/`processar_csv_ameco` mantêm-se aqui como fluxo
# manual para quem já tenha um ficheiro TXT/CSV descarregado por outra via.
# Ver docs/LIMITACOES.md (item 3).
# ============================================================================

"""URLs candidatas para o ficheiro TXT completo da AMECO — LEGADO, conhecidas como não
funcionais desde 2026-07 (a Comissão descontinuou esta distribuição). Mantidas apenas
como referência histórica/ponto de partida para quem procure um download manual."""
const URLS_AMECO_TENTAR = [
    "https://ec.europa.eu/economy_finance/db_indicators/ameco/documents/ameco0.txt",
    "https://economy-finance.ec.europa.eu/system/files/2024-05/ameco0.txt",
    "https://economy-finance.ec.europa.eu/system/files/2023-11/ameco0.txt",
]

"""Página oficial da AMECO (ponto de partida para download manual)."""
const URL_AMECO_PORTAL =
    "https://economy-finance.ec.europa.eu/economic-research-and-databases/economic-databases/ameco-database_en"

"""
    descarregar_ameco_automatico(; força_redownload=false, diretório="./dados_ameco")

Tenta descarregar automaticamente o ficheiro TXT completo da AMECO. Se todas
as URLs falharem, lança erro com instruções para download manual.
"""
function descarregar_ameco_automatico(; força_redownload = false,
                                      diretório = "./dados_ameco")
    println("\n" * "="^70)
    println("DOWNLOAD AUTOMÁTICO — BASE AMECO")
    println("="^70)
    mkpath(diretório)
    destino = joinpath(diretório, "ameco_completo.txt")

    if isfile(destino) && !força_redownload
        println("✓ Já existe: $destino (força_redownload=true para renovar)")
        return destino
    end

    for (i, url) in enumerate(URLS_AMECO_TENTAR)
        println("\n  Tentativa $i: $url")
        try
            resp = HTTP.get(url, redirect = true, retry = true, readtimeout = 60)
            if resp.status == 200 && length(resp.body) > 1000
                open(destino, "w") do f; write(f, resp.body); end
                mb = round(filesize(destino) / 1024 / 1024, digits = 2)
                println("  ✓ Sucesso! ($mb MB)")
                _registar_download(diretório, destino)
                return destino
            else
                println("  ✗ Resposta inesperada (status $(resp.status), $(length(resp.body)) bytes)")
            end
        catch e
            println("  ✗ Falhou: $(sprint(showerror, e))")
        end
    end

    println("\n⚠️  DOWNLOAD AUTOMÁTICO FALHOU")
    println("Descarregue manualmente em: $URL_AMECO_PORTAL")
    println("Guarde o TXT em: $diretório e use ler_ficheiro_ameco_txt(...)")
    error("Download automático falhou — ver instruções acima.")
end

"""Regista a data do último download num ficheiro info."""
function _registar_download(diretório, ficheiro)
    open(joinpath(diretório, "info_download.txt"), "w") do f
        write(f, "Data: $(today())\nFicheiro: $ficheiro\n")
    end
end

"""
    ler_ficheiro_ameco_txt(ficheiro, código_país)

Lê o ficheiro TXT (largura fixa) da AMECO e extrai as séries do país indicado.

FORMATO ASSUMIDO (heurístico — validar contra o ficheiro real):
- pos 1-2   código do país
- pos 4-8   código da variável
- pos 10-19 sub-categoria
- pos 21+   valores anuais, 15 caracteres cada, a começar em 1960
"""
function ler_ficheiro_ameco_txt(ficheiro::String, código_país::String;
                                ano_inicial = 1960, largura_campo = 15, pos_dados = 21)
    println("\n📂 Lendo AMECO TXT: $ficheiro (país $código_país)")
    isfile(ficheiro) || error("Ficheiro não encontrado: $ficheiro")

    dados = Dict{String, Dict{Int, Float64}}()
    anos_disp = Set{Int}()
    código_para_nome = Dict(v => k for (k, v) in CÓDIGOS_AMECO_VARIÁVEIS)

    linhas, linhas_país = 0, 0
    open(ficheiro, "r") do f
        for linha in eachline(f)
            linhas += 1
            length(linha) < 20 && continue
            strip(linha[1:2]) == código_país || continue
            linhas_país += 1
            código_var = strip(linha[4:min(8, length(linha))])
            haskey(código_para_nome, código_var) || continue
            nome_var = código_para_nome[código_var]
            get!(dados, nome_var, Dict{Int, Float64}())

            pos = pos_dados
            while pos <= length(linha)
                pfim = min(pos + largura_campo - 1, length(linha))
                s = strip(linha[pos:pfim])
                if !isempty(s) && s != ":" && s != "."
                    v = tryparse(Float64, replace(s, "," => "."))
                    if !isnothing(v)
                        ano = ano_inicial + (pos - pos_dados) ÷ largura_campo
                        dados[nome_var][ano] = v
                        push!(anos_disp, ano)
                    end
                end
                pos += largura_campo
            end
        end
    end

    isempty(anos_disp) && error("Nenhum dado extraído para $código_país (verificar formato/código).")

    anos = sort(collect(anos_disp))
    println("  ✓ $linhas linhas | $linhas_país do país | $(length(dados)) variáveis | anos $(anos[1])-$(anos[end])")

    série(nome) = [get(get(dados, nome, Dict{Int,Float64}()), a, NaN) for a in anos]

    nome_país = something(findfirst(==(código_país), CÓDIGOS_PAÍSES_AMECO), código_país)
    return DadosAMECO(nome_país, código_país, anos,
        série("PIB_corrente"), série("PIB_constante"), série("consumo_privado"),
        série("consumo_público"), série("FBCF"), série("exportações"), série("importações"),
        série("emprego_total"), série("emprego_assalariado"), série("taxa_desemprego"),
        série("população_ativa"), série("remunerações"), série("produtividade_trabalho"),
        série("custos_unit_trabalho"), série("deflator_PIB"), série("deflator_FBCF"), série("IPC"),
        série("CCF"),
        série("receitas_governo"), série("despesas_governo"), série("saldo_orçamental"),
        série("dívida_pública"), série("balança_corrente"), série("balança_comercial"),
        série("stock_capital_líquido"),
        "AMECO TXT: $(basename(ficheiro))", now(),
        Dict("linhas" => string(linhas), "linhas_país" => string(linhas_país)))
end

"""
    processar_csv_ameco(ficheiro, código_país, anos)

Processa um CSV da AMECO (colunas Code/Country/Y<ano>). Formato pode variar
consoante a exportação; ajustar nomes de colunas se necessário.
"""
function processar_csv_ameco(ficheiro::String, código_país::String, anos)
    println("\n📂 Processando CSV AMECO: $ficheiro")
    isfile(ficheiro) || error("Ficheiro não encontrado: $ficheiro")
    df = CSV.read(ficheiro, DataFrame)

    cols = names(df)
    col_country = "Country" in cols ? "Country" : first(filter(c -> occursin("ountry", c), cols))
    col_code = "Code" in cols ? "Code" : first(filter(c -> occursin("ode", c), cols))

    df_país = filter(row -> string(row[col_country]) == código_país, df)
    nrow(df_país) == 0 && error("Sem dados para $código_país em $ficheiro")

    anos_vec = collect(anos)
    extraídos = Dict{String, Vector{Float64}}()
    for (nome, cod) in CÓDIGOS_AMECO_VARIÁVEIS
        linha = findfirst(r -> string(r[col_code]) == cod, eachrow(df_país))
        if !isnothing(linha)
            vals = Float64[]
            for a in anos_vec
                cn = "Y$a"
                push!(vals, cn in cols && !ismissing(df_país[linha, cn]) ?
                            Float64(df_país[linha, cn]) : NaN)
            end
            extraídos[nome] = vals
        end
    end
    return construir_dados_ameco(código_país, anos_vec, extraídos, "CSV: $(basename(ficheiro))")
end

"""
    obter_dados_ameco(país; anos=1995:2023, método=:auto, diretório="./dados_ameco")

Ponto de entrada unificado. `método`:
- `:auto`      — tenta a API SDMX oficial; senão ficheiro local recente; senão sintético
- `:sdmx`      — força a obtenção via API SDMX oficial (ver `src/ameco_sdmx.jl`)
- `:download`  — alias de `:sdmx` (o download automático do TXT está descontinuado — a
                 Comissão retirou essa distribuição; ver docs/LIMITACOES.md item 3)
- `:local`     — exige ficheiro TXT local (fluxo legado, para quem já tem um ficheiro)
- `:csv`       — processa CSV (requer `ficheiro`; fluxo legado)
- `:sintético` — gera dados sintéticos
- `:manual`    — mostra instruções e devolve dados sintéticos
"""
function obter_dados_ameco(país::String; anos = 1995:2023, método = :auto,
                           diretório = "./dados_ameco", ficheiro = nothing)
    código = _resolver_código_país(país)
    código_sdmx = get(CÓDIGOS_PAÍSES_AMECO_SDMX, país, código)

    if método == :sintético
        return gerar_dados_sintéticos_ameco(código, collect(anos))
    elseif método == :manual
        println("\n📋 Download manual: $URL_AMECO_PORTAL")
        println("Guarde o TXT em $diretório e use método=:local.")
        return gerar_dados_sintéticos_ameco(código, collect(anos))
    elseif método == :csv
        isnothing(ficheiro) && error("Método :csv requer o argumento ficheiro=...")
        return processar_csv_ameco(ficheiro, código, anos)
    elseif método in (:sdmx, :download)
        return construir_dados_ameco(código, collect(anos),
            descarregar_ameco_sdmx(código_sdmx, anos), "AMECO SDMX (oficial)")
    end

    local_txt = joinpath(diretório, "ameco_completo.txt")

    if método == :local
        isfile(local_txt) || error("Sem ficheiro local: $local_txt (use método=:sdmx)")
        return ler_ficheiro_ameco_txt(local_txt, código)
    end

    # :auto — API SDMX oficial primeiro; depois ficheiro local recente; depois sintético
    try
        return construir_dados_ameco(código, collect(anos),
            descarregar_ameco_sdmx(código_sdmx, anos), "AMECO SDMX (oficial)")
    catch e
        @warn "API SDMX da AMECO falhou: $(sprint(showerror, e))"
        if isfile(local_txt)
            idade = (now() - unix2datetime(mtime(local_txt))) / Day(1)
            println("📂 A usar ficheiro local ($(round(idade)) dias) como recurso.")
            return ler_ficheiro_ameco_txt(local_txt, código)
        end
        @warn "A usar dados SINTÉTICOS como último recurso."
        return gerar_dados_sintéticos_ameco(código, collect(anos))
    end
end
