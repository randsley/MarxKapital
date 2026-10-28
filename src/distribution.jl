# ============================================================================
# DISTRIBUTIONAL ANALYSIS AND CALIBRATION VALIDATION
# ============================================================================

"""
    wage_profit_curve(A, l; n_points=100, show_plot=true)

Frontier of distributional possibilities (w-r curve): the trade-off between
the real wage and the profit rate set by the technology. Good 1 is the
numeraire (p₁ = 1).
"""
function wage_profit_curve(A, l; n_points = 100, show_plot = true)
    println("\n" * "="^70)
    println("FRONTIER OF DISTRIBUTIONAL POSSIBILITIES")
    println("="^70)

    N = size(A, 1)
    R_max = compute_max_profit_rate(A, l)
    println("\nMaximum profit rate (w=0): $(round(R_max*100, digits=2))%")

    r_values = range(0, R_max * 0.99, length = n_points)
    w_values = zeros(n_points)
    p_matrix = zeros(N, n_points)

    for (i, r) in enumerate(r_values)
        p_temp = compute_production_prices(A, l, 1.0, r)
        w_values[i] = 1.0 / p_temp[1]
        p_matrix[:, i] = p_temp / p_temp[1]
    end

    w_max = w_values[1]
    println("Maximum wage (r=0): $(round(w_max, digits=4))")

    dw_dr = diff(w_values) ./ diff(r_values)
    r_mid = (r_values[1:end-1] + r_values[2:end]) / 2
    w_mid = (w_values[1:end-1] + w_values[2:end]) / 2
    elasticity = dw_dr .* (r_mid ./ w_mid)
    mean_elasticity = mean(elasticity)
    println("Mean elasticity ε(w,r): $(round(mean_elasticity, digits=3))")

    if show_plot
        p1 = plot(r_values * 100, w_values, xlabel = "Profit Rate r (%)",
                  ylabel = "Real Wage w", title = "Wage-Profit Frontier w-r",
                  label = "Curve w(r)", lw = 3, color = :blue, legend = :topright)
        scatter!([0, R_max * 100 * 0.99], [w_max, w_values[end]],
                 label = "", markersize = 6, color = :red)

        p2 = plot(r_mid * 100, elasticity, xlabel = "Profit Rate r (%)",
                  ylabel = "Elasticity ε(w,r)", title = "Elasticity",
                  label = "ε = (dw/dr)·(r/w)", lw = 2, color = :purple)
        hline!([mean_elasticity], linestyle = :dash, color = :red, label = "Mean")

        p3 = plot(xlabel = "Profit Rate r (%)", ylabel = "Relative Price",
                  title = "Price Paths", legend = :outertopright)
        for i in 1:min(N, 5)
            plot!(r_values * 100, p_matrix[i, :], label = "Good $i", lw = 2, alpha = 0.7)
        end

        p4 = plot(w_values, r_values * 100, xlabel = "Real Wage w",
                  ylabel = "Profit Rate r (%)", title = "Phase Space",
                  label = "", lw = 2, color = :green)

        plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000))
        display(plt)
    end

    return (r = r_values, w = w_values, R_max = R_max, w_max = w_max,
            mean_elasticity = mean_elasticity, elasticity = elasticity,
            prices = p_matrix)
end

"""
    validate_calibrated_profit_rates(params)

Checks whether the calibrated profit rates are theoretically feasible
(within the technological bound R_max), assesses their dispersion,
consistency and position on the frontier, and returns a quality score in
[0, 100].
"""
function validate_calibrated_profit_rates(params::CalibratedParameters)
    println("\n" * "="^70)
    println("PROFIT RATE VALIDATION")
    println("="^70)
    println("\nBase year: $(params.base_year)  |  Sectors: $(params.N)")

    R_max = compute_max_profit_rate(params.A, params.l)

    r_mean   = mean(params.r)
    r_median = median(params.r)
    r_std     = std(params.r)

    println("\n📊 STATISTICS")
    println("-"^70)
    println("  Mean:     $(round(r_mean*100, digits=2))%")
    println("  Median:   $(round(r_median*100, digits=2))%")
    println("  Min/Max:  $(round(minimum(params.r)*100, digits=2))% / $(round(maximum(params.r)*100, digits=2))%")
    println("  Standard deviation: $(round(r_std*100, digits=2))pp")
    println("  Coef. of variation: $(round(r_std/r_mean, digits=3))")
    println("\n⚙️  Theoretical maximum rate (R_max): $(round(R_max*100, digits=2))%")

    # Test 1: feasibility of the mean
    feasible_mean = r_mean < R_max
    mean_margin = (R_max - r_mean) / R_max * 100
    println("\n🔍 TEST 1: Feasibility of the Mean Rate")
    if feasible_mean
        println("  ✓ Feasible, margin: $(round(mean_margin, digits=1))%")
        mean_margin < 10 && println("  ⚠️  Small margin, close to the bound")
    else
        println("  ✗ Exceeds the maximum (possible rent/monopoly, or A underestimated)")
    end

    # Test 2: sectoral feasibility
    problem_sectors = findall(params.r .>= R_max)
    println("\n🔍 TEST 2: Sectoral Feasibility")
    if isempty(problem_sectors)
        println("  ✓ All sectors within the bound")
    else
        println("  ✗ $(length(problem_sectors)) sectors exceed R_max")
        for idx in problem_sectors
            println("    • $(params.sector_names[idx]): $(round(params.r[idx]*100, digits=1))%")
        end
    end

    # Test 3: dispersion
    cv = r_std / r_mean
    println("\n🔍 TEST 3: Dispersion (CV = $(round(cv, digits=2)))")
    println(cv < 0.3 ? "  ✓ Low" : cv < 0.6 ? "  ⚠️  Moderate" : "  ✗ High")
    z = (params.r .- r_mean) / r_std
    high_outliers = findall(z .> 2)
    if !isempty(high_outliers)
        println("  Abnormally high profits (>2σ):")
        for idx in high_outliers
            println("    • $(params.sector_names[idx]): $(round(params.r[idx]*100, digits=1))%")
        end
    end

    # Test 4: consistency
    k_mean = mean(params.k)
    e_implied = r_mean * (k_mean + 1)
    println("\n🔍 TEST 4: Consistency")
    println("  mean k = $(round(k_mean, digits=2))  →  implied e = $(round(e_implied, digits=2))")
    println(0.5 < e_implied < 3.0 ? "  ✓ Reasonable" : "  ⚠️  Outside the expected range")

    # Test 5: position on the frontier
    r_position = r_mean / R_max * 100
    println("\n🔍 TEST 5: Position on the Frontier: $(round(r_position, digits=1))% of R_max")
    println(r_position < 30 ? "  → Low profit rate" :
            r_position < 70 ? "  → Intermediate zone" : "  → High profit rate")

    # Plots (no boxplot, so it works without StatsPlots)
    p1 = histogram(params.r * 100, bins = 15, xlabel = "Profit Rate (%)",
                   ylabel = "Frequency", title = "Distribution", label = "",
                   alpha = 0.7, color = :steelblue)
    vline!([r_mean * 100], color = :red, lw = 2, linestyle = :dash, label = "Mean")
    vline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max")

    p2 = scatter(params.k, params.r * 100, xlabel = "Organic Composition k",
                 ylabel = "Profit Rate r (%)", title = "r-k Relation",
                 label = "", markersize = 6, alpha = 0.7)
    k_range = range(minimum(params.k), maximum(params.k), length = 100)
    plot!(k_range, e_implied ./ (k_range .+ 1) * 100, color = :red, lw = 2,
          linestyle = :dash, label = "Theoretical")

    order = sortperm(params.r, rev = true)
    top5 = order[1:min(5, params.N)]
    bottom5 = order[max(1, params.N - 4):params.N]
    name_list = [params.sector_names[top5]; params.sector_names[bottom5]]
    values = [params.r[top5]; params.r[bottom5]] * 100
    p3 = bar(name_list, values, xlabel = "Sector", ylabel = "Profit Rate (%)",
             title = "Top/Bottom 5", legend = false, orientation = :horizontal,
             color = [fill(:green, length(top5)); fill(:red, length(bottom5))], alpha = 0.7)
    hline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot)

    p4 = histogram(params.r * 100, bins = 20, xlabel = "Profit Rate (%)",
                   ylabel = "Frequency", title = "Detailed Distribution",
                   legend = :topright, orientation = :horizontal, alpha = 0.7,
                   color = :steelblue, label = "")
    vline!([r_mean * 100], color = :red, lw = 2, label = "Mean")
    vline!([r_median * 100], color = :green, lw = 2, linestyle = :dash, label = "Median")
    vline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max")
    q25 = quantile(params.r, 0.25) * 100
    q75 = quantile(params.r, 0.75) * 100
    vline!([q25, q75], color = :gray, lw = 1, linestyle = :dot, alpha = 0.5, label = "Q1/Q3")

    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "Validation Diagnostics")
    display(plt)

    # Score
    score = 0.0
    feasible_mean && (score += 1.0)
    if isempty(problem_sectors)
        score += 1.0
    else
        score += max(0, 1.0 - length(problem_sectors) / params.N)
    end
    cv < 0.5 && (score += 1.0)
    (0.5 < e_implied < 3.0) && (score += 1.0)
    (20 < r_position < 80) && (score += 1.0)
    final_score = score / 5 * 100

    println("\n" * "-"^70)
    println("  FINAL SCORE: $(round(final_score, digits=1))%  " *
            (final_score >= 80 ? "✅ HIGH QUALITY" :
             final_score >= 60 ? "⚠️  ACCEPTABLE" : "❌ PROBLEMATIC"))
    println("="^70 * "\n")

    return (R_max = R_max, r_mean = r_mean, r_median = r_median,
            dispersion = r_std, cv = cv, feasible_mean = feasible_mean,
            margin = feasible_mean ? mean_margin : missing,
            problem_sectors = problem_sectors,
            e_implied = e_implied, frontier_position = r_position,
            score = final_score, plot = plt)
end
