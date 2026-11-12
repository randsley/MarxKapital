# ============================================================================
# BALANCED GROWTH: THE NORMALIZED SYSTEM
# ----------------------------------------------------------------------------
# The right-hand side of `system_Ndept!`/`system_Ndept_io!` is homogeneous of
# degree 1 in the state X = [C; V] (`f(λX) = λf(X)`), so trajectories do not
# settle in levels: the relevant steady states are balanced-growth rays,
# `f(X★) = g★·X★`. They are the fixed points of the normalized system on the
# simplex,
#
#     y = X/ΣX,      ẏ = f(y) − (1ᵀf(y))·y,
#
# written in 2N−1 free coordinates (the last one is 1 − Σ of the others), so
# that the simplex constraint is not a degenerate direction of the Jacobian.
#
# Without market prices, a sector's profit rate does not depend on its
# relative size and the equilibrium conditions are overdetermined: there is
# no interior balanced growth (capital concentrates in one sector), even with
# `μ_v`, `realization` or `rationing`. With the cross-dual dynamics
# (`src/cross_dual.jl`) there is, and that is the case studied in `accumulation_bifurcation`.
# ============================================================================

_is_cross_dual(p) = haskey(p, :β)

"""
Full state from the free coordinates `z`: quantities
`y = [z₁…z₂ₙ₋₁; 1 − Σ]` on the simplex and, in the cross-dual system,
mean-zero log prices `q = [z…; −Σ]` (only relative prices matter).
"""
function _from_free(z, p)
    N = length(p.e)
    nq = 2N
    y = [z[1:nq-1]; 1 - sum(z[1:nq-1])]
    if _is_cross_dual(p)
        qf = z[nq:nq+N-2]
        y = [y; qf; -sum(qf)]
        _tssi_on(p) && (y = [y; z[nq+N-1:end]])     # book value B, relative to Σ(C+V)
        return y
    end
    _tssi_on(p) && (y = [y; z[nq:end]])             # TSSI prices P, and B relative to Σ(C+V)
    return y
end

"""Free coordinates of a full state `X` (normalizes quantities and prices)."""
function _to_free(X, p)
    N = length(p.e)
    nq = 2N
    total = sum(X[1:nq])
    y = X[1:nq] ./ total
    B = _tssi_on(p) ? X[end-N+1:end] ./ total : X[1:0]
    if _is_cross_dual(p)
        q = X[nq+1:nq+N] .- mean(X[nq+1:nq+N])
        return [y[1:end-1]; q[1:end-1]; B]
    end
    _tssi_on(p) && return [y[1:end-1]; X[nq+1:nq+N]; B]
    return y[1:end-1]
end

"""Projection of the right-hand side onto the normalized full state
(quantities on the simplex, mean-zero log prices)."""
function _project(fX, X, p)
    N = length(p.e)
    nq = 2N
    growth = sum(fX[1:nq])
    hy = fX[1:nq] .- growth .* X[1:nq]
    # the book value is degree 1, normalized by the same total as C and V
    hB = _tssi_on(p) ? fX[end-N+1:end] .- growth .* X[end-N+1:end] : fX[1:0]
    if _is_cross_dual(p)
        return [hy; fX[nq+1:nq+N] .- mean(fX[nq+1:nq+N]); hB]
    end
    _tssi_on(p) && return [hy; fX[nq+1:nq+N]; hB]    # TSSI prices are degree 0
    return hy
end

"""Errors if `p` has a reinvestment schedule (`σ_schedule`): balanced growth needs an autonomous system."""
_require_autonomous(p) = haskey(p, :σ_times) &&
    throw(ArgumentError("balanced growth needs an autonomous system: drop σ_schedule (η is fine)"))

"""
    normalized_system(p; t=0.0)

Right-hand side of the normalized system in free coordinates, `z ↦ h(z)`:
`ẏ = f(y) − (1ᵀf(y))·y` for the quantities (2N−1 free coordinates) and, in
the cross-dual system (`p` with `β`), `q̇ − mean(q̇)` for the log prices
(N−1). Its zeros are the balanced-growth rays of `f` (with constant relative
prices, in the cross-dual system).
"""
function normalized_system(p; t = 0.0)
    _require_autonomous(p)
    f = _rhs(p, t)
    nq = 2 * length(p.e)
    return function (z)
        X = _from_free(z, p)
        h = _project(f(X), X, p)
        N = nq ÷ 2
        if _is_cross_dual(p)
            return [h[1:nq-1]; h[nq+1:nq+N-1]; h[nq+N+1:end]]
        end
        return [h[1:nq-1]; h[nq+1:end]]
    end
end

"""Normalized right-hand side on the full state, for integration."""
function _rhs_normalized!(dX, X, p, t)
    fX = similar(X)
    _system_of(p)(fX, X, p, t)
    dX .= _project(fX, X, p)
end

"""
    simulate_normalized(p, X0; T=500.0)

Integrates the normalized system from `X0` (normalized internally: quantities
on the simplex, mean-zero log prices), without the exponential growth of the
levels, which overflows over long horizons.
"""
function simulate_normalized(p, X0; T = 500.0, saveat = 1.0)
    _require_autonomous(p)
    prob = ODEProblem(_rhs_normalized!, _from_free(_to_free(X0, p), p), (0.0, T), p)
    return solve(prob, Tsit5(), saveat = saveat, abstol = 1e-10, reltol = 1e-8)
end

"""
    growth_indicators(p, X)

Indicators at a state `X` (normalized or not): growth rate `g`
(`1ᵀf/1ᵀ(C+V)`, the common balanced-growth rate at a fixed point), profit
rates `r` (at Sraffian production prices in the coupled system; at market
prices in the cross-dual one), organic compositions `k = C/V`, shares
`share_C`, `share_V`, aggregate wage share `ω = ΣV/(ΣV+ΣS)`, aggregate
profit rate `r_aggregate = ΣS/Σ(C+V)` and `r_dispersion`. In the cross-dual
system, also the market prices `P` and the relative excess demand.
"""
function growth_indicators(p, X)
    N = length(p.e)
    C, V = X[1:N], X[N+1:2N]
    S = p.e .* V
    fX = _rhs(p)(X)
    g = sum(fX[1:2N]) / sum(X[1:2N])
    base = (g = g, k = C ./ V, share_C = C ./ sum(C), share_V = V ./ sum(V),
            ω = sum(V) / (sum(V) + sum(S)), r_aggregate = sum(S) / sum(C .+ V))
    if _is_cross_dual(p)
        ec = cross_dual_state(C, V, X[2N+1:3N], p; B = _tssi_on(p) ? _book(X, p) : nothing)
        return merge(base, (r = ec.r, r_dispersion = std(ec.r), P = ec.P, excess = ec.excess))
    end
    r = _tssi_on(p) ? first(_book_rates(S, V, X, p)) :
        haskey(p, :μ) ? _io_profit_rates(C, V, S, p) : S ./ (C .+ V)
    return merge(base, (r = r, r_dispersion = std(r)))
end

"""
    balanced_growth(p, X0; T_warmup=400.0, tol=1e-12, max_iter=50)

Balanced-growth ray `X★` (`f(X★) = g★X★`) starting from `X0`: integrates the
normalized system for `T_warmup` and refines by Newton in the free
coordinates, with the exact Jacobian (ForwardDiff). Returns the
`growth_indicators` at the fixed point, plus `X` (normalized full state),
`z` (free coordinates), `J` (Jacobian of `normalized_system`),
`eigenvalues`, `stable` (all real parts < 0), `residual` and `converged`.

The eigenvalues of `J` are those of perturbations of the proportions; the
radial (scale) mode is removed by the normalization, so `stable` means that
the ray attracts nearby trajectories in proportions.
"""
function balanced_growth(p, X0; T_warmup = 400.0, tol = 1e-12, max_iter = 50)
    X = T_warmup > 0 ?
        simulate_normalized(p, X0; T = T_warmup, saveat = T_warmup).u[end] : X0
    z = _to_free(X, p)
    h = normalized_system(p)
    nq = 2 * length(p.e)
    converged = false
    for _ in 1:max_iter
        hz = h(z)
        maximum(abs.(hz)) < tol && (converged = true; break)
        F = lu(ForwardDiff.jacobian(h, z); check = false)
        issuccess(F) || break   # singular Jacobian: return converged = false instead of failing
        Δ = F \ hz
        # damped step: strictly positive quantities
        α = 1.0
        while α > 1e-8 && any(_from_free(z .- α .* Δ, p)[1:nq] .<= 0)
            α /= 2
        end
        z = z .- α .* Δ
    end
    J = ForwardDiff.jacobian(h, z)
    λs = eigvals(J)
    X = _from_free(z, p)
    return merge(growth_indicators(p, X),
                 (X = X, z = z, J = J, eigenvalues = λs,
                  stable = maximum(real.(λs)) < 0, residual = maximum(abs.(h(z))),
                  converged = converged))
end

"""
    with_parameter(p, parameter, θ; e_ref=p.e)

`p` with the bifurcation parameter set to `θ`:

- `:μ`, `:μ_v`: mobility coefficients of constant / variable capital;
- `:exit_friction`: the exit friction `ε` of the mobility terms;
- `:η`: the elasticity of the reinvestment share to relative profitability
  (`_reinvestment_share`, or `_linear_reinvestment` with
  `reinvestment_form = :linear`, the form the cross-dual system needs);
- `:exit_rate`, `:exit_hurdle`: the exit of unprofitable capital
  (`_exit_flow`); `:exit_hurdle` only matters once `exit_rate` is set;
- `:investment_floor`: the floor `θ` on gross reinvestment, `θ·δ·C`
  (`_investment_floor`);
- `:tssi_τ`: the lag of the TSSI prices (TSSI-driven dynamics,
  `src/tssi.jl`);
- `:ω`: uniform wage share, `eᵢ = (1−θ)/θ` in every sector;
- `:e_scale`: proportional exploitation, `eᵢ = θ·e_ref,ᵢ` (keeps the
  heterogeneity across sectors; the resulting aggregate wage share is
  reported by `growth_indicators`).
"""
function with_parameter(p, parameter::Symbol, θ; e_ref = p.e)
    parameter === :μ && return merge(p, (μ = θ,))
    parameter === :μ_v && return merge(p, (μ_v = θ,))
    parameter === :exit_friction && return merge(p, (exit_friction = θ,))
    parameter === :η && return merge(p, (η = θ,))
    parameter === :exit_rate && return merge(p, (exit_rate = θ, exit_hurdle = get(p, :exit_hurdle, 0.0)))
    parameter === :exit_hurdle && return merge(p, (exit_hurdle = θ,))
    parameter === :investment_floor && return merge(p, (investment_floor = θ,))
    parameter === :tssi_τ && return merge(p, (tssi_τ = θ,))
    parameter === :ω && return merge(p, (e = fill((1 - θ) / θ, length(p.e)),))
    parameter === :e_scale && return merge(p, (e = θ .* e_ref,))
    error("unknown parameter: $parameter (use :μ, :μ_v, :exit_friction, :η, :exit_rate, :exit_hurdle, :investment_floor, :tssi_τ, :ω or :e_scale)")
end

"""
    wage_sweep(p, X0; variant=:uniform, values=nothing)

Balanced growth as a function of distribution, by natural continuation (each
point starts from the previous one, Newton with the exact Jacobian):

- `variant = :uniform`: uniform wage share `ω` (`with_parameter` `:ω`,
  `eᵢ = (1−ω)/ω`), `values` defaulting to `0.15:0.01:0.70`;
- `variant = :proportional`: scaled exploitation `eᵢ = θ·eᵢ⁰`
  (`:e_scale`, keeps the sectoral heterogeneity), `values` defaulting to
  `0.2:0.05:3.0`.

Returns, per point: `θ`, the effective wage share `ω`, the growth rate `g`,
the aggregate profit rate `r`, the aggregate organic composition
`k = ΣC/ΣV`, `r_dispersion`, `max_real_part` and `oscillatory` (the dominant
eigenvalue is complex: equilibrium is approached in damped cycles),
`stable`, `min_share` and `converged`.
"""
function wage_sweep(p, X0; variant = :uniform, values = nothing)
    parameter = variant === :uniform ? :ω : variant === :proportional ? :e_scale :
                error("unknown variant: $variant (use :uniform or :proportional)")
    θs = collect(something(values, variant === :uniform ? (0.15:0.01:0.70) : (0.2:0.05:3.0)))
    nq = 2 * length(p.e)
    X = X0
    records = map(enumerate(θs)) do (k, θ)
        pθ = with_parameter(p, parameter, θ)
        eq = balanced_growth(pθ, X; T_warmup = k == 1 ? 400.0 : 0.0)
        eq.converged || (eq = balanced_growth(pθ, X0))   # restart with warm-up
        eq.converged && (X = eq.X)
        dominant = eq.eigenvalues[argmax(real.(eq.eigenvalues))]
        (θ = θ, ω = eq.ω, g = eq.g, r = eq.r_aggregate, k = sum(eq.X[1:nq÷2]) / sum(eq.X[nq÷2+1:nq]),
         r_dispersion = eq.r_dispersion, max_real_part = real(dominant),
         oscillatory = abs(imag(dominant)) > 1e-8, stable = eq.stable,
         min_share = minimum(eq.X[1:nq]), converged = eq.converged)
    end
    return (variant = variant, (c => getproperty.(records, c) for c in keys(records[1]))...)
end
