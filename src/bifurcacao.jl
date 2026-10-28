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
# Porquê mapas e não a EDO: `sistema_Ndept!`/`sistema_Ndept_io!` crescem sem
# limite (C, V exponenciais), pelo que não têm equilíbrios em níveis — não há
# pontos fixos da EDO a continuar sem a reescrever em variáveis normalizadas.
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
