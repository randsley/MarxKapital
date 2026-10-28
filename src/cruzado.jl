# ============================================================================
# DINÂMICA CRUZADA (CROSS-DUAL): PREÇOS DE MERCADO E MOBILIDADE DE CAPITAL
# ----------------------------------------------------------------------------
# Extensão opcional (`preços_mercado=true`) em que os preços de mercado
# respondem ao excesso de procura setorial e o capital responde aos
# diferenciais de lucro calculados a esses preços (Flaschel & Semmler). Sem
# ela, a taxa de lucro de um setor não depende da sua dimensão relativa e o
# capital concentra-se num só setor: não há crescimento equilibrado interior
# (ver `src/crescimento.jl`). Com ela, um setor que se expande para além da
# procura vê o seu preço cair, o seu lucro descer e o capital sair.
#
# Estado: X = [C; V; q], com q = log dos preços de mercado (3N).
# ============================================================================

"""
    estado_cruzado(C, V, q, p)

Grandezas do sistema cruzado num estado `(C, V, q)`:

- `x`: output bruto (unidades de valor-base), `xⱼ = Wⱼ/(1 − Σᵢ A[i,j])`;
- `P`: preços de mercado `exp(q)` normalizados para que o lucro total iguale
  a mais-valia total (`ΣΠ = ΣS`); a `P = 1`, `Π = S`;
- `Π`: lucros a preços de mercado, `(P − AᵀP)ᵢxᵢ − Vᵢ − δᵢCᵢ`;
- `r`: taxas de lucro `Π/(C + V)`;
- `investimento`: despesa bruta de investimento por setor comprador
  (`σ_cΠ + δC + μ(r − r̄)C`);
- `procura`: procura em quantidade, intermédia `Ax` + investimento + consumo;
  bens de capital comprados na composição das colunas de A, consumo
  (salários, `σ_vΠ` e consumo capitalista `γΠ`) no cabaz `p.cesto`.

Lei de Walras: `Σ Pᵢ·procuraᵢ = Σ Pᵢ·xᵢ` identicamente.
"""
function estado_cruzado(C, V, q, p)
    N = length(C)
    S = p.e .* V
    colsum = vec(sum(p.A, dims = 1))
    W = p.δ .* C .+ V .+ S
    x = W ./ (1 .- colsum)
    P0 = exp.(q)
    P = P0 .* sum(W) ./ sum((P0 .- p.A' * P0) .* x)   # ΣΠ = ΣW − ΣV − ΣδC = ΣS
    Π = (P .- p.A' * P) .* x .- V .- p.δ .* C
    r = Π ./ (C .+ V)
    r̄ = sum(r .* C) / sum(C)
    mobilidade_C = p.μ .* (r .- r̄) .* C
    investimento = p.σ_c .* Π .+ p.δ .* C .+ mobilidade_C
    γ = 1 .- p.σ_c .- p.σ_v
    consumo = sum(V) + sum((p.σ_v .+ γ) .* Π)
    # bens de capital: composição da coluna j de A (normalizada); colunas sem
    # inputs compram no cabaz de consumo
    composição = [colsum[j] > 0 ? p.A[i, j] / colsum[j] : p.cesto[i] for i in 1:N, j in 1:N]
    procura = p.A * x .+ (composição * investimento .+ p.cesto .* consumo) ./ P
    return (x = x, P = P, Π = Π, r = r, r̄ = r̄, mobilidade_C = mobilidade_C,
            investimento = investimento, procura = procura,
            excesso = (procura .- x) ./ x)
end

"""
    sistema_cruzado!(dX, X, p, t)

Dinâmica cruzada (`preços_mercado=true`), estado `X = [C; V; q]`:

    dCᵢ/dt = σ_c,ᵢ·Πᵢ − δᵢCᵢ + μ(rᵢ − r̄)Cᵢ
    dVᵢ/dt = σ_v,ᵢ·Πᵢ + μ_v(rᵢ − r̄_V)Vᵢ
    dqᵢ/dt = β·(procuraᵢ − xᵢ)/xᵢ

com lucros e taxas de lucro a preços de mercado (`estado_cruzado`). As
equações de acumulação são as de `sistema_Ndept_io!` com `Π` no lugar de
`S`. O lado direito é homogéneo de grau 1 em `(C, V)` e invariante a somar
uma constante a `q` (só os preços relativos importam).
"""
function sistema_cruzado!(dX, X, p, t)
    N = length(p.e)
    C, V, q = X[1:N], X[N+1:2N], X[2N+1:3N]
    ec = estado_cruzado(C, V, q, p)
    dX[1:N] = p.σ_c .* ec.Π .- p.δ .* C .+ ec.mobilidade_C
    μ_v = get(p, :μ_v, 0.0)
    dX[N+1:2N] = iszero(μ_v) ? p.σ_v .* ec.Π :
                 p.σ_v .* ec.Π .+ μ_v .* (ec.r .- sum(ec.r .* V) / sum(V)) .* V
    dX[2N+1:3N] = p.β .* ec.excesso
end

"""
    cesto_inicial(A, X0, p)

Cabaz de consumo por omissão: quotas do output líquido inicial
`((I − A)x₀)⁺`, normalizadas. É uma hipótese (não há dados de procura final
por setor de origem no pipeline — `docs/LIMITACOES.md`).
"""
function cesto_inicial(A, X0, p)
    N = size(A, 1)
    C, V = X0[1:N], X0[N+1:2N]
    x = (p.δ .* C .+ V .+ p.e .* V) ./ (1 .- vec(sum(A, dims = 1)))
    líquido = max.(x .- A * x, 1e-6 * sum(x))
    return líquido ./ sum(líquido)
end
