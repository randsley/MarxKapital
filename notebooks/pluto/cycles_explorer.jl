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

# ╔═╡ b2fcf8e8-d316-11f1-baa5-9592e26a7a9e
begin
	import Pkg
	# Use the repository's environment (this also turns off Pluto's own package manager).
	Pkg.activate(joinpath(@__DIR__, "..", ".."))
	using PlutoUI, Plots, Random, Statistics, LinearAlgebra
	include(joinpath(@__DIR__, "..", "..", "src", "MarxKapital.jl"))
	gr(margin = 3Plots.mm)
end

# ╔═╡ b2fcf866-d316-11f1-8089-3f3a23b9a6f5
md"""
# Accumulation cycles explorer

The cross-dual model (`market_prices = true`): market prices respond to sectoral excess demand, and capital moves on profit rates at those prices. It has interior balanced-growth rays. Raising the mobility of variable capital `μ_v` destabilizes balanced growth at a supercritical Hopf bifurcation; further up come a torus, a window where a stable cycle and the torus coexist, and chaos (paper, Sections 3.6 and 5.6).

Move the sliders and watch the eigenvalues of balanced growth cross the imaginary axis and the trajectory change from a point, to a cycle, to irregular motion. The economy is the paper's: six sectors, seed 5.

The code uses the MarxKapital API.
"""

# ╔═╡ b2fcf8fc-d316-11f1-9e7e-49cd356c53e4
begin
	Random.seed!(5)
	sol0, _, p0 = simulate_Ndept(6, T = 1.0, seed = 5, coupled = true, μ = 0.5,
	                            market_prices = true)
	X0 = sol0.u[1]
end;

# ╔═╡ b2fcf906-d316-11f1-ad96-9ba9c35ea720
md"""
## Parameters

Mobility of variable capital `μ_v`: $(@bind μ_v Slider(0.0:0.01:2.5, default = 1.1, show_value = true))

Speed of price adjustment `β`: $(@bind β Slider(0.05:0.05:1.0, default = 0.1, show_value = true))

Rates of surplus value × $(@bind e_scale Slider(0.5:0.05:2.0, default = 1.0, show_value = true))

Simulation length: $(@bind T Slider(1000:500:6000, default = 2500, show_value = true))
"""

# ╔═╡ b2fcf910-d316-11f1-9bcd-af73e561aadd
pβ = with_parameter(merge(p0, (β = β,)), :e_scale, e_scale);

# ╔═╡ b2fcf91a-d316-11f1-a596-5fc7deaf0216
pθ = with_parameter(pβ, :μ_v, μ_v);

# ╔═╡ b2fcf924-d316-11f1-9ac0-6feb0f265760
eq = balanced_growth(pθ, X0);

# ╔═╡ b2fcf92e-d316-11f1-84c9-3d36630574b1
md"""
Balanced growth: `g★ = $(round(eq.g, digits = 4))`, aggregate rate of profit `$(round(eq.r_aggregate, digits = 4))`, wage share `ω = $(round(eq.ω, digits = 3))`. Largest real part of the eigenvalues: `$(round(maximum(real.(eq.eigenvalues)), digits = 5))`, so the ray is **$(eq.stable ? "stable" : "unstable")**$(eq.converged ? "" : " (Newton did not converge: treat with care)").
"""

# ╔═╡ b2fcf938-d316-11f1-9727-d11f0258f5a2
s = simulate_normalized(pθ, X0; T = Float64(T), saveat = 0.5);

# ╔═╡ b2fcf942-d316-11f1-80f6-83abd3866ef7
let
	λs = eq.eigenvalues
	keep = s.t .> T / 2
	plot(
		begin
			scatter(real.(λs), imag.(λs), legend = false, xlabel = "Re λ", ylabel = "Im λ",
			        title = "eigenvalues of balanced growth")
			vline!([0.0], color = :black, ls = :dash)
		end,
		plot(s.t[keep], s[1:6, keep]', legend = false, xlabel = "t",
		     ylabel = "Cᵢ (normalized)", title = "second half of the run"),
		plot(s[1, keep], s[2, keep], legend = false, lw = 0.6, xlabel = "C₁", ylabel = "C₂",
		     title = "phase portrait"),
		layout = (1, 3), size = (1050, 340))
end

# ╔═╡ b2fcf94c-d316-11f1-bc86-c917e02db120
md"""
## Where is the Hopf point?

The largest real part of the eigenvalues along `μ_v`, at the current `β` and rates of surplus value. Balanced growth is stable where the curve is below zero; the vertical line marks the current `μ_v`.
"""

# ╔═╡ b2fcf956-d316-11f1-b54c-2be237c335da
# Depends on β and the rates of surplus value only, so moving μ_v does not recompute it.
sweep_μ_v = let grid_pts = 0.0:0.05:2.5
	(θ = grid_pts, real_part = map(grid_pts) do θ
		e = balanced_growth(with_parameter(pβ, :μ_v, θ), X0; T_warmup = 200.0)
		e.converged ? maximum(real.(e.eigenvalues)) : NaN   # gaps where Newton fails
	end)
end;

# ╔═╡ b2fcf962-d316-11f1-a9b8-c3a9d5aa2417
begin
	plot(sweep_μ_v.θ, sweep_μ_v.real_part, lw = 2, legend = false, xlabel = "μ_v",
	     ylabel = "max Re λ", title = "stability of balanced growth")
	hline!([0.0], color = :black, ls = :dash)
	vline!([μ_v], ls = :dot)
end

# ╔═╡ Cell order:
# ╟─b2fcf866-d316-11f1-8089-3f3a23b9a6f5
# ╟─b2fcf8e8-d316-11f1-baa5-9592e26a7a9e
# ╠═b2fcf8fc-d316-11f1-9e7e-49cd356c53e4
# ╟─b2fcf906-d316-11f1-ad96-9ba9c35ea720
# ╠═b2fcf910-d316-11f1-9bcd-af73e561aadd
# ╠═b2fcf91a-d316-11f1-a596-5fc7deaf0216
# ╠═b2fcf924-d316-11f1-9ac0-6feb0f265760
# ╟─b2fcf92e-d316-11f1-84c9-3d36630574b1
# ╠═b2fcf938-d316-11f1-9727-d11f0258f5a2
# ╠═b2fcf942-d316-11f1-80f6-83abd3866ef7
# ╟─b2fcf94c-d316-11f1-bc86-c917e02db120
# ╠═b2fcf956-d316-11f1-b54c-2be237c335da
# ╠═b2fcf962-d316-11f1-a9b8-c3a9d5aa2417
