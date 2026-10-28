# ============================================================================
# CRESCIMENTO EQUILIBRADO: O SISTEMA NORMALIZADO
# ----------------------------------------------------------------------------
# O lado direito de `sistema_Ndept!`/`sistema_Ndept_io!` é homogéneo de grau 1
# no estado X = [C; V] (`f(λX) = λf(X)`), pelo que as trajetórias não
# estabilizam em níveis: os estados estacionários relevantes são raios de
# crescimento equilibrado, `f(X★) = g★·X★`. São os pontos fixos do sistema
# normalizado no simplex,
#
#     y = X/ΣX,      ẏ = f(y) − (1ᵀf(y))·y,
#
# escrito em 2N−1 coordenadas livres (a última é 1 − Σ das outras), para que
# a restrição do simplex não seja uma direção degenerada da jacobiana.
#
# Sem preços de mercado, a taxa de lucro de um setor não depende da sua
# dimensão relativa e as condições de equilíbrio são sobredeterminadas: não
# há crescimento equilibrado interior (o capital concentra-se num setor),
# mesmo com `μ_v`, `realização` ou `racionamento`. Com a dinâmica cruzada
# (`src/cruzado.jl`) há, e é o caso analisado em `bifurcacao_acumulação`.
# ============================================================================

_cruzado(p) = haskey(p, :β)

"""
Estado completo a partir das coordenadas livres `z`: quantidades
`y = [z₁…z₂ₙ₋₁; 1 − Σ]` no simplex e, no sistema cruzado, log-preços com
média zero `q = [z…; −Σ]` (só os preços relativos importam).
"""
function _do_livre(z, p)
    nq = 2 * length(p.e)
    y = [z[1:nq-1]; 1 - sum(z[1:nq-1])]
    _cruzado(p) || return y
    qf = z[nq:end]
    return [y; qf; -sum(qf)]
end

"""Coordenadas livres de um estado completo `X` (normaliza quantidades e preços)."""
function _para_livre(X, p)
    nq = 2 * length(p.e)
    y = X[1:nq] ./ sum(X[1:nq])
    _cruzado(p) || return y[1:end-1]
    q = X[nq+1:end] .- mean(X[nq+1:end])
    return [y[1:end-1]; q[1:end-1]]
end

"""Projeção do lado direito no estado completo normalizado (quantidades no
simplex, log-preços com média zero)."""
function _projetar(fX, X, p)
    nq = 2 * length(p.e)
    hy = fX[1:nq] .- sum(fX[1:nq]) .* X[1:nq]
    _cruzado(p) || return hy
    return [hy; fX[nq+1:end] .- mean(fX[nq+1:end])]
end

"""
    sistema_normalizado(p; t=0.0)

Lado direito do sistema normalizado nas coordenadas livres, `z ↦ h(z)`:
`ẏ = f(y) − (1ᵀf(y))·y` para as quantidades (2N−1 coordenadas livres) e,
no sistema cruzado (`p` com `β`), `q̇ − média(q̇)` para os log-preços (N−1).
Os seus zeros são os raios de crescimento equilibrado de `f` (com preços
relativos constantes, no sistema cruzado).
"""
function sistema_normalizado(p; t = 0.0)
    f = _rhs(p, t)
    nq = 2 * length(p.e)
    return function (z)
        X = _do_livre(z, p)
        h = _projetar(f(X), X, p)
        _cruzado(p) || return h[1:nq-1]
        return [h[1:nq-1]; h[nq+1:end-1]]
    end
end

"""Lado direito normalizado no estado completo, para integração."""
function _rhs_normalizado!(dX, X, p, t)
    fX = similar(X)
    _sistema_de(p)(fX, X, p, t)
    dX .= _projetar(fX, X, p)
end

"""
    simular_normalizado(p, X0; T=500.0)

Integra o sistema normalizado a partir de `X0` (normalizado internamente:
quantidades no simplex, log-preços com média zero) — sem o crescimento
exponencial dos níveis, que transborda em horizontes longos.
"""
function simular_normalizado(p, X0; T = 500.0, saveat = 1.0)
    prob = ODEProblem(_rhs_normalizado!, _do_livre(_para_livre(X0, p), p), (0.0, T), p)
    return solve(prob, Tsit5(), saveat = saveat, abstol = 1e-10, reltol = 1e-8)
end

"""
    indicadores_crescimento(p, X)

Indicadores num estado `X` (normalizado ou não): taxa de crescimento `g`
(`1ᵀf/1ᵀ(C+V)`, a taxa comum de crescimento equilibrado num ponto fixo),
taxas de lucro `r` (a preços de produção de Sraffa no sistema acoplado; a
preços de mercado no cruzado), composições orgânicas `k = C/V`, quotas
`quota_C`, `quota_V`, parcela salarial agregada `ω = ΣV/(ΣV+ΣS)`, taxa de
lucro agregada `r_agregada = ΣS/Σ(C+V)` e `dispersão_r`. No sistema
cruzado, também os preços de mercado `P` e o excesso de procura relativo.
"""
function indicadores_crescimento(p, X)
    N = length(p.e)
    C, V = X[1:N], X[N+1:2N]
    S = p.e .* V
    fX = _rhs(p)(X)
    g = sum(fX[1:2N]) / sum(X[1:2N])
    base = (g = g, k = C ./ V, quota_C = C ./ sum(C), quota_V = V ./ sum(V),
            ω = sum(V) / (sum(V) + sum(S)), r_agregada = sum(S) / sum(C .+ V))
    if _cruzado(p)
        ec = estado_cruzado(C, V, X[2N+1:3N], p)
        return merge(base, (r = ec.r, dispersão_r = std(ec.r), P = ec.P, excesso = ec.excesso))
    end
    r = haskey(p, :μ) ? _taxas_lucro_io(C, V, S, p) : S ./ (C .+ V)
    return merge(base, (r = r, dispersão_r = std(r)))
end

"""
    crescimento_equilibrado(p, X0; T_aquecimento=400.0, tol=1e-12, max_iter=50)

Raio de crescimento equilibrado `X★` (`f(X★) = g★X★`) a partir de `X0`:
integra o sistema normalizado durante `T_aquecimento` e afina por Newton
nas coordenadas livres, com jacobiana exata (ForwardDiff). Devolve os
`indicadores_crescimento` no ponto fixo, mais `X` (estado completo
normalizado), `z` (coordenadas livres), `J` (jacobiana de `sistema_normalizado`), `valores_próprios`, `estável`
(todas as partes reais < 0), `resíduo` e `convergiu`.

Os valores próprios de `J` são os das perturbações das proporções; o modo
radial (escala) foi removido pela normalização, logo `estável` significa
que o raio atrai trajetórias próximas em proporções.
"""
function crescimento_equilibrado(p, X0; T_aquecimento = 400.0, tol = 1e-12, max_iter = 50)
    X = T_aquecimento > 0 ?
        simular_normalizado(p, X0; T = T_aquecimento, saveat = T_aquecimento).u[end] : X0
    z = _para_livre(X, p)
    h = sistema_normalizado(p)
    nq = 2 * length(p.e)
    convergiu = false
    for _ in 1:max_iter
        hz = h(z)
        maximum(abs.(hz)) < tol && (convergiu = true; break)
        Δ = ForwardDiff.jacobian(h, z) \ hz
        # passo amortecido: quantidades estritamente positivas
        α = 1.0
        while α > 1e-8 && any(_do_livre(z .- α .* Δ, p)[1:nq] .<= 0)
            α /= 2
        end
        z = z .- α .* Δ
    end
    J = ForwardDiff.jacobian(h, z)
    λs = eigvals(J)
    X = _do_livre(z, p)
    return merge(indicadores_crescimento(p, X),
                 (X = X, z = z, J = J, valores_próprios = λs,
                  estável = maximum(real.(λs)) < 0, resíduo = maximum(abs.(h(z))),
                  convergiu = convergiu))
end

"""
    com_parâmetro(p, parâmetro, θ; e_ref=p.e)

`p` com o parâmetro de bifurcação fixado em `θ`:

- `:μ`, `:μ_v` — coeficientes de mobilidade do capital constante / variável;
- `:ω` — parcela salarial uniforme: `eᵢ = (1−θ)/θ` em todos os setores;
- `:escala_e` — exploração proporcional: `eᵢ = θ·e_ref,ᵢ` (preserva a
  heterogeneidade entre setores; a parcela salarial agregada resultante é
  reportada por `indicadores_crescimento`).
"""
function com_parâmetro(p, parâmetro::Symbol, θ; e_ref = p.e)
    parâmetro === :μ && return merge(p, (μ = θ,))
    parâmetro === :μ_v && return merge(p, (μ_v = θ,))
    parâmetro === :ω && return merge(p, (e = fill((1 - θ) / θ, length(p.e)),))
    parâmetro === :escala_e && return merge(p, (e = θ .* e_ref,))
    error("parâmetro desconhecido: $parâmetro (use :μ, :μ_v, :ω ou :escala_e)")
end

"""
    varrimento_salarial(p, X0; variante=:uniforme, valores=nothing)

Crescimento equilibrado em função da distribuição, por continuação natural
(cada ponto parte do anterior, Newton com jacobiana exata):

- `variante = :uniforme` — parcela salarial uniforme `ω` (`com_parâmetro`
  `:ω`, `eᵢ = (1−ω)/ω`), `valores` por omissão `0.15:0.01:0.70`;
- `variante = :proporcional` — exploração escalada `eᵢ = θ·eᵢ⁰`
  (`:escala_e`, mantém a heterogeneidade setorial), `valores` por omissão
  `0.2:0.05:3.0`.

Devolve, por ponto: `θ`, a parcela salarial efetiva `ω`, a taxa de
crescimento `g`, a taxa de lucro agregada `r`, a composição orgânica
agregada `k = ΣC/ΣV`, `dispersão_r`, `parte_real_máx` e `oscilatório`
(o valor próprio dominante é complexo: aproximação ao equilíbrio em
ciclos amortecidos), `estável`, `quota_mín` e `convergiu`.
"""
function varrimento_salarial(p, X0; variante = :uniforme, valores = nothing)
    parâmetro = variante === :uniforme ? :ω : variante === :proporcional ? :escala_e :
                error("variante desconhecida: $variante (use :uniforme ou :proporcional)")
    θs = collect(something(valores, variante === :uniforme ? (0.15:0.01:0.70) : (0.2:0.05:3.0)))
    nq = 2 * length(p.e)
    X = X0
    linhas = map(enumerate(θs)) do (k, θ)
        pθ = com_parâmetro(p, parâmetro, θ)
        eq = crescimento_equilibrado(pθ, X; T_aquecimento = k == 1 ? 400.0 : 0.0)
        eq.convergiu || (eq = crescimento_equilibrado(pθ, X0))   # recomeço com aquecimento
        eq.convergiu && (X = eq.X)
        dominante = eq.valores_próprios[argmax(real.(eq.valores_próprios))]
        (θ = θ, ω = eq.ω, g = eq.g, r = eq.r_agregada, k = sum(eq.X[1:nq÷2]) / sum(eq.X[nq÷2+1:nq]),
         dispersão_r = eq.dispersão_r, parte_real_máx = real(dominante),
         oscilatório = abs(imag(dominante)) > 1e-8, estável = eq.estável,
         quota_mín = minimum(eq.X[1:nq]), convergiu = eq.convergiu)
    end
    return (variante = variante, (c => getproperty.(linhas, c) for c in keys(linhas[1]))...)
end
