# ============================================================================
# READY-MADE EXAMPLES AND HELP
# ============================================================================

"""Example: the 2-department model."""
function example_2dept()
    println("\n" * "="^70)
    println("TWO-DEPARTMENT MODEL")
    println("="^70)
    sol, depts, p = simulate_2dept(T = 50.0)
    for (i, d) in enumerate(depts)
        println("  Dept $i — $(d.name): C=$(d.c) V=$(d.v) k=$(round(d.k, digits=2)) e=$(d.e)")
    end
    plot_2dept(sol, depts, p)
    return sol, depts, p
end

"""Example: the N-department model."""
function example_Ndept(N = 5; seed = 42)
    println("\n" * "="^70)
    println("$N-DEPARTMENT MODEL")
    println("="^70)
    name_list = ["Energy", "Industry", "Manufacturing", "Services", "Consumption"]
    N > 5 && append!(name_list, ["Dept_$i" for i in 6:N])
    sol, depts, p = simulate_Ndept(N, T = 100.0, name_list = name_list[1:N], seed = seed)
    for (i, d) in enumerate(depts)
        println("  $i. $(d.name): k=$(round(d.k, digits=2)) e=$(round(d.e, digits=2)) r=$(round(profit_rate(d), digits=3))")
    end
    println("\nρ(A) = $(round(maximum(abs.(eigvals(p.A))), digits=4))")
    plot_Ndept(sol, depts, p)
    return sol, depts, p
end

"""Example: the transformation problem."""
example_transformation() = transformation_problem(5)

"""Example: INE calibration (Portugal) + validation."""
function example_portugal()
    params = calibrate_portugal_model(year = 2022)
    validation = validate_calibrated_profit_rates(params)
    return params, validation
end

# --- AMECO examples ---

"""Example: Portugal via AMECO (synthetic) + validation + time series."""
function example_ameco_portugal()
    list_ameco_countries()
    params, data = calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic)
    validation = validate_calibrated_profit_rates(params)
    temporal = analyze_ameco_time_series("Portugal", years = 2000:2022)
    return (params = params, data = data, validation = validation, temporal = temporal)
end

"""Example: Southern Europe comparison."""
example_southern_europe() =
    compare_ameco_countries(["Portugal", "Spain", "Italy", "Greece"], year = 2022)

"""Example: comparison of large European economies."""
example_large_economies() =
    compare_ameco_countries(["Germany", "France", "Italy", "Spain", "Netherlands"], year = 2022)

"""Example: full AMECO workflow (auto → calibration → validation → shock)."""
function example_full_ameco_workflow(country = "Portugal"; method = :auto)
    println("\n" * "="^80)
    println("FULL AMECO WORKFLOW — $country")
    println("="^80)
    data = fetch_ameco_data(country, method = method)
    params, _ = calibrate_with_ameco_data(data, 2022, :macro)
    validation = validate_calibrated_profit_rates(params)
    depts = departments_from_params(params)
    shock = simulate_wage_shock(depts, 0.10, show_plot = false)
    println("\n✅ Done: quality $(round(validation.score, digits=1))% | " *
            "shock impact $(round(shock.final_r_impact, digits=2))pp")
    return (data = data, params = params, validation = validation, shock = shock)
end

# --- Help ---

"""Short usage guide."""
function model_help()
    println("""
    ╔═══════════════════════════════════════════════════════════════════════╗
    ║  MarxKapital — N-DEPARTMENT MARXIAN MODEL                              ║
    ╚═══════════════════════════════════════════════════════════════════════╝

    BASICS
      example_2dept()                       Classic 2-department model
      example_Ndept(10)                     N-department model
      example_transformation()              Values → production prices
      example_portugal()                    INE calibration (synthetic)

    AMECO (all EU countries + comparison)
      list_ameco_countries()                Available countries
      calibrate_with_ameco_v2("Portugal")   Calibrate via AMECO (:auto)
      fetch_ameco_data("Germany")           Fetch series (auto/sdmx/local/csv/synthetic)
      compare_ameco_countries([...])        International comparison
      analyze_ameco_time_series("PT")       Historical evolution
      check_ameco_sdmx()                    Check access to the official SDMX API

    REAL SECTORAL DATA (Eurostat, opt-in; see README.md "Real sectoral data (Eurostat)")
      calibrate_portugal_model(data_source=:eurostat)             INE, 19 sectors, real matrix A
      calibrate_with_ameco_v2("Portugal", sector_data=:eurostat)  AMECO, 3 macro sectors
      check_eurostat_sectoral()             Check access to the Eurostat API

    ANALYSIS
      wage_profit_curve(A, l)               Wage-profit frontier w-r
      simulate_wage_shock(depts, 0.10)      +10% wage shock
      frontier_curvature(A, l, r)           Exact w(r), w'(r), w''(r) (AD)

    AUTOMATIC DIFFERENTIATION, TSSI AND BIFURCATIONS
      system_jacobian(p, X)                 Exact Jacobian of the ODE (ForwardDiff)
      system_hessian(p, X)                  Hessians of the ODE right-hand side
      rationing_jacobian(A,σ_c,S,O)         Rationing map spectrum, α_max, optimal α
      tssi_valuation(sol, p; τ=1.0)         TSSI values/prices with lag τ
      compare_tssi_simultaneous(sol, p)     TSSI vs. simultaneist profit rate
      rationing_bifurcation(A,σ_c,S,O)      Continuation in the demand scale (BifurcationKit)
      tssi_bifurcation(X, p; τ=1.0)         Continuation of the TSSI price map

    BALANCED GROWTH AND CYCLES (market_prices=true)
      balanced_growth(p, X0)                Balanced-growth ray g★, stability
      wage_sweep(p, X0)                     g★, r★ against the wage share ω
      accumulation_bifurcation(p, X0, :μ_v; interval=(0,2.5))
                                            Hopf, normal form and limit cycles
      simulated_cycle(p, :μ_v, θ, X0)       Check by simulation (Poincaré section)
      hopf_curve(p, X0)                     Hopf boundary in the (ω, μ_v) plane
      lyapunov_exponents(p, :μ_v, θ, X0)    Lyapunov exponents (λ₁ > 0: chaos)
      simulated_hysteresis(p, :μ_v, grid_pts, X0)
                                            Coexisting attractors (↑↓ sweep)

    TESTS / HELP
      test_model()                          Validation battery
      model_help()                          This guide

    Details of any function: ?function_name
    """)
end

"""Minimal battery of sanity tests."""
function test_model()
    println("\n" * "="^70)
    println("VALIDATION TESTS")
    println("="^70)
    passed = 0; total = 0

    total += 1
    try
        d = Department("Test", c = 100, v = 50, e = 1.5)
        @assert abs(d.σ_c + d.σ_v + d.γ - 1.0) < 1e-6
        println("✓ Test 1: valid Department"); passed += 1
    catch e; println("✗ Test 1: $e"); end

    total += 1
    try
        A = create_technical_matrix(5, seed = 1)
        ρ = maximum(abs.(eigvals(A)))
        @assert ρ < 1.0
        println("✓ Test 2: productive matrix (ρ=$(round(ρ, digits=3)))"); passed += 1
    catch e; println("✗ Test 2: $e"); end

    total += 1
    try
        sol, _, _ = simulate_Ndept(3, T = 10.0, seed = 1)
        @assert all(isfinite.(sol[end]))
        println("✓ Test 3: simulation converges"); passed += 1
    catch e; println("✗ Test 3: $e"); end

    total += 1
    try
        A = create_technical_matrix(3, seed = 1)
        λ = compute_labor_values(A, [0.5, 0.4, 0.3])
        @assert all(λ .> 0)
        println("✓ Test 4: positive labor values"); passed += 1
    catch e; println("✗ Test 4: $e"); end

    total += 1
    try
        params = calibrate_portugal_model(year = 2022)
        @assert params.N == 19
        println("✓ Test 5: INE calibration (19 sectors)"); passed += 1
    catch e; println("✗ Test 5: $e"); end

    total += 1
    try
        params, _ = calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic)
        @assert params.N == 3
        println("✓ Test 6: AMECO calibration (synthetic)"); passed += 1
    catch e; println("✗ Test 6: $e"); end

    println("\n" * "="^70)
    println("RESULT: $passed/$total tests passed")
    println("="^70 * "\n")
    return passed == total
end
