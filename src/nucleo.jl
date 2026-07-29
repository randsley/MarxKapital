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

`r̄` (a taxa usada no termo de mobilidade, distinta de `r̄_naive` acima) é a
média de `r` ponderada por `C` — não a razão agregada `ΣS/Σ(C+V)` — porque é
a única escolha para a qual `Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exatamente, garantindo que o
termo de mobilidade realoca capital constante agregado entre setores em vez
de o criar ou destruir (verificado por teste, `test/runtests.jl`,
"Mobilidade de capital — conservação exata").

Ver `docs/LIMITACOES.md` (item 1): esta é a versão opcional acoplada,
selecionável com `acoplado=true` em `simular_Ndept`/`simular_Ndept_customizado`.
`sistema_Ndept!` mantém-se como a versão "setores independentes".

Se `p.realização == true`, acresce um segundo mecanismo, independente da
mobilidade de capital: uma pressão de realização que trava o reinvestimento
quando a estrutura técnica (`A`) não consegue suportar os níveis de output
correntes. Define-se o output bruto por setor `Oᵢ = Cᵢ+Vᵢ+Sᵢ` e a procura
intermédia implícita em A, `(A·O)ᵢ`; a razão de realização agregada

    ρ_real = Σᵢ min(Oᵢ, (A·O)ᵢ) / Σᵢ (A·O)ᵢ

mede que fração da procura intermédia agregada os outputs correntes
conseguem cobrir (≤ 1; = 1 quando não há estrangulamento). O reinvestimento
planeado (`σ_c,ᵢ·Sᵢ`) é escalado por `min(ρ_real, 1)` — uma aproximação
agregada, a mesma escala para todos os setores.

Se `p.racionamento == true` (tem precedência sobre `p.realização`), usa-se
em vez disso um racionamento **por setor**, via `_resolver_racionamento`:
ver a sua docstring para o mecanismo (racionamento de quantidades à
Bénassy/Barro-Grossman, com tecnologia Leontief). Ambos os mecanismos ficam
uma EDO comum — não introduzem variáveis de estado novas nem exigem um
solver de equações algébrico-diferenciais (DAE): o racionamento é resolvido
por iteração de ponto fixo dentro do próprio cálculo do lado direito, tal
como os preços de Sraffa já o são. Nenhum dos dois impõe realização exata
por via de restrições algébricas geridas pelo solver; ver
`verificar_equilibrio_Ndept` (`src/analise.jl`) para uma verificação a
posteriori mais detalhada, e `docs/LIMITACOES.md` item 1 para a fronteira de
alcance explícita desta aproximação.
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
    # r̄ é a média de r ponderada por C (o stock em livro, o mesmo peso que
    # multiplica o termo de mobilidade abaixo) — não Σ S/Σ(C+V), a razão
    # agregada usada antes. É a única escolha para a qual Σμ(rᵢ-r̄)Cᵢ = 0
    # exatamente, de modo que o termo de mobilidade realoca capital
    # constante agregado em vez de o criar ou destruir (ver paper/main.tex,
    # discussão da conservação do termo de mobilidade).
    r̄ = sum(r .* C) / sum(C)

    κ = ones(N)
    # Output bruto de um período soma o valor de capital constante
    # TRANSFERIDO (δ.*C, depreciação do stock avançado), não o stock C em
    # si — C é uma magnitude de stock, V e S são fluxos anuais; somá-los
    # diretamente misturaria dimensões temporais distintas (ver
    # `estruturas.jl`, `capital_transferido`/`valor_produto`).
    if p.racionamento
        O = p.δ .* C .+ V .+ S
        κ = _resolver_racionamento(p.A, p.σ_c, S, O)
    elseif p.realização
        O = p.δ .* C .+ V .+ S
        procura_intermédia = p.A * O
        soma_procura = sum(procura_intermédia)
        soma_procura > 0 && (κ .= min(sum(min.(O, procura_intermédia)) / soma_procura, 1.0))
    end

    dX[1:N]    = κ .* p.σ_c .* S .- p.δ .* C .+ p.μ .* (r .- r̄) .* C
    dX[N+1:2N] = p.σ_v .* S
end

"""
    _resolver_racionamento(A, σ_c, S, O; max_iter=100, tol=1e-8)

Resolve o racionamento de mercado (regra do lado curto, tecnologia Leontief)
para os bens de investimento, dado o estado corrente. Para cada setor
comprador `j`, o reinvestimento planeado `σ_c,ⱼ·Sⱼ` exige inputs de
fornecedores na proporção `A[:,j]` — não há substituição entre inputs, logo
o reinvestimento realizado fica limitado pelo input mais escasso (lei do
mínimo). Isto torna o problema simultâneo: o racionamento sofrido por um
setor reduz a sua procura efetiva de TODOS os seus inputs, o que por sua vez
afeta o racionamento sofrido pelos seus fornecedores. Resolve-se por
iteração de ponto fixo (`ρ`= fator de racionamento por setor fornecedor,
`κ` = fração realizada do reinvestimento planeado por setor comprador):

    κⱼ = min_{i: A[i,j]>0} ρᵢ                    (limitado pelo input mais escasso)
    Dᵢ = Σⱼ A[i,j]·κⱼ·σ_c,ⱼ·Sⱼ                     (procura efetiva, já consistente com o racionamento)
    ρᵢ = min(1, Oᵢ / Dᵢ)                          (regra do lado curto)

Se não convergir em `max_iter` iterações, cai-se para `κ = ones(N)` (sem
racionamento, equivalente a desligar este mecanismo) com um aviso — a
mesma filosofia de degradação graciosa usada no resto do código (fallback
de preços de Sraffa na mesma função, fallbacks de rede AMECO/Eurostat).
"""
function _resolver_racionamento(A, σ_c, S, O; max_iter = 200, tol = 1e-8, relaxação = 0.5,
                                ρ_inicial = nothing, devolver_diagnóstico::Bool = false)
    N = length(S)
    D_planeado = σ_c .* S
    fornecedores(j) = A[:, j] .> 0
    ρ = isnothing(ρ_inicial) ? ones(N) : copy(ρ_inicial)
    convergiu = false
    iterações = max_iter
    for it in 1:max_iter
        κ = [minimum(ρ[fornecedores(j)]; init = 1.0) for j in 1:N]
        D_real = A * (κ .* D_planeado)
        ρ_alvo = min.(1.0, O ./ max.(D_real, 1e-12))
        # sub-relaxação: sem isto, a iteração pode oscilar entre dois estados em vez de
        # convergir (o mapa min(1,O/D) não é uma contração pura) — verificado num exemplo
        # de 2 setores em que a versão sem relaxação oscilava indefinidamente entre
        # ρ=[0.8,1] e ρ=[1,1].
        ρ_novo = (1 - relaxação) .* ρ .+ relaxação .* ρ_alvo
        if maximum(abs.(ρ_novo .- ρ)) < tol
            ρ = ρ_novo
            convergiu = true
            iterações = it
            break
        end
        ρ = ρ_novo
    end
    convergiu || @warn "Racionamento não convergiu em $max_iter iterações; a usar κ=1 (sem racionamento)."
    κ_final = convergiu ? [minimum(ρ[fornecedores(j)]; init = 1.0) for j in 1:N] : ones(N)
    if devolver_diagnóstico
        return (κ = κ_final, convergiu = convergiu, iterações = iterações,
                fração_racionada = count(κ_final .< 0.999) / N)
    end
    return κ_final
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
    simular_Ndept(N; T=100.0, nomes=String[], seed=nothing, acoplado=false, μ=0.3, realização=false, racionamento=false)

Simula o modelo de N departamentos com departamentos gerados aleatoriamente.
Com `acoplado=true`, usa `sistema_Ndept_io!` (mobilidade de capital via A e
preços de produção); `μ` é o coeficiente de mobilidade nesse caso.
`realização=true` (só tem efeito com `acoplado=true`) acresce a pressão de
realização agregada; `racionamento=true` (tem precedência sobre
`realização`) usa racionamento por setor — ver docstring de
`sistema_Ndept_io!`.
"""
function simular_Ndept(N::Int; T = 100.0, nomes::Vector{String} = String[],
                       seed = nothing, acoplado = false, μ = 0.3,
                       realização = false, racionamento = false)
    depts = criar_departamentos(N, nomes)
    return simular_Ndept_customizado(depts, T = T, seed = seed, acoplado = acoplado, μ = μ,
                                     realização = realização, racionamento = racionamento)
end

"""
    simular_Ndept_customizado(depts; T=100.0, seed=nothing, acoplado=false, μ=0.3, realização=false, racionamento=false)

Simula o modelo de N departamentos a partir de departamentos pré-configurados.
Com `acoplado=true`, usa `sistema_Ndept_io!` em vez de `sistema_Ndept!`.
`realização=true` (só tem efeito com `acoplado=true`) acresce a pressão de
realização agregada; `racionamento=true` (tem precedência sobre
`realização`) usa racionamento por setor — ver docstring de
`sistema_Ndept_io!`.
"""
function simular_Ndept_customizado(depts::Vector{Departamento}; T = 100.0,
                                   seed = nothing, acoplado = false, μ = 0.3,
                                   realização = false, racionamento = false)
    N = length(depts)
    X0 = [ [d.c for d in depts]; [d.v for d in depts] ]
    A = criar_matriz_tecnica(N, seed = seed)

    if acoplado
        l = [d.v for d in depts]
        p = (
            e           = [d.e for d in depts],
            σ_c         = [d.σ_c for d in depts],
            σ_v         = [d.σ_v for d in depts],
            δ           = [d.δ for d in depts],
            A           = A,
            l           = l,
            R_max       = calcular_taxa_lucro_maxima(A, l),
            μ           = μ,
            w           = 1.0,
            realização  = realização,
            racionamento = racionamento,
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
