# ============================================================================
# PLOTTING
# ============================================================================

"""Panels for the 2-department model: capital, composition, profit, equilibrium."""
function plot_2dept(sol, depts, p)
    t = sol.t
    C1, V1, C2, V2 = (sol[i, :] for i in 1:4)
    e1, e2 = p[1], p[2]
    σ_c1, σ_c2 = p[3], p[5]

    K1 = C1 .+ V1; K2 = C2 .+ V2
    S1 = e1 .* V1; S2 = e2 .* V2
    k1 = C1 ./ V1; k2 = C2 ./ V2
    r1 = e1 ./ (k1 .+ 1); r2 = e2 ./ (k2 .+ 1)
    r_mean = (S1 .+ S2) ./ (K1 .+ K2)

    p1 = plot(t, [K1 K2], label = ["Dept I" "Dept II"], xlabel = "Time",
              ylabel = "Total Capital", title = "Capital Paths", lw = 2)
    p2 = plot(t, [k1 k2], label = ["Dept I" "Dept II"], xlabel = "Time",
              ylabel = "k", title = "Organic Composition", lw = 2)
    p3 = plot(t, [r1 r2 r_mean], label = ["Dept I" "Dept II" "Mean"],
              xlabel = "Time", ylabel = "r", title = "Profit Rates", lw = 2)
    diseq = (V1 .+ (1 .- σ_c1) .* S1) .- (C2 .+ σ_c2 .* S2)
    p4 = plot(t, diseq, label = "", xlabel = "Time", ylabel = "Disequilibrium",
              title = "Intersectoral Equilibrium", lw = 2, color = :red)
    hline!([0], color = :black, linestyle = :dash, label = "")

    plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 800))
end

"""Panels for the N-department model: capital, compositions, profits, final distribution."""
function plot_Ndept(sol, depts, p; save_figure = nothing)
    N = length(depts)
    t = sol.t
    r = compute_profit_rates(sol, p.e)
    k = compute_organic_compositions(sol)
    r_mean = compute_average_profit_rate(sol, p.e)

    K = zeros(N, length(t))
    for idx in 1:length(t)
        K[:, idx] = sol[1:N, idx] .+ sol[N+1:2N, idx]
    end

    p1 = plot(t, K', xlabel = "Time", ylabel = "Capital",
              title = "Paths (N=$N)", legend = false, alpha = 0.6)
    p2 = plot(t, k', xlabel = "Time", ylabel = "k",
              title = "Organic Compositions", legend = false, alpha = 0.6)
    p3 = plot(t, r', xlabel = "Time", ylabel = "r", title = "Profit Rates",
              legend = false, alpha = 0.6)
    plot!(t, r_mean, lw = 3, color = :black, label = "Mean")
    p4 = histogram(r[:, end], xlabel = "Profit Rate", ylabel = "Frequency",
                   title = "Final Distribution", legend = false, bins = 15)

    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1200, 800))
    isnothing(save_figure) || savefig(plt, save_figure)
    display(plt)
    return plt
end
