# ============================================================================
# ANALYSIS: PROFIT RATES, LABOR VALUES AND PRODUCTION PRICES
# ============================================================================

# ----------------------------------------------------------------------------
# Metrics over time
# ----------------------------------------------------------------------------

"""Sectoral profit rates over time (N × T matrix)."""
function compute_profit_rates(sol, e)
    N = length(e)
    T = length(sol.t)
    r = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        k = C ./ V
        r[:, idx] = e ./ (k .+ 1)
    end
    return r
end

"""
Sectoral profit rates over time, with constant capital valued at Sraffian
production prices (N × T matrix). Uses the same logic as `system_Ndept_io!`
(see `src/core.jl`) to reproduce, outside the ODE, the profit rate `rᵢ` that
the coupled dynamics uses internally. Needs `p` with the fields
`e, A, l, R_max, w` (see `simulate_Ndept_custom(..., coupled=true)`).
"""
function compute_price_profit_rates(sol, p)
    N = length(p.e)
    T = length(sol.t)
    r = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        S = p.e .* V

        r[:, idx] = _io_profit_rates(C, V, S, p)
    end
    return r
end

"""Sectoral organic compositions over time (N × T matrix)."""
function compute_organic_compositions(sol)
    N = Int(length(sol.u[1]) / 2)
    T = length(sol.t)
    k = zeros(N, T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        k[:, idx] = C ./ V
    end
    return k
end

"""Average (aggregate) profit rate over time (vector of length T)."""
function compute_average_profit_rate(sol, e)
    N = length(e)
    T = length(sol.t)
    r_mean = zeros(T)
    for idx in 1:T
        C = sol[1:N, idx]
        V = sol[N+1:2N, idx]
        S = e .* V
        r_mean[idx] = sum(S) / (sum(C) + sum(V))
    end
    return r_mean
end

"""Plot of the dispersion (standard deviation) of profit rates over time."""
function analyze_convergence(sol, depts, p)
    r = compute_profit_rates(sol, p.e)
    σ_r = [std(r[:, i]) for i in 1:size(r, 2)]
    plot(sol.t, σ_r,
         xlabel = "Time", ylabel = "Standard deviation of profit rates",
         title = "Convergence of profit rates", lw = 2, legend = false)
end

"""
Checks the intersectoral equilibrium condition of the classic 2-department
scheme: V1+(1-σc1)S1 = C2+σc2·S2. `C1`,`C2` stand here, as in Marx's classic
scheme, for the constant capital \\emph{used up/transferred} in the period
(not the advanced stock), the magnitude that has to be replaced by purchases
from Department I."""
function check_equilibrium_2dept(C1, V1, C2, V2, e1, e2, σ_c1, σ_c2)
    S1 = e1 * V1
    S2 = e2 * V2
    lhs = V1 + (1 - σ_c1) * S1
    rhs = C2 + σ_c2 * S2
    diseq = lhs - rhs
    return (equilibrium = abs(diseq) < 0.01, disequilibrium = diseq,
            lhs = lhs, rhs = rhs)
end

"""
    check_equilibrium_Ndept(sol, p; t_idx=length(sol.t))

Generalization of `check_equilibrium_2dept` to N sectors. It checks after
the fact (it does not feed back into the dynamics, just as the 2-department
version does not feed back into `system_2dept!`) whether current output
levels can sustain the intermediate demand implied by the technical matrix
`p.A`.

At time `t_idx` (the last one by default), it first rebuilds the
value-added-type flow `Wᵢ = δᵢCᵢ+Vᵢ+Sᵢ` (constant capital
\emph{transferred}, δᵢCᵢ, not the stock Cᵢ; see `transferred_capital`/
`product_value` in `types.jl`) and then the genuine gross output
`xᵢ = Wᵢ/(1-Σⱼ A[j,i])` from the model's cost-output identity (the same
reconstruction used in `system_Ndept_io!`, `src/core.jl`). `Wᵢ` alone leaves
out circulating intermediate consumption and is not directly comparable with
`(A··)ᵢ`, which is input demand per unit of gross output. With `xᵢ` it
computes intermediate demand `(A·x)ᵢ` and returns the deviation per sector
(`xᵢ − (A·x)ᵢ`, positive when the sector produces more than the economy needs
from it as an input, negative when it produces less) and the aggregate
realization ratio `ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1; = 1 with no
bottleneck). `system_Ndept_io!` (`realization=true`, `src/core.jl`) uses it as
the basis of the reinvestment damping factor; it is exposed here so the
result can be inspected outside the ODE, like `compute_price_profit_rates`.
"""
function check_equilibrium_Ndept(sol, p; t_idx = length(sol.t))
    N = length(p.e)
    X = sol.u[t_idx]
    C = X[1:N]
    V = X[N+1:2N]
    S = p.e .* V
    W = p.δ .* C .+ V .+ S
    # Admissibility (Σᵢ A[i,j]<1 for every j) is ensured once, when the
    # simulation is set up (`_ensure_output_admissibility`, `src/core.jl`),
    # and is not re-checked here; see `system_Ndept_io!`.
    colsum = vec(sum(p.A, dims = 1))
    O = W ./ (1 .- colsum)
    intermediate_demand = p.A * O
    deviation = O .- intermediate_demand
    demand_sum = sum(intermediate_demand)
    ρ_real = demand_sum > 0 ? sum(min.(O, intermediate_demand)) / demand_sum : 1.0
    return (equilibrium = ρ_real > 0.95, ρ_real = ρ_real, deviation = deviation,
            output = O, intermediate_demand = intermediate_demand)
end

# ----------------------------------------------------------------------------
# Labor values and production prices
# ----------------------------------------------------------------------------

"""
    compute_labor_values(A, l)

Labor values λ = (I − A)⁻¹ · l. Requires a productive economy (ρ(A) < 1).
"""
function compute_labor_values(A, l)
    N = size(A, 1)
    Id = identity_matrix(N)
    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && error("Matrix is not productive! ρ(A) = $ρ_A ≥ 1")
    λ = (Id - A) \ l
    any(λ .< 0) && @warn "Negative labor values detected"
    return λ
end

"""
    compute_max_profit_rate(A, l)

Maximum profit rate (wages = 0): R_max = 1/λ_max(Aᵀ) − 1.
"""
function compute_max_profit_rate(A, l)
    λ_max = maximum(real.(eigvals(A')))
    return (1 / λ_max) - 1
end

"""
    compute_production_prices(A, l, w, r_bar)

Sraffian production prices: p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ · l.
Rejects any r̄ that makes the system singular (r̄ ≥ R_max).
"""
function compute_production_prices(A, l, w, r_bar)
    N = size(A, 1)
    Id = identity_matrix(N)
    factor = 1 + r_bar
    matrix = Id - factor * A'
    R_max = compute_max_profit_rate(A, l)
    if r_bar >= R_max || abs(det(matrix)) < 1e-10
        error("Singular system for r̄=$r_bar. Maximum rate R_max=$(round(R_max, digits=3))")
    end
    p = w * factor * (matrix \ l)
    any(p .< 0) && @warn "Negative prices for r̄=$r_bar"
    return p
end

"""
    transformation_problem(N=3)

Analyzes the transformation of values into prices for several profit rates
and draws the comparison plots.
"""
function transformation_problem(N = 3)
    println("\n" * "="^70)
    println("TRANSFORMATION OF VALUES INTO PRICES")
    println("="^70)

    A = create_technical_matrix(N, density = 0.5)
    l = 0.3 .+ rand(N) * 0.3

    λ = compute_labor_values(A, l)
    λ_norm = λ / sum(λ)
    w = 1.0
    R_max = compute_max_profit_rate(A, l)
    println("\nMaximum profit rate: $(round(R_max*100, digits=1))%")

    profit_rates = [0.0, 0.1, 0.2, 0.3, min(0.4, R_max * 0.9)]
    results = []
    for r_bar in profit_rates
        p = compute_production_prices(A, l, w, r_bar)
        p_norm = p / sum(p)
        deviations = (p_norm - λ_norm) ./ λ_norm * 100
        push!(results, (r = r_bar, p = p_norm, deviations = deviations))
    end

    println("\nTechnical Matrix A:")
    display(round.(A, digits = 3))
    println("\n\nLabor Values λ (normalized):")
    display(round.(λ_norm, digits = 4))
    println("\n\nAnalysis by Profit Rate:")
    println("-"^70)
    for res in results
        println("\nr̄ = $(round(res.r*100, digits=1))%")
        println("Deviations (%): ", round.(res.deviations, digits = 2))
    end

    r_mean_idx = findfirst(x -> x.r ≈ 0.3, results)
    if !isnothing(r_mean_idx)
        res_mean = results[r_mean_idx]
        x = 1:N
        col_width = 0.35

        p1 = bar(x .- col_width/2, λ_norm, bar_width = col_width,
                 label = "Labor Values", ylabel = "Share",
                 title = "Normalized Comparison", color = :blue, alpha = 0.7)
        bar!(x .+ col_width/2, res_mean.p, bar_width = col_width,
             label = "Production Prices", color = :red, alpha = 0.7)

        p2 = bar(x, res_mean.deviations, xlabel = "Department",
                 ylabel = "Deviation (%)", title = "Percentage Deviations",
                 legend = false,
                 color = ifelse.(res_mean.deviations .> 0, :red, :blue), alpha = 0.7)
        hline!([0], color = :black, linestyle = :dash, label = "")

        p3 = plot(xlabel = "Profit Rate r̄", ylabel = "Mean Absolute Deviation (%)",
                  title = "Value-Price Divergence", legend = false)
        r_values = [res.r for res in results]
        mean_deviations = [mean(abs.(res.deviations)) for res in results]
        plot!(r_values, mean_deviations, marker = :circle, markersize = 6,
              lw = 2, color = :purple)

        p4 = scatter(λ_norm, res_mean.p, xlabel = "Labor Values (norm.)",
                     ylabel = "Production Prices (norm.)",
                     title = "Value-Price Correlation", label = "",
                     markersize = 8, alpha = 0.7)
        max_val = maximum([λ_norm; res_mean.p])
        plot!([0, max_val], [0, max_val], linestyle = :dash, color = :black,
              label = "Equality", lw = 2)
        ρ = cor(λ_norm, res_mean.p)
        annotate!(max_val * 0.7, max_val * 0.2, text("ρ = $(round(ρ, digits=3))", 12))

        combined = plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 900))
        display(combined)

        return (A = A, l = l, λ = λ_norm, results = results,
                plot = combined, R_max = R_max, correlation = ρ)
    end
end
