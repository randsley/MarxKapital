# ============================================================================
# Testes do MarxKapital
# ----------------------------------------------------------------------------
# Run:  julia --project=. test/runtests.jl
# ============================================================================

using Test

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

@testset "MarxKapital" begin

    @testset "Estruturas" begin
        d = Department("Teste", c = 1000.0, v = 500.0, e = 1.5)
        @test d.k == 2.0
        @test abs(d.σ_c + d.σ_v + d.γ - 1.0) < 1e-6
        @test profit_rate(d) ≈ 1.5 / 3.0
        @test total_capital(d) == 1500.0
        @test surplus_value(d) == 750.0
    end

    @testset "Technical matrix" begin
        for est in (:random, :triangular, :blocks)
            A = create_technical_matrix(6, structure = est, seed = 1)
            @test maximum(abs.(eigvals(A))) < 1.0
        end
    end

    @testset "2-dept simulation" begin
        sol, depts, p = simulate_2dept(T = 30.0)
        @test length(sol.t) > 0
        @test all(isfinite.(sol[end]))
    end

    @testset "N-dept simulation" begin
        sol, depts, p = simulate_Ndept(7, T = 40.0, seed = 3)
        @test all(isfinite.(sol[end]))
        r = compute_profit_rates(sol, p.e)
        @test size(r) == (7, length(sol.t))
    end

    @testset "Coupled N-dept simulation" begin
        # `seed` in `simulate_Ndept` only fixes the technical matrix A;
        # `create_departments` uses `rand()` without its own seed for e/σ_c/σ_v/δ.
        # Fixing the global RNG here makes the department parameters reproducible too.
        Random.seed!(5)
        sol, depts, p = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5)
        @test all(isfinite.(sol[end]))
        r = compute_price_profit_rates(sol, p)
        @test size(r) == (6, length(sol.t))
        @test std(r[:, end]) < std(r[:, 1])
    end

    @testset "Capital mobility — exact conservation" begin
        # Σᵢ μ(rᵢ-r̄)Cᵢ must be exactly 0 (r̄ weighted by C, not the aggregate
        # ratio ΣS/Σ(C+V)), tested directly on the ODE right-hand side,
        # isolating the mobility term from the reinvestment/depreciation terms.
        Random.seed!(9)
        N = 8
        A = create_technical_matrix(N, seed = 9)
        depts = create_departments(N)
        l = [d.v for d in depts]
        p = (e = [d.e for d in depts], σ_c = [d.σ_c for d in depts],
             σ_v = [d.σ_v for d in depts], δ = [d.δ for d in depts],
             A = A, l = l, R_max = compute_max_profit_rate(A, l),
             μ = 0.5, w = 1.0, realization = false, rationing = false)
        X0 = [[d.c for d in depts]; [d.v for d in depts]]
        dX_without_mobility = similar(X0)
        dX_with_mobility = similar(X0)
        system_Ndept_io!(dX_with_mobility, X0, p, 0.0)
        system_Ndept_io!(dX_without_mobility, X0, merge(p, (μ = 0.0,)), 0.0)
        mobility_term = dX_with_mobility[1:N] .- dX_without_mobility[1:N]
        @test abs(sum(mobility_term)) < 1e-10
        @test !all(iszero, mobility_term)  # the term is active, not trivially zero
    end

    @testset "N-dept simulation with realization pressure" begin
        Random.seed!(5)
        sol_without, _, p_without = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5)
        Random.seed!(5)
        sol_with, _, p_with = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5,
                                          realization = true)
        @test all(isfinite.(sol_with[end]))
        eq = check_equilibrium_Ndept(sol_with, p_with)
        @test 0.0 <= eq.ρ_real <= 1.0
        # the realization factor can only dampen reinvestment (never boost it),
        # so total accumulation cannot exceed that of the system without this pressure
        @test sum(sol_with[end]) <= sum(sol_without[end])
    end

    @testset "Market rationing (fixed point)" begin
        # example with a closed-form solution checked by hand: sector 2 depends on a
        # single supplier (sector 1), which is heavily supply-constrained (O₁=2 vs
        # potential demand of 5); the fixed-point condition reduces to
        # ρ₁ = O₁/(A[1,2]·ρ₁·D₂) ⟹ ρ₁² = O₁/(A[1,2]·D₂) = 2/2.5 = 0.8 ⟹ ρ₁=√0.8
        A = [0.0 0.5; 0.0 0.0]
        σ_c = [0.5, 0.5]
        S = [10.0, 10.0]
        O = [2.0, 100.0]
        κ = _solve_rationing(A, σ_c, S, O)
        @test κ[1] ≈ 1.0                    # sector 1 depends on no one
        @test κ[2] ≈ sqrt(0.8) atol = 1e-6   # sector 2 rationed by the scarce supplier
        @test all(0.0 .<= κ .<= 1.0)
    end

    @testset "Rationing — sensitivity to initial ρ, order and tolerance" begin
        # Checks empirically the practical uniqueness of the fixed point (the
        # antitonicity of the map does not guarantee it in theory; see paper/main.tex)
        # in a regime with genuine rationing (non-trivial, κ<1 for every sector).
        Random.seed!(11)
        N = 12
        A = create_technical_matrix(N, density = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        base = _solve_rationing(A, σ_c, S, O)
        @test count(base .< 0.999) == N   # genuine rationing in every sector

        for _ in 1:20
            ρ0 = rand(N) .* 0.9 .+ 0.1
            κ = _solve_rationing(A, σ_c, S, O; ρ_initial = ρ0)
            @test maximum(abs.(κ .- base)) < 1e-6
        end

        for _ in 1:10
            perm = randperm(N)
            κp = _solve_rationing(A[perm, perm], σ_c[perm], S[perm], O[perm])
            @test maximum(abs.(κp[invperm(perm)] .- base)) < 1e-6
        end
    end

    @testset "N-dept simulation with rationing" begin
        Random.seed!(5)
        sol_without, _, p_without = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5)
        Random.seed!(5)
        sol_with, _, p_with = simulate_Ndept(6, T = 200.0, seed = 5, coupled = true, μ = 0.5,
                                          rationing = true)
        @test all(isfinite.(sol_with[end]))
        # κ ≤ 1 always, so total accumulation cannot exceed that of the system without rationing
        @test sum(sol_with[end]) <= sum(sol_without[end])
    end

    @testset "Reconstructed gross output (x) vs. value-added-type flow (W)" begin
        # x = W/(1-colsum(A)) must exceed W whenever the corresponding column
        # of A is positive (there is circulating intermediate consumption to
        # account for), and equal W exactly when the column is zero (no inputs).
        Random.seed!(5)
        sol_with, _, p_with = simulate_Ndept(6, T = 20.0, seed = 5, coupled = true, μ = 0.5,
                                          rationing = true)
        @test all(isfinite.(sol_with.u[end]))
        eq = check_equilibrium_Ndept(sol_with, p_with)
        N = 6
        final_state = sol_with.u[end]
        C = final_state[1:N]; V = final_state[N+1:2N]
        S = p_with.e .* V
        W = p_with.δ .* C .+ V .+ S
        x = eq.output
        @test all(x .>= W .- 1e-9)
        colsum = vec(sum(p_with.A, dims = 1))
        for j in 1:N
            if colsum[j] ≈ 0.0
                @test x[j] ≈ W[j] atol = 1e-6
            else
                @test x[j] > W[j]
            end
        end
    end

    @testset "Admissibility of the gross output reconstruction" begin
        # Already admissible (all column sums < 0.95): returned unchanged.
        A_ok = [0.0 0.3; 0.2 0.0]
        A_returned, rescaled = _ensure_output_admissibility(A_ok)
        @test A_returned == A_ok
        @test !rescaled

        # Inadmissible (column 2 sum = 1.3 > 0.95): rescaled until the
        # largest column sum is exactly 0.95.
        A_bad = [0.6 0.9; 0.3 0.4]  # colsums = [0.9, 1.3]
        A_corrected, rescaled2 = _ensure_output_admissibility(A_bad)
        @test rescaled2
        @test maximum(vec(sum(A_corrected, dims = 1))) ≈ 0.95 atol = 1e-9
        # the rescaling is uniform (same factor over the whole matrix)
        factor = A_corrected[1, 1] / A_bad[1, 1]
        @test A_corrected ≈ A_bad .* factor

        # End-to-end check: any coupled simulation with
        # rationing/realization built by simulate_Ndept_custom must
        # in practice already satisfy the admissibility condition:
        # not just the isolated helper, but the real pipeline.
        for seed in 1:10
            Random.seed!(seed)
            _, _, p = simulate_Ndept(8, T = 1.0, seed = seed, coupled = true,
                                    rationing = true)
            @test maximum(vec(sum(p.A, dims = 1))) < 1.0
        end
    end

    @testset "Technical matrix aggregation (Leontief)" begin
        A = [0.1 0.2 0.3 0.4; 0.5 0.6 0.7 0.8; 0.1 0.1 0.1 0.1; 0.2 0.2 0.2 0.2]
        sections = ["a", "b", "c", "d"]
        groups = [["a", "b"], ["c", "d"]]
        weights = Dict("a" => 1.0, "b" => 1.0, "c" => 1.0, "d" => 1.0)
        A_coarse = aggregate_io_matrix(A, sections, groups, weights)
        @test size(A_coarse) == (2, 2)
        @test A_coarse ≈ [0.7 1.1; 0.3 0.3]
        @test all(A_coarse .>= 0)
    end

    @testset "Final demand from the IOT" begin
        # hand-built rows in the layout of NAIO_10_CP1700 (product rows prd_ava,
        # use columns prd_use); two A64 products map to section C
        rows = [("CPA_A01", "P3_S14", 10.0), ("CPA_A01", "P3_S15", 2.0), ("CPA_A01", "P3_S13", 0.0),
                ("CPA_A01", "P5", 1.0), ("CPA_A01", "P6", 3.0), ("CPA_A01", "TU", 40.0),
                ("CPA_C10-12", "P3_S14", 20.0), ("CPA_C10-12", "P6", 30.0), ("CPA_C10-12", "TU", 80.0),
                ("CPA_C13-15", "P3_S14", 5.0), ("CPA_C13-15", "P6", 5.0), ("CPA_C13-15", "TU", 20.0),
                ("CPA_C10-12", "CPA_A01", 7.0),   # intermediate flow: not final demand
                ("B1G", "P3_S14", 99.0),          # value-added row: ignored
                ("CPA_A01", "TFU", 16.0)]         # total final use: ignored
        df = DataFrame(prd_ava = first.(rows), prd_use = getindex.(rows, 2),
                       OBS_VALUE = Union{Missing, Float64}[last.(rows)...])
        push!(df, ("CPA_A01", "P6", missing))
        fd = final_demand_from_iot(df, ["A", "C"])
        @test fd.household == [12.0, 25.0]
        @test fd.government == [0.0, 0.0]
        @test fd.investment == [1.0, 0.0]
        @test fd.exports == [3.0, 35.0]
        @test fd.output == [40.0, 100.0]
        @test consumption_basket(fd) ≈ [12, 25] ./ 37
        @test exogenous_demand_share(fd) ≈ [15 / 40, 60 / 100]
        @test exogenous_demand_share(fd; cap = 0.5) ≈ [15 / 40, 0.5]
        fa = aggregate_final_demand(fd, [["A", "C"]], ["ALL"])
        @test fa.sections == ["ALL"] && fa.household == [37.0] && fa.output == [140.0]
    end

    @testset "Real-data options in the simulation" begin
        Random.seed!(11)
        depts = create_departments(4)
        A = create_technical_matrix(4, seed = 3)
        sol, _, p = simulate_Ndept_custom(depts; T = 5.0, coupled = true, A = A)
        @test p.A == A
        # with rationing, φ = 0 is the default; φ > 0 leaves less output to
        # investment, so accumulation can only fall
        Random.seed!(11); depts = create_departments(4)
        s0, _, _ = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A)
        sz, _, _ = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A,
                                         final_demand_share = zeros(4))
        sφ, _, _ = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A,
                                         final_demand_share = fill(0.9, 4))
        @test sz.u[end] ≈ s0.u[end]
        @test sum(sφ.u[end][1:4]) <= sum(s0.u[end][1:4]) + 1e-9
        b = [0.1, 0.2, 0.3, 0.4]
        _, _, pb = simulate_Ndept_custom(depts; T = 1.0, coupled = true, market_prices = true,
                                         A = A, basket = b)
        @test pb.basket == b
        @test_throws ErrorException simulate_Ndept_custom(depts; A = zeros(3, 3))
        @test_throws ErrorException simulate_Ndept_custom(depts; coupled = true,
                                                          final_demand_share = zeros(4))
    end

    @testset "Perpetual inventory capital stock" begin
        # constant GFCF=10, δ=0.2, K₀=100 ⟹ K₁=0.8·100+10=90, K₂=0.8·90+10=82
        gfcf = Dict(2000 => 10.0, 2001 => 10.0, 2002 => 10.0)
        K = compute_pim_capital_stock(gfcf, 0.2, 2000, 100.0, [2000, 2001, 2002])
        @test K[2000] ≈ 100.0
        @test K[2001] ≈ 90.0
        @test K[2002] ≈ 82.0
        # a year without GFCF truncates the series instead of extrapolating
        K2 = compute_pim_capital_stock(Dict(2000 => 10.0), 0.2, 2000, 100.0, [2000, 2001])
        @test !haskey(K2, 2001)
    end

    @testset "Values and prices" begin
        A = create_technical_matrix(4, seed = 2)
        l = [0.6, 0.5, 0.4, 0.3]
        λ = compute_labor_values(A, l)
        @test all(λ .> 0)
        @test all(λ .>= l .- 1e-9)          # include indirect labor
        R_max = compute_max_profit_rate(A, l)
        @test R_max > 0
        p = compute_production_prices(A, l, 1.0, min(0.2, R_max * 0.5))
        @test all(p .> 0)
        @test_throws ErrorException compute_production_prices(A, l, 1.0, R_max * 1.2)
    end

    @testset "Transformation" begin
        res = transformation_problem(4)
        @test haskey(res, :R_max)
        @test -1 <= res.correlation <= 1
    end

    @testset "INE calibration" begin
        params = calibrate_portugal_model(year = 2022)
        @test params.N == 19
        @test size(params.A) == (19, 19)
        @test all(params.e .> 0)
        # e is the raw ratio with a 0.1 floor; e_raw keeps the value before it
        @test params.e == max.(0.1, params.e_raw)
        @test params.r ≈ params.e ./ (params.k .+ 1)
        pa, _ = calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic)
        @test pa.e == max.(0.1, pa.e_raw)
    end

    @testset "Wage-profit frontier" begin
        A = create_technical_matrix(6, seed = 5)
        l = fill(0.4, 6) .+ 0.1 .* (1:6) ./ 6
        curve = wage_profit_curve(A, l, n_points = 60, show_plot = false)
        @test curve.R_max > 0
        @test all(curve.w .> 0)
        @test curve.w[1] >= curve.w[end]    # maximum wage at r=0 (downward-sloping frontier)
    end

    @testset "Wage shock" begin
        depts = create_departments(6)
        res = simulate_wage_shock(depts, 0.15, T = 30.0, show_plot = false, seed = 7)
        @test res.initial_r_impact < 0     # a wage rise cuts immediate profit
    end

    @testset "Synthetic AMECO" begin
        data = generate_synthetic_ameco_data("PT", collect(1995:2022))
        @test length(data.years) == 28
        @test all(data.GDP .> 0)
        params, _ = calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic)
        @test params.N == 3
        # fixed weights: CFC from the AMECO series (not 10% of the stock) and
        # plausible stock shares give positive net surplus in every sector
        @test all(params.e .> 0.1)
        @test all(params.r .> 0)
        @test params.r ≈ params.e ./ (params.k .+ 1)
        @test sum(params.δ .* params.C) ≈ data.CFC[end]
        comp = compare_ameco_countries(["Portugal", "Greece"], year = 2022)
        @test all(0 .< comp.table.Wage_Share .< 100)
        @test comp.table.GDP[1] ≈ round(data.GDP[end] / 1000, digits = 1)
    end

    @testset "AMECO forecast years" begin
        @test _release_year("03/06/26 09:37:05") == 2026
        @test _release_year("15/11/2027 10:00:00") == 2027
        @test _release_year("2026-06-03T09:37:05") == 2026
        @test _release_year("n/a") === nothing
        # the 2026 release forecasts 2026 and 2027: both are dropped
        years, series = _drop_forecast_years(collect(2020:2027),
                                             Dict("GDP_current" => collect(1.0:8.0)), 2026)
        @test years == collect(2020:2025)
        @test series["GDP_current"] == collect(1.0:6.0)
        # a calibration year beyond the last actual year falls back to it
        data = generate_synthetic_ameco_data("PT", collect(1995:2020))
        data.notes["last_actual_year"] = "2020"
        params, _ = calibrate_with_ameco_data(data, 2022, :macro)
        p2020, _ = calibrate_with_ameco_data(data, 2020, :macro)
        @test params.GVA ≈ p2020.GVA
        # without the note (no forecast information) an unknown year is still an error
        delete!(data.notes, "last_actual_year")
        @test_throws ErrorException calibrate_with_ameco_data(data, 2022, :macro)
    end

    @testset "AMECO time series — consistent vs. current valuation" begin
        # Hand-worked case: GDP_current=200, real_GDP=100 (GDP_deflator=200);
        # compensation=80, CFC=20 (both at current prices); C=400 (stock,
        # already at constant prices). GFCF_deflator=400 (a distinct index, to
        # test sensitivity to the chosen deflator).
        z = fill(0.0, 1)
        data = AMECOData(
            "Teste", "TST", [2020],
            fill(200.0, 1), fill(100.0, 1), z, z, z, z, z,       # PIB, real_GDP, ...
            z, z, z, z,                                          # labor market
            fill(80.0, 1), z, z,                                 # compensation, productivity, costs
            fill(200.0, 1), fill(400.0, 1), z, fill(20.0, 1),    # GDP_deflator, GFCF_deflator, CPI, CFC
            z, z, z, z,                                          # public finances
            z, z,                                                # external sector
            fill(400.0, 1),                                      # total_capital_stock
            "test", now(), Dict{String, String}())

        st_current = analyze_time_series_with_data(data; valuation = :current)
        st_consistent = analyze_time_series_with_data(data; valuation = :consistent)
        st_gfcf = analyze_time_series_with_data(data; valuation = :consistent_gfcf)

        @test st_current.k[1] ≈ 400.0 / 80.0
        @test st_consistent.k[1] ≈ 400.0 / 40.0  # 80 deflated by 200/100
        @test st_consistent.k[1] ≈ 2 * st_current.k[1]
        @test st_gfcf.k[1] ≈ 400.0 / 20.0          # 80 deflated by 400/100
        @test st_gfcf.k[1] ≈ 4 * st_current.k[1]

        # The (GVA-V)/V part of e is algebraically invariant under a common
        # deflator applied to V and GVA (CFC is deflated by the same index as
        # V, preserving that invariance); this confirms the algebra: dividing
        # both by a common factor does not change the ratio (Y-V)/V.
        @test st_current.e[1] ≈ (200.0 - 80.0 - 20.0) / 80.0  # = 1.25
        @test st_consistent.e[1] ≈ st_current.e[1]
        # :consistent_gfcf uses a different index (GFCF_deflator) for V and
        # CFC but keeps real_GDP (deflated by GDP_deflator) for GVA: they are
        # not on the same basis, so the invariance does NOT apply here, on
        # purpose (this is precisely the deflator sensitivity test).
        @test !(st_gfcf.e[1] ≈ st_current.e[1])
    end

    # Central finite differences, an independent reference for automatic differentiation.
    function jacobian_fd(f, x; h = 1e-6)
        f0 = f(x)
        J = zeros(length(f0), length(x))
        for j in eachindex(x)
            δx = zeros(length(x)); δx[j] = h
            J[:, j] = (f(x .+ δx) .- f(x .- δx)) ./ (2h)
        end
        return J
    end

    @testset "Exact ODE Jacobian (AD vs. finite differences)" begin
        for (realization, rationing) in ((false, false), (true, false), (false, true))
            Random.seed!(5)
            sol, _, p = simulate_Ndept(6, T = 50.0, seed = 5, coupled = true, μ = 0.5,
                                      realization = realization, rationing = rationing)
            X = sol.u[end]
            J = system_jacobian(p, X)
            J_df = jacobian_fd(_rhs(p), X; h = 1e-4 * maximum(X))
            @test size(J) == (12, 12)
            @test maximum(abs.(J .- J_df)) / maximum(abs.(J)) < 1e-2
        end
        Random.seed!(3)
        sol, _, p = simulate_Ndept(5, T = 20.0, seed = 3)
        X = sol.u[end]   # linear system: finite differences exact up to rounding
        @test system_jacobian(p, X) ≈ jacobian_fd(_rhs(p), X; h = 1e-3 * maximum(X)) rtol = 1e-8
        @test size(parameter_jacobian(p, X, :e)) == (10, 5)
    end

    @testset "ODE Hessian" begin
        Random.seed!(5)
        sol, _, p = simulate_Ndept(4, T = 20.0, seed = 5, coupled = true, μ = 0.5)
        X = sol.u[end]
        H = system_hessian(p, X)
        @test size(H) == (8, 8, 8)
        @test maximum(abs.(H .- permutedims(H, (1, 3, 2)))) < 1e-8 * max(1, maximum(abs.(H)))
        # row k of the Hessian = Jacobian of ∂f_k/∂X
        H_df = jacobian_fd(x -> system_jacobian(p, x)[1, :], X; h = 1e-4 * maximum(X))
        @test maximum(abs.(H[1, :, :] .- H_df)) <= 1e-3 * max(1e-12, maximum(abs.(H[1, :, :])))
    end

    @testset "Rationing Jacobian — 2-sector example" begin
        # Section 3.3 of the paper: a single active eigenvalue λ = −1. Sector 2 is
        # not rationed (λ = 0), hence α_max = 1 (flip in the undamped iteration) and
        # the minimax α is 2/3 = DEFAULT_RELAXATION (not 1/2: the λ = 0 mode decays as |1−α|).
        jr = rationing_jacobian([0.0 0.5; 0.0 0.0], [0.5, 0.5], [10.0, 10.0], [2.0, 100.0])
        @test jr.ρ[1] ≈ sqrt(0.8) atol = 1e-9
        @test sort(real.(jr.eigenvalues)) ≈ [-1.0, 0.0] atol = 1e-9
        @test jr.antitone
        @test jr.α_max ≈ 1.0 atol = 1e-9
        @test jr.α_optimal ≈ 2 / 3 atol = 1e-6
        @test jr.α_optimal ≈ DEFAULT_RELAXATION atol = 1e-6
        @test jr.spectral_radius ≈ 1 / 3 atol = 1e-9    # max(|1−α|, |1−2α|) with α = 2/3
        # α = 0.5 cancels the λ = −1 mode, but the λ = 0 mode stays at 0.5
        @test damped_spectral_radius(jr.eigenvalues, 0.5) ≈ 0.5 atol = 1e-9
        @test jr.local_convergence
    end

    @testset "Rationing — structural λ = −1 and closed form" begin
        Random.seed!(11)
        N = 12
        A = create_technical_matrix(N, density = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        jr = rationing_jacobian(A, σ_c, S, O)
        @test jr.antitone
        @test minimum(abs.(jr.eigenvalues .+ 1)) < 1e-9
        k = argmin(jr.ρ)
        @test jr.J[k, :] ≈ -[i == k ? 1.0 : 0.0 for i in 1:N] atol = 1e-9
        L_k = sum(A[k, :] .* σ_c .* S)
        @test jr.ρ[k] ≈ sqrt(O[k] / L_k) atol = 1e-9
        @test jr.α_max <= 1 + 1e-9
        # J is triangular with sectors ordered by ρ* (J_ik ≠ 0 only if ρ_k ≤ ρ_i):
        # eigenvalues = diagonal, real and in [−1, 0].
        order = sortperm(jr.ρ)
        Jo = jr.J[order, order]
        @test all(abs(Jo[i, j]) < 1e-10 for i in 1:N, j in 1:N if j > i)
        @test sort(real.(jr.eigenvalues)) ≈ sort(diag(jr.J)) atol = 1e-10
        @test all(-1 - 1e-10 .<= real.(jr.eigenvalues) .<= 1e-10)
        @test jr.spectral_radius ≈ 1 / 3 atol = 1e-9
    end

    @testset "Derivative of the rationing fixed point (implicit function)" begin
        Random.seed!(11)
        N = 12
        A = create_technical_matrix(N, density = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        f(o) = _solve_rationing(A, σ_c, S, o; tol = 1e-13, max_iter = 10_000)
        J = ForwardDiff.jacobian(f, O)
        @test J ≈ jacobian_fd(f, O) rtol = 1e-6
    end

    @testset "Curvature of the wage-profit frontier (closed form)" begin
        # If l is an eigenvector of Aᵀ with eigenvalue λ, w(r) = (1/(1+r) − λ)/l₁,
        # donde w''(r) = 2/((1+r)³·l₁).
        A = [0.20 0.10 0.05; 0.10 0.30 0.10; 0.05 0.10 0.20]   # irreducible: PF vector > 0
        vals, vecs = eigen(Matrix(A'))
        k = argmax(real.(vals))
        l = abs.(real.(vecs[:, k]))
        λ = real(vals[k])
        c = frontier_curvature(A, l, 0.2)
        @test c.w ≈ (1 / 1.2 - λ) / l[1]
        @test c.dw ≈ -1 / (1.2^2 * l[1])
        @test c.d2w ≈ 2 / (1.2^3 * l[1])
        @test c.shape == :convex
    end

    @testset "TSSI — invariants and convergence" begin
        Random.seed!(5)
        sol, _, p = simulate_Ndept(6, T = 60.0, seed = 5, coupled = true, μ = 0.5,
                                  realization = true)
        v = tssi_valuation(sol, p; τ = 1.0, h = 0.5)
        @test v.invariance_error < 1e-12
        @test length(v.r_tssi) == length(v.t)
        @test all(v.r_tssi .> 0)
        # τ must be a multiple of h
        @test_throws ErrorException tssi_valuation(sol, p; τ = 0.7, h = 0.5)

        # With frozen data, TSSI prices converge to the simultaneist ones,
        # at the rate given by the spectral radius of the exact Jacobian.
        d = tssi_data(sol.u[end], p)
        est = tssi_stability(d; τ = 2.0)
        @test est.stable
        @test est.convergence_rate ≈ log(est.spectral_radius) / 2.0
        q = ones(6)
        for _ in 1:300
            q = tssi_map(q, d).p
        end
        @test q ≈ est.p★ rtol = 1e-10
        # J in closed form: [(1+r)I − r·c·xᵀ/(xᵀc)]·Aᵀ
        c = d.A' * est.p★ .+ d.d .+ d.v
        J_closed = ((1 + est.r★) .* identity_matrix(6) .- est.r★ .* (c * d.x') ./ sum(d.x .* c)) * d.A'
        @test est.J ≈ J_closed rtol = 1e-10
        # Fixed point ⇒ TSSI and simultaneism coincide.
        step = tssi_map(est.p★, d)
        @test step.r ≈ est.r★

        # Historical-cost depreciation: invariants still hold, and the book
        # value of a stock bought at constant prices equals its value at
        # those prices.
        vh = tssi_valuation(sol, p; τ = 1.0, h = 0.5, depreciation = :historical)
        @test vh.invariance_error < 1e-12
        @test size(vh.book_value) == (6, length(vh.t))
        @test all(vh.book_value .> 0)
        @test vh.r_simultaneous ≈ v.r_simultaneous
        @test_throws ErrorException tssi_valuation(sol, p; τ = 1.0, h = 0.5,
                                                   depreciation = :replacement)
        Ab = [0.2 0.0; 0.2 0.0]                          # column 2 empty: mean price
        @test _capital_goods_price([1.0, 3.0], Ab) ≈ [2.0, 2.0]
        K, C0, C1, δ = [2.0, 4.0], [1.0, 2.0], [1.5, 1.0], [0.1, 0.1]
        K1 = _book_value_step(K, C0, C1, δ, 0.5, [2.0, 2.0])
        @test K1 ≈ 2.0 .* C1                             # gross investment and disinvestment
    end

    @testset "Bifurcations — rationing" begin
        Random.seed!(11)
        N = 12
        A = create_technical_matrix(N, density = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        br = rationing_bifurcation(A, σ_c, S, O; scale = (0.005, 2.0))
        @test isempty(br.points)                        # α = 2/3 stable along the whole branch
        @test all(br.radius .< 1)
        @test br.α_max[1] ≈ 2.0                          # no rationing: F constant
        @test all(br.α_max[br.rationed_fraction .> 0] .<= 1 + 1e-9)
        @test br.rationed_fraction[end] == 1.0
        k = length(br.θ)
        diag = _solve_rationing(A, ones(N), br.θ[k] .* σ_c .* S, O; tol = 1e-12,
                                      max_iter = 10_000, return_diagnostics = true)
        @test diag.ρ ≈ br.z[:, k] atol = 1e-8

        # α > 1: flip (period doubling) at the onset of rationing, at
        # s_c = minᵢ Oᵢ/Lᵢ (Lᵢ = demand without rationing), a border collision,
        # located to the resolution of the continuation step (dsmax = 0.05).
        s_c = minimum(O ./ (A * (σ_c .* S)))
        @test br.θ[findfirst(br.rationed_fraction .> 0)] >= s_c - 1e-9
        br_flip = rationing_bifurcation(A, σ_c, S, O; scale = (0.005, 2.0), relaxation = 1.1)
        @test !isempty(br_flip.points)
        @test br_flip.points[1].kind == :flip
        @test br_flip.points[1].θ ≈ s_c atol = 0.05
    end

    @testset "Bifurcations — TSSI prices (fixed τ)" begin
        Random.seed!(5)
        sol, _, p = simulate_Ndept(6, T = 60.0, seed = 5, coupled = true, μ = 0.5,
                                  realization = true)
        bt = tssi_bifurcation(sol.u[end], p; τ = 1.0, scale = (0.05, 10.0))
        @test bt.θ[end] ≈ 10.0
        @test all(bt.radius .< 1)
        @test isempty(bt.points)
        @test issorted(bt.r★)                            # r★ grows with surplus value
        @test all(bt.r★ .< p.R_max)
    end

    @testset "Mobility of variable capital (μ_v)" begin
        Random.seed!(3)
        sol0, _, p0 = simulate_Ndept(4, T = 5.0, seed = 3, coupled = true, μ = 0.5)
        Random.seed!(3)
        sol1, _, _ = simulate_Ndept(4, T = 5.0, seed = 3, coupled = true, μ = 0.5, μ_v = 0.0)
        @test sol0.u[end] == sol1.u[end]                 # μ_v = 0: no change
        X = sol0.u[end]
        N = 4
        f0 = similar(X); system_Ndept_io!(f0, X, p0, 0.0)
        f1 = similar(X); system_Ndept_io!(f1, X, merge(p0, (μ_v = 0.7,)), 0.0)
        @test sum(f1[N+1:2N]) ≈ sum(f0[N+1:2N]) rtol = 1e-12   # the term sums to 0
        @test f1[1:N] == f0[1:N]
        # homogeneity of degree 1 (Euler): J·X = f(X)
        pv = merge(p0, (μ_v = 0.7,))
        @test system_jacobian(pv, X) * X ≈ f1 rtol = 1e-9
    end

    @testset "Cross-dual system — identities" begin
        Random.seed!(2)
        sol, _, p = simulate_Ndept(3, T = 1.0, seed = 2, coupled = true, μ = 0.5,
                                  market_prices = true)
        X = sol.u[end] .+ [zeros(6); [0.1, -0.2, 0.05]]
        C, V, q = X[1:3], X[4:6], X[7:9]
        ec = cross_dual_state(C, V, q, p)
        @test sum(ec.P .* ec.demand) ≈ sum(ec.P .* ec.x) rtol = 1e-12   # Walras' law
        @test sum(ec.Π) ≈ sum(p.e .* V) rtol = 1e-12                      # ΣΠ = ΣS
        ec2 = cross_dual_state(C, V, q .+ 0.3, p)
        @test ec2.P ≈ ec.P rtol = 1e-12                                     # relative prices only
        f = similar(X); cross_dual_system!(f, X, p, 0.0)
        f2 = similar(X); cross_dual_system!(f2, [2 .* X[1:6]; q], p, 0.0)
        @test f2 ≈ [2 .* f[1:6]; f[7:9]] rtol = 1e-12                      # homogeneidade
        @test_throws ErrorException simulate_Ndept(3, T = 1.0, seed = 2, coupled = true,
                                                  market_prices = true, realization = true)
    end

    @testset "Balanced growth" begin
        Random.seed!(2)
        sol, _, p = simulate_Ndept(3, T = 1.0, seed = 2, coupled = true, μ = 0.5,
                                  market_prices = true)
        eq = balanced_growth(p, sol.u[1])
        @test eq.converged && eq.stable
        @test minimum(eq.X[1:6]) > 0
        # the ray grows at exactly g★ in the ODE in levels
        s = solve(ODEProblem(cross_dual_system!, eq.X, (0.0, 20.0), p), Tsit5(),
                  abstol = 1e-11, reltol = 1e-11)
        @test log(sum(s.u[end][1:6]) / sum(s.u[1][1:6])) / 20 ≈ eq.g rtol = 1e-7
        @test s.u[end][1:6] ./ sum(s.u[end][1:6]) ≈ eq.X[1:6] rtol = 1e-7
        # and is the limit of a long simulation
        ys = simulate_normalized(p, sol.u[1]; T = 1500.0, saveat = 1500.0)
        @test ys.u[end][1:6] ≈ eq.X[1:6] rtol = 1e-5
        # TSSI = simultaneism on the balanced-growth ray
        v = tssi_valuation(s, p; τ = 1.0, h = 0.5)
        @test v.r_tssi[end] ≈ v.r_simultaneous[end] rtol = 1e-10
        # wage share: g and r fall with ω
        vs = wage_sweep(p, sol.u[1]; values = 0.3:0.1:0.6)
        @test all(vs.converged) && all(vs.stable)
        @test vs.ω ≈ collect(0.3:0.1:0.6)
        @test issorted(vs.g; rev = true) && issorted(vs.r; rev = true)
    end

    @testset "Hopf bifurcation and accumulation limit cycles" begin
        Random.seed!(2)
        sol, _, p0 = simulate_Ndept(3, T = 1.0, seed = 2, coupled = true, μ = 0.5,
                                   market_prices = true)
        p = merge(p0, (β = 0.1,))
        r = accumulation_bifurcation(p, sol.u[1], :μ_v; interval = (0.0, 2.0),
                                  orbit_interval = (0.0, 1.3), Ntst = 20)
        @test r.max_real_part[1] < 0
        H = r.hopf[1]
        @test H.supercritical && H.transversality > 0
        # two close Hopf points (≈ 1.220 and 1.232): both detected with dsmax = 0.01
        @test count(pt -> pt.kind == :hopf && pt.θ < 1.24, r.points) == 2
        k = findfirst(>(H.θ), r.θ)
        @test r.max_real_part[k-2] < 0 < r.max_real_part[k+1]
        o = r.orbits
        @test o.θ[1] ≈ H.θ atol = 1e-6
        @test o.amplitude[1] < 1e-2                          # born with amplitude 0
        @test o.period[1] ≈ H.period rtol = 1e-3
        @test o.stable[2]                                   # supercritical: stable cycle
        # cycle confirmed by direct simulation
        θ = 1.225
        k = argmin(abs.(o.θ .- θ))
        cs = simulated_cycle(p, :μ_v, o.θ[k], sol.u[1]; T = 6000.0)
        @test cs.section_dispersion < 1e-2
        @test cs.T_min ≈ o.period[k] rtol = 1e-2
        @test cs.amplitude ≈ o.amplitude[k] rtol = 0.1    # coarse collocation (Ntst = 20)
        # and convergence to equilibrium before the Hopf
        @test simulated_cycle(p, :μ_v, H.θ - 0.1, sol.u[1]; T = 3000.0).amplitude < 1e-4
    end

    @testset "Lyapunov exponents and hysteresis" begin
        Random.seed!(5)
        sol, _, p0 = simulate_Ndept(6, T = 1.0, seed = 5, coupled = true, μ = 0.5,
                                   market_prices = true)
        p = merge(p0, (β = 0.1,))
        # limit cycle: (0, −, −)
        cycle = lyapunov_exponents(p, :μ_v, 1.1, sol.u[1]; T_transient = 2000.0, T = 4000.0)
        @test abs(cycle.λ[1]) < 1e-3
        @test cycle.λ[2] < -3e-3
        # irregular regime: one positive exponent and the flow one ≈ 0 (chaos)
        chaos = lyapunov_exponents(p, :μ_v, 1.9, sol.u[1]; T_transient = 2000.0, T = 6000.0)
        @test chaos.λ[1] > 0.015
        @test abs(chaos.λ[2]) < 6e-3                 # finite estimate, CPU-sensitive
        # coexistence: sweeping up reaches the torus, sweeping down keeps the cycle
        hs = simulated_hysteresis(p, :μ_v, [1.40, 1.46], sol.u[1]; T_transient = 2000.0,
                                T = 1500.0)
        @test hs.up.class == [:irregular, :cycle]
        @test hs.down.class == [:cycle, :cycle]
        @test hs.coexistence == [1.40]
    end

    @testset "Internal battery" begin
        @test test_model()
    end
end
