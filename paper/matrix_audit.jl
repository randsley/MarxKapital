# ============================================================================
# Audit of the real 19-sector technical matrix A (Portugal), per external
# review. This script documents the investigation that found and fixed the
# root cause of an implausibly low spectral radius (rho(A)~=0.13): the
# codebase was pulling from NAIO_10_CP1620 ("Table of trade and transport
# margins", a small satellite table), not the actual symmetric input-output
# table (NAIO_10_CP1700). It also reports the diagnostics the review asked
# for on the corrected construction: reconciliation against the table's own
# published output, and the domestic-use vs. total-use question checked
# directly against the live API rather than assumed.
#
# Run with:  julia --project=. paper/matrix_audit.jl
# Requires network access (Eurostat SDMX API).
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const PAÍS = "PT"
const ANO = 2022

println("\n" * "="^70)
println("AUDITORIA DA MATRIZ TÉCNICA A — Portugal")
println("="^70)

# ----------------------------------------------------------------------------
# 1. stk_flow: confirm directly whether the real symmetric IOT
#    (NAIO_10_CP1700) offers anything other than the combined
#    domestic+imports ("TOTAL") table.
# ----------------------------------------------------------------------------

println("\n[1/3] stk_flow (domestic-use vs. total-use) — checking directly...")
url_stkflow = "$URL_BASE_EUROSTAT_SDMX/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR..CPA_A01.CPA_A01.$PAÍS" *
              "?format=SDMX-CSV"
resp = HTTP.get(url_stkflow, ["Accept-Encoding" => "identity"], status_exception = false)
df_stk = CSV.read(IOBuffer(resp.body), DataFrame)
valores_stk_flow = unique(df_stk.stk_flow)
println("  ✓ valores de stk_flow devolvidos (dimensão não fixada): ", valores_stk_flow)
if "DOM" in valores_stk_flow
    println("  ✓ NAIO_10_CP1700 publica DOM (uso doméstico), IMP (importado) e TOTAL — ",
            "ao contrário de NAIO_10_CP1620 (só TOTAL). A construção em produção usa DOM: ",
            "a matriz A representa interdependência produtiva doméstica, sem tratar inputs ",
            "importados como se fossem fornecidos por um setor doméstico.")
end

# ----------------------------------------------------------------------------
# 2. Available reference years (this is a benchmark table, not annual)
# ----------------------------------------------------------------------------

println("\n[2/3] Anos de referência disponíveis (NAIO_10_CP1700 não é anual)...")
url_anos = "$URL_BASE_EUROSTAT_SDMX/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.TOTAL.CPA_A01.B1G.$PAÍS" *
           "?format=SDMX-CSV"
resp = HTTP.get(url_anos, ["Accept-Encoding" => "identity"], status_exception = false)
df_anos = CSV.read(IOBuffer(resp.body), DataFrame)
anos_disponíveis = sort(Int.(df_anos.TIME_PERIOD))
ano_usado = _ano_iot_mais_próximo(PAÍS, ANO)
println("  ✓ anos disponíveis para $PAÍS: ", anos_disponíveis)
println("  ✓ para o pedido ano=$ANO, usa-se o ano de referência mais próximo: $ano_usado")
if ano_usado != ANO
    println("  ⚠ Isto significa que a matriz A do perfil setorial de $ANO (Tabela 1) tem, na ",
            "prática, um vintage de $ano_usado — um desfasamento explícito, não um perfil de ",
            "um único ano genuinamente coerente. Ver Secção 6.2 do artigo.")
end

# ----------------------------------------------------------------------------
# 3. Reconciliation of the corrected construction against the IOT's own
#    published P1 (gross output) row — the diagnostic the review asked for.
# ----------------------------------------------------------------------------

println("\n[3/3] Reconciliação: A corrigida vs. P1 (output bruto) da própria tabela...")
secções = SECÇÕES_NACE
G = length(secções)
secção_idx = Dict(s => i for (i, s) in enumerate(secções))

url = "$URL_BASE_EUROSTAT_SDMX/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.DOM...$PAÍS" *
      "?format=SDMX-CSV&startPeriod=$ano_usado&endPeriod=$ano_usado"
resp = HTTP.get(url, ["Accept-Encoding" => "identity"], retry = true, readtimeout = 60,
                status_exception = false)
df = CSV.read(IOBuffer(resp.body), DataFrame)

F = zeros(G, G)
P1 = zeros(G)
negativos = 0
for row in eachrow(df)
    ismissing(row.OBS_VALUE) && continue
    v = Float64(row.OBS_VALUE)
    pu, pa = String(row.prd_use), String(row.prd_ava)
    if pa == "P1" && startswith(pu, "CPA_")
        sj = _secção_do_código_a64(pu)
        haskey(secção_idx, sj) && (P1[secção_idx[sj]] += v)
        continue
    end
    (startswith(pa, "CPA_") && startswith(pu, "CPA_")) || continue
    si, sj = _secção_do_código_a64(pa), _secção_do_código_a64(pu)
    (haskey(secção_idx, si) && haskey(secção_idx, sj)) || continue
    v < 0 && (negativos += 1)
    F[secção_idx[si], secção_idx[sj]] += max(v, 0.0)
end
println("  ✓ células negativas produto×indústria: $negativos ",
        "(a tabela de margens usada antes desta correção tinha 272-317; a tabela real não devia ter nenhuma)")

vab_s, _, _ = obter_vab_remuneracoes_ccf_eurostat(PAÍS, ano_usado)
output_bruto_via_vab = [sum(F[:, j]) + get(vab_s, secções[j], 0.0) for j in 1:G]

resíduos = Float64[]
for j in 1:G
    if P1[j] > 0
        resíduo_pct = 100 * (output_bruto_via_vab[j] - P1[j]) / P1[j]
        push!(resíduos, resíduo_pct)
        println("  $(secções[j]): via-VAB=$(round(output_bruto_via_vab[j],digits=1))  ",
                "P1(tabela)=$(round(P1[j],digits=1))  resíduo=$(round(resíduo_pct,digits=1))%")
    end
end
println("  ✓ resíduo médio absoluto (via-VAB vs. P1 da própria tabela): ",
        "$(round(mean(abs.(resíduos)), digits = 1))%, máximo: $(round(maximum(abs.(resíduos)), digits = 1))%")
println("  ✓ nota: a construção em produção usa P1 diretamente quando disponível ",
        "(reconciliação por construção); este resíduo mede apenas a via de reserva ",
        "(Σfluxos+VAB externo), para diagnóstico.")

A_produção = construir_matriz_io_eurostat(PAÍS, ANO, [[s] for s in secções], vab_s)
println("\n  ✓ ρ(A) da construção em produção (usa P1 diretamente): ",
        round(maximum(abs.(eigvals(A_produção))), digits = 4))

println("\n" * "="^70)
println("Concluído.")
println("="^70)
