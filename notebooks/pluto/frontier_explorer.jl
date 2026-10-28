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

# ╔═╡ b2fd103a-d316-11f1-abe2-258fb5f14cc2
md"""
# Wage–profit frontier explorer

Pick an economy (number of sectors, random seed, density of the technical matrix `A`) and a uniform rate of profit `r̄`. The notebook shows where `r̄` sits on the wage–profit frontier and how far prices of production are from labour values at that rate.

- Labour values: `λ = (I − Aᵀ)⁻¹ l`
- Prices of production: `p = w(1 + r̄)[I − (1 + r̄)Aᵀ]⁻¹ l`, with wage `w = 1`
- Maximum rate of profit: `R = 1/ρ(A) − 1`

The code uses the MarxKapital API, whose names are Portuguese.
"""

# ╔═╡ b2fd1062-d316-11f1-b1a8-9be77f58258e
begin
	import Pkg
	# Use the repository's environment (this also turns off Pluto's own package manager).
	Pkg.activate(joinpath(@__DIR__, "..", ".."))
	using PlutoUI, Plots, Random, Statistics, LinearAlgebra
	include(joinpath(@__DIR__, "..", "..", "src", "MarxKapital.jl"))
	gr(margin = 3Plots.mm)
end

# ╔═╡ b2fd106c-d316-11f1-b83e-83d2debf792d
md"""
## Economy

Sectors `N`: $(@bind N Slider(3:10, default = 5, show_value = true))

Seed: $(@bind semente Slider(1:50, default = 3, show_value = true))

Density of `A`: $(@bind densidade Slider(0.1:0.05:0.9, default = 0.3, show_value = true))
"""

# ╔═╡ b2fd1080-d316-11f1-b542-790f07dba06f
begin
	A = criar_matriz_tecnica(N, seed = semente, densidade = densidade)
	l = 0.3 .+ 0.3 .* rand(Random.MersenneTwister(semente), N)   # direct labour per unit
	λ = calcular_valores_trabalho(A, l)
	fr = curva_salario_lucro(A, l; plotar = false)
	R = fr.R_max
end;

# ╔═╡ b2fd108a-d316-11f1-af12-55d48540ca70
md"""
## Rate of profit

`r̄` as a fraction of `R`: $(@bind fração Slider(0.0:0.01:0.98, default = 0.4, show_value = true))
"""

# ╔═╡ b2fd1094-d316-11f1-8abb-150e3e06eadf
begin
	r̄ = fração * R
	curv = curvatura_fronteira(A, l, r̄)
	preços = calcular_precos_producao(A, l, 1.0, r̄)
	razão = (preços .* sum(λ) ./ sum(preços)) ./ λ   # prices normalized to total value
end;

# ╔═╡ b2fd109e-d316-11f1-8d84-7f34cc1372cb
md"""
At `r̄ = $(round(r̄, digits = 3))` (maximum `R = $(round(R, digits = 3))`) the wage is `w = $(round(curv.w, digits = 3))`, the slope of the frontier `w′ = $(round(curv.dw, digits = 3))`, and its curvature `w″ = $(round(curv.d2w, digits = 3))`: the frontier is locally **$(curv.forma)**.
"""

# ╔═╡ b2fd10a8-d316-11f1-a1ce-cf573caa5f55
plot(
	begin
		plot(fr.r, fr.w, lw = 2, label = "w(r)", xlabel = "rate of profit r",
		     ylabel = "wage w", title = "Wage–profit frontier")
		scatter!([r̄], [curv.w], markersize = 7, label = "r̄")
	end,
	begin
		bar(1:N, razão, legend = false, xlabel = "sector", ylabel = "price / value",
		    title = "Prices of production / values at r̄", ylims = (0, max(1.6, 1.05maximum(razão))))
		hline!([1.0], color = :black, ls = :dash)
	end,
	layout = (1, 2), size = (900, 380))

# ╔═╡ b2fd10b4-d316-11f1-b0c0-d7e6c6bcc925
md"""
Value–price correlation at `r̄`: $(round(cor(λ ./ sum(λ), preços ./ sum(preços)), digits = 4)). At `r̄ = 0` prices are proportional to values, and the correlation is 1.
"""

# ╔═╡ Cell order:
# ╟─b2fd103a-d316-11f1-abe2-258fb5f14cc2
# ╟─b2fd1062-d316-11f1-b1a8-9be77f58258e
# ╟─b2fd106c-d316-11f1-b83e-83d2debf792d
# ╠═b2fd1080-d316-11f1-b542-790f07dba06f
# ╟─b2fd108a-d316-11f1-af12-55d48540ca70
# ╠═b2fd1094-d316-11f1-8abb-150e3e06eadf
# ╟─b2fd109e-d316-11f1-8d84-7f34cc1372cb
# ╠═b2fd10a8-d316-11f1-a1ce-cf573caa5f55
# ╟─b2fd10b4-d316-11f1-b0c0-d7e6c6bcc925
