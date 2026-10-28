# ============================================================================
# ANÁLISE DE BIFURCAÇÕES (BifurcationKit + ForwardDiff)
# ----------------------------------------------------------------------------
# Continuação numérica de pontos fixos de MAPAS `z ↦ G(z, θ)` num parâmetro
# θ, com estabilidade lida dos multiplicadores `μ` da jacobiana exata
# `∂G/∂z` (ForwardDiff). Aplica-se a:
#
#   - o passo amortecido do racionamento, `ρ ↦ (1−α)ρ + αF(ρ; s)`, com a
#     escala de procura `s` como parâmetro (`bifurcacao_racionamento`);
#   - o mapa de preços TSSI com desfasamento τ fixo, `p(t−τ) ↦ p(t)`, com a
#     intensidade da mais-valia como parâmetro (`bifurcacao_tssi`).
#
# As EDOs de acumulação crescem sem limite (C, V exponenciais) e não têm
# equilíbrios em níveis; os seus estados estacionários são raios de
# crescimento equilibrado, pontos fixos do sistema normalizado de
# `src/crescimento.jl`. Esses são continuados na secção final
# (`bifurcacao_acumulação`), com deteção de Hopf e continuação de órbitas
# periódicas.
#
# O BifurcationKit faz a continuação (pseudo-comprimento de arco, PALC) do
# ramo `G(z, θ) − z = 0`. A deteção de bifurcações dele assume EDOs (valores
# próprios de ∂F/∂z a cruzar o eixo imaginário) e não deteta flips de mapas
# (μ = −1); por isso a classificação é feita aqui, sobre os multiplicadores
# de G: fold (μ = +1), flip / duplicação de período (μ = −1) e
# Neimark–Sacker (par complexo com |μ| = 1).
# ============================================================================

"""Classifica o multiplicador que cruza |μ| = 1 pelo seu argumento."""
function _tipo_bifurcação_mapa(μ)
    abs(imag(μ)) > 1e-6 * max(1, abs(μ)) && return :neimark_sacker
    return real(μ) > 0 ? :fold : :flip
end

"""
    continuar_ponto_fixo(G, z0, θ0, θ_min, θ_max; ds=0.01, dsmax=0.05, max_passos=1000,
                         tol_estabilidade=1e-8)

Continua o ramo de pontos fixos `z★(θ) = G(z★, θ)` a partir de `(z0, θ0)`
(que deve ser já um ponto fixo, ou próximo) em `θ ∈ [θ_min, θ_max]`, com o
BifurcationKit (PALC, jacobiana `∂G/∂z − I` por ForwardDiff). Em cada ponto
do ramo calcula os multiplicadores de `∂G/∂z` e devolve:

- `θ`, `z` (dim(z) × K), `raio` (raio espectral de ∂G/∂z) e
  `multiplicadores` ao longo do ramo;
- `pontos`: vetor de `(tipo, θ, μ)` onde o número de multiplicadores
  instáveis (|μ| > 1 + `tol_estabilidade`) muda — `tipo ∈ (:fold, :flip, :neimark_sacker)`,
  `θ` interpolado linearmente em `raio − 1` entre os dois passos;
- `ramo`: o objeto devolvido por `BK.continuation`.
"""
function continuar_ponto_fixo(G, z0, θ0, θ_min, θ_max; ds = 0.01, dsmax = 0.05,
                              max_passos = 1000, tol_estabilidade = 1e-8)
    F(z, par) = G(z, par.θ) .- z
    J(z, par) = ForwardDiff.jacobian(zz -> F(zz, par), z)
    prob = BK.BifurcationProblem(F, collect(float.(z0)), (θ = θ0,), (BK.@optic _.θ); J = J)
    opts = BK.ContinuationPar(p_min = θ_min, p_max = θ_max, ds = ds, dsmax = dsmax,
                              max_steps = max_passos, save_sol_every_step = 1,
                              detect_bifurcation = 0, detect_fold = false)
    ramo = BK.continuation(prob, BK.PALC(), opts; verbosity = 0)

    θs = [s.p for s in ramo.sol]
    Z = reduce(hcat, [s.x for s in ramo.sol])
    μs = [eigvals(ForwardDiff.jacobian(z -> G(z, θ), Z[:, k])) for (k, θ) in enumerate(θs)]
    raio = [maximum(abs.(μ)) for μ in μs]
    # |μ| = 1 ± arredondamento (p.ex. o λ = −1 estrutural do racionamento com
    # α = 1) conta como neutro, não instável — sem a tolerância, o ruído
    # numérico em torno de |μ| = 1 dá deteções espúrias a cada passo.
    n_instáveis = [count(abs.(μ) .> 1 + tol_estabilidade) for μ in μs]

    pontos = NamedTuple[]
    for k in 2:length(θs)
        n_instáveis[k] == n_instáveis[k-1] && continue
        # o multiplicador responsável: o de |μ| mais próximo de 1 no lado instável
        μ_lado = n_instáveis[k] > n_instáveis[k-1] ? μs[k] : μs[k-1]
        μ★ = μ_lado[argmin(abs.(abs.(μ_lado) .- 1))]
        w = (1 - raio[k-1]) / (raio[k] - raio[k-1])
        θ★ = isfinite(w) && 0 <= w <= 1 ? θs[k-1] + w * (θs[k] - θs[k-1]) : θs[k]
        push!(pontos, (tipo = _tipo_bifurcação_mapa(μ★), θ = θ★, μ = μ★))
    end
    return (θ = θs, z = Z, raio = raio, multiplicadores = μs, pontos = pontos, ramo = ramo)
end

"""
    bifurcacao_racionamento(A, σ_c, S, O; escala=(0.1, 3.0), relaxação=RELAXAÇÃO_PADRÃO, ds=0.01)

Bifurcações do esquema iterativo de racionamento quando a procura planeada
é escalada por `s` (`D = s·σ_c·S`; `s` pequeno: sem racionamento, `s`
grande: racionamento em todos os setores). Continua o ponto fixo `ρ★(s)` do
passo amortecido `ρ ↦ (1−α)ρ + αF(ρ; s)` com `α = relaxação` (o ponto fixo
não depende de α; a estabilidade sim) e devolve, além do resultado de
`continuar_ponto_fixo`:

- `α_max`: para cada `s`, o maior `α` com convergência local
  (`intervalo_relaxação` dos valores próprios de `∂F/∂ρ`) — a fronteira de
  flip no plano (s, α), já que os valores próprios de F são reais ≤ 0 nos
  casos testados;
- `fração_racionada`: fração de setores com `ρᵢ★ < 1`.

Assim que algum setor é racionado, `λ = −1` é valor próprio de `∂F/∂ρ`:
seja `k` o setor com o menor `ρₖ★`; todo o comprador `j` que `k` abastece
tem `κⱼ = ρₖ`, logo `Dₖ = ρₖ·Lₖ` (`Lₖ = Σⱼ A[k,j]·Dⱼ`, procura sem
racionamento), `Fₖ = xₖ/(ρₖLₖ)` e a linha k de J é `−eₖᵀ`. Daí
`ρₖ★ = √(xₖ/Lₖ)` em forma fechada (generaliza o `√0.8` do exemplo de 2
setores), `α_max ≤ 1`, e `α = 1` (sem amortecimento) fica exatamente na
fronteira de flip: nunca converge localmente quando o racionamento atua.
O salto de `α_max` de 2 para ≤ 1 no início do racionamento é uma
bifurcação de colisão de fronteira (o mapa é seccionalmente suave), não
uma bifurcação suave.
"""
function bifurcacao_racionamento(A, σ_c, S, O; escala = (0.1, 3.0), relaxação = RELAXAÇÃO_PADRÃO,
                                 ds = 0.01, dsmax = 0.05, max_passos = 2000)
    D = σ_c .* S
    G(ρ, s) = (1 - relaxação) .* ρ .+ relaxação .* _mapa_racionamento(ρ, A, s .* D, O)
    s0 = escala[1]
    diag = _resolver_racionamento(A, ones(length(S)), s0 .* D, O; tol = 1e-12,
                                  max_iter = 10_000, devolver_diagnóstico = true)
    res = continuar_ponto_fixo(G, diag.ρ, s0, escala[1], escala[2]; ds = ds, dsmax = dsmax,
                               max_passos = max_passos)
    α_max = [intervalo_relaxação(eigvals(ForwardDiff.jacobian(
                 ρ -> _mapa_racionamento(ρ, A, s .* D, O), res.z[:, k])))
             for (k, s) in enumerate(res.θ)]
    fração = [count(res.z[:, k] .< 1 - 1e-9) / size(res.z, 1) for k in eachindex(res.θ)]
    return merge(res, (α_max = α_max, fração_racionada = fração, relaxação = relaxação))
end

"""
    bifurcacao_tssi(X, p; τ=1.0, escala=(0.1, 3.0), ds=0.01)

Bifurcações do mapa de preços TSSI `p(t−τ) ↦ p(t)` (`mapa_tssi`), com
desfasamento τ FIXO e dados congelados no estado `X`, em função da
intensidade da mais-valia `θ` (`S → θ·S`, ver `dados_tssi`). O ramo
`p★(θ)` é o dos preços simultaneístas; a sua estabilidade decide se os
preços TSSI convergem para eles. Como o atraso é único, os pontos de
bifurcação em θ não dependem de τ; τ fixa apenas a escala de tempo
(`taxa_convergência = log(raio)/τ`, também devolvida).
"""
function bifurcacao_tssi(X, p; τ = 1.0, escala = (0.1, 3.0), ds = 0.01, dsmax = 0.05,
                         max_passos = 2000)
    G(q, θ) = mapa_tssi(q, dados_tssi(X, p; escala_mais_valia = θ)).p
    θ0 = escala[1]
    p0 = preços_simultâneos(dados_tssi(X, p; escala_mais_valia = θ0)).p
    res = continuar_ponto_fixo(G, p0, θ0, escala[1], escala[2]; ds = ds, dsmax = dsmax,
                               max_passos = max_passos)
    r★ = [preços_simultâneos(dados_tssi(X, p; escala_mais_valia = θ)).r for θ in res.θ]
    return merge(res, (τ = τ, r★ = r★, taxa_convergência = log.(res.raio) ./ τ))
end

"""
    plotar_bifurcacao(res; titulo="")

Raio espectral dos multiplicadores ao longo do ramo (estável abaixo de 1),
com os pontos de bifurcação detetados; para `bifurcacao_racionamento`,
acrescenta a fronteira de flip `α_max(s)` contra a relaxação usada.
"""
function plotar_bifurcacao(res; titulo = "")
    p1 = plot(res.θ, res.raio, lw = 2, label = "raio espectral de ∂G/∂z",
              xlabel = "parâmetro", ylabel = "max |μ|", title = titulo)
    hline!(p1, [1.0], ls = :dash, color = :black, label = "|μ| = 1")
    for pt in res.pontos
        vline!(p1, [pt.θ], ls = :dot, label = string(pt.tipo))
    end
    haskey(res, :α_max) || return p1
    p2 = plot(res.θ, res.α_max, lw = 2, label = "α_max(s) (fronteira de flip)",
              xlabel = "escala da procura s", ylabel = "relaxação α",
              title = "Região de convergência local")
    hline!(p2, [res.relaxação], ls = :dash, label = "α usado")
    return plot(p1, p2, layout = (1, 2), size = (1000, 400))
end

# ============================================================================
# ACUMULAÇÃO: CRESCIMENTO EQUILIBRADO, HOPF E ÓRBITAS PERIÓDICAS
# ----------------------------------------------------------------------------
# Continuação dos raios de crescimento equilibrado (zeros de
# `sistema_normalizado`) num parâmetro de `com_parâmetro`. Aqui o problema é
# uma EDO, e as deteções do BifurcationKit aplicam-se diretamente: Hopf
# (par complexo a cruzar o eixo imaginário) com forma normal (primeiro
# coeficiente de Lyapunov), e folds / pontos de ramificação. Dos Hopf
# supercríticos continuam-se os ciclos-limite por colocação ortogonal, com
# estabilidade pelos multiplicadores de Floquet e as bifurcações de ciclos
# (fold de ciclos, duplicação de período, Neimark–Sacker / toro).
# ============================================================================

"""Problema do BifurcationKit para o sistema normalizado com `θ` = `parâmetro`."""
function _problema_acumulação(p, parâmetro, z0, θ0; e_ref = p.e)
    F(z, par) = sistema_normalizado(com_parâmetro(p, parâmetro, par.θ; e_ref = e_ref))(z)
    J(z, par) = ForwardDiff.jacobian(zz -> F(zz, par), z)
    return BK.BifurcationProblem(F, collect(float.(z0)), (θ = θ0,), (BK.@optic _.θ); J = J,
                                 record_from_solution = (z, par; k...) -> (quota_mín = minimum(_do_livre(z, p)[1:2length(p.e)]),))
end

"""Amplitude e quota mínima de uma órbita (matriz dim(z) × pontos)."""
function _medidas_órbita(U, p)
    nq = 2 * length(p.e)
    Y = vcat(U[1:nq-1, :], 1 .- sum(U[1:nq-1, :], dims = 1))
    amplitude = maximum(maximum(Y, dims = 2) .- minimum(Y, dims = 2))
    return (amplitude = amplitude, quota_mín = minimum(Y))
end

"""
    ciclo_simulado(p, parâmetro, θ, X0; T=4000.0, dt=0.02, e_ref=p.e)

Verificação por simulação direta do sistema normalizado em `θ`: integra
desde `X0` e, na segunda metade da trajetória, mede uma secção de Poincaré
(cruzamentos ascendentes da média na primeira coordenada). Devolve `n`
(número de cruzamentos), `dispersão_secção` (variação da segunda coordenada
nos cruzamentos: ≈ 0 num ciclo-limite, > 0 num toro ou atrator irregular),
`T_min`/`T_max` (tempos de retorno; iguais num ciclo, ≈ período),
`amplitude` e `quota_mín` (como em `bifurcacao_acumulação`). Sem
cruzamentos (`n < 2`) a trajetória convergiu para o equilíbrio.
"""
function ciclo_simulado(p, parâmetro, θ, X0; T = 4000.0, dt = 0.02, e_ref = p.e)
    pθ = com_parâmetro(p, parâmetro, θ; e_ref = e_ref)
    h = sistema_normalizado(pθ)
    prob = ODEProblem((z, _, t) -> h(z), _para_livre(X0, pθ), (0.0, T))
    sol = solve(prob, Tsit5(), abstol = 1e-11, reltol = 1e-9, saveat = dt)
    U = reduce(hcat, sol.u[end÷2:end])
    medidas = _medidas_órbita(U, pθ)
    c = mean(U[1, :])
    idx = findall(i -> U[1, i] < c && U[1, i+1] >= c, 1:size(U, 2)-1)
    length(idx) < 2 && return merge((n = length(idx), dispersão_secção = 0.0, T_min = NaN, T_max = NaN), medidas)
    secção = U[2, idx]
    retornos = diff(idx) .* dt
    return merge((n = length(idx), dispersão_secção = maximum(secção) - minimum(secção),
                  T_min = minimum(retornos), T_max = maximum(retornos)), medidas)
end

"""
    bifurcacao_acumulação(p, X0, parâmetro; intervalo, θ0=intervalo[1], ds=0.01,
                          dsmax=0.01, max_passos=1000, órbitas=true,
                          intervalo_órbitas=intervalo, δθ=1e-3, Ntst=40, m=4)

Bifurcações do crescimento equilibrado do sistema cruzado (`p` de
`simular_Ndept(...; acoplado=true, preços_mercado=true)`) no `parâmetro` de
`com_parâmetro` (`:μ`, `:μ_v`, `:ω`, `:escala_e`), em `θ ∈ intervalo`:

1. Ramo de equilíbrios: `crescimento_equilibrado` em `θ0` (a partir de `X0`)
   e continuação PALC com jacobiana exata (ForwardDiff). Devolve `θ`, `z`,
   `parte_real_máx` (maior parte real dos valores próprios, < 0 = estável),
   `g` e `quota_mín` ao longo do ramo, e `pontos` (`(tipo, θ)` do
   BifurcationKit: `:hopf`, `:bp`, `:fold`, ...).
2. `hopf`: forma normal de cada Hopf (`θ`, frequência `ω`, `período = 2π/ω`,
   coeficiente de Lyapunov `l1 = Re b`, `supercrítico = l1 < 0` e
   `transversalidade = Re a`, a velocidade de cruzamento: > 0 se o par
   passa a instável com θ a subir).
3. `órbitas` (se `órbitas=true` e o primeiro Hopf for supercrítico): ramo de
   ciclos-limite por colocação (`Ntst` intervalos de grau `m`), semeado pelo
   preditor da forma normal em `θ_H + δθ` (integrado um período) e
   continuado em ambos os sentidos — para o Hopf (amplitude → 0) e até ao
   limite de `intervalo_órbitas`. Devolve `θ`, `amplitude` (máxima oscilação de uma
   quota), `período`, `quota_mín`, `estável` (multiplicadores de Floquet) e
   `pontos` (bifurcações de ciclos: `:bp` = fold de ciclos, `:pd` =
   duplicação de período, `:ns` = Neimark–Sacker).

Confirmar os resultados com `ciclo_simulado` (o BifurcationKit não sabe se
um ciclo encosta à fronteira do simplex — ver `quota_mín`).
"""
function bifurcacao_acumulação(p, X0, parâmetro::Symbol; intervalo, θ0 = intervalo[1],
                               ds = 0.01, dsmax = 0.01, max_passos = 1000, órbitas = true,
                               intervalo_órbitas = intervalo, δθ = 1e-3, Ntst = 40, m = 4,
                               e_ref = p.e)
    _cruzado(p) || error("bifurcacao_acumulação requer o sistema cruzado (preços_mercado=true)")
    eq = crescimento_equilibrado(com_parâmetro(p, parâmetro, θ0; e_ref = e_ref), X0)
    eq.convergiu || @warn "crescimento_equilibrado não convergiu em θ0 = $θ0 (resíduo $(eq.resíduo))"
    prob = _problema_acumulação(p, parâmetro, eq.z, θ0; e_ref = e_ref)
    nz = length(eq.z)
    opts = BK.ContinuationPar(p_min = intervalo[1], p_max = intervalo[2], ds = ds, dsmax = dsmax,
                              max_steps = max_passos, detect_bifurcation = 3, n_inversion = 8,
                              nev = nz, save_sol_every_step = 1)
    ramo = BK.continuation(prob, BK.PALC(), opts; verbosity = 0)

    θs = [s.p for s in ramo.sol]
    Z = reduce(hcat, [s.x for s in ramo.sol])
    pθ(θ) = com_parâmetro(p, parâmetro, θ; e_ref = e_ref)
    λs = [eigvals(ForwardDiff.jacobian(sistema_normalizado(pθ(θ)), Z[:, k])) for (k, θ) in enumerate(θs)]
    λ_máx = [maximum(real.(λ)) for λ in λs]
    g = [indicadores_crescimento(pθ(θ), _do_livre(Z[:, k], p)).g for (k, θ) in enumerate(θs)]
    quota = [minimum(_do_livre(Z[:, k], p)[1:2length(p.e)]) for k in eachindex(θs)]
    pontos = [(tipo = sp.type, θ = sp.param) for sp in ramo.specialpoint if sp.type !== :endpoint]
    # salvaguarda: dois cruzamentos no mesmo passo escapam à deteção — comparar
    # com a contagem direta de valores próprios instáveis ao longo do ramo
    n_inst = [count(real.(λ) .> 1e-9) for λ in λs]
    cruzamentos = sum(abs, diff(n_inst); init = 0)
    detetados = sum(pt.tipo === :hopf ? 2 : 1 for pt in pontos; init = 0)
    cruzamentos == detetados ||
        @warn "bifurcacao_acumulação: $cruzamentos cruzamentos de valores próprios, $detetados nos pontos detetados — reduzir dsmax"

    hopf = NamedTuple[]
    formas = []
    for (i, sp) in enumerate(ramo.specialpoint)
        sp.type === :hopf || continue
        nf = BK.get_normal_form(ramo, i; verbose = false)
        push!(formas, nf)
        l1 = real(nf.nf.b)
        push!(hopf, (θ = nf.p, ω = nf.ω, período = 2π / abs(nf.ω), l1 = l1, supercrítico = l1 < 0,
                     transversalidade = real(nf.nf.a)))
    end

    res = (parâmetro = parâmetro, θ = θs, z = Z, parte_real_máx = λ_máx, g = g, quota_mín = quota,
           pontos = pontos, hopf = hopf, ramo = ramo, órbitas = nothing)
    (órbitas && !isempty(hopf)) || return res
    H = hopf[1]
    H.supercrítico || (@warn "primeiro Hopf subcrítico (θ = $(H.θ)): ciclos instáveis, sem semente por simulação"; return res)

    # semente: preditor da forma normal em θ_H + δθ (lado supercrítico),
    # integrado ~1 período e projetado na malha de colocação — a troca de
    # ramo automática do BifurcationKit falha aqui (jacobiana singular)
    lado = sign(H.transversalidade)
    pred = BK.predictor(formas[1], δθ)
    θ_s = pred.p
    T_s = 2π / abs(pred.ω)
    h = sistema_normalizado(pθ(θ_s))
    ode = ODEProblem((z, par, t) -> h(z), pred.orbit(0.0), (0.0, 1.25 * T_s), (θ = θ_s,))
    sol = solve(ode, Tsit5(), abstol = 1e-11, reltol = 1e-9)
    probθ = BK.re_make(prob; params = (θ = θ_s,))
    probPO, ci = BK.generate_ci_problem(BK.Collocation(Ntst, m), probθ, sol, T_s)

    registo = (x, par; k...) -> begin
        U = BK.get_periodic_orbit(par.prob, x, par.p).u
        merge(_medidas_órbita(U, p), (período = x[end],))
    end
    limite_fora = intervalo_órbitas[lado > 0 ? 2 : 1]
    function perna(alvo)
        o = BK.ContinuationPar(p_min = min(θ_s, alvo), p_max = max(θ_s, alvo),
                               ds = sign(alvo - θ_s) * 0.005, dsmax = 0.01, max_steps = max_passos,
                               detect_bifurcation = 3, nev = nz, tol_stability = 1e-5)
        BK.continuation(probPO, ci, BK.PALC(), o; verbosity = 0, record_from_solution = registo)
    end
    para_hopf = perna(H.θ)
    para_fora = perna(limite_fora)
    b1, b2 = para_hopf.branch, para_fora.branch
    junta(campo) = [reverse(getproperty(b1, campo)[2:end]); getproperty(b2, campo)]
    pontos_po = [(tipo = sp.type, θ = sp.param) for br in (para_hopf, para_fora)
                 for sp in br.specialpoint if sp.type !== :endpoint]
    órb = (θ = junta(:param), amplitude = junta(:amplitude), período = junta(:período),
           quota_mín = junta(:quota_mín), estável = junta(:stable), pontos = pontos_po,
           ramos = (para_hopf, para_fora))
    return merge(res, (órbitas = órb,))
end

"""
    curva_hopf(p, X0; ω_valores=0.2:0.05:0.65, intervalo_μv=(0.0, 4.0))

Fronteira de Hopf no plano (parcela salarial ω, mobilidade do capital
variável μ_v): para cada ω uniforme, continua o crescimento equilibrado em
`μ_v` (`bifurcacao_acumulação`, sem órbitas) e regista o primeiro Hopf —
`μ_v_H` (`NaN` se não houver em `intervalo_μv`), a sua frequência, o
coeficiente de Lyapunov `l1` e `supercrítico`. Abaixo da curva o
crescimento equilibrado é estável; acima, oscila.
"""
function curva_hopf(p, X0; ω_valores = 0.2:0.05:0.65, intervalo_μv = (0.0, 4.0), dsmax = 0.01)
    linhas = map(ω_valores) do ω
        pω = com_parâmetro(p, :ω, ω)
        r = bifurcacao_acumulação(pω, X0, :μ_v; intervalo = intervalo_μv, órbitas = false,
                                  dsmax = dsmax, ds = dsmax)
        isempty(r.hopf) && return (ω = ω, μ_v_H = NaN, frequência = NaN, l1 = NaN, supercrítico = false)
        H = r.hopf[1]
        (ω = ω, μ_v_H = H.θ, frequência = abs(H.ω), l1 = H.l1, supercrítico = H.supercrítico)
    end
    return (; (c => getproperty.(linhas, c) for c in keys(linhas[1]))...)
end

"""
    expoentes_lyapunov(p, parâmetro, θ, X0; k=3, T_transiente=3000.0, T=30000.0,
                       Δ=1.0, tol=1e-11, z0=nothing)

Os `k` maiores expoentes de Lyapunov do sistema normalizado em `θ`
(método de Benettin: equações variacionais com a jacobiana exata,
ForwardDiff, e re-ortonormalização QR a cada `Δ`), depois de um transiente
`T_transiente`, a partir de `X0` (ou das coordenadas livres `z0`).

Classificação do atrator: equilíbrio `(−, −, …)`; ciclo-limite
`(0, −, …)`; toro `(0, 0, −, …)`; caos `(+, 0, …)`; hipercaos com dois
expoentes positivos. Um dos expoentes é sempre ≈ 0 (direção do fluxo)
fora de um equilíbrio. São estimativas de tempo finito: o erro é da ordem
de `1/T` mais a variação lenta ao longo da trajetória (comparar `λ` com
`λ_meio`, a estimativa a meio do tempo). Evidência numérica de caos, não
prova.

Devolve `λ`, `λ_meio`, `z` (estado final) e `quota_mín` (menor quota
setorial no estado final).
"""
function expoentes_lyapunov(p, parâmetro, θ, X0; k = 3, T_transiente = 3000.0, T = 30000.0,
                            Δ = 1.0, tol = 1e-11, z0 = nothing, e_ref = p.e)
    pθ = com_parâmetro(p, parâmetro, θ; e_ref = e_ref)
    h = sistema_normalizado(pθ)
    z = isnothing(z0) ? _para_livre(X0, pθ) .+ 1e-3 : collect(float.(z0))
    n = length(z)
    if T_transiente > 0
        z = solve(ODEProblem((u, _, t) -> h(u), z, (0.0, T_transiente)), Vern9(),
                  abstol = tol, reltol = tol, save_everystep = false).u[end]
    end
    function variacional!(du, u, _, t)
        x = u[1:n]
        du[1:n] = h(x)
        du[n+1:end] = vec(ForwardDiff.jacobian(h, x) * reshape(u[n+1:end], n, k))
    end
    Q0 = Matrix(qr(Matrix{Float64}(I, n, k)).Q)
    integ = init(ODEProblem(variacional!, [z; vec(Q0)], (0.0, T)), Vern9(),
                 abstol = tol, reltol = tol, save_everystep = false)
    passos = round(Int, T / Δ)
    soma = zeros(k)
    λ_meio = zeros(k)
    for i in 1:passos
        step!(integ, Δ, true)
        F = qr(reshape(integ.u[n+1:end], n, k))
        d = diag(F.R)
        soma .+= log.(abs.(d))
        integ.u[n+1:end] = vec(Matrix(F.Q) .* sign.(d)')
        u_modified!(integ, true)
        i == passos ÷ 2 && (λ_meio .= soma ./ (i * Δ))
    end
    zf = integ.u[1:n]
    return (λ = soma ./ (passos * Δ), λ_meio = λ_meio, z = zf,
            quota_mín = minimum(_do_livre(zf, p)[1:2length(p.e)]))
end

"""
    histerese_simulada(p, parâmetro, grelha, X0; T_transiente=3000.0, T=3000.0, dt=0.02)

Varrimento do parâmetro por simulação, para cima e depois para baixo em
`grelha`, partindo cada ponto do estado final do anterior: deteta
coexistência de atratores (histerese). Em cada ponto classifica o
atrator pela secção de Poincaré (como `ciclo_simulado`): `:equilíbrio`,
`:ciclo` ou `:irregular` (toro ou caos). Devolve `θ` e, para `subir` e
`descer`, vetores com `classe`, `amplitude` e `retorno_médio`; e
`coexistência`, os `θ` onde os dois sentidos dão atratores diferentes.
"""
function histerese_simulada(p, parâmetro, grelha, X0; T_transiente = 3000.0, T = 3000.0,
                            dt = 0.02, e_ref = p.e)
    nq = 2 * length(p.e)
    function medir(θ, z)
        h = sistema_normalizado(com_parâmetro(p, parâmetro, θ; e_ref = e_ref))
        z1 = solve(ODEProblem((u, _, t) -> h(u), z, (0.0, T_transiente)), Vern9(),
                   abstol = 1e-12, reltol = 1e-12, save_everystep = false).u[end]
        s = solve(ODEProblem((u, _, t) -> h(u), z1, (0.0, T)), Vern9(),
                  abstol = 1e-12, reltol = 1e-12, saveat = dt)
        U = reduce(hcat, s.u)
        m = _medidas_órbita(U, p)
        c = mean(U[1, :])
        idx = findall(i -> U[1, i] < c && U[1, i+1] >= c, 1:size(U, 2)-1)
        esp = length(idx) < 2 ? 0.0 : maximum(U[2, idx]) - minimum(U[2, idx])
        classe = m.amplitude < 1e-4 ? :equilíbrio : esp < 0.01 * m.amplitude ? :ciclo : :irregular
        retorno = length(idx) < 2 ? NaN : mean(diff(idx)) * dt
        return (classe = classe, amplitude = m.amplitude, retorno_médio = retorno), s.u[end]
    end
    θs = collect(grelha)
    z = _para_livre(X0, com_parâmetro(p, parâmetro, θs[1]; e_ref = e_ref)) .+ 1e-3
    subir = NamedTuple[]
    for θ in θs
        r, z = medir(θ, z); push!(subir, r)
    end
    descer = NamedTuple[]
    for θ in reverse(θs)
        r, z = medir(θ, z); pushfirst!(descer, r)
    end
    tabela(v) = (classe = getproperty.(v, :classe), amplitude = getproperty.(v, :amplitude),
                 retorno_médio = getproperty.(v, :retorno_médio))
    difere = [θs[i] for i in eachindex(θs) if subir[i].classe != descer[i].classe ||
              abs(subir[i].retorno_médio - descer[i].retorno_médio) > 0.05 * subir[i].retorno_médio]
    return (θ = θs, subir = tabela(subir), descer = tabela(descer), coexistência = difere)
end
