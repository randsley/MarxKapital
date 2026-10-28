# ============================================================================
# AUTOMATIC DIFFERENTIATION: JACOBIANS AND HESSIANS (ForwardDiff)
# ----------------------------------------------------------------------------
# Exact Jacobians (not finite differences) of the ODE right-hand sides, of the
# rationing map and of the TSSI price maps (`src/tssi.jl`); Hessians for
# second-order terms (curvature of the wage-profit frontier, normal forms).
# The rationing fixed point is differentiated through the implicit function
# theorem (`_rationing_dual`, `src/core.jl`), not iteration by iteration.
# ============================================================================

"""Picks the ODE system from the fields of `p`: cross-dual if it has `β`
(market prices), coupled if it has `μ`, independent otherwise."""
_system_of(p) = haskey(p, :β) ? cross_dual_system! : haskey(p, :μ) ? system_Ndept_io! : system_Ndept!

"""Common numeric type of the numeric fields of `p` (Dual when
differentiating with respect to a parameter)."""
_parameter_type(p) = mapreduce(v -> v isa Number ? typeof(v) :
                                     v isa AbstractArray{<:Number} ? eltype(v) : Bool,
                                promote_type, values(p); init = Bool)

"""ODE right-hand side as a non-mutating function `X ↦ f(X)` (for
ForwardDiff, with respect to the state or to parameters in `p`)."""
function _rhs(p, t = 0.0)
    system! = _system_of(p)
    T = _parameter_type(p)
    return X -> (dX = similar(X, promote_type(eltype(X), T)); system!(dX, X, p, t); dX)
end

"""
    system_jacobian(p, X; t=0.0)

Exact Jacobian `∂f/∂X` (2N × 2N) of the ODE right-hand side at the state
`X = [C; V]`, by automatic differentiation. Uses `system_Ndept_io!` if `p` is
coupled (has a `μ` field) and `system_Ndept!` otherwise. With
`rationing=true` this includes the derivative of the rationing fixed point
through the implicit function theorem.
"""
system_jacobian(p, X; t = 0.0) = ForwardDiff.jacobian(_rhs(p, t), X)

"""
    parameter_jacobian(p, X, field::Symbol; t=0.0)

Sensitivity `∂f/∂θ` of the ODE right-hand side to a field of `p` (scalar,
such as `:μ`, or vector, such as `:e` or `:σ_c`). Returns a vector (2N) for
scalar fields and a matrix (2N × dim θ) for vector fields.
"""
function parameter_jacobian(p, X, field::Symbol; t = 0.0)
    θ0 = getfield(p, field)
    system! = _system_of(p)
    function f(θ)
        q = merge(p, NamedTuple{(field,)}((θ,)))
        dX = similar(X, promote_type(eltype(X), eltype(θ)))
        system!(dX, X, q, t)
        return dX
    end
    θ0 isa Number && return ForwardDiff.derivative(f, θ0)
    return ForwardDiff.jacobian(f, θ0)
end

"""
    system_hessian(p, X; t=0.0)

Hessians of all components of the ODE right-hand side: an array
`H[k, i, j] = ∂²f_k/∂X_i∂X_j` (2N × 2N × 2N), obtained as the Jacobian of the
Jacobian (nested ForwardDiff). Not supported with `rationing=true` (the
fixed-point derivative is first-order only).
"""
function system_hessian(p, X; t = 0.0)
    n = length(X)
    JJ = ForwardDiff.jacobian(x -> vec(ForwardDiff.jacobian(_rhs(p, t), x)), X)
    # Row of JJ = linear index of (k, i) in vec (column-major), column = j.
    return reshape(JJ, n, n, n)
end

# ----------------------------------------------------------------------------
# Rationing map: Jacobian, spectrum and damping
# ----------------------------------------------------------------------------

"""
    damped_spectral_radius(λs, α)

Spectral radius of the damped step `ρ ↦ (1−α)ρ + αF(ρ)` given the
eigenvalues `λs` of `∂F/∂ρ`: `maxₖ |1 − α(1 − λₖ)|`.
"""
damped_spectral_radius(λs, α) = maximum(abs.(1 .- α .* (1 .- λs)))

"""
    relaxation_interval(λs)

Largest `α_max` such that the damped step is locally stable (spectral
radius < 1) for every `α ∈ (0, α_max)`: `|1 − αzₖ| < 1 ⇔ α < 2Re(zₖ)/|zₖ|²`
with `zₖ = 1 − λₖ`. Returns 0 if some `Re(λₖ) ≥ 1` (no damping
stabilizes).
"""
function relaxation_interval(λs)
    z = 1 .- λs
    any(real.(z) .<= 0) && return 0.0
    return minimum(2 .* real.(z) ./ abs2.(z))
end

"""
    optimal_relaxation(λs; α_max=relaxation_interval(λs))

The `α` that minimizes the spectral radius of the damped step. `α ↦ |1 − αz|`
is convex, so their maximum is too, and a ternary search on `(0, α_max)`
finds it. For a single real eigenvalue `λ` it coincides with
`α★ = 1/(1−λ)` (`paper/main.tex`, Section 3.3).
"""
function optimal_relaxation(λs; α_max = relaxation_interval(λs))
    α_max <= 0 && return NaN
    a, b = 0.0, α_max
    for _ in 1:200
        m1 = a + (b - a) / 3
        m2 = b - (b - a) / 3
        damped_spectral_radius(λs, m1) < damped_spectral_radius(λs, m2) ? (b = m2) : (a = m1)
    end
    return (a + b) / 2
end

"""
    rationing_jacobian(A, σ_c, S, O; relaxation=DEFAULT_RELAXATION, tol=1e-12)

Exact Jacobian `J = ∂F/∂ρ` of the rationing map (`_rationing_map`, equation
`eq:rationing` in `paper/main.tex`) at the fixed point `ρ*` computed by
`_solve_rationing`. It generalizes the hand derivation of Section 3.3
(2-sector example) to any N, and returns:

- `ρ`, `J`, `eigenvalues` (the `λₖ` of J);
- `antitone`: every element of J ≤ 0 (a local check of the antitonicity
  proved in the paper);
- `interior`: no `ρᵢ*` pinned at the boundary `ρᵢ = 1`;
- `spectral_radius`: that of the damped step with the `relaxation` used;
- `α_max`: upper bound on `α` for local convergence (all
  `|1 − α(1−λₖ)| < 1`);
- `α_optimal`: the `α` that minimizes the spectral radius of the damped step;
- `local_convergence`: `spectral_radius < 1` (the `relaxation` used lies in
  `(0, α_max)`).

At ties in the minimum that defines `κⱼ` the map is not differentiable;
automatic differentiation returns the derivative of the branch selected by
`minimum` (the first supplier that attains the minimum).
"""
function rationing_jacobian(A, σ_c, S, O; relaxation = DEFAULT_RELAXATION, tol = 1e-12,
                                max_iter = 10_000)
    D = σ_c .* S
    diag = _solve_rationing(A, ones(length(S)), D, O; relaxation = relaxation, tol = tol,
                                  max_iter = max_iter, return_diagnostics = true)
    ρ = diag.ρ
    J = ForwardDiff.jacobian(r -> _rationing_map(r, A, D, O), ρ)
    λs = eigvals(J)
    α_max = relaxation_interval(λs)
    radius = damped_spectral_radius(λs, relaxation)
    return (ρ = ρ, J = J, eigenvalues = λs, converged = diag.converged,
            iterations = diag.iterations,
            antitone = all(J .<= 1e-12), interior = all(ρ .< 1 - 1e-9),
            spectral_radius = radius, α_max = α_max,
            α_optimal = optimal_relaxation(λs; α_max = α_max),
            local_convergence = radius < 1)
end

# ----------------------------------------------------------------------------
# Hessians: curvature of the wage-profit frontier
# ----------------------------------------------------------------------------

"""
    frontier_curvature(A, l, r; numeraire=1)

Wage `w(r)`, slope `w'(r)` and curvature `w''(r)` of the wage-profit frontier
(`wage_profit_curve`, good `numeraire` with price 1), by exact automatic
differentiation, instead of the finite differences used for the elasticity
in `wage_profit_curve`. `w'' > 0`: the frontier is convex at that point;
`w'' < 0`: concave.
"""
function frontier_curvature(A, l, r; numeraire::Int = 1)
    w(rr) = 1 / compute_production_prices(A, l, 1.0, rr)[numeraire]
    dw(rr) = ForwardDiff.derivative(w, rr)
    d2w = ForwardDiff.derivative(dw, r)
    return (w = w(r), dw = dw(r), d2w = d2w,
            shape = abs(d2w) < 1e-10 ? :linear : (d2w > 0 ? :convex : :concave))
end

"""
    model_hessian(f, x)

Exact Hessian of a scalar function `f` at `x` (a thin wrapper over
`ForwardDiff.hessian`, for use with the model's functions, for example the
TSSI profit rate as a function of the exploitation rates; see `src/tssi.jl`).
"""
model_hessian(f, x) = ForwardDiff.hessian(f, x)
