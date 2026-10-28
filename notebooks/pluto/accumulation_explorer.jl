### A Pluto.jl notebook ###
# v1.0.4

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ b2f48014-d316-11f1-a51d-b907de9fce88
md"""
# Accumulation explorer

Simulate N departments and change, interactively, the rate of exploitation, how the sectors are coupled, and a wage-policy shock. Each department accumulates part of its surplus value as constant and variable capital. With coupling, capital moves between sectors through the technical matrix `A`.

The code uses the MarxKapital API, whose names are Portuguese.
"""

# ╔═╡ b2f480be-d316-11f1-a90b-cd5d4ad6332e
begin
	import Pkg
	# Use the repository's environment (this also turns off Pluto's own package manager).
	Pkg.activate(joinpath(@__DIR__, "..", ".."))
	using PlutoUI, Plots, Random, Statistics, LinearAlgebra
	include(joinpath(@__DIR__, "..", "..", "src", "MarxKapital.jl"))
	gr(margin = 3Plots.mm)
end

# ╔═╡ b2f480d2-d316-11f1-82f9-d78af6b2cd92
md"""
## Economy

Departments `N`: $(@bind N Slider(2:10, default = 6, show_value = true))

Seed: $(@bind seed Slider(1:50, default = 42, show_value = true))

Horizon `T`: $(@bind T Slider(20:10:200, default = 100, show_value = true))

Rate of surplus value × $(@bind e_factor Slider(0.5:0.05:2.0, default = 1.0, show_value = true))
"""

# ╔═╡ b2f480dc-d316-11f1-bb24-55fc22dca5f2
md"""
## Coupling

Mechanism: $(@bind mode Select(["independent" => "independent sectors", "mobility" => "capital mobility", "realization" => "mobility + aggregate realization", "rationing" => "mobility + per-sector rationing"], default = "mobility"))

Capital mobility `μ`: $(@bind μ Slider(0.0:0.05:1.0, default = 0.3, show_value = true))
"""

# ╔═╡ b2f480e6-d316-11f1-ac98-017de605df89
begin
	Random.seed!(seed)   # create_departments uses the global random number generator
	base = create_departments(N)
	depts = [Department(d.name, c = d.c, v = d.v, e = e_factor * d.e, σ_c = d.σ_c,
	                      σ_v = d.σ_v, δ = d.δ) for d in base]
	options = Dict("independent" => (;), "mobility" => (coupled = true,),
	              "realization" => (coupled = true, realization = true),
	              "rationing" => (coupled = true, rationing = true))[mode]
	sol, _, p = simulate_Ndept_custom(depts; T = Float64(T), seed = seed, μ = μ, options...)
end;

# ╔═╡ b2f480f0-d316-11f1-8784-ff3314a7cb5d
let
	k = compute_organic_compositions(sol)
	r = haskey(p, :R_max) ? compute_price_profit_rates(sol, p) : compute_profit_rates(sol, p.e)
	share = reduce(hcat, [u[1:N] ./ sum(u[1:N]) for u in sol.u])'
	plot(plot(sol.t, k', title = "organic composition kᵢ", legend = false),
	     plot(sol.t, r', title = "rates of profit rᵢ", legend = false),
	     plot(sol.t, compute_average_profit_rate(sol, p.e), title = "aggregate rate of profit",
	          legend = false, lw = 2, color = :black),
	     plot(sol.t, share, title = "share of total constant capital", legend = false),
	     layout = (2, 2), size = (900, 560), xlabel = "t")
end

# ╔═╡ b2f480fc-d316-11f1-aee7-533beb994fc5
md"""
With coupling, sectoral profit rates are measured at Sraffa prices of production. Capital mobility moves constant capital towards above-average profit rates without creating or destroying it. Without market prices the profit rates do not depend on relative sector sizes, so capital concentrates: see the cycles explorer for the cross-dual model with market prices.

## Wage shock

Wages × (1 + Δw), with surplus value unchanged in the short run (independent sectors, same `A`). Δw: $(@bind Δw Slider(-0.3:0.05:0.5, default = 0.1, show_value = true))
"""

# ╔═╡ b2f48104-d316-11f1-b046-8ba84e2bca70
shock = redirect_stdout(devnull) do   # the library prints a report; keep the notebook quiet
	simulate_wage_shock(depts, Δw; T = Float64(T), show_plot = false, seed = seed)
end;

# ╔═╡ b2f48118-d316-11f1-ba37-a9d63f2d40ec
md"""
Mean rate of profit at `T`: **$(round(100shock.r_base_final, digits = 2))%** without the shock, **$(round(100shock.r_shock_final, digits = 2))%** with it ($(round(shock.final_r_impact, digits = 2)) percentage points).
"""

# ╔═╡ b2f48122-d316-11f1-bb53-7507e5c235af
let
	grid_pts = collect(-0.3:0.05:0.5)
	r_final = redirect_stdout(devnull) do
		[simulate_wage_shock(depts, x; T = Float64(T), show_plot = false,
		                         seed = seed).r_shock_final for x in grid_pts]
	end
	plot(grid_pts, 100 .* r_final, lw = 2, legend = false, xlabel = "wage shock Δw",
	     ylabel = "mean rate of profit at T (%)", title = "Profit rate after a wage shock")
	scatter!([Δw], [100shock.r_shock_final], markersize = 7)
end

# ╔═╡ Cell order:
# ╟─b2f48014-d316-11f1-a51d-b907de9fce88
# ╟─b2f480be-d316-11f1-a90b-cd5d4ad6332e
# ╟─b2f480d2-d316-11f1-82f9-d78af6b2cd92
# ╟─b2f480dc-d316-11f1-bb24-55fc22dca5f2
# ╠═b2f480e6-d316-11f1-ac98-017de605df89
# ╠═b2f480f0-d316-11f1-8784-ff3314a7cb5d
# ╟─b2f480fc-d316-11f1-aee7-533beb994fc5
# ╠═b2f48104-d316-11f1-b046-8ba84e2bca70
# ╟─b2f48118-d316-11f1-ba37-a9d63f2d40ec
# ╠═b2f48122-d316-11f1-bb53-7507e5c235af
