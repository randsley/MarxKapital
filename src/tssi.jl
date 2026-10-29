# ============================================================================
# TSSI: TEMPORAL SINGLE-SYSTEM INTERPRETATION (valuation layer)
# ----------------------------------------------------------------------------
# Temporal values and production prices (Kliman & McGlone 1999; Freeman &
# Carchedi 1996) along a simulated trajectory, with a fixed production lag τ:
# inputs used at t were bought at t − τ, and enter cost at the prices of THAT
# date, not at current prices. Compared with simultaneist valuation (inputs
# at current prices, Sraffa).
#
# Valuation layer only: the dynamics (`system_Ndept!`, `system_Ndept_io!`)
# do not change. Quantities come from the model state, in base-period value
# units (base price 1 per unit of gross output), and TSSI prices are indices
# relative to that base.
# ============================================================================

"""
    tssi_data(X, p; surplus_value_scale=1.0)

Data per unit of gross output at a model state `X = [C; V]`: gross output `x`
(rebuilt as in `system_Ndept_io!`, `xⱼ = Wⱼ/(1 − Σᵢ A[i,j])`), depreciation
`d = δC/x`, wages `v = V/x` and total surplus value `ΣS` (multiplied by
`surplus_value_scale`, the parameter used in `tssi_bifurcation`). Requires
`Σᵢ A[i,j] < 1` for every j.
"""
function tssi_data(X, p; surplus_value_scale = 1.0)
    N = length(p.e)
    C = X[1:N]
    V = X[N+1:2N]
    S = surplus_value_scale .* p.e .* V
    colsum = vec(sum(p.A, dims = 1))
    maximum(colsum) < 1 ||
        error("Σᵢ A[i,j] ≥ 1 for some j: gross output cannot be rebuilt " *
              "(see `_ensure_output_admissibility`).")
    x = (p.δ .* C .+ V .+ S) ./ (1 .- colsum)
    return (A = p.A, x = x, d = p.δ .* C ./ x, v = V ./ x, s = S ./ x, S_total = sum(S))
end

"""
    tssi_map(p_past, data)

One step of TSSI valuation: given the prices `p_past = p(t − τ)` at which
inputs were bought, returns `(p, r, λ)` at t:

    cⱼ  = (Aᵀ·p_past)ⱼ + dⱼ + vⱼ          (historical cost price)
    r   = ΣS / Σⱼ xⱼcⱼ                         (TSSI profit rate)
    pⱼ  = (1 + r)·cⱼ                            (temporal production price)
    λⱼ  = (Aᵀ·p_past)ⱼ + dⱼ + vⱼ + sⱼ        (unit value, in money)

By construction, total price = total value (`Σpx = Σλx`) and total profit =
total surplus value, the two TSSI invariants. Generic in the number type
(ForwardDiff computes `∂p/∂p_past` in `tssi_stability`).
"""
function tssi_map(p_past, data)
    transferred = data.A' * p_past
    c = transferred .+ data.d .+ data.v
    r = data.S_total / sum(data.x .* c)
    return (p = (1 + r) .* c, r = r, λ = transferred .+ data.d .+ data.v .+ data.s)
end

"""
    simultaneous_prices(data; tol=1e-12)

Simultaneist valuation with the same data: the prices and uniform rate that
solve `p = (1+r)(Aᵀp + d + v)` with `r = ΣS / Σx(Aᵀp + d + v)`, with inputs at
current prices. It is the fixed point of the TSSI map with frozen data. For a
given `r`, `p(r) = (1+r)[I − (1+r)Aᵀ]⁻¹(d + v)`; the condition on `r`,
`g(r) = r·Σx·p(r)/(1+r) − ΣS`, is strictly increasing on `[0, R_max)` with
`g(0) < 0` and `g → ∞` at `R_max = 1/ρ(A) − 1`, so it has a unique root,
found by bisection. Returns `(p, r)`.
"""
function simultaneous_prices(data; tol = 1e-12)
    N = length(data.x)
    Id = identity_matrix(N)
    b = data.d .+ data.v
    ρ_A = maximum(abs.(eigvals(data.A)))
    p_of(r) = (1 + r) .* ((Id .- (1 + r) .* data.A') \ b)
    g(r) = r * sum(data.x .* p_of(r)) / (1 + r) - data.S_total
    if ρ_A > 0
        lo, hi = 0.0, (1 / ρ_A - 1) * (1 - 1e-12)
    else
        # Nilpotent A (ρ(A) = 0, e.g. no cycles): R_max = ∞, so expand until g > 0.
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
    return (p = p_of(r), r = r)
end

"""
    _capital_goods_price(prices, A)

Price of the capital goods each sector buys: the price index of column `j`
of `A` (capital goods are bought in the composition of the sector's inputs,
as in the cross-dual model), or the mean price for a column with no inputs.
"""
function _capital_goods_price(prices, A)
    colsum = vec(sum(A, dims = 1))
    return [colsum[j] > 0 ? sum(A[:, j] .* prices) / colsum[j] : sum(prices) / length(prices)
            for j in axes(A, 2)]
end

"""
    _book_value_step(K, C_old, C_new, δ, h, π)

One step of the book value of fixed capital at historical cost. Gross
purchases over the step are `G = C_new − (1 − δh)·C_old` (in base-value
units) and are bought at the price `π`; depreciation removes `δh` of the
book value. If `G < 0` (net disposal), the capital that leaves is valued at
the current average acquisition price `K/C_old`, which then does not change.
With `π` equal to that average price, the average stays exactly where it is.
"""
function _book_value_step(K, C_old, C_new, δ, h, π)
    G = C_new .- (1 .- δ .* h) .* C_old
    return [G[j] >= 0 ? (1 - δ[j] * h) * K[j] + π[j] * G[j] : K[j] / C_old[j] * C_new[j]
            for j in eachindex(K)]
end

"""
    tssi_valuation(sol, p; τ=1.0, h=0.5, p_initial=:simultaneous, depreciation=:base)

TSSI valuation along a trajectory `sol` (from `simulate_Ndept`/
`simulate_Ndept_custom`; `p` with fields `e, δ, A`), with a fixed production
lag `τ`, on a grid of step `h` (`τ` must be a multiple of `h`). Delayed
recursion, `p(t) = tssi_map(p(t − τ), data(t))`: a continuous-time delay
difference equation, discretized at `h`. Before `t₀ + τ` the inputs were
bought at `p_initial`: `:simultaneous` (simultaneist prices at t₀, the
default), `:base` (base price 1) or a vector.

`depreciation` sets how fixed capital used up, `dⱼ`, is valued:

- `:base` (default): at base prices, `d = δC/x`, as before.
- `:historical`: at historical acquisition cost, the TSSI treatment of
  fixed capital. Each sector's book value `K` starts at `C` valued at the
  initial capital-goods prices and is updated on the grid by
  `_book_value_step`, with purchases made at the previous step's TSSI prices
  (`_capital_goods_price`); then `d = δK/x`. Fixed capital bought when prices
  were lower keeps being depreciated at those prices. The returned
  `book_value` is `K` (N × K grid points); with `:base` it is `C`.

Returns `t`, the TSSI prices `p` and unit values `λ` (N × K), the profit rates
`r_tssi` and `r_simultaneous` (inputs at current prices, `simultaneous_prices`),
the simultaneist prices `p_simultaneous`, and `invariance_error` (largest
relative error of total price = total value and total profit = total surplus
value; zero up to rounding, by construction).

With constant data, the recursion converges to the simultaneist prices iff the
spectral radius of `∂tssi_map/∂p` at the fixed point is < 1; see
`tssi_stability`. With accumulation the two valuations diverge: TSSI values
the advanced capital at the prices it was actually bought at.
"""
function tssi_valuation(sol, p; τ = 1.0, h = 0.5, p_initial = :simultaneous,
                        depreciation::Symbol = :base)
    m = round(Int, τ / h)
    (m >= 1 && isapprox(m * h, τ; rtol = 1e-9)) ||
        error("τ=$τ must be a positive multiple of h=$h")
    depreciation in (:base, :historical) ||
        error("depreciation must be :base or :historical, got :$depreciation")
    N = length(p.e)
    ts = collect(sol.t[1]:h:sol.t[end])
    K = length(ts)
    states = [sol(t) for t in ts]
    data = [tssi_data(X, p) for X in states]
    data_simultaneous = copy(data)   # simultaneism values inputs at current, not historical, cost

    p0 = p_initial === :simultaneous ? simultaneous_prices(data[1]).p :
         p_initial === :base ? ones(N) : collect(Float64, p_initial)

    P = zeros(N, K); Λ = zeros(N, K); P_sim = zeros(N, K); book = zeros(N, K)
    r_tssi = zeros(K); r_sim = zeros(K); error_ = 0.0
    for k in 1:K
        C = states[k][1:N]
        if depreciation === :historical
            book[:, k] = k == 1 ? C .* _capital_goods_price(p0, p.A) :
                _book_value_step(book[:, k - 1], states[k - 1][1:N], C, p.δ, h,
                                 _capital_goods_price(P[:, k - 1], p.A))
            data[k] = merge(data[k], (d = p.δ .* book[:, k] ./ data[k].x,))
        else
            book[:, k] = C
        end
        p_past = k > m ? P[:, k - m] : p0
        step = tssi_map(p_past, data[k])
        P[:, k] = step.p; Λ[:, k] = step.λ; r_tssi[k] = step.r
        sim = simultaneous_prices(data_simultaneous[k])
        P_sim[:, k] = sim.p; r_sim[k] = sim.r

        x = data[k].x
        cost = sum(x .* ((data[k].A' * p_past) .+ data[k].d .+ data[k].v))
        total_price, total_value = sum(x .* step.p), sum(x .* step.λ)
        error_ = max(error_, abs(total_price - total_value) / total_value,
                   abs((total_price - cost) - data[k].S_total) / data[k].S_total)
    end
    return (t = ts, τ = τ, p = P, λ = Λ, r_tssi = r_tssi, r_simultaneous = r_sim,
            p_simultaneous = P_sim, invariance_error = error_, book_value = book)
end

"""
    tssi_stability(data; τ=1.0)

Local stability of TSSI prices with frozen data: the exact (ForwardDiff)
Jacobian `J = ∂p(t)/∂p(t−τ)` of `tssi_map` at the simultaneist fixed point
`p★`, its multipliers `μₖ` and the spectral radius. Because the lag is single
and fixed, stability does not depend on `τ`; `τ` only sets the time scale,
and the continuous convergence rate is `log(radius)/τ` (negative =
converges). In closed form, `J = [(1+r)I − r·c·xᵀ/(xᵀc)]·Aᵀ` with
`c = Aᵀp★ + d + v`.
"""
function tssi_stability(data; τ = 1.0)
    sim = simultaneous_prices(data)
    J = ForwardDiff.jacobian(q -> tssi_map(q, data).p, sim.p)
    μs = eigvals(J)
    radius = maximum(abs.(μs))
    return (p★ = sim.p, r★ = sim.r, J = J, multipliers = μs,
            spectral_radius = radius, convergence_rate = log(radius) / τ, stable = radius < 1)
end

"""
    compare_tssi_simultaneous(sol, p; τ=1.0, h=0.5, show_plot=true)

Summary and plot of the TSSI profit rate against the simultaneist one along
the trajectory (see `tssi_valuation`).
"""
function compare_tssi_simultaneous(sol, p; τ = 1.0, h = 0.5, show_plot = true)
    v = tssi_valuation(sol, p; τ = τ, h = h)
    println("\n" * "="^70)
    println("TSSI vs. SIMULTANEISM (τ = $τ)")
    println("="^70)
    println("r TSSI          initial/final: $(round(v.r_tssi[1]*100, digits=2))% → $(round(v.r_tssi[end]*100, digits=2))%")
    println("r simultaneous  initial/final: $(round(v.r_simultaneous[1]*100, digits=2))% → $(round(v.r_simultaneous[end]*100, digits=2))%")
    println("Max. invariance error (price=value, profit=surplus value): $(v.invariance_error)")
    if show_plot
        plt = plot(v.t, 100 .* v.r_tssi, label = "TSSI (τ=$τ)", lw = 2,
                   xlabel = "Time", ylabel = "Profit rate (%)",
                   title = "Profit rate: TSSI vs. simultaneist")
        plot!(plt, v.t, 100 .* v.r_simultaneous, label = "Simultaneist", lw = 2, ls = :dash)
        display(plt)
    end
    return v
end
