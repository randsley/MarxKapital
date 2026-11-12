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

        # Exit friction: still conservative, outflows damped by s/(s+ε),
        # inflows scaled by a common factor, homogeneous of degree 1.
        r, K = [0.1, 0.2, 0.05, 0.3], [10.0, 1.0, 0.01, 5.0]
        m0 = _mobility_flow(r, K, 0.5, 0.0)
        m = _mobility_flow(r, K, 0.5, 0.05)
        @test abs(sum(m)) < 1e-12
        s = K ./ sum(K)
        @test m[m0 .< 0] ≈ m0[m0 .< 0] .* s[m0 .< 0] ./ (s[m0 .< 0] .+ 0.05)
        ratio = m[m0 .> 0] ./ m0[m0 .> 0]
        @test length(ratio) >= 2 && all(ratio .≈ ratio[1]) && 0 < ratio[1] < 1
        @test _mobility_flow(r, 3 .* K, 0.5, 0.05) ≈ 3 .* m
        system_Ndept_io!(dX_with_mobility, X0, merge(p, (exit_friction = 0.05,)), 0.0)
        @test abs(sum(dX_with_mobility[1:N] .- dX_without_mobility[1:N])) < 1e-10
        @test with_parameter(p, :exit_friction, 0.1).exit_friction == 0.1
        @test_throws ErrorException simulate_Ndept(3, T = 1.0, exit_friction = 0.1)
        @test_throws ErrorException simulate_Ndept(3, T = 1.0, coupled = true, exit_friction = -0.1)
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

    @testset "Imported intermediate inputs" begin
        # the domestic table's P1 (gross output) and IMP (imported inputs) rows,
        # by buying industry; two A64 industries map to section C
        dom = DataFrame(prd_ava = ["P1", "P1", "P1", "IMP", "IMP", "IMP", "CPA_A01", "CPA_TOTAL", "B1G"],
                        prd_use = ["CPA_A01", "CPA_C10-12", "CPA_C13-15", "CPA_A01", "CPA_C10-12",
                                   "CPA_C13-15", "CPA_C10-12", "CPA_C10-12", "CPA_A01"],
                        OBS_VALUE = Union{Missing, Float64}[100.0, 150.0, 50.0, 5.0, 20.0, 10.0,
                                                            30.0, 30.0, 60.0])
        push!(dom, ("IMP", "P3_S14", 99.0))     # final use: not an input
        push!(dom, ("IMP", "CPA_A01", missing))
        m = import_coefficients_from_iot(dom, ["A", "C", "F"])
        @test m["A"] ≈ 5 / 100
        @test m["C"] ≈ 30 / 200            # domestic flows and CPA_TOTAL are not imports
        @test !haskey(m, "F")              # no gross output
        # aggregated with the same GVA weights as A's columns, so colsum + m of
        # the aggregate is the weighted mean of the fine colsum + m
        w = Dict("A" => 1.0, "C" => 3.0)
        @test aggregate_import_coefficients(m, [["A", "C"], ["F"]], w) ≈ [(0.05 + 3 * 0.15) / 4, 0.0]
        A_f = [0.1 0.2; 0.3 0.4]
        A_c = aggregate_io_matrix(A_f, ["A", "C"], [["A", "C"]], w)
        m_c = aggregate_import_coefficients(m, [["A", "C"]], w)
        @test sum(A_c) + m_c[1] ≈ (1 * (0.4 + 0.05) + 3 * (0.6 + 0.15)) / 4

        # gross output and admissibility
        p0 = (A = A_f,)
        pm = (A = A_f, import_coefficients = [0.05, 0.15])
        W = [10.0, 20.0]
        @test _gross_output(W, p0) ≈ W ./ (1 .- [0.4, 0.6])
        @test _gross_output(W, pm) ≈ W ./ (1 .- [0.45, 0.75])
        A_ok, r1 = _ensure_output_admissibility(A_f; m = [0.05, 0.15])
        @test A_ok == A_f && !r1
        A_r, r2 = _ensure_output_admissibility(A_f; m = [0.05, 0.5])   # column 2: 0.6 + 0.5
        @test r2 && maximum(vec(sum(A_r, dims = 1)) .+ [0.05, 0.5]) ≈ 0.95
        @test A_r ≈ A_f .* (A_r[1, 1] / A_f[1, 1])                    # uniform, m untouched
        @test_throws ErrorException _ensure_output_admissibility(A_f; m = [0.0, 0.96])

        # in the simulation: m = 0 is the default; invalid uses are refused
        Random.seed!(11); depts = create_departments(4)
        A = create_technical_matrix(4, seed = 3)
        s0, _, _ = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A)
        sz, _, pz = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A,
                                          import_coefficients = zeros(4))
        @test sz.u[end] ≈ s0.u[end] && pz.import_coefficients == zeros(4)
        sm, _, pmi = simulate_Ndept_custom(depts; T = 20.0, coupled = true, rationing = true, A = A,
                                           import_coefficients = fill(0.1, 4))
        X = sm.u[end]
        J = system_jacobian(pmi, X)          # AD through _gross_output with imports
        f = _rhs(pmi); h = 1e-6 .* abs.(X)
        J_fd = reduce(hcat, [(f(X .+ h[j] .* (1:8 .== j)) .- f(X .- h[j] .* (1:8 .== j))) ./ (2h[j]) for j in 1:8])
        @test maximum(abs.(J .- J_fd)) < 1e-4 * maximum(abs.(J))
        @test_throws ErrorException simulate_Ndept_custom(depts; coupled = true, A = A,
                                                          import_coefficients = zeros(4))
        @test_throws ErrorException simulate_Ndept_custom(depts; coupled = true, market_prices = true,
                                                          A = A, import_coefficients = zeros(4))
        @test_throws ErrorException simulate_Ndept_custom(depts; coupled = true, rationing = true,
                                                          A = A, import_coefficients = zeros(3))
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

    @testset "Self-employed imputed by section" begin
        @test _self_employed_ratio(300.0, 100.0) ≈ 3.0
        @test _self_employed_ratio(100.0, 100.0) == 1.0
        @test isnan(_self_employed_ratio(90.0, 100.0))    # more employees than employed
        @test isnan(_self_employed_ratio(10.0, 0.0))
        @test isnan(_self_employed_ratio(NaN, 5.0))
        @test _check_self_employed(:imputed) == :imputed
        @test_throws ArgumentError _check_self_employed(:other)

        comp = Dict("A" => 10.0, "C" => 100.0, "L" => 5.0)
        emp  = Dict("A" => 300.0, "C" => 740.0, "L" => 40.0)
        sal  = Dict("A" => 100.0, "C" => 700.0, "L" => 32.0)
        imp = impute_self_employed(comp, emp, sal, ["A", "C"])
        @test imp["A"] ≈ 30.0 && imp["C"] ≈ 100.0 * 740 / 700
        @test !haskey(imp, "L")                            # only the sections asked for
        @test_throws ErrorException impute_self_employed(comp, emp, Dict("A" => 400.0, "C" => 700.0),
                                                         ["A", "C"])

        # imputing at the fine sections and then aggregating differs from
        # imputing with the aggregate ratio (self-employment is uneven)
        fine = sum(imp[s] for s in ["A", "C"])
        coarse = (comp["A"] + comp["C"]) * (emp["A"] + emp["C"]) / (sal["A"] + sal["C"])
        @test !(fine ≈ coarse)

        # aggregate_sectors carries the employees column when present
        df = DataFrame(nace_code = ["A", "B", "C"], sector = ["a", "b", "c"],
                       GVA = [1.0, 2.0, 3.0], compensation = [0.5, 1.0, 1.5], GOS = [0.5, 1.0, 1.5],
                       CFC = [0.1, 0.2, 0.3], business_income = [0.4, 0.8, 1.2],
                       employment = [3.0, 2.0, 4.0], GFCF = [0.2, 0.3, 0.4],
                       capital_stock = [2.0, 3.0, 4.0], employees = [1.0, 2.0, 3.5])
        dfa, _ = aggregate_sectors(df, zeros(3, 3), [["A"], ["B", "C"]], ["A", "BC"], ["a", "bc"])
        @test dfa.employees == [1.0, 5.5]
        dfn, _ = aggregate_sectors(select(df, Not(:employees)), zeros(3, 3), [["A"], ["B", "C"]],
                                   ["A", "BC"], ["a", "bc"])
        @test !("employees" in names(dfn))

        # the synthetic INE data have no employee counts
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, self_employed = :imputed)
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, self_employed = :other)
    end

    @testset "Market sectors, e window and floor" begin
        # drop_sections removes sections and the groups left empty
        g, kept = drop_sections(NACE_MEDIUM_GROUPS)
        @test kept == [1, 2, 3, 4, 5, 6, 8, 10] && length(g) == 8
        @test !any(s in NON_MARKET_SECTIONS for grp in g for s in grp)
        gm, km = drop_sections(NACE_MACRO_GROUPS)
        @test km == [1, 2, 3] && gm[3] == ["G", "H", "I", "J", "K", "M", "N", "R", "S"]

        # inputs bought from the dropped sections, per unit of gross output
        A = [0.1 0.2 0.0; 0.3 0.1 0.4; 0.05 0.0 0.2]
        oc = outside_input_coefficients(A, ["A", "L", "C"], ["L"])
        @test sort(collect(keys(oc))) == ["A", "C"] && oc["A"] ≈ 0.3 && oc["C"] ≈ 0.4
        keep = [1, 3]
        @test vec(sum(A[keep, keep]; dims = 1)) .+ [oc["A"], oc["C"]] ≈ vec(sum(A[:, keep]; dims = 1))

        # what the dropped industries buy from the kept sections (IOT layout)
        rows = [("CPA_A01", "CPA_O84", 4.0), ("CPA_C10-12", "CPA_P85", 6.0), ("CPA_C13-15", "CPA_Q86", 1.0),
                ("CPA_C10-12", "CPA_C13-15", 50.0),   # market to market: not counted
                ("CPA_O84", "CPA_O84", 9.0),          # within the dropped sections
                ("B1G", "CPA_O84", 99.0),             # value-added row: ignored
                ("CPA_A01", "P3_S13", 7.0)]           # final use: ignored
        df = DataFrame(prd_ava = first.(rows), prd_use = getindex.(rows, 2),
                       OBS_VALUE = Union{Missing, Float64}[last.(rows)...])
        push!(df, ("CPA_A01", "CPA_Q86", missing))
        @test outside_purchases_from_iot(df, NON_MARKET_SECTIONS, ["A", "C", "O"]) == [4.0, 7.0, 9.0]

        # the synthetic calibration with sectors = :market
        Random.seed!(3)
        pm = calibrate_portugal_model(year = 2022, sectors = :market)
        @test pm.N == 15 && size(pm.A) == (15, 15)
        @test isempty(intersect(pm.nace_codes, NON_MARKET_SECTIONS))
        Random.seed!(3)
        pall = calibrate_portugal_model(year = 2022)
        keep = findall(c -> !(c in NON_MARKET_SECTIONS), pall.nace_codes)
        @test pm.A == pall.A[keep, keep]                     # same random A, restricted
        @test pm.e_raw == pall.e_raw[keep]
        pmed = calibrate_portugal_model(year = 2022, sectors = :market, aggregation = :medium)
        @test pmed.N == 8 && pmed.nace_codes == ["A", "BCDE", "F", "GHI", "J", "K", "MN", "RS"]
        @test calibrate_portugal_model(year = 2022, sectors = :market, aggregation = :macro).N == 3

        # the floor is a keyword
        pf = calibrate_portugal_model(year = 2022, e_floor = 0.5)
        @test pf.e == max.(0.5, pf.e_raw) && any(pf.e_raw .< 0.5)
        @test pf.r ≈ pf.e ./ (pf.k .+ 1)
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, e_floor = 0.0)
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, e_floor = -0.1)
        @test_throws ArgumentError estimate_sector_parameters(process_supply_use(generate_synthetic_portugal_data(2022)),
                                                              zeros(19, 19); e_floor = Inf)

        # e over a window: process_supply_use reads the window sums, aggregate_sectors sums them
        d = generate_synthetic_portugal_data(2022).supply_use
        d.compensation_e = 3 .* d.compensation
        d.business_income_e = 2 .* d.business_income
        @test process_supply_use(INEData(2022, d, d, d, d, Dict{String, Any}())).surplus_value_rate ≈
              (2 / 3) .* d.business_income ./ d.compensation
        da, _ = aggregate_sectors(d, zeros(19, 19), NACE_MACRO_GROUPS, ["P", "S", "T"], ["p", "s", "t"])
        @test da.compensation_e ≈ [sum(d.compensation_e[in.(d.nace_code, Ref(g))]) for g in NACE_MACRO_GROUPS]

        # argument checks
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, sectors = :other)
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, e_years = 3)       # synthetic
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, e_years = 0)
        @test_throws ArgumentError calibrate_portugal_model(year = 2022, self_employed = :imputed_hours)
        @test_throws ArgumentError fetch_portugal_eurostat_data(2022; e_years = 0)
        @test_throws ArgumentError fetch_eurostat_sector_hours("PT", 2022; who = :other)

        # hours: only the Portuguese sectoral calibration accepts :imputed_hours
        @test _check_self_employed(:imputed_hours; hours_ok = true) == :imputed_hours
        @test_throws ArgumentError _check_self_employed(:imputed_hours)
        @test_throws ArgumentError calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic,
                                                           self_employed = :imputed_hours)
        raw = DataFrame(geo = ["PT"], section = ["A"], year = [2020], GVA = [1.0], V = [0.5], CFC = [0.1],
                        GFCF = [0.2], capital_stock = [2.0], employment = [3.0], employees = [1.0])
        @test_throws ArgumentError compute_mobility_panel(raw; sections = ["A"], self_employed = :imputed_hours)
        # impute_self_employed works with hours as with persons
        hrs = impute_self_employed(Dict("A" => 10.0), Dict("A" => 425.0), Dict("A" => 190.0), ["A"])
        @test hrs["A"] ≈ 10.0 * 425 / 190
    end

    @testset "Capital mobility estimation" begin
        rng = MersenneTwister(11)
        # demean_fe equals OLS residuals on explicit dummies (unbalanced panel)
        a = repeat(1:4, inner = 6); b = repeat(1:6, outer = 4)
        keep = trues(24); keep[[2, 9, 15, 20]] .= false
        a, b = a[keep], b[keep]
        c = rand(rng, 1:3, length(a))
        v = randn(rng, length(a))
        onehot(g) = Float64[gi == l for gi in g, l in sort(unique(g))]
        for (groups, D) in (((a, b), hcat(ones(length(a)), onehot(a)[:, 2:end], onehot(b)[:, 2:end])),
                            ((a, b, c), hcat(ones(length(a)), onehot(a)[:, 2:end], onehot(b)[:, 2:end],
                                             onehot(c)[:, 2:end])))
            @test demean_fe(v, groups...) ≈ v - D * (D \ v) atol = 1e-9
        end
        @test demean_fe(v, a) ≈ v .- [mean(v[a .== ai]) for ai in a]
        @test _absorbed([repeat(1:5, inner = 7), repeat(1:7, outer = 5)]) == 5 + 7 - 1
        # two countries whose effects never meet: one redundancy per country
        @test _absorbed([[1, 1, 2, 2, 3, 3, 4, 4], [1, 2, 1, 2, 3, 4, 3, 4]]) == 4 + 4 - 2

        # the panel, built per country, from a hand-made two-country extract
        secs, yrs = ["A", "C", "J"], 2000:2005
        raw = DataFrame(geo = String[], section = String[], year = Int[], GVA = Float64[],
                        compensation = Float64[], CFC = Float64[], GFCF = Float64[],
                        capital_stock = Float64[], employment = Float64[], employees = Float64[])
        for g in ("AA", "BB"), s in secs, y in yrs
            K = 100 + 50rand(rng)
            push!(raw, (g, s, y, 20 + 5rand(rng), 8 + 2rand(rng), 0.05K, 0.05K + 3randn(rng), K,
                        12 + rand(rng), 10.0))
        end
        P = compute_mobility_panel(raw; sections = secs)
        @test nrow(P) == 2 * length(secs) * (length(yrs) - 2)
        @test sort(unique(P.year)) == collect(2002:2005)
        for sub in groupby(P, [:geo, :year])                 # Σ R = 0 in every country-year
            @test abs(sum(sub.R)) < 1e-9 * sum(abs, sub.R)
        end
        # one entry by hand: country BB, sector C, 2003
        cell(s, y, col) = raw[(raw.geo .== "BB") .& (raw.section .== s) .& (raw.year .== y), col][1]
        S(s, y) = cell(s, y, :GVA) - cell(s, y, :compensation) - cell(s, y, :CFC)
        rr(s) = S(s, 2002) / (cell(s, 2001, :capital_stock) + cell(s, 2002, :compensation))
        r̄ = sum(rr(s) * cell(s, 2001, :capital_stock) for s in secs) /
             sum(cell(s, 2001, :capital_stock) for s in secs)
        σ = sum(cell(s, 2003, :GFCF) - cell(s, 2003, :CFC) for s in secs) / sum(S(s, 2003) for s in secs)
        R = cell("C", 2003, :GFCF) - cell("C", 2003, :CFC) - σ * S("C", 2003)
        row = P[(P.geo .== "BB") .& (P.section .== "C") .& (P.year .== 2003), :][1, :]
        @test row.gap ≈ 100 * (rr("C") - r̄)
        @test row.y ≈ 100 * R / cell("C", 2002, :capital_stock)
        @test row.σ ≈ σ && row.K == cell("C", 2002, :capital_stock)
        # one country without a geo column is the same panel
        P1 = compute_mobility_panel(select(raw[raw.geo .== "BB", :], Not(:geo)); sections = secs)
        @test P1.y ≈ P[P.geo .== "BB", :y] && all(P1.geo .== "")
        @test compute_mobility_panel(raw; sections = secs, countries = ["AA"]).y ≈ P[P.geo .== "AA", :y]
        Pi = compute_mobility_panel(raw; sections = secs, self_employed = :imputed, own = :lagged)
        @test nrow(Pi) == nrow(P) && !(Pi.y ≈ P.y)
        @test_throws ArgumentError compute_mobility_panel(raw; sections = secs, own = :other)
        @test_throws ArgumentError compute_mobility_panel(select(raw, Not(:geo)); sections = secs,
                                                          countries = ["AA"])
        @test_throws ErrorException compute_mobility_panel(raw[.!((raw.section .== "J") .& (raw.year .== 2003)), :];
                                                           sections = secs)
        @test_throws ErrorException compute_mobility_panel(raw[raw.year .!= 2003, :]; sections = secs)

        # single balanced country: the matrix formulas of notebook 9
        N, T = 15, 22
        Y, X = randn(rng, N, T), randn(rng, N, T) .+ 0.3 .* (1:N)
        Pm = DataFrame(geo = "", section = repeat(string.(1:N), outer = T), year = repeat(1:T, inner = N),
                       y = vec(Y), gap = vec(X))
        tw(M) = M .- mean(M; dims = 2) .- mean(M; dims = 1) .+ mean(M)
        Yd, Xd = tw(Y), tw(X)
        bm = dot(Xd, Yd) / dot(Xd, Xd)
        U = Yd .- bm .* Xd
        h = vec(sum(Xd .* U; dims = 1))
        Sdk = sum(abs2, h) + 2 * sum((1 - l / 3) * sum(h[l+1:end] .* h[1:end-l]) for l in 1:2)
        est = estimate_mobility(Pm; effects = (:section, :year))
        @test est.μ ≈ bm
        @test est.se ≈ sqrt(sum(abs2, U) / (N * T - N - T) / dot(Xd, Xd))
        @test est.se_DK ≈ sqrt(Sdk) / dot(Xd, Xd)
        @test isnan(est.se_cluster) && est.countries == 1
        @test estimate_mobility(Pm).μ ≈ bm                  # default effects, one country
        my, mx = vec(mean(Y; dims = 2)), vec(mean(X; dims = 2))
        Xb = hcat(ones(N), mx); βb = Xb \ my; ub = my - Xb * βb
        btw = estimate_mobility_between(Pm)
        @test btw.μ ≈ βb[2] && btw.se ≈ sqrt(inv(Xb'Xb)[2, 2] * sum(abs2, ub) / (N - 2)) && btw.n == N
        @test_throws ArgumentError estimate_mobility(Pm; effects = (:sector,))

        # synthetic multi-country panel with known μ: country-year shocks move
        # gaps and transfers together, so only country × year effects remove them
        μ0, G, Ns, Ty = 0.25, 8, 10, 25
        rows = DataFrame(geo = String[], section = String[], year = Int[], y = Float64[], gap = Float64[])
        αcs, ψst = randn(rng, G, Ns), randn(rng, Ns, Ty)
        for g in 1:G
            λ = 3 .* randn(rng, Ty)                         # national credit cycle
            load = randn(rng, Ns)                            # sectors exposed to it unequally
            for s in 1:Ns, t in 1:Ty
                gap = αcs[g, s] + load[s] * λ[t] + ψst[s, t] + randn(rng)
                y = μ0 * gap + 2αcs[g, s] + 4λ[t] + 1.5ψst[s, t] + 0.5randn(rng)
                push!(rows, ("G$g", "S$s", 2000 + t, y, gap))
            end
        end
        full = estimate_mobility(rows; effects = (:geo_section, :geo_year, :section_year))
        @test abs(full.μ - μ0) < 4 * full.se_cluster && abs(full.μ - μ0) < 0.05
        @test full.countries == G && full.n == G * Ns * Ty
        @test abs(estimate_mobility(rows; effects = (:geo_section, :year)).μ - μ0) > 0.1
    end

    @testset "Fixed-effects OLS and the investment function" begin
        rng = MersenneTwister(21)
        # estimate_fe_ols equals OLS with explicit dummies (two regressors, unbalanced)
        geo = repeat(["AA", "BB"], inner = 30); sec = repeat(repeat(["s1", "s2", "s3"], inner = 10), 2)
        yr = repeat(1:10, 6)
        keep = trues(60); keep[[4, 17, 33, 48]] .= false
        P = DataFrame(geo = geo[keep], section = sec[keep], year = yr[keep])
        n = nrow(P)
        X = randn(rng, n, 2); y = X * [0.5, -1.0] .+ randn(rng, n)
        e = estimate_fe_ols(P, y, X; effects = (:geo_section, :year))
        onehot(g) = Float64[gi == l for gi in g, l in sort(unique(g))]
        D = hcat(X, onehot(tuple.(P.geo, P.section)), onehot(P.year)[:, 2:end])
        βD = D \ y; uD = y - D * βD
        VD = inv(D'D) .* (sum(abs2, uD) / (n - size(D, 2)))
        @test e.β ≈ βD[1:2]
        @test e.se ≈ sqrt.(diag(VD)[1:2])
        @test e.ssr ≈ sum(abs2, uD)
        @test e.countries == 2 && all(isfinite, e.se_cluster) && all(isfinite, e.se_DK)
        # one regressor: the same as estimate_mobility
        P.y, P.gap = y, X[:, 1]
        m = estimate_mobility(P; effects = (:geo_section, :year))
        e1 = estimate_fe_ols(P, y, X[:, 1]; effects = (:geo_section, :year))
        @test (m.μ, m.se, m.se_DK, m.se_cluster) == (e1.β[1], e1.se[1], e1.se_DK[1], e1.se_cluster[1])
        @test_throws DimensionMismatch estimate_fe_ols(P, y[1:end-1], X)
        @test_throws ErrorException estimate_fe_ols(P, y, hcat(X[:, 1], 2 .* X[:, 1]))   # collinear
        @test_throws ErrorException estimate_fe_ols(P, y, Float64.(length.(P.geo)))  # absorbed by the effects

        # the investment panel, by hand on a two-country extract
        secs, yrs = ["A", "C", "J"], 2000:2005
        raw = DataFrame(geo = String[], section = String[], year = Int[], GVA = Float64[],
                        compensation = Float64[], CFC = Float64[], GFCF = Float64[],
                        capital_stock = Float64[], employment = Float64[], employees = Float64[])
        for g in ("AA", "BB"), s in secs, y in yrs
            K = 100 + 50rand(rng)
            push!(raw, (g, s, y, 20 + 5rand(rng), 8 + 2rand(rng), 0.05K, 0.05K + 3randn(rng), K,
                        12 + rand(rng), 10.0))
        end
        IP = compute_investment_panel(raw; sections = secs)
        @test nrow(IP) == nrow(compute_mobility_panel(raw; sections = secs)) && all(IP.valid)
        cell(s, y, col) = raw[(raw.geo .== "AA") .& (raw.section .== s) .& (raw.year .== y), col][1]
        S(s, y) = cell(s, y, :GVA) - cell(s, y, :compensation) - cell(s, y, :CFC)
        row = IP[(IP.geo .== "AA") .& (IP.section .== "J") .& (IP.year .== 2004), :][1, :]
        @test row.gk ≈ 100 * cell("J", 2004, :GFCF) / cell("J", 2003, :capital_stock)
        @test row.sk ≈ 100 * S("J", 2004) / cell("J", 2003, :capital_stock)
        @test row.gap ≈ 100 * (row.r - row.rbar)
        @test row.σbar ≈ sum(cell("J", y, :GFCF) for y in 2002:2005) / sum(S("J", y) for y in 2002:2005)
        IPi = compute_investment_panel(raw; sections = secs, self_employed = :imputed)
        @test !(IPi.sk ≈ IP.sk)

        # the profile recovers the level, η and μ of data generated by the model's equation
        G, Ns, Ty, η0, μ0 = 8, 10, 25, 0.6, 0.15
        rows = DataFrame(geo = String[], section = String[], year = Int[], gk = Float64[], sk = Float64[],
                         r = Float64[], rbar = Float64[], σbar = Float64[], gap = Float64[], valid = Bool[])
        a = randn(rng, G, Ns); σb = 0.3 .+ 0.2 .* rand(rng, G, Ns)
        for g in 1:G
            b = randn(rng, Ty); rb = 0.1 .* exp.(0.2 .* randn(rng, Ty))
            for s in 1:Ns, t in 1:Ty
                r = rb[t] * exp(0.4 * randn(rng)); sk = 100 * r * 1.4
                gap = 100 * (r - rb[t])
                gk = a[g, s] + b[t] + σb[g, s] * (rb[t] / r)^η0 * sk + μ0 * gap + 0.3 * randn(rng)
                push!(rows, ("G$g", "S$s", 2000 + t, gk, sk, r, rb[t], σb[g, s], gap, true))
            end
        end
        res = estimate_investment_function(rows; η_grid = 0:0.1:1.2)
        k = argmin(res.profile.ssr)
        @test res.profile.η[k] ≈ η0
        @test res.profile.λ[k] ≈ 1 atol = 0.05
        @test res.profile.μ[k] ≈ μ0 atol = 0.03
        @test res.n == G * Ns * Ty && res.dropped == 0
        @test estimate_investment_function(rows; ratio_bounds = (0.8, 1.25)).dropped > 0
        @test_throws ArgumentError estimate_investment_function(rows; η_grid = Float64[])
        @test_throws ArgumentError estimate_investment_function(rows; ratio_bounds = (2.0, 1.0))
    end

    @testset "Incremental rate of profit and persistence" begin
        rng = MersenneTwister(31)
        secs, yrs = ["A", "C", "J"], 2000:2007
        raw = DataFrame(geo = String[], section = String[], year = Int[], GVA = Float64[],
                        compensation = Float64[], CFC = Float64[], GFCF = Float64[],
                        capital_stock = Float64[], employment = Float64[], employees = Float64[],
                        GVA_volume = Float64[], GFCF_volume = Float64[])
        for g in ("AA", "BB"), s in secs, (k, y) in enumerate(yrs)
            K = 100 + 50rand(rng); gva = 20 + 5rand(rng); gfcf = 0.05K + 3rand(rng)
            push!(raw, (g, s, y, gva, 8 + 2rand(rng), 0.05K, gfcf, K, 12 + rand(rng), 10.0,
                        gva / (1 + 0.02k + 0.01rand(rng)), gfcf / (1 + 0.03k)))
        end
        cell(g, s, y, col) = raw[(raw.geo .== g) .& (raw.section .== s) .& (raw.year .== y), col][1]
        Π(g, s, y) = cell(g, s, y, :GVA) - cell(g, s, y, :compensation)
        Πr(g, s, y) = Π(g, s, y) * cell(g, s, y, :GVA_volume) / cell(g, s, y, :GVA)

        # nominal, one year: (Πₜ₋₁ − Πₜ₋₂) / Iₜ₋₂, on the rows of the mobility panel
        r1 = compute_incremental_panel(raw; sections = secs, real = false)
        P1 = r1.panel
        @test r1.dropped == 0 && nrow(P1) == nrow(compute_mobility_panel(raw; sections = secs))
        row = P1[(P1.geo .== "BB") .& (P1.section .== "C") .& (P1.year .== 2005), :][1, :]
        @test row.rI ≈ (Π("BB", "C", 2004) - Π("BB", "C", 2003)) / cell("BB", "C", 2003, :GFCF)
        @test row.gap_I ≈ 100 * (row.rI - row.rIbar)
        # real, three years: deflated profit, investment volumes, backward sums
        r3 = compute_incremental_panel(raw; sections = secs, window = 3)
        P3 = r3.panel
        row = P3[(P3.geo .== "AA") .& (P3.section .== "J") .& (P3.year .== 2006), :][1, :]
        @test row.rI ≈ (Πr("AA", "J", 2005) - Πr("AA", "J", 2002)) /
                       sum(cell("AA", "J", y, :GFCF_volume) for y in 2002:2004)
        @test minimum(P3.year) == 2004 && r3.dropped == 2 * length(secs) * 2
        # the gaps weighted by the investment that defines them sum to zero in each country-year
        for d in groupby(P3, [:geo, :year])
            @test abs(sum(d.I_lag .* d.gap_I)) < 1e-9 * sum(d.I_lag)
        end
        @test !(compute_incremental_panel(raw; sections = secs, self_employed = :imputed,
                                          real = false).panel.rI ≈ P1.rI)
        @test_throws ArgumentError compute_incremental_panel(raw; sections = secs, window = 0)
        @test_throws ArgumentError compute_incremental_panel(select(raw, Not(:GFCF_volume)); sections = secs)

        # Hodrick–Prescott: identity at λ = 0, a straight line is its own trend
        x = randn(rng, 30)
        @test hp_filter(x; λ = 0) ≈ x
        line = 2.0 .+ 0.5 .* (1:30)
        @test hp_filter(line; λ = 1600) ≈ line
        @test std(diff(diff(hp_filter(x; λ = 100)))) < std(diff(diff(x)))
        @test_throws ArgumentError hp_filter(x; λ = -1)

        # persistence: recovers ρ and the permanent positions aᵢ/(1−ρ) of an AR(1) panel
        ρ0, T = 0.5, 400
        rows = DataFrame(geo = String[], section = String[], year = Int[], gap = Float64[])
        a = Dict{Tuple{String, String}, Float64}()
        for g in ("G1", "G2", "G3"), s in ("S1", "S2", "S3", "S4")
            a[(g, s)] = 2randn(rng)
            z = a[(g, s)] / (1 - ρ0)
            for t in 1:T
                z = a[(g, s)] + ρ0 * z + randn(rng)
                push!(rows, (g, s, 1900 + t, z))
            end
        end
        pe = estimate_persistence(rows, :gap)
        @test pe.ρ ≈ ρ0 atol = 0.03
        @test pe.n == nrow(rows) - 12
        for r in eachrow(pe.permanent)
            @test r.p ≈ a[(r.geo, r.section)] / (1 - ρ0) atol = 0.4
        end
        @test 0.5 < pe.between_share < 1
        @test_throws ArgumentError estimate_persistence(rows[1:3, :], :gap)
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
        # the same rule end to end, and the case with no readable release year:
        # nothing can be dropped, so it must warn rather than keep forecasts silently
        y, sr, notes = _apply_forecast_rule(collect(2020:2027),
                                            Dict("GDP_current" => collect(1.0:8.0)), 2026, false)
        @test y == collect(2020:2025) && notes["last_actual_year"] == "2025"
        y, _, notes = _apply_forecast_rule(collect(2020:2027),
                                           Dict("GDP_current" => collect(1.0:8.0)), 2026, true)
        @test y == collect(2020:2027) && !haskey(notes, "last_actual_year")
        y, _, notes = @test_logs (:warn, r"No AMECO release year") _apply_forecast_rule(
            collect(2020:2027), Dict("GDP_current" => collect(1.0:8.0)), 0, false)
        @test y == collect(2020:2027) && isempty(notes)
        @test_logs _apply_forecast_rule(collect(2020:2027), Dict{String, Vector{Float64}}(), 0, true)
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

    @testset "AMECO aggregation method" begin
        # an aggregate (EU27) returns one row per year and aggregation method;
        # the standard aggregation (0) must win, whatever the row order
        agg = DataFrame(AGG_METHOD = [2, 0, 1, 1, 2, 0], TIME_PERIOD = [2000, 2000, 2000, 2001, 2001, 2001],
                        OBS_VALUE = [7348.0, 7885.0, 7743.0, 8100.0, 8000.0, 8200.0])
        @test sort(_select_agg_method(agg).OBS_VALUE) == [7885.0, 8200.0]
        # series with only the growth-rate means (OVGD, PIGT): the euro-weighted one (1)
        @test _select_agg_method(agg[agg.AGG_METHOD .!= 0, :]).OBS_VALUE == [7743.0, 8100.0]
        # a single country, or a response without the column, passes through
        @test nrow(_select_agg_method(agg[agg.AGG_METHOD .== 0, :])) == 2
        @test nrow(_select_agg_method(select(agg, Not(:AGG_METHOD)))) == 6
    end

    @testset "AMECO calibration: capital valuation and self-employed" begin
        # OKND is at constant 2020 prices: with the GFCF deflator at 125 the
        # stock is revalued by 1.25, so k scales by 1.25 and e does not move
        data = generate_synthetic_ameco_data("PT", collect(2015:2020))
        i = findfirst(==(2020), data.years)
        data.GFCF_deflator[i] = 100.0
        p100, _ = calibrate_with_ameco_data(data, 2020, :macro)
        data.GFCF_deflator[i] = 125.0
        p125, _ = calibrate_with_ameco_data(data, 2020, :macro)
        @test p125.k ≈ 1.25 .* p100.k
        @test p125.e ≈ p100.e
        # self-employed imputed: V scales by employment/employees, and the
        # calibration's k matches the :consistent_gfcf time series exactly
        pim, _ = calibrate_with_ameco_data(data, 2020, :macro; self_employed = :imputed)
        ratio = data.employment[i] / data.employees[i]
        @test sum(pim.V) ≈ ratio * sum(p125.V)
        @test pim.e_raw[1] < p125.e_raw[1]
        ts = analyze_time_series_with_data(data; valuation = :consistent_gfcf, self_employed = :imputed)
        @test sum(pim.C) / sum(pim.V) ≈ ts.k[i]
        # :current_cost is the calibration's own valuation: e as at current
        # prices, k as under :consistent_gfcf, and r = e/(1+k)
        cc = analyze_time_series_with_data(data; valuation = :current_cost, self_employed = :imputed)
        cur = analyze_time_series_with_data(data; valuation = :current, self_employed = :imputed)
        @test cc.e ≈ cur.e && cc.wage_share ≈ cur.wage_share
        @test cc.k ≈ ts.k
        @test cc.r ≈ cc.e ./ (1 .+ cc.k)
        @test mean(pim.e_raw) ≈ cc.e[i] && sum(pim.C) / sum(pim.V) ≈ cc.k[i]
        ts0 = analyze_time_series_with_data(data; valuation = :current)
        ts1 = analyze_time_series_with_data(data; valuation = :current, self_employed = :imputed)
        @test ts1.wage_share ≈ ts0.wage_share .* (data.employment ./ data.employees)
        @test_throws ArgumentError calibrate_with_ameco_data(data, 2020, :macro; self_employed = :other)
        @test_throws ArgumentError analyze_time_series_with_data(data; self_employed = :other)
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

    @testset "ODE Hessian through rationing (nested implicit function)" begin
        # Relative steps: under heavy rationing the state spans several orders
        # of magnitude, and a step scaled to max(X) crosses zero in small components.
        function jacobian_fd_rel(f, x; h = 1e-5)
            J = zeros(length(f(x)), length(x))
            for j in eachindex(x)
                hj = h * abs(x[j]); δx = zeros(length(x)); δx[j] = hj
                J[:, j] = (f(x .+ δx) .- f(x .- δx)) ./ (2hj)
            end
            return J
        end
        Random.seed!(7)
        sol, _, p = simulate_Ndept(6, T = 50.0, seed = 7, coupled = true, μ = 0.5, rationing = true)
        X = sol.u[end]
        H = system_hessian(p, X)
        @test size(H) == (12, 12, 12)
        @test maximum(abs.(H .- permutedims(H, (1, 3, 2)))) < 1e-10 * maximum(abs.(H))
        err = maximum(maximum(abs.(H[k, :, :] .- jacobian_fd_rel(x -> system_jacobian(p, x)[k, :], X)))
                      for k in 1:12)
        @test err < 1e-6 * maximum(abs.(H))
        # rationing binds here, so the fixed point's curvature is actually exercised
        C, V = X[1:6], X[7:12]; S = p.e .* V
        x = (p.δ .* C .+ V .+ S) ./ (1 .- vec(sum(p.A, dims = 1)))
        @test count(_solve_rationing(p.A, ones(6), p.σ_c .* S .* x ./ C, x) .< 0.999) >= 2

        # Closed form (paper, Section 3.3): sector 1 supplies only sector 2, so
        # ρ₁ = O₁/(0.5·κ₂·D₂) with κ₂ = ρ₁, i.e. κ₂ = √(2·O₁/D₂)
        A2 = [0.0 0.5; 0.0 0.0]
        κ2(v) = _solve_rationing(A2, [1.0, 1.0], [10.0, v[2]], [v[1], 100.0];
                                 tol = 1e-14, max_iter = 10_000)[2]
        a, b = 2.0, 5.0
        @test κ2([a, b]) ≈ sqrt(2a / b) atol = 1e-10
        H2 = ForwardDiff.hessian(κ2, [a, b])
        H2_exact = sqrt(2) / 4 .* [-a^-1.5 * b^-0.5  -a^-0.5 * b^-1.5;
                                   -a^-0.5 * b^-1.5  3 * a^0.5 * b^-2.5]
        @test H2 ≈ H2_exact rtol = 1e-8
    end

    @testset "Reinvestment share: elasticity η and σ_schedule" begin
        fd_rel(f, x; h = 1e-6) = reduce(hcat, map(eachindex(x)) do j
            hj = h * abs(x[j]); δx = zeros(length(x)); δx[j] = hj
            (f(x .+ δx) .- f(x .- δx)) ./ (2hj)
        end)
        # the defaults leave the parameters and the solution exactly as before
        Random.seed!(3); sol0, _, p0 = simulate_Ndept(5, T = 20.0, seed = 3, coupled = true, μ = 0.3)
        Random.seed!(3); sol1, _, p1 = simulate_Ndept(5, T = 20.0, seed = 3, coupled = true, μ = 0.3,
                                                      η = 0.0, σ_schedule = nothing)
        @test keys(p1) == keys(p0) && sol1.u == sol0.u
        Random.seed!(3); sol2, _, p2 = simulate_Ndept(5, T = 20.0, seed = 3, coupled = true, μ = 0.3,
                                                      σ_schedule = [(0.0, 1.0)])
        @test p2.σ_times == [0.0]
        @test sol2.u[end] ≈ sol0.u[end] rtol = 1e-10
        X = sol0.u[end]
        C, V = X[1:5], X[6:10]
        r = _io_profit_rates(C, V, p0.e .* V, p0)
        @test _reinvestment_share(r, C, p0, 0.0) === p0.σ_c
        # η: above-average sectors reinvest a smaller share, the factor has
        # degree 0, and a uniform profit rate leaves every share unchanged
        pη = merge(p0, (η = 0.7,))
        σe = _reinvestment_share(r, C, pη, 0.0)
        r̄ = sum(r .* C) / sum(C)
        @test σe ≈ p0.σ_c .* (r̄ ./ r) .^ 0.7
        @test all((σe .< p0.σ_c) .== (r .> r̄))
        @test _reinvestment_share(fill(0.1, 5), C, pη, 0.0) ≈ p0.σ_c
        f = _rhs(pη)
        @test f(3 .* X) ≈ 3 .* f(X)                          # homogeneous of degree 1
        @test !(f(X) ≈ _rhs(p0)(X))
        # exact Jacobian, parameter sensitivity, and Hessian (also through rationing)
        @test system_jacobian(pη, X) ≈ fd_rel(f, X) rtol = 1e-6
        gη(θ) = _rhs(merge(p0, (η = θ,)))(X)
        @test parameter_jacobian(pη, X, :η) ≈ (gη(0.7 + 1e-6) .- gη(0.7 - 1e-6)) ./ 2e-6 rtol = 1e-6
        @test length(parameter_jacobian(p0, X, :η)) == 10    # η absent = 0
        Random.seed!(7)
        solr, _, pr = simulate_Ndept(6, T = 50.0, seed = 7, coupled = true, μ = 0.5, rationing = true,
                                     η = 0.7)
        Xr = solr.u[end]
        @test solr.retcode == ReturnCode.Success && pr.η == 0.7
        @test system_jacobian(pr, Xr) ≈ fd_rel(_rhs(pr), Xr) rtol = 1e-5
        H = system_hessian(pr, Xr)
        @test maximum(abs.(H .- permutedims(H, (1, 3, 2)))) < 1e-10 * maximum(abs.(H))
        @test with_parameter(p0, :η, 0.5).η == 0.5

        # the schedule: σ_c multiplied by the multiplier of the last break at or before t
        Random.seed!(3)
        sols, _, ps = simulate_Ndept(5, T = 20.0, seed = 3, coupled = true, μ = 0.3,
                                     σ_schedule = [(5.0, 0.5), (12.0, 0.8)])
        @test sols.retcode == ReturnCode.Success && sols.t[end] == 20.0
        S = ps.e .* V
        fs(t) = (dX = similar(X); system_Ndept_io!(dX, X, ps, t); dX)
        @test fs(4.9) ≈ _rhs(p0)(X)
        @test fs(5.0)[1:5] .- fs(4.9)[1:5] ≈ -0.5 .* ps.σ_c .* S
        @test fs(12.0)[1:5] .- fs(4.9)[1:5] ≈ -0.2 .* ps.σ_c .* S
        @test fs(5.0)[6:10] == fs(4.9)[6:10]                 # V is not affected
        @test !(sols.u[end] ≈ sol0.u[end])
        @test_throws ArgumentError normalized_system(ps)      # not autonomous
        @test_throws ArgumentError simulate_normalized(ps, X)

        # argument checks
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, coupled = true, η = -0.1)
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, η = 0.5)          # uncoupled
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, coupled = true, market_prices = true, η = 0.5)
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, coupled = true, σ_schedule = [(2.0, 1.0), (1.0, 0.5)])
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, coupled = true, σ_schedule = [(1.0, -0.5)])
        @test_throws ArgumentError simulate_Ndept(4, T = 1.0, coupled = true, σ_schedule = Tuple{Float64, Float64}[])
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
