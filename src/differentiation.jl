# ============================================================================
# DIFERENCIAÇÃO AUTOMÁTICA: JACOBIANAS E HESSIANAS (ForwardDiff)
# ----------------------------------------------------------------------------
# Jacobianas exatas (não diferenças finitas) do lado direito das EDOs, do mapa
# de racionamento e dos mapas de preços TSSI (`src/tssi.jl`); hessianas para
# termos de segunda ordem (curvatura da fronteira distributiva, formas
# normais). O ponto fixo do racionamento diferencia-se pelo teorema da função
# implícita (`_racionamento_dual`, `src/nucleo.jl`), não iteração a iteração.
# ============================================================================

"""Escolhe o sistema de EDOs a partir dos campos de `p`: cruzado se tiver `β`
(preços de mercado), acoplado se tiver `μ`, independente caso contrário."""
_sistema_de(p) = haskey(p, :β) ? sistema_cruzado! : haskey(p, :μ) ? sistema_Ndept_io! : sistema_Ndept!

"""Tipo numérico comum aos campos numéricos de `p` (Dual quando se diferencia
em ordem a um parâmetro)."""
_tipo_parâmetros(p) = mapreduce(v -> v isa Number ? typeof(v) :
                                     v isa AbstractArray{<:Number} ? eltype(v) : Bool,
                                promote_type, values(p); init = Bool)

"""Lado direito da EDO como função não-mutante `X ↦ f(X)` (para ForwardDiff,
em ordem ao estado ou a parâmetros de `p`)."""
function _rhs(p, t = 0.0)
    sistema! = _sistema_de(p)
    T = _tipo_parâmetros(p)
    return X -> (dX = similar(X, promote_type(eltype(X), T)); sistema!(dX, X, p, t); dX)
end

"""
    jacobiana_sistema(p, X; t=0.0)

Jacobiana exata `∂f/∂X` (2N × 2N) do lado direito da EDO no estado
`X = [C; V]`, por diferenciação automática. Usa `sistema_Ndept_io!` se `p`
for acoplado (tem campo `μ`), `sistema_Ndept!` caso contrário — incluindo,
com `racionamento=true`, a derivada do ponto fixo de racionamento pelo
teorema da função implícita.
"""
jacobiana_sistema(p, X; t = 0.0) = ForwardDiff.jacobian(_rhs(p, t), X)

"""
    jacobiana_parametro(p, X, campo::Symbol; t=0.0)

Sensibilidade `∂f/∂θ` do lado direito da EDO a um campo de `p` (escalar,
como `:μ`, ou vetorial, como `:e` ou `:σ_c`). Devolve um vetor (2N) para
campos escalares e uma matriz (2N × dim θ) para campos vetoriais.
"""
function jacobiana_parametro(p, X, campo::Symbol; t = 0.0)
    θ0 = getfield(p, campo)
    sistema! = _sistema_de(p)
    function f(θ)
        q = merge(p, NamedTuple{(campo,)}((θ,)))
        dX = similar(X, promote_type(eltype(X), eltype(θ)))
        sistema!(dX, X, q, t)
        return dX
    end
    θ0 isa Number && return ForwardDiff.derivative(f, θ0)
    return ForwardDiff.jacobian(f, θ0)
end

"""
    hessiana_sistema(p, X; t=0.0)

Hessianas de todas as componentes do lado direito da EDO: array
`H[k, i, j] = ∂²f_k/∂X_i∂X_j` (2N × 2N × 2N), obtido como jacobiana da
jacobiana (ForwardDiff aninhado). Não suportado com `racionamento=true` (a
derivada do ponto fixo é só de primeira ordem).
"""
function hessiana_sistema(p, X; t = 0.0)
    n = length(X)
    JJ = ForwardDiff.jacobian(x -> vec(ForwardDiff.jacobian(_rhs(p, t), x)), X)
    # Linha de JJ = índice linear de (k, i) em vec (column-major), coluna = j.
    return reshape(JJ, n, n, n)
end

# ----------------------------------------------------------------------------
# Mapa de racionamento: jacobiana, espetro e amortecimento
# ----------------------------------------------------------------------------

"""
    raio_espectral_amortecido(λs, α)

Raio espectral do passo amortecido `ρ ↦ (1−α)ρ + αF(ρ)` dados os valores
próprios `λs` de `∂F/∂ρ`: `maxₖ |1 − α(1 − λₖ)|`.
"""
raio_espectral_amortecido(λs, α) = maximum(abs.(1 .- α .* (1 .- λs)))

"""
    intervalo_relaxação(λs)

Maior `α_max` tal que o passo amortecido é localmente estável (raio
espectral < 1) para todo `α ∈ (0, α_max)`: `|1 − αzₖ| < 1 ⇔ α < 2Re(zₖ)/|zₖ|²`
com `zₖ = 1 − λₖ`. Devolve 0 se algum `Re(λₖ) ≥ 1` (nenhum amortecimento
estabiliza).
"""
function intervalo_relaxação(λs)
    z = 1 .- λs
    any(real.(z) .<= 0) && return 0.0
    return minimum(2 .* real.(z) ./ abs2.(z))
end

"""
    relaxação_ótima(λs; α_max=intervalo_relaxação(λs))

`α` que minimiza o raio espectral do passo amortecido. `α ↦ |1 − αz|` é
convexa, logo o máximo também — pesquisa ternária em `(0, α_max)`. Para um
único valor próprio real `λ`, coincide com `α★ = 1/(1−λ)` (`paper/main.tex`,
Secção 3.3).
"""
function relaxação_ótima(λs; α_max = intervalo_relaxação(λs))
    α_max <= 0 && return NaN
    a, b = 0.0, α_max
    for _ in 1:200
        m1 = a + (b - a) / 3
        m2 = b - (b - a) / 3
        raio_espectral_amortecido(λs, m1) < raio_espectral_amortecido(λs, m2) ? (b = m2) : (a = m1)
    end
    return (a + b) / 2
end

"""
    jacobiana_racionamento(A, σ_c, S, O; relaxação=RELAXAÇÃO_PADRÃO, tol=1e-12)

Jacobiana exata `J = ∂F/∂ρ` do mapa de racionamento
(`_mapa_racionamento`, Equação `eq:rationing` de `paper/main.tex`) no ponto
fixo `ρ*`, calculado por `_resolver_racionamento`. Generaliza a derivação à
mão da Secção 3.3 (exemplo de 2 setores) a qualquer N, e devolve:

- `ρ`, `J`, `valores_próprios` (`λₖ` de J);
- `antítona`: todos os elementos de J ≤ 0 (verificação local da
  antitonicidade provada no artigo);
- `interior`: nenhum `ρᵢ*` fixado na fronteira `ρᵢ = 1`;
- `raio_espectral`: o do passo amortecido com a `relaxação` usada;
- `α_max`: limite superior de `α` para convergência local (todas as
  `|1 − α(1−λₖ)| < 1`);
- `α_ótimo`: `α` que minimiza o raio espectral do passo amortecido;
- `convergência_local`: `raio_espectral < 1` (a `relaxação` usada está em
  `(0, α_max)`).

Em empates no mínimo que define `κⱼ` o mapa não é diferenciável; a
diferenciação automática devolve a derivada do ramo selecionado por
`minimum` (o primeiro fornecedor que atinge o mínimo).
"""
function jacobiana_racionamento(A, σ_c, S, O; relaxação = RELAXAÇÃO_PADRÃO, tol = 1e-12,
                                max_iter = 10_000)
    D = σ_c .* S
    diag = _resolver_racionamento(A, ones(length(S)), D, O; relaxação = relaxação, tol = tol,
                                  max_iter = max_iter, devolver_diagnóstico = true)
    ρ = diag.ρ
    J = ForwardDiff.jacobian(r -> _mapa_racionamento(r, A, D, O), ρ)
    λs = eigvals(J)
    α_max = intervalo_relaxação(λs)
    raio = raio_espectral_amortecido(λs, relaxação)
    return (ρ = ρ, J = J, valores_próprios = λs, convergiu = diag.convergiu,
            iterações = diag.iterações,
            antítona = all(J .<= 1e-12), interior = all(ρ .< 1 - 1e-9),
            raio_espectral = raio, α_max = α_max,
            α_ótimo = relaxação_ótima(λs; α_max = α_max),
            convergência_local = raio < 1)
end

# ----------------------------------------------------------------------------
# Hessianas: curvatura da fronteira distributiva
# ----------------------------------------------------------------------------

"""
    curvatura_fronteira(A, l, r; numerário=1)

Salário `w(r)`, declive `w'(r)` e curvatura `w''(r)` da fronteira
salário-lucro (`curva_salario_lucro`, bem `numerário` com preço 1), por
diferenciação automática exata — em vez das diferenças finitas usadas na
elasticidade de `curva_salario_lucro`. `w'' > 0`: fronteira convexa nesse
ponto; `w'' < 0`: côncava.
"""
function curvatura_fronteira(A, l, r; numerário::Int = 1)
    w(rr) = 1 / calcular_precos_producao(A, l, 1.0, rr)[numerário]
    dw(rr) = ForwardDiff.derivative(w, rr)
    d2w = ForwardDiff.derivative(dw, r)
    return (w = w(r), dw = dw(r), d2w = d2w,
            forma = abs(d2w) < 1e-10 ? :linear : (d2w > 0 ? :convexa : :côncava))
end

"""
    hessiana_mk(f, x)

Hessiana exata de uma função escalar `f` em `x` (fino invólucro de
`ForwardDiff.hessian`, para uso com as funções do modelo — por exemplo, a
taxa de lucro TSSI em função das taxas de exploração; ver `src/tssi.jl`).
"""
hessiana_mk(f, x) = ForwardDiff.hessian(f, x)
