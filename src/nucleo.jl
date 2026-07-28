# ============================================================================
# NÚCLEO: MATRIZES, DEPARTAMENTOS, SISTEMAS DINÂMICOS E SIMULAÇÃO
# ============================================================================

# ----------------------------------------------------------------------------
# Auxiliares matemáticos
# ----------------------------------------------------------------------------

"""Cria matriz identidade N×N (evita a constante `I` do LinearAlgebra)."""
matriz_identidade(N::Int) = diagm(ones(N))

"""
    criar_matriz_tecnica(N; densidade=0.3, max_coef=0.15,
                         estrutura=:aleatoria, seed=nothing)

Cria uma matriz técnica input-output A (N×N) com raio espectral < 1.

# Estruturas
- `:aleatoria`  — ligações aleatórias
- `:triangular` — hierárquica (setores iniciais → finais)
- `:blocos`     — clusters com ligações inter-bloco fracas

Passar `seed` fixa a semente e torna a matriz reprodutível (recomendado
sempre que se comparam cenários).
"""
function criar_matriz_tecnica(N::Int; densidade = 0.3, max_coef = 0.15,
                              estrutura = :aleatoria, seed = nothing)
    isnothing(seed) || Random.seed!(seed)

    A = zeros(N, N)

    if estrutura == :aleatoria
        for i in 1:N, j in 1:N
            rand() < densidade && (A[i, j] = rand() * max_coef)
        end

    elseif estrutura == :triangular
        for i in 1:N, j in i:N
            rand() < densidade && (A[i, j] = rand() * max_coef)
        end

    elseif estrutura == :blocos
        n_blocos = max(2, N ÷ 3)
        tamanho_bloco = N ÷ n_blocos
        for bloco in 1:n_blocos
            inicio = (bloco - 1) * tamanho_bloco + 1
            fim = min(bloco * tamanho_bloco, N)
            for i in inicio:fim, j in inicio:fim
                rand() < densidade * 2 && (A[i, j] = rand() * max_coef)
            end
            if bloco < n_blocos
                prox_i = fim + 1
                prox_f = min((bloco + 1) * tamanho_bloco, N)
                for i in inicio:fim, j in prox_i:prox_f
                    rand() < densidade * 0.5 && (A[i, j] = rand() * max_coef * 0.5)
                end
            end
        end
    else
        error("Estrutura '$estrutura' desconhecida (:aleatoria, :triangular, :blocos)")
    end

    # Garantir produtividade: ρ(A) < 1
    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && (A = A / ρ_A * 0.8)

    return A
end

# ----------------------------------------------------------------------------
# Criação de departamentos
# ----------------------------------------------------------------------------

"""Modelo clássico de Marx com 2 departamentos (meios de produção / consumo)."""
function modelo_dois_departamentos()
    dept1 = Departamento("Meios de Produção",
                         c = 4000.0, v = 1000.0, e = 1.0,
                         σ_c = 0.5, σ_v = 0.1, δ = 0.05)
    dept2 = Departamento("Bens de Consumo",
                         c = 2000.0, v = 500.0, e = 1.0,
                         σ_c = 0.3, σ_v = 0.15, δ = 0.05)
    return [dept1, dept2]
end

"""
    criar_departamentos(N, nomes=String[])

Cria N departamentos com parâmetros aleatórios mas plausíveis. A composição
orgânica cresce com o índice do setor.
"""
function criar_departamentos(N::Int, nomes::Vector{String} = String[])
    isempty(nomes) && (nomes = ["Dept_$i" for i in 1:N])
    depts = Departamento[]
    for i in 1:N
        k_base = 1.5 + (i / N) * 2.0
        c = 100.0 * k_base
        v = 100.0
        e = 1.0 + rand()
        σ_c = 0.4 + rand() * 0.3
        σ_v = 0.1 + rand() * 0.15
        δ = 0.03 + rand() * 0.05
        push!(depts, Departamento(nomes[i], c = c, v = v, e = e,
                                  σ_c = σ_c, σ_v = σ_v, δ = δ))
    end
    return depts
end

# ----------------------------------------------------------------------------
# Sistemas de equações diferenciais
# ----------------------------------------------------------------------------

"""Sistema de EDOs para o modelo de 2 departamentos. Estado: [C1,V1,C2,V2]."""
function sistema_2dept!(dX, X, p, t)
    C1, V1, C2, V2 = X
    e1, e2, σ_c1, σ_v1, σ_c2, σ_v2, δ1, δ2 = p
    S1 = e1 * V1
    S2 = e2 * V2
    dX[1] = σ_c1 * S1 - δ1 * C1
    dX[2] = σ_v1 * S1
    dX[3] = σ_c2 * S2 - δ2 * C2
    dX[4] = σ_v2 * S2
end

"""
    sistema_Ndept!(dX, X, p, t)

Sistema de EDOs para N departamentos. Estado: [C1..CN, V1..VN].

LIMITAÇÃO CONHECIDA: a acumulação de cada departamento depende apenas da
sua própria mais-valia; a matriz técnica `p.A` é transportada nos parâmetros
mas **não realimenta** a dinâmica. Ver `docs/LIMITACOES.md` (item 1) para a
correção pendente que acopla os setores via A.
"""
function sistema_Ndept!(dX, X, p, t)
    N = length(p.e)
    C = @view X[1:N]
    V = @view X[N+1:2N]
    S = p.e .* V
    dX[1:N]      = p.σ_c .* S .- p.δ .* C
    dX[N+1:2N]   = p.σ_v .* S
end

"""
    sistema_Ndept_io!(dX, X, p, t)

Sistema de EDOs para N departamentos, com a matriz técnica `p.A` a realimentar
a dinâmica através de um termo de mobilidade de capital:

    dCᵢ/dt = σ_c,ᵢ·Sᵢ − δᵢ·Cᵢ + μ·(rᵢ − r̄)·Cᵢ

onde `rᵢ` é a taxa de lucro do setor i com o capital constante valorizado a
preços de produção de Sraffa (que dependem de A), não pelo valor contabilístico
nu. Para evitar a circularidade de usar r̄ para calcular preços que por sua vez
definem r̄, a taxa de lucro que entra em `calcular_precos_producao` é a média
não ponderada por preços (`r̄_naive`), fixada a um máximo de 95% de `p.R_max`
para não colidir com a singularidade de Sraffa. Se mesmo assim o sistema de
preços falhar (matriz mal condicionada), cai-se para preços = valores-trabalho
(sem ajuste, π = 1).

Ver `docs/LIMITACOES.md` (item 1): esta é a versão opcional acoplada,
selecionável com `acoplado=true` em `simular_Ndept`/`simular_Ndept_customizado`.
`sistema_Ndept!` mantém-se como a versão "setores independentes".
"""
function sistema_Ndept_io!(dX, X, p, t)
    N = length(p.e)
    C = @view X[1:N]
    V = @view X[N+1:2N]
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

    C_valorizado = π .* C
    r = S ./ (C_valorizado .+ V)
    r̄ = sum(S) / sum(C_valorizado .+ V)

    dX[1:N]    = p.σ_c .* S .- p.δ .* C .+ p.μ .* (r .- r̄) .* C
    dX[N+1:2N] = p.σ_v .* S
end

# ----------------------------------------------------------------------------
# Simulação
# ----------------------------------------------------------------------------

"""Simula o modelo de 2 departamentos."""
function simular_2dept(; T = 100.0)
    depts = modelo_dois_departamentos()
    X0 = [depts[1].c, depts[1].v, depts[2].c, depts[2].v]
    p = (depts[1].e, depts[2].e,
         depts[1].σ_c, depts[1].σ_v,
         depts[2].σ_c, depts[2].σ_v,
         depts[1].δ, depts[2].δ)
    prob = ODEProblem(sistema_2dept!, X0, (0.0, T), p)
    sol = solve(prob, Tsit5(), saveat = 0.5)
    return sol, depts, p
end

"""
    simular_Ndept(N; T=100.0, nomes=String[], seed=nothing, acoplado=false, μ=0.3)

Simula o modelo de N departamentos com departamentos gerados aleatoriamente.
Com `acoplado=true`, usa `sistema_Ndept_io!` (mobilidade de capital via A e
preços de produção); `μ` é o coeficiente de mobilidade nesse caso.
"""
function simular_Ndept(N::Int; T = 100.0, nomes::Vector{String} = String[],
                       seed = nothing, acoplado = false, μ = 0.3)
    depts = criar_departamentos(N, nomes)
    return simular_Ndept_customizado(depts, T = T, seed = seed,
                                     acoplado = acoplado, μ = μ)
end

"""
    simular_Ndept_customizado(depts; T=100.0, seed=nothing, acoplado=false, μ=0.3)

Simula o modelo de N departamentos a partir de departamentos pré-configurados.
Com `acoplado=true`, usa `sistema_Ndept_io!` em vez de `sistema_Ndept!`.
"""
function simular_Ndept_customizado(depts::Vector{Departamento}; T = 100.0,
                                   seed = nothing, acoplado = false, μ = 0.3)
    N = length(depts)
    X0 = [ [d.c for d in depts]; [d.v for d in depts] ]
    A = criar_matriz_tecnica(N, seed = seed)

    if acoplado
        l = [d.v for d in depts]
        p = (
            e     = [d.e for d in depts],
            σ_c   = [d.σ_c for d in depts],
            σ_v   = [d.σ_v for d in depts],
            δ     = [d.δ for d in depts],
            A     = A,
            l     = l,
            R_max = calcular_taxa_lucro_maxima(A, l),
            μ     = μ,
            w     = 1.0,
        )
        prob = ODEProblem(sistema_Ndept_io!, X0, (0.0, T), p)
    else
        p = (
            e   = [d.e for d in depts],
            σ_c = [d.σ_c for d in depts],
            σ_v = [d.σ_v for d in depts],
            δ   = [d.δ for d in depts],
            A   = A,
        )
        prob = ODEProblem(sistema_Ndept!, X0, (0.0, T), p)
    end

    sol = solve(prob, Tsit5(), saveat = 0.5)
    return sol, depts, p
end
