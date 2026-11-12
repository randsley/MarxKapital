# ============================================================================
# CROSS-DUAL DYNAMICS: MARKET PRICES AND CAPITAL MOBILITY
# ----------------------------------------------------------------------------
# Optional extension (`market_prices=true`) in which market prices respond to
# sectoral excess demand and capital responds to the profit differentials
# computed at those prices (Flaschel & Semmler). Without it, a sector's profit
# rate does not depend on its relative size and capital concentrates in a
# single sector: there is no interior balanced growth (see `src/growth.jl`).
# With it, a sector that expands beyond demand sees its price fall, its profit
# drop and capital leave.
#
# State: X = [C; V; q], with q = log of market prices (3N).
# ============================================================================

"""
    cross_dual_state(C, V, q, p, t = 0.0)

Quantities of the cross-dual system at a state `(C, V, q)`:

- `x`: gross output (base-value units), `xⱼ = Wⱼ/(1 − Σᵢ A[i,j])`;
- `P`: market prices `exp(q)`, normalized so that total profit equals total
  surplus value (`ΣΠ = ΣS`); at `P = 1`, `Π = S`;
- `Π`: profits at market prices, `(P − AᵀP)ᵢxᵢ − Vᵢ − δᵢCᵢ`;
- `r`: profit rates `Π/(C + V)`;
- `investment`: gross investment spending per buying sector
  (`σ_cΠ + δC + μ(r − r̄)C`; with `p.reinvestment_form == :linear`,
  `_linear_reinvestment(σ_c·m(t), Π, C + V, η) + δC + μ(r − r̄)C`, and
  the difference between `σ_cΠ` and that planned reinvestment is spent on
  capitalist consumption, so Walras's law still holds; the same with the
  investment floor, `max(·, θδC)`, whose extra investment comes out of
  capitalist consumption);
- `reinvestment`: the planned net reinvestment in `C` (`σ_cΠ`, or the
  linear form);
- `demand`: demand in quantities, intermediate `Ax` + investment +
  consumption; capital goods are bought in the composition of A's columns,
  consumption (wages, `σ_vΠ` and capitalist consumption `γΠ`) in the basket
  `p.basket`.

Walras's law: `Σ Pᵢ·demandᵢ = Σ Pᵢ·xᵢ` identically.
"""
function cross_dual_state(C, V, q, p, t = 0.0)
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
    mobility_C = _mobility_flow(r, C, p.μ, get(p, :exit_friction, 0.0))
    γ = 1 .- p.σ_c .- p.σ_v
    floor_on = haskey(p, :investment_floor)
    if _linear_form(p) || floor_on
        reinvestment = _linear_form(p) ?
            _linear_reinvestment(_scheduled_σ(p, t), Π, C .+ V, get(p, :η, 0.0)) :
            p.σ_c .* Π
        floor_on && (reinvestment = _investment_floor(reinvestment, C, p))
        investment = reinvestment .+ p.δ .* C .+ mobility_C
        # what is not reinvested out of σ_c·m(t)·Π (positive or negative) is consumed
        consumption = sum(V) + sum((p.σ_v .+ γ) .* Π) + sum(p.σ_c .* Π) - sum(reinvestment)
    else
        reinvestment = p.σ_c .* Π
        investment = p.σ_c .* Π .+ p.δ .* C .+ mobility_C
        consumption = sum(V) + sum((p.σ_v .+ γ) .* Π)
    end
    # capital goods: composition of column j of A (normalized); columns with
    # no inputs buy in the consumption basket
    composition = [colsum[j] > 0 ? p.A[i, j] / colsum[j] : p.basket[i] for i in 1:N, j in 1:N]
    demand = p.A * x .+ (composition * investment .+ p.basket .* consumption) ./ P
    return (x = x, P = P, Π = Π, r = r, r̄ = r̄, mobility_C = mobility_C,
            reinvestment = reinvestment, investment = investment, demand = demand,
            excess = (demand .- x) ./ x)
end

"""
    cross_dual_system!(dX, X, p, t)

Cross-dual dynamics (`market_prices=true`), state `X = [C; V; q]`:

    dCᵢ/dt = σ_c,ᵢ·Πᵢ − δᵢCᵢ + μ(rᵢ − r̄)Cᵢ
    dVᵢ/dt = σ_v,ᵢ·Πᵢ + μ_v(rᵢ − r̄_V)Vᵢ
    dqᵢ/dt = β·(demandᵢ − xᵢ)/xᵢ

with profits and profit rates at market prices (`cross_dual_state`). The
accumulation equations are those of `system_Ndept_io!` with `Π` in place of
`S`, including the optional exit friction (`p.exit_friction`, `_mobility_flow`),
the linear reinvestment form (`p.reinvestment_form == :linear`, the only form
with `η` here, since `Π` can be ≤ 0), the investment floor
(`p.investment_floor`, `_investment_floor`) and the exit of unprofitable capital
(`p.exit_rate`, `_exit_flow`; scrapping is not investment demand). The right-hand side is homogeneous of degree 1 in `(C, V)` and
invariant to adding a constant to `q` (only relative prices matter).
"""
function cross_dual_system!(dX, X, p, t)
    N = length(p.e)
    C, V, q = X[1:N], X[N+1:2N], X[2N+1:3N]
    ec = cross_dual_state(C, V, q, p, t)
    if _linear_form(p) || haskey(p, :investment_floor)
        dX[1:N] = ec.reinvestment .- p.δ .* C .+ ec.mobility_C
    else
        dX[1:N] = p.σ_c .* ec.Π .- p.δ .* C .+ ec.mobility_C
    end
    haskey(p, :exit_rate) && (dX[1:N] = dX[1:N] .- _exit_flow(ec.r, C, p.exit_rate, get(p, :exit_hurdle, 0.0)))
    μ_v = get(p, :μ_v, 0.0)
    dX[N+1:2N] = iszero(μ_v) ? p.σ_v .* ec.Π :
                 p.σ_v .* ec.Π .+ _mobility_flow(ec.r, V, μ_v, get(p, :exit_friction, 0.0))
    dX[2N+1:3N] = p.β .* ec.excess
end

"""
    basket_initial(A, X0, p)

Default consumption basket: shares of initial net output `((I − A)x₀)⁺`,
normalized. This is an assumption; on a real-data calibration,
`consumption_basket(params.final_demand)` gives real household consumption
shares instead (`src/eurostat_sdmx.jl`).
"""
function basket_initial(A, X0, p)
    N = size(A, 1)
    C, V = X0[1:N], X0[N+1:2N]
    x = (p.δ .* C .+ V .+ p.e .* V) ./ (1 .- vec(sum(A, dims = 1)))
    net = max.(x .- A * x, 1e-6 * sum(x))
    return net ./ sum(net)
end
