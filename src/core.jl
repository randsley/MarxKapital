# ============================================================================
# CORE: MATRICES, DEPARTMENTS, DYNAMICAL SYSTEMS AND SIMULATION
# ============================================================================

# ----------------------------------------------------------------------------
# Math helpers
# ----------------------------------------------------------------------------

"""Creates an N×N identity matrix (avoids LinearAlgebra's `I` constant)."""
identity_matrix(N::Int) = diagm(ones(N))

"""
    create_technical_matrix(N; density=0.3, max_coef=0.15,
                         structure=:random, seed=nothing)

Creates an input-output technical matrix A (N×N) with spectral radius < 1.

# Estruturas
- `:random`  — random links
- `:triangular` — hierarchical (upstream → downstream sectors)
- `:blocks`     — clusters with weak inter-block links

Passing `seed` fixes the random seed and makes the matrix reproducible
(recommended whenever scenarios are compared).
"""
function create_technical_matrix(N::Int; density = 0.3, max_coef = 0.15,
                              structure = :random, seed = nothing)
    isnothing(seed) || Random.seed!(seed)

    A = zeros(N, N)

    if structure == :random
        for i in 1:N, j in 1:N
            rand() < density && (A[i, j] = rand() * max_coef)
        end

    elseif structure == :triangular
        for i in 1:N, j in i:N
            rand() < density && (A[i, j] = rand() * max_coef)
        end

    elseif structure == :blocks
        n_blocks = max(2, N ÷ 3)
        block_size = N ÷ n_blocks
        for block in 1:n_blocks
            start = (block - 1) * block_size + 1
            stop = min(block * block_size, N)
            for i in start:stop, j in start:stop
                rand() < density * 2 && (A[i, j] = rand() * max_coef)
            end
            if block < n_blocks
                next_i = stop + 1
                next_f = min((block + 1) * block_size, N)
                for i in start:stop, j in next_i:next_f
                    rand() < density * 0.5 && (A[i, j] = rand() * max_coef * 0.5)
                end
            end
        end
    else
        error("Unknown structure '$structure' (:random, :triangular, :blocks)")
    end

    # Ensure productivity: ρ(A) < 1
    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && (A = A / ρ_A * 0.8)

    return A
end

"""
    _ensure_output_admissibility(A; margin=0.95)

Reconstructing gross output from the value-added-type flow
(`xⱼ = Wⱼ/(1-Σᵢ A[i,j])`, Equation 2 of the paper) requires `Σᵢ A[i,j] < 1`
for every `j`. This is an admissibility condition of the model, not a
numerical detail. `ρ(A)<1` (guaranteed by `create_technical_matrix`) does
\\emph{not} imply it: ρ(A) is an upper bound on the largest column sum, not a
lower bound, so a matrix that is productive in Leontief's sense can still
have a column summing to ≥1.

The condition only holds when `A` is the \\emph{complete} circulating-input
requirement of each sector. That is true by construction for the closed
synthetic matrices used in the dynamic simulations
(`create_technical_matrix`), but not necessarily for an empirical
domestic-use matrix (which by definition leaves out imported inputs). This
is why the reconstruction of `x` in this function is never applied to the
real Eurostat matrix (`build_eurostat_io_matrix`), only to the synthetic
matrices used by the `system_Ndept_io!` dynamics.

The condition is checked explicitly rather than enforced silently at every
evaluation of the ODE right-hand side: if some column sum exceeds `margin`,
the whole of `A` is rescaled (same logic as `create_technical_matrix` uses
for ρ(A)<1) until the largest column sum is below `margin`. This happens
once, at the start of the simulation, not at every solver step.
Returns `(A_admissible, was_rescaled::Bool)`.
"""
function _ensure_output_admissibility(A; margin = 0.95)
    colsum = vec(sum(A, dims = 1))
    maxcol = maximum(colsum)
    maxcol < margin && return A, false
    factor = margin / maxcol
    @warn "Largest column sum of A ($(round(maxcol,digits=3))) exceeds $margin; " *
          "rescaled by a factor of $(round(factor,digits=3)) to satisfy the " *
          "admissibility condition of the gross-output reconstruction (Equation 2)."
    return A .* factor, true
end

# ----------------------------------------------------------------------------
# Creating departments
# ----------------------------------------------------------------------------

"""Marx's classic 2-department model (means of production / means of consumption)."""
function two_department_model()
    dept1 = Department("Means of Production",
                         c = 4000.0, v = 1000.0, e = 1.0,
                         σ_c = 0.5, σ_v = 0.1, δ = 0.05)
    dept2 = Department("Consumer Goods",
                         c = 2000.0, v = 500.0, e = 1.0,
                         σ_c = 0.3, σ_v = 0.15, δ = 0.05)
    return [dept1, dept2]
end

"""
    create_departments(N, name_list=String[])

Creates N departments with random but plausible parameters. The organic
composition rises with the sector index.
"""
function create_departments(N::Int, name_list::Vector{String} = String[])
    isempty(name_list) && (name_list = ["Dept_$i" for i in 1:N])
    depts = Department[]
    for i in 1:N
        k_base = 1.5 + (i / N) * 2.0
        c = 100.0 * k_base
        v = 100.0
        e = 1.0 + rand()
        σ_c = 0.4 + rand() * 0.3
        σ_v = 0.1 + rand() * 0.15
        δ = 0.03 + rand() * 0.05
        push!(depts, Department(name_list[i], c = c, v = v, e = e,
                                  σ_c = σ_c, σ_v = σ_v, δ = δ))
    end
    return depts
end

# ----------------------------------------------------------------------------
# Systems of differential equations
# ----------------------------------------------------------------------------

"""ODE system for the 2-department model. State: [C1,V1,C2,V2]."""
function system_2dept!(dX, X, p, t)
    C1, V1, C2, V2 = X
    e1, e2, σ_c1, σ_v1, σ_c2, σ_v2, δ1, δ2 = p
    S1 = e1 * V1
    S2 = e2 * V2
    dX[1] = σ_c1 * S1 - δ1 * C1
    dX[2] = σ_v1 * S1
    dX[3] = σ_c2 * S2 - δ2 * C2
    dX[4] = σ_v2 * S2
end

"""
    system_Ndept!(dX, X, p, t)

ODE system for N departments. State: [C1..CN, V1..VN].

KNOWN LIMITATION: each department's accumulation depends only on its own
surplus value; the technical matrix `p.A` is carried in the parameters but
**does not feed back** into the dynamics. See `docs/LIMITATIONS.md` (item 1)
and the coupled version `system_Ndept_io!`, which links the sectors via A.
"""
function system_Ndept!(dX, X, p, t)
    N = length(p.e)
    C = @view X[1:N]
    V = @view X[N+1:2N]
    S = p.e .* V
    dX[1:N]      = p.σ_c .* S .- p.δ .* C
    dX[N+1:2N]   = p.σ_v .* S
end

"""
    system_Ndept_io!(dX, X, p, t)

ODE system for N departments, with the technical matrix `p.A` feeding back
into the dynamics through a capital-mobility term:

    dCᵢ/dt = σ_c,ᵢ·Sᵢ − δᵢ·Cᵢ + μ·(rᵢ − r̄)·Cᵢ

where `rᵢ` is the profit rate of sector i with constant capital valued at
Sraffian production prices (which depend on A), not at bare book value. To
avoid the circularity of using r̄ to compute prices that in turn define r̄,
the profit rate passed to `compute_production_prices` is the
non-price-weighted average (`r̄_naive`), capped at 95% of `p.R_max` so it
stays clear of the Sraffian singularity. If the price system still fails
(ill-conditioned matrix), prices fall back to labor values (no adjustment,
π = 1).

`r̄` (the rate used in the mobility term, distinct from `r̄_naive` above) is
the `C`-weighted mean of `r`, not the aggregate ratio `ΣS/Σ(C+V)`, because
it is the only choice for which `Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exactly. This guarantees
that the mobility term reallocates aggregate constant capital between
sectors instead of creating or destroying it (checked by a test,
`test/runtests.jl`, "Capital mobility — exact conservation").

See `docs/LIMITATIONS.md` (item 1): this is the optional coupled version,
selected with `coupled=true` in `simulate_Ndept`/`simulate_Ndept_custom`.
`system_Ndept!` remains the "independent sectors" version.

If `p.realization == true`, a second mechanism is added, independent of
capital mobility: a realization pressure that brakes reinvestment when the
technical structure (`A`) cannot support current output levels. Gross
output per sector is `Oᵢ = Cᵢ+Vᵢ+Sᵢ` and the intermediate demand implied by
A is `(A·O)ᵢ`; the aggregate realization ratio

    ρ_real = Σᵢ min(Oᵢ, (A·O)ᵢ) / Σᵢ (A·O)ᵢ

measures what fraction of aggregate intermediate demand current outputs can
cover (≤ 1; = 1 when there is no bottleneck). Planned reinvestment
(`σ_c,ᵢ·Sᵢ`) is scaled by `min(ρ_real, 1)`. This is an aggregate
approximation: the same scale applies to every sector.

If `p.rationing == true` (takes precedence over `p.realization`), exact
**per-sector** rationing is used instead, via `_solve_rationing`; see its
docstring for the mechanism (Bénassy/Barro-Grossman quantity rationing with
Leontief technology). Both mechanisms remain an ordinary ODE: they add no
new state variables and need no differential-algebraic (DAE) solver. The
rationing is solved by fixed-point iteration inside the right-hand side
itself, just as the Sraffian prices already are. Neither imposes exact
realization through algebraic constraints handled by the solver; see
`check_equilibrium_Ndept` (`src/analysis.jl`) for a more detailed check
after the fact, and `docs/LIMITATIONS.md` item 1 for the explicit scope of
this approximation.

If `p.μ_v ≠ 0` (optional field), variable capital also moves between
sectors: `dVᵢ/dt = σ_v,ᵢ·Sᵢ + μ_v·(rᵢ − r̄_V)·Vᵢ`, with `r̄_V` the
`V`-weighted mean of `r`. Without this term each `Vᵢ` grows at its own rate
`σ_v,ᵢ·eᵢ` and there is no interior balanced growth (the sector with the
highest rate ends up with all the variable capital); see `src/growth.jl`.

The right-hand side is homogeneous of degree 1 in the state
(`f(λX) = λf(X)`): only proportions matter, and the relevant steady states
are balanced-growth rays, `f(X★) = g★·X★`.
"""
function system_Ndept_io!(dX, X, p, t)
    N = length(p.e)
    C = @view X[1:N]
    V = @view X[N+1:2N]
    S = p.e .* V

    r = _io_profit_rates(C, V, S, p)
    # r̄ is the C-weighted mean of r (the book stock, the same weight that
    # multiplies the mobility term below), not ΣS/Σ(C+V), the aggregate
    # ratio used before. It is the only choice for which Σμ(rᵢ-r̄)Cᵢ = 0
    # exactly, so the mobility term reallocates aggregate constant capital
    # instead of creating or destroying it (see paper/main.tex, discussion
    # of the conservation of the mobility term).
    r̄ = sum(r .* C) / sum(C)

    # `κ` inherits the type of `S` (not `ones(N)`, Float64): under automatic
    # differentiation (ForwardDiff, `src/differentiation.jl`) the state is `Dual`.
    κ = fill(one(eltype(S)), N)
    if p.rationing || p.realization
        # W = value-added-type flow of the period (constant capital
        # TRANSFERRED, δ.*C, not the stock C; see `transferred_capital` in
        # `types.jl`). It is not gross output: circulating intermediate
        # consumption zᵢ is missing. x (gross output) is recovered from the
        # model's own cost-output identity, xⱼ = zⱼ+Wⱼ with zⱼ=Σᵢ A[i,j]·xⱼ
        # (A is defined per unit of the buyer's gross output), so that
        # xⱼ = Wⱼ/(1-Σᵢ A[i,j]), with no new state. Valid only when A is the
        # COMPLETE circulating-input requirement of each sector (true by
        # construction for the closed synthetic matrices used here; it does
        # not apply to Eurostat's real domestic-use matrix, which leaves out
        # imported inputs by definition; see `build_eurostat_io_matrix`,
        # never used in this ODE). The admissibility condition
        # Σᵢ A[i,j]<1 is checked and enforced once, at the start of the
        # simulation (`_ensure_output_admissibility`), not at every
        # evaluation.
        W = p.δ .* C .+ V .+ S
        colsum = vec(sum(p.A, dims = 1))
        x = W ./ (1 .- colsum)
        O = x  # genuine gross output, not W: fixes the external review's
                # criticism that O left out circulating intermediate consumption.
        # Optional (`final_demand_share`): the part of output taken by final
        # consumption and exports is not available to investment demand.
        haskey(p, :final_demand_share) && (O = (1 .- p.final_demand_share) .* x)
        if p.rationing
            # Desired output expansion implied by planned reinvestment
            # σ_c,ⱼSⱼ, via the current capital/output ratio Cⱼ/xⱼ
            # (Δxⱼ = planned investment ÷ capital-output ratio). Aᵢⱼ
            # applies to this OUTPUT expansion, not to investment spending
            # directly (the earlier simplification, already
            # documented as such in the paper).
            Δx = p.σ_c .* S .* x ./ C
            κ = _solve_rationing(p.A, ones(N), Δx, O)
        else
            intermediate_demand = p.A * O
            demand_sum = sum(intermediate_demand)
            demand_sum > 0 && (κ = fill(min(sum(min.(O, intermediate_demand)) / demand_sum, 1.0), N))
        end
    end

    dX[1:N]    = κ .* p.σ_c .* S .- p.δ .* C .+ p.μ .* (r .- r̄) .* C
    # Mobility of variable capital (optional, `p.μ_v`; absent or 0 = off,
    # dynamics identical to before). With r̄_V weighted by V, Σᵢ μ_v(rᵢ-r̄_V)Vᵢ = 0
    # exactly: the term reallocates variable capital between sectors without creating it.
    μ_v = get(p, :μ_v, 0.0)
    if iszero(μ_v)
        dX[N+1:2N] = p.σ_v .* S
    else
        r̄_V = sum(r .* V) / sum(V)
        dX[N+1:2N] = p.σ_v .* S .+ μ_v .* (r .- r̄_V) .* V
    end
end

"""
Default relaxation of the rationing iteration, `ρ ↦ (1−α)ρ + αF(ρ)`. With
the sectors ordered by ρ*, the Jacobian of `F` is triangular with
eigenvalues `−θₖ ∈ [−1, 0]`, and 0 and −1 always occur when there is
rationing (`paper/main.tex`, Proposition 1). `α = 2/3` minimizes
`max(|1−α|, |1−2α|)`, shrinking the local error by 1/3 at each step (0.5,
the previous value, shrinks it by 1/2). Checked on 6870 cases (the
`paper/monte_carlo.jl` sweep, random starting points, very scarce supply):
convergence in all of them, with ≈30% fewer iterations than with 0.5.
"""
const DEFAULT_RELAXATION = 2 / 3

"""
    _io_profit_rates(C, V, S, p)

Sectoral profit rates with constant capital valued at Sraffian production
prices, `rᵢ = Sᵢ/(πᵢCᵢ + Vᵢ)`, as `system_Ndept_io!` uses them. To avoid the
circularity of using r̄ to compute prices that in turn define r̄, the rate
passed to the prices is the aggregate ratio `ΣS/Σ(C+V)`, capped at 95% of
`p.R_max`.
"""
function _io_profit_rates(C, V, S, p)
    r_effective = clamp(sum(S) / sum(C .+ V), 0.0, 0.95 * p.R_max)
    π = _price_value_ratio(p, r_effective, length(S))
    return S ./ (π .* C .+ V)
end

"""
    _price_value_ratio(p, r_effective, N)

Ratio of production price to labor value, `πᵢ = pᵢ/λᵢ`, used to value
constant capital in `system_Ndept_io!` and `compute_price_profit_rates`. If
the price system is singular (`compute_production_prices` throws
`ErrorException`), it falls back to `π = 1` (prices = values). Other errors,
for example a `MethodError` under automatic differentiation, are rethrown
so the fallback does not silently hide them.
"""
function _price_value_ratio(p, r_effective, N)
    try
        prices = compute_production_prices(p.A, p.l, p.w, r_effective)
        λ = compute_labor_values(p.A, p.l)
        return prices ./ λ
    catch err
        err isa ErrorException || rethrow()
        return fill(one(r_effective), N)
    end
end

"""
    _solve_rationing(A, σ_c, S, O; max_iter=200, tol=1e-8, relaxation=DEFAULT_RELAXATION)

Solves market rationing (short-side rule, Leontief technology) for
investment goods, given the current state. For each buying sector `j`,
planned reinvestment `σ_c,ⱼ·Sⱼ` needs inputs from suppliers in the
proportions `A[:,j]`. There is no substitution between inputs, so realized
reinvestment is limited by the scarcest input (law of the minimum). This
makes the problem simultaneous: the rationing a sector suffers lowers its
effective demand for ALL its inputs, which in turn affects the rationing
its suppliers suffer. It is solved by fixed-point iteration (`ρ` = rationing
factor per supplying sector, `κ` = realized fraction of planned
reinvestment per buying sector):

    κⱼ = min_{i: A[i,j]>0} ρᵢ                    (limited by the scarcest input)
    Dᵢ = Σⱼ A[i,j]·κⱼ·σ_c,ⱼ·Sⱼ                     (effective demand, already consistent with the rationing)
    ρᵢ = min(1, Oᵢ / Dᵢ)                          (short-side rule)

The iteration is damped, `ρ ← (1−α)ρ + α·F(ρ)` with `α = relaxation`
(`DEFAULT_RELAXATION = 2/3` by default; see its docstring).

If it does not converge within `max_iter` iterations, it falls back to
`κ = ones(N)` (no rationing, equivalent to switching this mechanism off)
with a warning. This is the same graceful-degradation approach used in the
rest of the code (the Sraffian price fallback in the same function, the
AMECO/Eurostat network fallbacks).
"""
function _solve_rationing(A, σ_c, S, O; max_iter = 200, tol = 1e-8,
                                relaxation = DEFAULT_RELAXATION,
                                ρ_initial = nothing, return_diagnostics::Bool = false)
    N = length(S)
    D_planned = σ_c .* S
    # Under automatic differentiation the fixed point is solved in values
    # (Float64) and the derivative propagates through the implicit function
    # theorem (`_rationing_dual`), instead of differentiating each iteration.
    if eltype(D_planned) <: ForwardDiff.Dual || eltype(O) <: ForwardDiff.Dual ||
       eltype(A) <: ForwardDiff.Dual
        return_diagnostics && error("return_diagnostics is not supported with Dual numbers")
        return _rationing_dual(A, D_planned, O; max_iter = max_iter, tol = tol,
                                  relaxation = relaxation, ρ_initial = ρ_initial)
    end
    ρ = isnothing(ρ_initial) ? ones(N) : copy(ρ_initial)
    converged = false
    iterations = max_iter
    for it in 1:max_iter
        ρ_target = _rationing_map(ρ, A, D_planned, O)
        # under-relaxation: without it the iteration can oscillate between two states
        # instead of converging (the map min(1,O/D) is not a pure contraction), as seen
        # in a 2-sector example where the undamped version oscillated forever between
        # ρ=[0.8,1] and ρ=[1,1]. See `rationing_jacobian` (`src/differentiation.jl`)
        # for the range of `relaxation` that guarantees local convergence.
        ρ_new = (1 - relaxation) .* ρ .+ relaxation .* ρ_target
        if maximum(abs.(ρ_new .- ρ)) < tol
            ρ = ρ_new
            converged = true
            iterations = it
            break
        end
        ρ = ρ_new
    end
    converged || @warn "Rationing did not converge in $max_iter iterations; using κ=1 (no rationing)."
    κ_final = converged ? _κ_rationing(ρ, A) : ones(N)
    if return_diagnostics
        return (κ = κ_final, ρ = ρ, converged = converged, iterations = iterations,
                rationed_fraction = count(κ_final .< 0.999) / N)
    end
    return κ_final
end

"""
    _κ_rationing(ρ, A)

`κⱼ = min_{i: A[i,j]>0} ρᵢ` (1 if column j of A has no suppliers).
"""
_κ_rationing(ρ, A) = [minimum((ρ[i] for i in axes(A, 1) if A[i, j] > 0); init = one(eltype(ρ)))
                         for j in axes(A, 2)]

"""
    _rationing_map(ρ, A, D_planned, O)

The map `F(ρ)` whose fixed point `_solve_rationing` looks for (equation
`eq:rationing` in `paper/main.tex`): `F(ρ)ᵢ = min(1, Oᵢ/Dᵢ(κ(ρ)))`, with
`Dᵢ = Σⱼ A[i,j]·κⱼ·D_plannedⱼ`. Generic in the number type, so that
ForwardDiff can compute `∂F/∂ρ` (see `rationing_jacobian`).
"""
function _rationing_map(ρ, A, D_planned, O)
    κ = _κ_rationing(ρ, A)
    D_real = A * (κ .* D_planned)
    return min.(one(eltype(D_real)), O ./ max.(D_real, 1e-12))
end

"""
    _rationing_dual(A, D_planned, O; kwargs...)

Version of `_solve_rationing` for `ForwardDiff.Dual` inputs. Solves the
fixed point `ρ* = F(ρ*; θ)` in values and propagates the derivatives through
the implicit function theorem, `dρ* = (I − ∂F/∂ρ)⁻¹ · ∂F/∂θ·dθ`, which is
exact at the fixed point (the same technique
`SpatialEconometrics.StructuralMacroCalibration` uses for GRAS balancing).
Returns `κ(ρ*)` as a vector of `Dual`.
"""
function _rationing_dual(A, D_planned, O; kwargs...)
    val(x) = ForwardDiff.value.(x)
    Av, Dv, Ov = val(A), val(D_planned), val(O)
    diag = _solve_rationing(Av, ones(length(Dv)), Dv, Ov; return_diagnostics = true, kwargs...)
    diag.converged || return fill(one(eltype(promote_type(eltype(A), eltype(D_planned), eltype(O)))), length(Dv))
    ρ★ = diag.ρ
    Fθ = _rationing_map(ρ★, A, D_planned, O)            # ∂F/∂θ·dθ in the partials
    Jρ = ForwardDiff.jacobian(r -> _rationing_map(r, Av, Dv, Ov), ρ★)
    TD = eltype(Fθ)
    P = reduce(vcat, (collect(ForwardDiff.partials(f))' for f in Fθ))
    dρ = (identity_matrix(length(ρ★)) .- Jρ) \ P
    ρ_dual = [TD(ρ★[i], ForwardDiff.Partials(Tuple(dρ[i, :]))) for i in eachindex(ρ★)]
    return _κ_rationing(ρ_dual, A)
end

# ----------------------------------------------------------------------------
# Simulation
# ----------------------------------------------------------------------------

"""Simulates the 2-department model."""
function simulate_2dept(; T = 100.0)
    depts = two_department_model()
    X0 = [depts[1].c, depts[1].v, depts[2].c, depts[2].v]
    p = (depts[1].e, depts[2].e,
         depts[1].σ_c, depts[1].σ_v,
         depts[2].σ_c, depts[2].σ_v,
         depts[1].δ, depts[2].δ)
    prob = ODEProblem(system_2dept!, X0, (0.0, T), p)
    sol = solve(prob, Tsit5(), saveat = 0.5)
    return sol, depts, p
end

"""
    simulate_Ndept(N; T=100.0, name_list=String[], seed=nothing, coupled=false, μ=0.3, μ_v=0.0,
                  realization=false, rationing=false, market_prices=false, β=0.5, basket=nothing)

Simulates the N-department model with randomly generated departments. With
`coupled=true` it uses `system_Ndept_io!` (capital mobility via A and
production prices); `μ` is then the mobility coefficient, and `μ_v` that of
variable capital (0 = off, the default). `realization=true` (only has an
effect with `coupled=true`) adds the aggregate realization pressure;
`rationing=true` (takes precedence over `realization`) uses per-sector
rationing; see the `system_Ndept_io!` docstring. `market_prices=true`
(requires `coupled=true`) uses the cross-dual dynamics of
`cross_dual_system!`: market prices with adjustment speed `β` and consumption
basket `basket` (`basket_initial` by default).
"""
function simulate_Ndept(N::Int; T = 100.0, name_list::Vector{String} = String[],
                       seed = nothing, coupled = false, μ = 0.3, μ_v = 0.0,
                       realization = false, rationing = false,
                       market_prices = false, β = 0.5, basket = nothing)
    depts = create_departments(N, name_list)
    return simulate_Ndept_custom(depts, T = T, seed = seed, coupled = coupled, μ = μ,
                                     μ_v = μ_v, realization = realization,
                                     rationing = rationing,
                                     market_prices = market_prices, β = β, basket = basket)
end

"""
    simulate_Ndept_custom(depts; T=100.0, seed=nothing, coupled=false, μ=0.3, μ_v=0.0,
                              realization=false, rationing=false,
                              market_prices=false, β=0.5, basket=nothing,
                              A=nothing, final_demand_share=nothing)

Simulates the N-department model from pre-configured departments. With
`coupled=true` it uses `system_Ndept_io!` instead of `system_Ndept!` (`μ_v`,
the mobility of variable capital, only has an effect in that case).
`market_prices=true` uses `cross_dual_system!` (see `simulate_Ndept`); it
cannot be combined with `realization`/`rationing`.
`realization=true` (only has an effect with `coupled=true`) adds the
aggregate realization pressure; `rationing=true` (takes precedence over
`realization`) uses per-sector rationing; see the docstring of
`system_Ndept_io!`.

Real-data options, typically from a calibration (`departments_from_params`):

- `A`: a given technical matrix (e.g. `params.A`) instead of a random one
  (`seed` is then ignored). Eurostat's matrix covers domestic inputs only,
  so the gross output the coupled mechanisms reconstruct,
  `xⱼ = Wⱼ/(1 − Σᵢ A[i,j])`, leaves out imported intermediate inputs.
- `basket`: e.g. `consumption_basket(params.final_demand)`, real household
  consumption shares in place of `basket_initial`.
- `final_demand_share` (only with `rationing=true`): the share `φ` of each
  sector's output taken by final consumption and exports
  (`exogenous_demand_share(params.final_demand)`); rationing then allocates
  only `(1 − φ)·x` to investment demand.
"""
function simulate_Ndept_custom(depts::Vector{Department}; T = 100.0,
                                   seed = nothing, coupled = false, μ = 0.3, μ_v = 0.0,
                                   realization = false, rationing = false,
                                   market_prices = false, β = 0.5, basket = nothing,
                                   A = nothing, final_demand_share = nothing)
    N = length(depts)
    X0 = [ [d.c for d in depts]; [d.v for d in depts] ]
    if isnothing(A)
        A = create_technical_matrix(N, seed = seed)
    else
        size(A) == (N, N) || error("A must be $N×$N, got $(size(A))")
        A = Matrix{Float64}(A)
    end
    if !isnothing(final_demand_share)
        (coupled && rationing) || error("final_demand_share requires coupled=true and rationing=true")
        length(final_demand_share) == N || error("final_demand_share must have $N elements")
        all(0 .<= final_demand_share .< 1) || error("final_demand_share must be in [0, 1)")
    end
    (coupled && (realization || rationing || market_prices)) &&
        (A, _ = _ensure_output_admissibility(A))

    if market_prices
        coupled || error("market_prices=true requires coupled=true")
        (realization || rationing) &&
            error("market_prices=true cannot be combined with realization/rationing")
        p = (e = [d.e for d in depts], σ_c = [d.σ_c for d in depts],
             σ_v = [d.σ_v for d in depts], δ = [d.δ for d in depts],
             A = A, μ = μ, μ_v = μ_v, β = β)
        p = merge(p, (basket = isnothing(basket) ? basket_initial(A, X0, p) : basket,))
        prob = ODEProblem(cross_dual_system!, [X0; zeros(N)], (0.0, T), p)
        return solve(prob, Tsit5(), saveat = 0.5), depts, p
    end

    if coupled
        l = [d.v for d in depts]
        p = (
            e           = [d.e for d in depts],
            σ_c         = [d.σ_c for d in depts],
            σ_v         = [d.σ_v for d in depts],
            δ           = [d.δ for d in depts],
            A           = A,
            l           = l,
            R_max       = compute_max_profit_rate(A, l),
            μ           = μ,
            μ_v         = μ_v,
            w           = 1.0,
            realization  = realization,
            rationing = rationing,
        )
        isnothing(final_demand_share) ||
            (p = merge(p, (final_demand_share = collect(Float64, final_demand_share),)))
        prob = ODEProblem(system_Ndept_io!, X0, (0.0, T), p)
    else
        p = (
            e   = [d.e for d in depts],
            σ_c = [d.σ_c for d in depts],
            σ_v = [d.σ_v for d in depts],
            δ   = [d.δ for d in depts],
            A   = A,
        )
        prob = ODEProblem(system_Ndept!, X0, (0.0, T), p)
    end

    sol = solve(prob, Tsit5(), saveat = 0.5)
    return sol, depts, p
end
