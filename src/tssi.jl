# ============================================================================
# TSSI: INTERPRETAÇÃO TEMPORAL DE SISTEMA ÚNICO (camada de valorização)
# ----------------------------------------------------------------------------
# Valores e preços de produção temporais (Kliman & McGlone 1999; Freeman &
# Carchedi 1996) ao longo de uma trajetória simulada, com desfasamento de
# produção τ fixo: os inputs usados em t foram comprados em t − τ, e entram
# no custo aos preços DESSA data, não aos preços correntes. Comparação com a
# valorização simultaneísta (inputs aos preços correntes, Sraffa).
#
# Camada de valorização apenas: a dinâmica (`sistema_Ndept!`,
# `sistema_Ndept_io!`) não muda. As quantidades vêm do estado do modelo, em
# unidades de valor do período-base (preço-base 1 por unidade de output
# bruto), e os preços TSSI são índices relativos a essa base.
# ============================================================================

"""
    dados_tssi(X, p; escala_mais_valia=1.0)

Dados por unidade de output bruto, num estado `X = [C; V]` do modelo:
output bruto `x` (reconstruído como em `sistema_Ndept_io!`,
`xⱼ = Wⱼ/(1 − Σᵢ A[i,j])`), depreciação `d = δC/x`, salários `v = V/x` e
mais-valia total `ΣS` (multiplicada por `escala_mais_valia`, o parâmetro
usado em `bifurcacao_tssi`). Requer `Σᵢ A[i,j] < 1` para todo j.
"""
function dados_tssi(X, p; escala_mais_valia = 1.0)
    N = length(p.e)
    C = X[1:N]
    V = X[N+1:2N]
    S = escala_mais_valia .* p.e .* V
    colsum = vec(sum(p.A, dims = 1))
    maximum(colsum) < 1 ||
        error("Σᵢ A[i,j] ≥ 1 para algum j: o output bruto não é reconstruível " *
              "(ver `_garantir_admissibilidade_output`).")
    x = (p.δ .* C .+ V .+ S) ./ (1 .- colsum)
    return (A = p.A, x = x, d = p.δ .* C ./ x, v = V ./ x, s = S ./ x, S_total = sum(S))
end

"""
    mapa_tssi(p_passado, dados)

Um passo da valorização TSSI: dados os preços `p_passado = p(t − τ)` a que os
inputs foram comprados, devolve `(p, r, λ)` em t:

    cⱼ  = (Aᵀ·p_passado)ⱼ + dⱼ + vⱼ          (preço de custo histórico)
    r   = ΣS / Σⱼ xⱼcⱼ                         (taxa de lucro TSSI)
    pⱼ  = (1 + r)·cⱼ                            (preço de produção temporal)
    λⱼ  = (Aᵀ·p_passado)ⱼ + dⱼ + vⱼ + sⱼ        (valor unitário, em moeda)

Por construção, preço total = valor total (`Σpx = Σλx`) e lucro total =
mais-valia total — os dois invariantes da TSSI. Genérico no tipo de número
(ForwardDiff calcula `∂p/∂p_passado` em `estabilidade_tssi`).
"""
function mapa_tssi(p_passado, dados)
    transferido = dados.A' * p_passado
    c = transferido .+ dados.d .+ dados.v
    r = dados.S_total / sum(dados.x .* c)
    return (p = (1 + r) .* c, r = r, λ = transferido .+ dados.d .+ dados.v .+ dados.s)
end

"""
    preços_simultâneos(dados; tol=1e-12)

Valorização simultaneísta com os mesmos dados: preços e taxa uniforme que
resolvem `p = (1+r)(Aᵀp + d + v)` com `r = ΣS / Σx(Aᵀp + d + v)` — inputs aos
preços correntes. É o ponto fixo do mapa TSSI com dados congelados. Para
`r` dado, `p(r) = (1+r)[I − (1+r)Aᵀ]⁻¹(d + v)`; a condição sobre `r`,
`g(r) = r·Σx·p(r)/(1+r) − ΣS`, é estritamente crescente em `[0, R_max)` com
`g(0) < 0` e `g → ∞` em `R_max = 1/ρ(A) − 1`, logo tem raiz única —
resolvida por bisseção. Devolve `(p, r)`.
"""
function preços_simultâneos(dados; tol = 1e-12)
    N = length(dados.x)
    Id = matriz_identidade(N)
    b = dados.d .+ dados.v
    ρ_A = maximum(abs.(eigvals(dados.A)))
    p_de(r) = (1 + r) .* ((Id .- (1 + r) .* dados.A') \ b)
    g(r) = r * sum(dados.x .* p_de(r)) / (1 + r) - dados.S_total
    if ρ_A > 0
        lo, hi = 0.0, (1 / ρ_A - 1) * (1 - 1e-12)
    else
        # A nilpotente (ρ(A) = 0, p.ex. sem ciclos): R_max = ∞ — expande até g > 0.
        lo, hi = 0.0, 1.0
        while g(hi) <= 0
            lo, hi = hi, 2hi
        end
    end
    for _ in 1:200
        mid = (lo + hi) / 2
        g(mid) > 0 ? (hi = mid) : (lo = mid)
        hi - lo < tol && break
    end
    r = (lo + hi) / 2
    return (p = p_de(r), r = r)
end

"""
    valorizar_tssi(sol, p; τ=1.0, h=0.5, p_inicial=:simultâneo)

Valorização TSSI ao longo de uma trajetória `sol` (de `simular_Ndept`/
`simular_Ndept_customizado`; `p` com campos `e, δ, A`), com desfasamento
de produção `τ` fixo, numa grelha de passo `h` (`τ` tem de ser múltiplo de
`h`). Recursão com atraso, `p(t) = mapa_tssi(p(t − τ), dados(t))`: uma
equação às diferenças com atraso em tempo contínuo, discretizada em `h`.
Antes de `t₀ + τ` os inputs foram comprados a `p_inicial`: `:simultâneo`
(preços simultaneístas em t₀, por omissão), `:base` (preço-base 1) ou um
vetor.

Devolve `t`, preços TSSI `p` e valores unitários `λ` (N × K), taxas de lucro
`r_tssi` e `r_simultâneo` (inputs aos preços correntes, `preços_simultâneos`),
preços simultaneístas `p_simultâneo`, e `erro_invariantes` (máximo erro
relativo de preço total = valor total e lucro total = mais-valia total —
zero a menos de arredondamento, por construção).

Com dados constantes, a recursão converge para os preços simultaneístas sse
o raio espectral de `∂mapa_tssi/∂p` no ponto fixo for < 1 — ver
`estabilidade_tssi`. Com acumulação, as duas valorizações divergem: a TSSI
valoriza o capital adiantado aos preços a que foi de facto comprado.
"""
function valorizar_tssi(sol, p; τ = 1.0, h = 0.5, p_inicial = :simultâneo)
    m = round(Int, τ / h)
    (m >= 1 && isapprox(m * h, τ; rtol = 1e-9)) ||
        error("τ=$τ tem de ser um múltiplo positivo de h=$h")
    N = length(p.e)
    ts = collect(sol.t[1]:h:sol.t[end])
    K = length(ts)
    dados = [dados_tssi(sol(t), p) for t in ts]

    p0 = p_inicial === :simultâneo ? preços_simultâneos(dados[1]).p :
         p_inicial === :base ? ones(N) : collect(Float64, p_inicial)

    P = zeros(N, K); Λ = zeros(N, K); P_sim = zeros(N, K)
    r_tssi = zeros(K); r_sim = zeros(K); erro = 0.0
    for k in 1:K
        p_passado = k > m ? P[:, k - m] : p0
        passo = mapa_tssi(p_passado, dados[k])
        P[:, k] = passo.p; Λ[:, k] = passo.λ; r_tssi[k] = passo.r
        sim = preços_simultâneos(dados[k])
        P_sim[:, k] = sim.p; r_sim[k] = sim.r

        x = dados[k].x
        custo = sum(x .* ((dados[k].A' * p_passado) .+ dados[k].d .+ dados[k].v))
        preço_total, valor_total = sum(x .* passo.p), sum(x .* passo.λ)
        erro = max(erro, abs(preço_total - valor_total) / valor_total,
                   abs((preço_total - custo) - dados[k].S_total) / dados[k].S_total)
    end
    return (t = ts, τ = τ, p = P, λ = Λ, r_tssi = r_tssi, r_simultâneo = r_sim,
            p_simultâneo = P_sim, erro_invariantes = erro)
end

"""
    estabilidade_tssi(dados; τ=1.0)

Estabilidade local dos preços TSSI com dados congelados: jacobiana exata
(ForwardDiff) `J = ∂p(t)/∂p(t−τ)` do `mapa_tssi` no ponto fixo simultaneísta
`p★`, os seus multiplicadores `μₖ` e o raio espectral. Como o atraso é único
e fixo, a estabilidade não depende de `τ`; `τ` só fixa a escala de tempo —
a taxa contínua de convergência é `log(raio)/τ` (negativa = converge). Em
forma fechada, `J = [(1+r)I − r·c·xᵀ/(xᵀc)]·Aᵀ` com `c = Aᵀp★ + d + v`.
"""
function estabilidade_tssi(dados; τ = 1.0)
    sim = preços_simultâneos(dados)
    J = ForwardDiff.jacobian(q -> mapa_tssi(q, dados).p, sim.p)
    μs = eigvals(J)
    raio = maximum(abs.(μs))
    return (p★ = sim.p, r★ = sim.r, J = J, multiplicadores = μs,
            raio_espectral = raio, taxa_convergência = log(raio) / τ, estável = raio < 1)
end

"""
    comparar_tssi_simultaneo(sol, p; τ=1.0, h=0.5, plotar=true)

Resumo e gráfico da taxa de lucro TSSI contra a simultaneísta ao longo da
trajetória (ver `valorizar_tssi`).
"""
function comparar_tssi_simultaneo(sol, p; τ = 1.0, h = 0.5, plotar = true)
    v = valorizar_tssi(sol, p; τ = τ, h = h)
    println("\n" * "="^70)
    println("TSSI vs. SIMULTANEÍSMO (τ = $τ)")
    println("="^70)
    println("r TSSI         inicial/final: $(round(v.r_tssi[1]*100, digits=2))% → $(round(v.r_tssi[end]*100, digits=2))%")
    println("r simultâneo   inicial/final: $(round(v.r_simultâneo[1]*100, digits=2))% → $(round(v.r_simultâneo[end]*100, digits=2))%")
    println("Erro máx. invariantes (preço=valor, lucro=mais-valia): $(v.erro_invariantes)")
    if plotar
        plt = plot(v.t, 100 .* v.r_tssi, label = "TSSI (τ=$τ)", lw = 2,
                   xlabel = "Tempo", ylabel = "Taxa de lucro (%)",
                   title = "Taxa de lucro: TSSI vs. simultaneísta")
        plot!(plt, v.t, 100 .* v.r_simultâneo, label = "Simultaneísta", lw = 2, ls = :dash)
        display(plt)
    end
    return v
end
