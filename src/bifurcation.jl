# ============================================================================
# BIFURCATION ANALYSIS (BifurcationKit + ForwardDiff)
# ----------------------------------------------------------------------------
# Numerical continuation of fixed points of MAPS `z ↦ G(z, θ)` in a
# parameter θ, with stability read from the multipliers `μ` of the exact
# Jacobian `∂G/∂z` (ForwardDiff). It applies to:
#
#   - the damped rationing step, `ρ ↦ (1−α)ρ + αF(ρ; s)`, with the demand
#     scale `s` as the parameter (`rationing_bifurcation`);
#   - the TSSI price map with a fixed lag τ, `p(t−τ) ↦ p(t)`, with the
#     surplus-value intensity as the parameter (`tssi_bifurcation`).
#
# The accumulation ODEs grow without bound (exponential C, V) and have no
# equilibria in levels; their steady states are balanced-growth rays, fixed
# points of the normalized system of `src/growth.jl`. Those are continued in
# the final section (`accumulation_bifurcation`), with Hopf detection and
# continuation of periodic orbits.
#
# BifurcationKit does the continuation (pseudo-arclength, PALC) of the branch
# `G(z, θ) − z = 0`. Its bifurcation detection assumes ODEs (eigenvalues of
# ∂F/∂z crossing the imaginary axis) and does not detect flips of maps
# (μ = −1), so the classification is done here, on the multipliers of G:
# fold (μ = +1), flip / period doubling (μ = −1) and Neimark–Sacker (complex
# pair with |μ| = 1).
# ============================================================================

"""Classifies the multiplier that crosses |μ| = 1 by its argument."""
function _map_bifurcation_type(μ)
    abs(imag(μ)) > 1e-6 * max(1, abs(μ)) && return :neimark_sacker
    return real(μ) > 0 ? :fold : :flip
end

"""
    continue_fixed_point(G, z0, θ0, θ_min, θ_max; ds=0.01, dsmax=0.05, max_steps=1000,
                         stability_tol=1e-8)

Continues the branch of fixed points `z★(θ) = G(z★, θ)` from `(z0, θ0)`
(which should already be a fixed point, or close to one) over
`θ ∈ [θ_min, θ_max]`, with BifurcationKit (PALC, Jacobian `∂G/∂z − I` by
ForwardDiff). At each point of the branch it computes the multipliers of
`∂G/∂z`, and returns:

- `θ`, `z` (dim(z) × K), `radius` (spectral radius of ∂G/∂z) and
  `multipliers` along the branch;
- `points`: a vector of `(kind, θ, μ)` where the number of unstable
  multipliers (|μ| > 1 + `stability_tol`) changes, with
  `kind ∈ (:fold, :flip, :neimark_sacker)` and `θ` interpolated linearly in
  `radius − 1` between the two steps;
- `branch`: the object returned by `BK.continuation`.
"""
function continue_fixed_point(G, z0, θ0, θ_min, θ_max; ds = 0.01, dsmax = 0.05,
                              max_steps = 1000, stability_tol = 1e-8)
    F(z, par) = G(z, par.θ) .- z
    J(z, par) = ForwardDiff.jacobian(zz -> F(zz, par), z)
    prob = BK.BifurcationProblem(F, collect(float.(z0)), (θ = θ0,), (BK.@optic _.θ); J = J)
    opts = BK.ContinuationPar(p_min = θ_min, p_max = θ_max, ds = ds, dsmax = dsmax,
                              max_steps = max_steps, save_sol_every_step = 1,
                              detect_bifurcation = 0, detect_fold = false)
    branch = BK.continuation(prob, BK.PALC(), opts; verbosity = 0)

    θs = [s.p for s in branch.sol]
    Z = reduce(hcat, [s.x for s in branch.sol])
    μs = [eigvals(ForwardDiff.jacobian(z -> G(z, θ), Z[:, k])) for (k, θ) in enumerate(θs)]
    radius = [maximum(abs.(μ)) for μ in μs]
    # |μ| = 1 ± rounding (e.g. the structural λ = −1 of rationing with
    # α = 1) counts as neutral, not unstable; without the tolerance, numerical
    # noise around |μ| = 1 gives spurious detections at every step.
    n_unstable = [count(abs.(μ) .> 1 + stability_tol) for μ in μs]

    points = NamedTuple[]
    for k in 2:length(θs)
        n_unstable[k] == n_unstable[k-1] && continue
        # the multiplier responsible: the one with |μ| closest to 1 on the unstable side
        μ_side = n_unstable[k] > n_unstable[k-1] ? μs[k] : μs[k-1]
        μ★ = μ_side[argmin(abs.(abs.(μ_side) .- 1))]
        w = (1 - radius[k-1]) / (radius[k] - radius[k-1])
        θ★ = isfinite(w) && 0 <= w <= 1 ? θs[k-1] + w * (θs[k] - θs[k-1]) : θs[k]
        push!(points, (kind = _map_bifurcation_type(μ★), θ = θ★, μ = μ★))
    end
    return (θ = θs, z = Z, radius = radius, multipliers = μs, points = points, branch = branch)
end

"""
    rationing_bifurcation(A, σ_c, S, O; scale=(0.1, 3.0), relaxation=DEFAULT_RELAXATION, ds=0.01)

Bifurcations of the iterative rationing scheme when planned demand is scaled
by `s` (`D = s·σ_c·S`; small `s`: no rationing, large `s`: rationing in every
sector). Continues the fixed point `ρ★(s)` of the damped step
`ρ ↦ (1−α)ρ + αF(ρ; s)` with `α = relaxation` (the fixed point does not
depend on α, its stability does) and returns, besides the result of
`continue_fixed_point`:

- `α_max`: for each `s`, the largest `α` with local convergence
  (`relaxation_interval` of the eigenvalues of `∂F/∂ρ`), i.e. the flip
  boundary in the (s, α) plane, since the eigenvalues of F are real ≤ 0 in
  the cases tested;
- `rationed_fraction`: the fraction of sectors with `ρᵢ★ < 1`.

As soon as some sector is rationed, `λ = −1` is an eigenvalue of `∂F/∂ρ`. Let
`k` be the sector with the smallest `ρₖ★`; every buyer `j` that `k` supplies
has `κⱼ = ρₖ`, so `Dₖ = ρₖ·Lₖ` (`Lₖ = Σⱼ A[k,j]·Dⱼ`, unrationed demand),
`Fₖ = xₖ/(ρₖLₖ)` and row k of J is `−eₖᵀ`. Hence `ρₖ★ = √(xₖ/Lₖ)` in closed
form (generalizing the `√0.8` of the 2-sector example), `α_max ≤ 1`, and
`α = 1` (no damping) sits exactly on the flip boundary: it never converges
locally once rationing binds. The jump of `α_max` from 2 to ≤ 1 at the onset
of rationing is a border-collision bifurcation (the map is piecewise smooth),
not a smooth bifurcation.
"""
function rationing_bifurcation(A, σ_c, S, O; scale = (0.1, 3.0), relaxation = DEFAULT_RELAXATION,
                                 ds = 0.01, dsmax = 0.05, max_steps = 2000)
    D = σ_c .* S
    G(ρ, s) = (1 - relaxation) .* ρ .+ relaxation .* _rationing_map(ρ, A, s .* D, O)
    s0 = scale[1]
    diag = _solve_rationing(A, ones(length(S)), s0 .* D, O; tol = 1e-12,
                                  max_iter = 10_000, return_diagnostics = true)
    res = continue_fixed_point(G, diag.ρ, s0, scale[1], scale[2]; ds = ds, dsmax = dsmax,
                               max_steps = max_steps)
    α_max = [relaxation_interval(eigvals(ForwardDiff.jacobian(
                 ρ -> _rationing_map(ρ, A, s .* D, O), res.z[:, k])))
             for (k, s) in enumerate(res.θ)]
    fraction = [count(res.z[:, k] .< 1 - 1e-9) / size(res.z, 1) for k in eachindex(res.θ)]
    return merge(res, (α_max = α_max, rationed_fraction = fraction, relaxation = relaxation))
end

"""
    tssi_bifurcation(X, p; τ=1.0, scale=(0.1, 3.0), ds=0.01)

Bifurcations of the TSSI price map `p(t−τ) ↦ p(t)` (`tssi_map`), with a FIXED
lag τ and data frozen at the state `X`, as a function of the surplus-value
intensity `θ` (`S → θ·S`, see `tssi_data`). The branch `p★(θ)` is that of
the simultaneist prices; its stability decides whether TSSI prices converge
to them. Because the lag is single, the bifurcation points in θ do not
depend on τ; τ only sets the time scale (`convergence_rate =
log(radius)/τ`, also returned).
"""
function tssi_bifurcation(X, p; τ = 1.0, scale = (0.1, 3.0), ds = 0.01, dsmax = 0.05,
                         max_steps = 2000)
    G(q, θ) = tssi_map(q, tssi_data(X, p; surplus_value_scale = θ)).p
    θ0 = scale[1]
    p0 = simultaneous_prices(tssi_data(X, p; surplus_value_scale = θ0)).p
    res = continue_fixed_point(G, p0, θ0, scale[1], scale[2]; ds = ds, dsmax = dsmax,
                               max_steps = max_steps)
    r★ = [simultaneous_prices(tssi_data(X, p; surplus_value_scale = θ)).r for θ in res.θ]
    return merge(res, (τ = τ, r★ = r★, convergence_rate = log.(res.radius) ./ τ))
end

"""
    plot_bifurcation(res; title="")

Spectral radius of the multipliers along the branch (stable below 1), with
the detected bifurcation points; for `rationing_bifurcation` it adds the
flip boundary `α_max(s)` against the relaxation used.
"""
function plot_bifurcation(res; title = "")
    p1 = plot(res.θ, res.radius, lw = 2, label = "spectral radius of ∂G/∂z",
              xlabel = "parameter", ylabel = "max |μ|", title = title)
    hline!(p1, [1.0], ls = :dash, color = :black, label = "|μ| = 1")
    for pt in res.points
        vline!(p1, [pt.θ], ls = :dot, label = string(pt.kind))
    end
    haskey(res, :α_max) || return p1
    p2 = plot(res.θ, res.α_max, lw = 2, label = "α_max(s) (flip boundary)",
              xlabel = "demand scale s", ylabel = "relaxation α",
              title = "Local convergence region")
    hline!(p2, [res.relaxation], ls = :dash, label = "α used")
    return plot(p1, p2, layout = (1, 2), size = (1000, 400))
end

# ============================================================================
# ACCUMULATION: BALANCED GROWTH, HOPF AND PERIODIC ORBITS
# ----------------------------------------------------------------------------
# Continuation of the balanced-growth rays (zeros of `normalized_system`) in
# a parameter of `with_parameter`. Here the problem is an ODE, and
# BifurcationKit's detectors apply directly: Hopf (complex pair crossing the
# imaginary axis) with its normal form (first Lyapunov coefficient), and
# folds / branch points. From supercritical Hopf points the limit cycles are
# continued by orthogonal collocation, with stability from the Floquet
# multipliers and the bifurcations of cycles (fold of cycles, period
# doubling, Neimark–Sacker / torus).
# ============================================================================

"""BifurcationKit problem for the normalized system with `θ` = `parameter`."""
function _accumulation_problem(p, parameter, z0, θ0; e_ref = p.e)
    F(z, par) = normalized_system(with_parameter(p, parameter, par.θ; e_ref = e_ref))(z)
    J(z, par) = ForwardDiff.jacobian(zz -> F(zz, par), z)
    return BK.BifurcationProblem(F, collect(float.(z0)), (θ = θ0,), (BK.@optic _.θ); J = J,
                                 record_from_solution = (z, par; k...) -> (min_share = minimum(_from_free(z, p)[1:2length(p.e)]),))
end

"""Amplitude and minimum share of an orbit (dim(z) × points matrix)."""
function _orbit_measures(U, p)
    nq = 2 * length(p.e)
    Y = vcat(U[1:nq-1, :], 1 .- sum(U[1:nq-1, :], dims = 1))
    amplitude = maximum(maximum(Y, dims = 2) .- minimum(Y, dims = 2))
    return (amplitude = amplitude, min_share = minimum(Y))
end

"""
    simulated_cycle(p, parameter, θ, X0; T=4000.0, dt=0.02, e_ref=p.e)

Check by direct simulation of the normalized system at `θ`: integrates from
`X0` and, over the second half of the trajectory, measures a Poincaré
section (upward crossings of the mean in the first coordinate). Returns `n`
(number of crossings), `section_dispersion` (spread of the second coordinate
at the crossings: ≈ 0 on a limit cycle, > 0 on a torus or irregular
attractor), `T_min`/`T_max` (return times; equal on a cycle, ≈ the period),
`amplitude` and `min_share` (as in `accumulation_bifurcation`). With no
crossings (`n < 2`) the trajectory has converged to the equilibrium.
"""
function simulated_cycle(p, parameter, θ, X0; T = 4000.0, dt = 0.02, e_ref = p.e)
    pθ = with_parameter(p, parameter, θ; e_ref = e_ref)
    h = normalized_system(pθ)
    prob = ODEProblem((z, _, t) -> h(z), _to_free(X0, pθ), (0.0, T))
    sol = solve(prob, Tsit5(), abstol = 1e-11, reltol = 1e-9, saveat = dt)
    U = reduce(hcat, sol.u[end÷2:end])
    measures = _orbit_measures(U, pθ)
    c = mean(U[1, :])
    idx = findall(i -> U[1, i] < c && U[1, i+1] >= c, 1:size(U, 2)-1)
    length(idx) < 2 && return merge((n = length(idx), section_dispersion = 0.0, T_min = NaN, T_max = NaN), measures)
    section = U[2, idx]
    returns = diff(idx) .* dt
    return merge((n = length(idx), section_dispersion = maximum(section) - minimum(section),
                  T_min = minimum(returns), T_max = maximum(returns)), measures)
end

"""
    accumulation_bifurcation(p, X0, parameter; interval, θ0=interval[1], ds=0.01,
                          dsmax=0.01, max_steps=1000, orbits=true,
                          orbit_interval=interval, δθ=1e-3, Ntst=40, m=4)

Bifurcations of balanced growth in the cross-dual system (`p` from
`simulate_Ndept(...; coupled=true, market_prices=true)`) in the `parameter`
of `with_parameter` (`:μ`, `:μ_v`, `:ω`, `:e_scale`), over `θ ∈ interval`:

1. Branch of equilibria: `balanced_growth` at `θ0` (from `X0`) and PALC
   continuation with the exact Jacobian (ForwardDiff). Returns `θ`, `z`,
   `max_real_part` (largest real part of the eigenvalues, < 0 = stable), `g`
   and `min_share` along the branch, and `points` (BifurcationKit's
   `(kind, θ)`: `:hopf`, `:bp`, `:fold`, ...).
2. `hopf`: the normal form of each Hopf point (`θ`, frequency `ω`,
   `period = 2π/ω`, Lyapunov coefficient `l1 = Re b`, `supercritical = l1 < 0`
   and `transversality = Re a`, the crossing speed: > 0 if the pair becomes
   unstable as θ rises).
3. `orbits` (if `orbits=true` and the first Hopf point is supercritical): the
   branch of limit cycles by collocation (`Ntst` intervals of degree `m`),
   seeded by the normal-form predictor at `θ_H + δθ` (integrated over one
   period) and continued in both directions, towards the Hopf point
   (amplitude → 0) and up to the limit of `orbit_interval`. Returns `θ`,
   `amplitude` (largest oscillation of a share), `period`, `min_share`,
   `stable` (Floquet multipliers) and `points` (bifurcations of cycles:
   `:bp` = fold of cycles, `:pd` = period doubling, `:ns` = Neimark–Sacker).

Confirm the results with `simulated_cycle` (BifurcationKit does not know
whether a cycle runs into the boundary of the simplex; see `min_share`).
"""
function accumulation_bifurcation(p, X0, parameter::Symbol; interval, θ0 = interval[1],
                               ds = 0.01, dsmax = 0.01, max_steps = 1000, orbits = true,
                               orbit_interval = interval, δθ = 1e-3, Ntst = 40, m = 4,
                               e_ref = p.e)
    _is_cross_dual(p) || error("accumulation_bifurcation requires the cross-dual system (market_prices=true)")
    eq = balanced_growth(with_parameter(p, parameter, θ0; e_ref = e_ref), X0)
    eq.converged || @warn "balanced_growth did not converge at θ0 = $θ0 (residual $(eq.residual))"
    prob = _accumulation_problem(p, parameter, eq.z, θ0; e_ref = e_ref)
    nz = length(eq.z)
    opts = BK.ContinuationPar(p_min = interval[1], p_max = interval[2], ds = ds, dsmax = dsmax,
                              max_steps = max_steps, detect_bifurcation = 3, n_inversion = 8,
                              nev = nz, save_sol_every_step = 1)
    branch = BK.continuation(prob, BK.PALC(), opts; verbosity = 0)

    θs = [s.p for s in branch.sol]
    Z = reduce(hcat, [s.x for s in branch.sol])
    pθ(θ) = with_parameter(p, parameter, θ; e_ref = e_ref)
    λs = [eigvals(ForwardDiff.jacobian(normalized_system(pθ(θ)), Z[:, k])) for (k, θ) in enumerate(θs)]
    λ_max2 = [maximum(real.(λ)) for λ in λs]
    g = [growth_indicators(pθ(θ), _from_free(Z[:, k], p)).g for (k, θ) in enumerate(θs)]
    share = [minimum(_from_free(Z[:, k], p)[1:2length(p.e)]) for k in eachindex(θs)]
    points = [(kind = sp.type, θ = sp.param) for sp in branch.specialpoint if sp.type !== :endpoint]
    # safeguard: two crossings in the same step escape detection, so compare
    # with the direct count of unstable eigenvalues along the branch
    n_inst = [count(real.(λ) .> 1e-9) for λ in λs]
    crossings = sum(abs, diff(n_inst); init = 0)
    detected = sum(pt.kind === :hopf ? 2 : 1 for pt in points; init = 0)
    crossings == detected ||
        @warn "accumulation_bifurcation: $crossings eigenvalue crossings, $detected at the detected points; reduce dsmax"

    hopf = NamedTuple[]
    shapes = []
    for (i, sp) in enumerate(branch.specialpoint)
        sp.type === :hopf || continue
        nf = BK.get_normal_form(branch, i; verbose = false)
        push!(shapes, nf)
        l1 = real(nf.nf.b)
        push!(hopf, (θ = nf.p, ω = nf.ω, period = 2π / abs(nf.ω), l1 = l1, supercritical = l1 < 0,
                     transversality = real(nf.nf.a)))
    end

    res = (parameter = parameter, θ = θs, z = Z, max_real_part = λ_max2, g = g, min_share = share,
           points = points, hopf = hopf, branch = branch, orbits = nothing)
    (orbits && !isempty(hopf)) || return res
    H = hopf[1]
    H.supercritical || (@warn "first Hopf point is subcritical (θ = $(H.θ)): unstable cycles, no seed by simulation"; return res)

    # seed: normal-form predictor at θ_H + δθ (supercritical side), integrated
    # over ~1 period and projected onto the collocation mesh; BifurcationKit's
    # automatic branch switching fails here (singular Jacobian)
    side = sign(H.transversality)
    pred = BK.predictor(shapes[1], δθ)
    θ_s = pred.p
    T_s = 2π / abs(pred.ω)
    h = normalized_system(pθ(θ_s))
    ode = ODEProblem((z, par, t) -> h(z), pred.orbit(0.0), (0.0, 1.25 * T_s), (θ = θ_s,))
    sol = solve(ode, Tsit5(), abstol = 1e-11, reltol = 1e-9)
    probθ = BK.re_make(prob; params = (θ = θ_s,))
    probPO, ci = BK.generate_ci_problem(BK.Collocation(Ntst, m), probθ, sol, T_s)

    entries = (x, par; k...) -> begin
        U = BK.get_periodic_orbit(par.prob, x, par.p).u
        merge(_orbit_measures(U, p), (period = x[end],))
    end
    outer_limit = orbit_interval[side > 0 ? 2 : 1]
    function leg(target)
        o = BK.ContinuationPar(p_min = min(θ_s, target), p_max = max(θ_s, target),
                               ds = sign(target - θ_s) * 0.005, dsmax = 0.01, max_steps = max_steps,
                               detect_bifurcation = 3, nev = nz, tol_stability = 1e-5)
        BK.continuation(probPO, ci, BK.PALC(), o; verbosity = 0, record_from_solution = entries)
    end
    to_hopf = leg(H.θ)
    outward = leg(outer_limit)
    b1, b2 = to_hopf.branch, outward.branch
    join_(field) = [reverse(getproperty(b1, field)[2:end]); getproperty(b2, field)]
    points_po = [(kind = sp.type, θ = sp.param) for br in (to_hopf, outward)
                 for sp in br.specialpoint if sp.type !== :endpoint]
    orb = (θ = join_(:param), amplitude = join_(:amplitude), period = join_(:period),
           min_share = join_(:min_share), stable = join_(:stable), points = points_po,
           branches = (to_hopf, outward))
    return merge(res, (orbits = orb,))
end

"""
    hopf_curve(p, X0; ω_values=0.2:0.05:0.65, μv_interval=(0.0, 4.0))

Hopf boundary in the (wage share ω, variable-capital mobility μ_v) plane: for
each uniform ω, continues balanced growth in `μ_v`
(`accumulation_bifurcation`, without orbits) and records the first Hopf
point: `μ_v_H` (`NaN` if there is none in `μv_interval`), its frequency, the
Lyapunov coefficient `l1` and `supercritical`. Below the curve balanced
growth is stable; above it, it oscillates.
"""
function hopf_curve(p, X0; ω_values = 0.2:0.05:0.65, μv_interval = (0.0, 4.0), dsmax = 0.01)
    records = map(ω_values) do ω
        pω = with_parameter(p, :ω, ω)
        r = accumulation_bifurcation(pω, X0, :μ_v; interval = μv_interval, orbits = false,
                                  dsmax = dsmax, ds = dsmax)
        isempty(r.hopf) && return (ω = ω, μ_v_H = NaN, frequency = NaN, l1 = NaN, supercritical = false)
        H = r.hopf[1]
        (ω = ω, μ_v_H = H.θ, frequency = abs(H.ω), l1 = H.l1, supercritical = H.supercritical)
    end
    return (; (c => getproperty.(records, c) for c in keys(records[1]))...)
end

"""
    lyapunov_exponents(p, parameter, θ, X0; k=3, T_transient=3000.0, T=30000.0,
                       Δ=1.0, tol=1e-11, z0=nothing)

The `k` largest Lyapunov exponents of the normalized system at `θ`
(Benettin's method: variational equations with the exact Jacobian,
ForwardDiff, and QR re-orthonormalization every `Δ`), after a transient
`T_transient`, from `X0` (or from the free coordinates `z0`).

Attractor classification: equilibrium `(−, −, …)`; limit cycle `(0, −, …)`;
torus `(0, 0, −, …)`; chaos `(+, 0, …)`; hyperchaos with two positive
exponents. Away from an equilibrium one exponent is always ≈ 0 (the flow
direction). These are finite-time estimates: the error is of order `1/T`
plus the slow drift along the trajectory (compare `λ` with `λ_mid`, the
estimate at half time). Numerical evidence of chaos, not proof.

Returns `λ`, `λ_mid`, `z` (final state) and `min_share` (smallest sectoral
share at the final state).
"""
function lyapunov_exponents(p, parameter, θ, X0; k = 3, T_transient = 3000.0, T = 30000.0,
                            Δ = 1.0, tol = 1e-11, z0 = nothing, e_ref = p.e)
    pθ = with_parameter(p, parameter, θ; e_ref = e_ref)
    h = normalized_system(pθ)
    z = isnothing(z0) ? _to_free(X0, pθ) .+ 1e-3 : collect(float.(z0))
    n = length(z)
    if T_transient > 0
        z = solve(ODEProblem((u, _, t) -> h(u), z, (0.0, T_transient)), Vern9(),
                  abstol = tol, reltol = tol, save_everystep = false).u[end]
    end
    function variational!(du, u, _, t)
        x = u[1:n]
        du[1:n] = h(x)
        du[n+1:end] = vec(ForwardDiff.jacobian(h, x) * reshape(u[n+1:end], n, k))
    end
    Q0 = Matrix(qr(Matrix{Float64}(I, n, k)).Q)
    integ = init(ODEProblem(variational!, [z; vec(Q0)], (0.0, T)), Vern9(),
                 abstol = tol, reltol = tol, save_everystep = false)
    steps = round(Int, T / Δ)
    total_sum = zeros(k)
    λ_mid = zeros(k)
    for i in 1:steps
        step!(integ, Δ, true)
        F = qr(reshape(integ.u[n+1:end], n, k))
        d = diag(F.R)
        total_sum .+= log.(abs.(d))
        integ.u[n+1:end] = vec(Matrix(F.Q) .* sign.(d)')
        u_modified!(integ, true)
        i == steps ÷ 2 && (λ_mid .= total_sum ./ (i * Δ))
    end
    zf = integ.u[1:n]
    return (λ = total_sum ./ (steps * Δ), λ_mid = λ_mid, z = zf,
            min_share = minimum(_from_free(zf, p)[1:2length(p.e)]))
end

"""
    simulated_hysteresis(p, parameter, grid_pts, X0; T_transient=3000.0, T=3000.0, dt=0.02)

Parameter sweep by simulation, up and then down over `grid_pts`, each point
starting from the final state of the previous one: detects coexisting
attractors (hysteresis). At each point it classifies the attractor by the
Poincaré section (as `simulated_cycle` does): `:equilibrium`, `:cycle` or
`:irregular` (torus or chaos). Returns `θ` and, for `up` and `down`, vectors
with `class`, `amplitude` and `mean_return`; and `coexistence`, the `θ`
where the two directions give different attractors.
"""
function simulated_hysteresis(p, parameter, grid_pts, X0; T_transient = 3000.0, T = 3000.0,
                            dt = 0.02, e_ref = p.e)
    nq = 2 * length(p.e)
    function measure(θ, z)
        h = normalized_system(with_parameter(p, parameter, θ; e_ref = e_ref))
        z1 = solve(ODEProblem((u, _, t) -> h(u), z, (0.0, T_transient)), Vern9(),
                   abstol = 1e-12, reltol = 1e-12, save_everystep = false).u[end]
        s = solve(ODEProblem((u, _, t) -> h(u), z1, (0.0, T)), Vern9(),
                  abstol = 1e-12, reltol = 1e-12, saveat = dt)
        U = reduce(hcat, s.u)
        m = _orbit_measures(U, p)
        c = mean(U[1, :])
        idx = findall(i -> U[1, i] < c && U[1, i+1] >= c, 1:size(U, 2)-1)
        spread = length(idx) < 2 ? 0.0 : maximum(U[2, idx]) - minimum(U[2, idx])
        class = m.amplitude < 1e-4 ? :equilibrium : spread < 0.01 * m.amplitude ? :cycle : :irregular
        return_ = length(idx) < 2 ? NaN : mean(diff(idx)) * dt
        return (class = class, amplitude = m.amplitude, mean_return = return_), s.u[end]
    end
    θs = collect(grid_pts)
    z = _to_free(X0, with_parameter(p, parameter, θs[1]; e_ref = e_ref)) .+ 1e-3
    up = NamedTuple[]
    for θ in θs
        r, z = measure(θ, z); push!(up, r)
    end
    down = NamedTuple[]
    for θ in reverse(θs)
        r, z = measure(θ, z); pushfirst!(down, r)
    end
    table(v) = (class = getproperty.(v, :class), amplitude = getproperty.(v, :amplitude),
                 mean_return = getproperty.(v, :mean_return))
    differs = [θs[i] for i in eachindex(θs) if up[i].class != down[i].class ||
              abs(up[i].mean_return - down[i].mean_return) > 0.05 * up[i].mean_return]
    return (θ = θs, up = table(up), down = table(down), coexistence = differs)
end
