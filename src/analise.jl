# ============================================================================
# ANÁLISE: TAXAS DE LUCRO, VALORES-TRABALHO E PREÇOS DE PRODUÇÃO
# ============================================================================

# ----------------------------------------------------------------------------
# Métricas ao longo do tempo
# ----------------------------------------------------------------------------

"""Taxas de lucro por setor ao longo do tempo (matriz N × T)."""
function calcular_taxas_lucro(sol, e)
    N = length(e)
    T = length(sol.t)
    r = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        k = C ./ V
        r[:, idx] = e ./ (k .+ 1)
    end
    return r
end

"""
Taxas de lucro por setor ao longo do tempo, com capital constante valorizado
a preços de produção de Sraffa (matriz N × T). Usa a mesma lógica de
`sistema_Ndept_io!` (ver `src/nucleo.jl`) para reproduzir, fora da EDO, a taxa
de lucro `rᵢ` que a dinâmica acoplada usa internamente. Requer `p` com os
campos `e, A, l, R_max, w` (ver `simular_Ndept_customizado(..., acoplado=true)`).
"""
function calcular_taxas_lucro_precos(sol, p)
    N = length(p.e)
    T = length(sol.t)
    r = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        S = p.e .* V

        r̄_naive = sum(S) / sum(C .+ V)
        r_efetivo = clamp(r̄_naive, 0.0, 0.95 * p.R_max)

        π = try
            precos = calcular_precos_producao(p.A, p.l, p.w, r_efetivo)
            λ = calcular_valores_trabalho(p.A, p.l)
            precos ./ λ
        catch
            ones(N)
        end

        r[:, idx] = S ./ (π .* C .+ V)
    end
    return r
end

"""Composições orgânicas por setor ao longo do tempo (matriz N × T)."""
function calcular_composicoes_organicas(sol)
    N = Int(length(sol.u[1]) / 2)
    T = length(sol.t)
    k = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        k[:, idx] = C ./ V
    end
    return k
end

"""Taxa média (agregada) de lucro ao longo do tempo (vetor de comprimento T)."""
function calcular_taxa_media_lucro(sol, e)
    N = length(e)
    T = length(sol.t)
    r_media = zeros(T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        S = e .* V
        r_media[idx] = sum(S) / (sum(C) + sum(V))
    end
    return r_media
end

"""Gráfico da dispersão (desvio-padrão) das taxas de lucro ao longo do tempo."""
function analisar_convergencia(sol, depts, p)
    r = calcular_taxas_lucro(sol, p.e)
    σ_r = [std(r[:, i]) for i in 1:size(r, 2)]
    plot(sol.t, σ_r,
         xlabel = "Tempo", ylabel = "Desvio-padrão das taxas de lucro",
         title = "Convergência das taxas de lucro", lw = 2, legend = false)
end

"""Verifica a condição de equilíbrio intersetorial do modelo de 2 departamentos."""
function verificar_equilibrio_2dept(C1, V1, C2, V2, e1, e2, σ_c1, σ_c2)
    S1 = e1 * V1
    S2 = e2 * V2
    lado_esq = V1 + (1 - σ_c1) * S1
    lado_dir = C2 + σ_c2 * S2
    deseq = lado_esq - lado_dir
    return (equilibrio = abs(deseq) < 0.01, desequilibrio = deseq,
            lado_esquerdo = lado_esq, lado_direito = lado_dir)
end

"""
    verificar_equilibrio_Ndept(sol, p; t_idx=length(sol.t))

Generalização a N setores de `verificar_equilibrio_2dept`: verifica a
posteriori (não realimenta a dinâmica — tal como a versão de 2 departamentos
não realimenta `sistema_2dept!`) se os níveis de output correntes conseguem
sustentar a procura intermédia implícita na matriz técnica `p.A`.

Para o instante `t_idx` (por omissão, o último), calcula o output bruto por
setor `Oᵢ = Cᵢ+Vᵢ+Sᵢ` e a procura intermédia `(A·O)ᵢ`; devolve o desvio por
setor (`Oᵢ − (A·O)ᵢ`, positivo quando o setor produz mais do que a economia
precisa dele como input, negativo quando produz menos) e a razão de
realização agregada `ρ_real = Σ min(Oᵢ,(A·O)ᵢ) / Σ(A·O)ᵢ` (≤ 1; = 1 sem
estrangulamento). Usada por `sistema_Ndept_io!` (`realização=true`,
`src/nucleo.jl`) como base do fator de amortecimento do reinvestimento —
aqui exposta para inspecionar o resultado fora da EDO, à semelhança de
`calcular_taxas_lucro_precos`.
"""
function verificar_equilibrio_Ndept(sol, p; t_idx = length(sol.t))
    N = length(p.e)
    X = sol.u[t_idx]
    C = X[1:N]
    V = X[N+1:2N]
    S = p.e .* V
    O = C .+ V .+ S
    procura_intermédia = p.A * O
    desvio = O .- procura_intermédia
    soma_procura = sum(procura_intermédia)
    ρ_real = soma_procura > 0 ? sum(min.(O, procura_intermédia)) / soma_procura : 1.0
    return (equilibrio = ρ_real > 0.95, ρ_real = ρ_real, desvio = desvio,
            output = O, procura_intermédia = procura_intermédia)
end

# ----------------------------------------------------------------------------
# Valores-trabalho e preços de produção
# ----------------------------------------------------------------------------

"""
    calcular_valores_trabalho(A, l)

Valores-trabalho λ = (I − A)⁻¹ · l. Requer economia produtiva (ρ(A) < 1).
"""
function calcular_valores_trabalho(A, l)
    N = size(A, 1)
    Id = matriz_identidade(N)
    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && error("Matriz não produtiva! ρ(A) = $ρ_A ≥ 1")
    λ = (Id - A) \ l
    any(λ .< 0) && @warn "Valores-trabalho negativos detetados"
    return λ
end

"""
    calcular_taxa_lucro_maxima(A, l)

Taxa máxima de lucro (salários = 0): R_max = 1/λ_max(Aᵀ) − 1.
"""
function calcular_taxa_lucro_maxima(A, l)
    λ_max = maximum(real.(eigvals(A')))
    return (1 / λ_max) - 1
end

"""
    calcular_precos_producao(A, l, w, r_barra)

Preços de produção de Sraffa: p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ · l.
Rejeita r̄ que torne o sistema singular (r̄ ≥ R_max).
"""
function calcular_precos_producao(A, l, w, r_barra)
    N = size(A, 1)
    Id = matriz_identidade(N)
    fator = 1 + r_barra
    matriz = Id - fator * A'
    R_max = calcular_taxa_lucro_maxima(A, l)
    if r_barra >= R_max || abs(det(matriz)) < 1e-10
        error("Sistema singular para r̄=$r_barra. Taxa máxima R_max=$(round(R_max, digits=3))")
    end
    p = w * fator * (matriz \ l)
    any(p .< 0) && @warn "Preços negativos para r̄=$r_barra"
    return p
end

"""
    problema_transformacao(N=3)

Analisa o problema da transformação de valores em preços, para várias taxas
de lucro, e produz a visualização comparativa.
"""
function problema_transformacao(N = 3)
    println("\n" * "="^70)
    println("PROBLEMA DA TRANSFORMAÇÃO DE VALORES EM PREÇOS")
    println("="^70)

    A = criar_matriz_tecnica(N, densidade = 0.5)
    l = 0.3 .+ rand(N) * 0.3

    λ = calcular_valores_trabalho(A, l)
    λ_norm = λ / sum(λ)
    w = 1.0
    R_max = calcular_taxa_lucro_maxima(A, l)
    println("\nTaxa máxima de lucro: $(round(R_max*100, digits=1))%")

    taxas_lucro = [0.0, 0.1, 0.2, 0.3, min(0.4, R_max * 0.9)]
    resultados = []
    for r_barra in taxas_lucro
        p = calcular_precos_producao(A, l, w, r_barra)
        p_norm = p / sum(p)
        desvios = (p_norm - λ_norm) ./ λ_norm * 100
        push!(resultados, (r = r_barra, p = p_norm, desvios = desvios))
    end

    println("\nMatriz Técnica A:")
    display(round.(A, digits = 3))
    println("\n\nValores-Trabalho λ (normalizados):")
    display(round.(λ_norm, digits = 4))
    println("\n\nAnálise por Taxa de Lucro:")
    println("-"^70)
    for res in resultados
        println("\nr̄ = $(round(res.r*100, digits=1))%")
        println("Desvios (%): ", round.(res.desvios, digits = 2))
    end

    r_medio_idx = findfirst(x -> x.r ≈ 0.3, resultados)
    if !isnothing(r_medio_idx)
        res_medio = resultados[r_medio_idx]
        x = 1:N
        largura = 0.35

        p1 = bar(x .- largura/2, λ_norm, bar_width = largura,
                 label = "Valores-Trabalho", ylabel = "Proporção",
                 title = "Comparação Normalizada", color = :blue, alpha = 0.7)
        bar!(x .+ largura/2, res_medio.p, bar_width = largura,
             label = "Preços de Produção", color = :red, alpha = 0.7)

        p2 = bar(x, res_medio.desvios, xlabel = "Departamento",
                 ylabel = "Desvio (%)", title = "Desvios Percentuais",
                 legend = false,
                 color = ifelse.(res_medio.desvios .> 0, :red, :blue), alpha = 0.7)
        hline!([0], color = :black, linestyle = :dash, label = "")

        p3 = plot(xlabel = "Taxa de Lucro r̄", ylabel = "Desvio Médio Absoluto (%)",
                  title = "Divergência Valores-Preços", legend = false)
        r_values = [res.r for res in resultados]
        desvios_médios = [mean(abs.(res.desvios)) for res in resultados]
        plot!(r_values, desvios_médios, marker = :circle, markersize = 6,
              lw = 2, color = :purple)

        p4 = scatter(λ_norm, res_medio.p, xlabel = "Valores-Trabalho (norm.)",
                     ylabel = "Preços de Produção (norm.)",
                     title = "Correlação Valores-Preços", label = "",
                     markersize = 8, alpha = 0.7)
        max_val = maximum([λ_norm; res_medio.p])
        plot!([0, max_val], [0, max_val], linestyle = :dash, color = :black,
              label = "Igualdade", lw = 2)
        ρ = cor(λ_norm, res_medio.p)
        annotate!(max_val * 0.7, max_val * 0.2, text("ρ = $(round(ρ, digits=3))", 12))

        combined = plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 900))
        display(combined)

        return (A = A, l = l, λ = λ_norm, resultados = resultados,
                plot = combined, R_max = R_max, correlação = ρ)
    end
end
