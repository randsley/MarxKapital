# ============================================================================
# DISTRIBUTIONAL SHOCK SIMULATION
# ============================================================================

"""
    simulate_wage_shock(depts, Δw; T=50.0, show_plot=true, seed=42)

Simulates the impact of a wage rise of fraction `Δw` (e.g. 0.10 = +10%).
V rises by (1+Δw); e falls proportionally (s constant in the short run);
r = e/(k+1) adjusts. Compares the baseline scenario with the shock.

R_max is computed with the simulation's actual technical matrix and labor
coefficients (`p_base.A`, `l ∝ V`), not an auxiliary matrix (see
docs/LIMITATIONS.md, item 2, fixed). The same `seed` is passed to both
scenarios so that the generated technical matrices are comparable.
"""
function simulate_wage_shock(depts, Δw::Float64; T = 50.0, show_plot = true, seed = 42)
    println("\n" * "="^70)
    println("WAGE SHOCK SIMULATION — Δw = +$(round(Δw*100, digits=1))%")
    println("="^70)

    N = length(depts)

    # Baseline scenario: same seed for reproducibility/comparability
    sol_base, _, p_base = simulate_Ndept_custom(depts, T = T, seed = seed)

    # R_max with the actual matrix and labor coefficients of the baseline simulation
    l = [d.v for d in depts]
    R_max = compute_max_profit_rate(p_base.A, l)
    r_base_initial = mean([profit_rate(d) for d in depts])
    r_base_final = mean(compute_profit_rates(sol_base, p_base.e)[:, end])

    # Shock scenario
    depts_shock = Department[]
    for d in depts
        push!(depts_shock, Department(d.name, c = d.c, v = d.v * (1 + Δw),
                                         e = d.e / (1 + Δw), σ_c = d.σ_c,
                                         σ_v = d.σ_v, δ = d.δ))
    end
    sol_shock, _, p_shock = simulate_Ndept_custom(depts_shock, T = T, seed = seed)
    r_shock_initial = mean([profit_rate(d) for d in depts_shock])
    r_shock_final = mean(compute_profit_rates(sol_shock, p_shock.e)[:, end])

    initial_impact = (r_shock_initial - r_base_initial) * 100
    final_impact   = (r_shock_final - r_base_final) * 100

    K_base_initial   = sum(total_capital(d) for d in depts)
    K_shock_initial = sum(total_capital(d) for d in depts_shock)
    K_base_final     = sum(sol_base[1:N, end]) + sum(sol_base[N+1:2N, end])
    K_shock_final   = sum(sol_shock[1:N, end]) + sum(sol_shock[N+1:2N, end])

    println("\n📈 PROFIT RATES")
    println("  Base:   initial $(round(r_base_initial*100, digits=2))%  →  final $(round(r_base_final*100, digits=2))%")
    println("  Shock:  initial $(round(r_shock_initial*100, digits=2))%  →  final $(round(r_shock_final*100, digits=2))%")
    println("  Impact: immediate $(round(initial_impact, digits=2))pp | long run $(round(final_impact, digits=2))pp")
    println("\n💰 CAPITAL ACCUMULATION")
    println("  Base:   +$(round((K_base_final/K_base_initial - 1)*100, digits=1))%")
    println("  Shock:  +$(round((K_shock_final/K_shock_initial - 1)*100, digits=1))%")

    if show_plot
        r_base_traj   = vec(mean(compute_profit_rates(sol_base, p_base.e), dims = 1))
        r_shock_traj = vec(mean(compute_profit_rates(sol_shock, p_shock.e), dims = 1))

        p1 = plot(sol_base.t, r_base_traj * 100, label = "Base", xlabel = "Time",
                  ylabel = "Average Profit Rate (%)", title = "Impact of the Shock", lw = 2)
        plot!(sol_shock.t, r_shock_traj * 100, label = "Shock", lw = 2, linestyle = :dash)
        hline!([R_max * 100], color = :orange, lw = 2, linestyle = :dot, label = "R_max (ref.)")

        K_base_traj   = vec(sum(sol_base[1:N, :], dims = 1) + sum(sol_base[N+1:2N, :], dims = 1))
        K_shock_traj = vec(sum(sol_shock[1:N, :], dims = 1) + sum(sol_shock[N+1:2N, :], dims = 1))
        p2 = plot(sol_base.t, K_base_traj, label = "Base", xlabel = "Time",
                  ylabel = "Total Capital", title = "Accumulation", lw = 2)
        plot!(sol_shock.t, K_shock_traj, label = "Shock", lw = 2, linestyle = :dash)

        p3 = plot(sol_base.t, (r_shock_traj - r_base_traj) * 100, xlabel = "Time",
                  ylabel = "Δr (pp)", title = "Net Effect", lw = 2, label = "",
                  fill = (0, 0.3, :purple))
        hline!([0], color = :black, linestyle = :dash, label = "")

        display(plot(p1, p2, p3, layout = (1, 3), size = (1400, 400)))
    end

    return (r_base_final = r_base_final, r_shock_final = r_shock_final,
            initial_r_impact = initial_impact, final_r_impact = final_impact,
            R_max = R_max, feasible = r_shock_final < R_max)
end

"""
    compare_wage_shocks(depts, shocks; T=50.0, seed=42)

Runs several shock scenarios and returns the final profit rate of each.
"""
function compare_wage_shocks(depts, shocks::Vector{Float64}; T = 50.0, seed = 42)
    println("\n🔬 Comparing $(length(shocks)) shock scenarios...")
    results = []
    sol_base, _, p_base = simulate_Ndept_custom(depts, T = T, seed = seed)
    r_base = mean(compute_profit_rates(sol_base, p_base.e)[:, end])
    push!(results, (shock = 0.0, r_final = r_base))
    for Δw in shocks
        res = simulate_wage_shock(depts, Δw, T = T, show_plot = false, seed = seed)
        push!(results, (shock = Δw, r_final = res.r_shock_final))
    end
    return results
end
