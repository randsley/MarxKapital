# ============================================================================
# Estimating capital mobility (μ) from sectoral accounts.
#
# The model's mobility term moves capital towards sectors with a higher
# profit rate, μ·(rᵢ − r̄)·Cᵢ, and sums to zero across sectors. Its empirical
# counterpart is the transfer Rᵢₜ = Iᵢₜ − σₜ·Sᵢₜ: the net investment of a
# sector beyond the share σₜ = ΣI/ΣS of its own surplus that the economy as a
# whole reinvests, which also sums to zero. The estimating equation is
#
#     Rᵢₜ / Kᵢ,ₜ₋₁ = μ·(rᵢ,ₜ₋₁ − r̄ₜ₋₁) + fixed effects + uᵢₜ
#
# with r̄ the capital-weighted mean. These functions build that panel from a
# sectoral extract (data/eurostat_eu_sectors.csv: one country or several)
# and estimate μ with any set of fixed effects, Driscoll–Kraay and
# country-clustered standard errors. Used by notebooks 09–14; notebook 12
# compares the average rate with Shaikh's incremental rate of profit
# (compute_incremental_panel, estimate_persistence), and notebook 14 estimates
# the mobility of variable capital μ_v (compute_labor_panel,
# estimate_variable_mobility).
# ============================================================================

const _MOBILITY_EFFECTS = (:geo, :section, :year, :geo_section, :geo_year, :section_year)

"""
    compute_mobility_panel(raw; sections, countries = nothing,
                           self_employed = :excluded, own = :current)

The panel of the mobility equation, built per country from a sectoral
extract with columns `section, year, GVA, compensation, CFC, GFCF,
capital_stock` (and `employment, employees` for `self_employed = :imputed`),
plus `geo` for several countries. Without a `geo` column the extract is one
country (`geo = ""` in the result).

For each country, over the `sections` chosen (e.g. the market sectors):
surplus value `S = GVA − V − CFC`, net investment `I = GFCF − CFC`, the
reinvestment share `σₜ = ΣI/ΣS`, the transfer `R = I − σ·S` (sums to zero
in every country-year) and the profit rate `r = S/(K + V)` with the
end-of-year stock `K` of the year before. `self_employed = :imputed` counts
each self-employed worker at the average employee's compensation of the
section (`V·employment/employees`, see `impute_self_employed`); `own =
:lagged` nets own financing out of last year's surplus instead of this
year's.

Returns a long DataFrame, one row per country, section and year from the
third year of each country on (flows in t, stock and gap in t−1): `geo,
section, year`, `y = 100·R/Kₜ₋₁` (% of capital), `gap = 100·(rₜ₋₁ − r̄ₜ₋₁)`
(pp, r̄ capital-weighted within the country), `r` (of t−1), `R`, `K`
(Kₜ₋₁) and `σ`. Errors if a section or a year is missing inside a
country's range.
"""
function compute_mobility_panel(raw::AbstractDataFrame; sections, countries = nothing,
                                self_employed::Symbol = :excluded, own::Symbol = :current)
    _check_self_employed(self_employed)
    own in (:current, :lagged) || throw(ArgumentError("own must be :current or :lagged, got :$own"))
    secs = String.(collect(sections))
    isempty(secs) && throw(ArgumentError("no sections"))
    has_geo = "geo" in names(raw)
    geos = has_geo ? (countries === nothing ? sort(unique(String.(raw.geo))) : String.(collect(countries))) :
                     (countries === nothing ? [""] :
                      throw(ArgumentError("countries given but the extract has no geo column")))

    out = DataFrame(geo = String[], section = String[], year = Int[], y = Float64[], gap = Float64[],
                    r = Float64[], R = Float64[], K = Float64[], σ = Float64[])
    for g in geos
        d = has_geo ? raw[String.(raw.geo) .== g, :] : raw
        nrow(d) == 0 && throw(ArgumentError("no rows for country $g"))
        years = sort(unique(Int.(d.year)))
        years == first(years):last(years) ||
            error("$g: years missing inside $(first(years))–$(last(years))")
        length(years) >= 3 || error("$g: at least 3 years are needed, got $(length(years))")
        row = Dict((String(r.section), Int(r.year)) => i for (i, r) in enumerate(eachrow(d)))
        for s in secs, y in years
            haskey(row, (s, y)) || error("$g: no data for section $s in $y")
        end
        grid(col) = [Float64(d[row[(s, y)], col]) for s in secs, y in years]

        V = grid(:compensation)
        self_employed == :imputed && (V = V .* grid(:employment) ./ grid(:employees))
        S = grid(:GVA) .- V .- grid(:CFC)
        I = grid(:GFCF) .- grid(:CFC)
        K = grid(:capital_stock)
        t = 3:length(years)
        r = S[:, t .- 1] ./ (K[:, t .- 2] .+ V[:, t .- 1])
        r̄ = vec(sum(r .* K[:, t .- 2]; dims = 1) ./ sum(K[:, t .- 2]; dims = 1))
        Sown = own == :lagged ? S[:, t .- 1] : S[:, t]
        σ = vec(sum(I[:, t]; dims = 1) ./ sum(Sown; dims = 1))
        R = I[:, t] .- σ' .* Sown
        y = 100 .* R ./ K[:, t .- 1]
        gap = 100 .* (r .- r̄')
        for (j, yr) in enumerate(years[t]), (i, s) in enumerate(secs)
            push!(out, (g, s, yr, y[i, j], gap[i, j], r[i, j], R[i, j], K[i, j+1], σ[j]))
        end
    end
    return out
end

"""Integer codes 1…L of the labels in `v`, and the number of levels L."""
function _codes(v)
    lv = Dict{eltype(v), Int}()
    c = [get!(lv, x, length(lv) + 1) for x in v]
    return c, length(lv)
end

"""
    demean_fe(v, groups...; tol = 1e-13, maxiter = 10_000)

`v` with the fixed effects of every grouping in `groups` swept out (each a
vector of labels, one per observation), by alternating projections (the
Gauss–Seidel method of Guimarães–Portugal and `reghdfe`): subtract the group
means of each grouping in turn until the largest change is below `tol`
times the scale of `v`. Exact in one sweep for a single grouping or for
two crossed groupings of a balanced panel. Errors if it does not converge.
"""
function demean_fe(v::AbstractVector{<:Real}, groups::AbstractVector...;
                   tol::Real = 1e-13, maxiter::Integer = 10_000)
    x = Float64.(v)
    isempty(groups) && return x .- mean(x)
    all(length(g) == length(x) for g in groups) ||
        throw(DimensionMismatch("every grouping needs one label per observation"))
    coded = [_codes(g) for g in groups]
    scale = max(maximum(abs, x; init = 0.0), eps())
    for _ in 1:maxiter
        change = 0.0
        for (c, L) in coded
            s, n = zeros(L), zeros(Int, L)
            @inbounds for i in eachindex(x)
                s[c[i]] += x[i]; n[c[i]] += 1
            end
            @inbounds for i in eachindex(x)
                m = s[c[i]] / n[c[i]]
                x[i] -= m
                change = max(change, abs(m))
            end
        end
        (length(groups) == 1 || change <= tol * scale) && return x
    end
    error("demean_fe: no convergence in $maxiter sweeps")
end

"""Number of connected components of the bipartite graph linking the levels of two groupings."""
function _components(c1, L1, c2, L2)
    parent = collect(1:(L1 + L2))
    find(i) = (while parent[i] != i; parent[i] = parent[parent[i]]; i = parent[i]; end; i)
    for k in eachindex(c1)
        a, b = find(c1[k]), find(L1 + c2[k])
        a != b && (parent[a] = b)
    end
    return count(i -> find(i) == i, 1:(L1 + L2))
end

"""
Number of parameters absorbed by the fixed effects: exact for one or two
groupings (levels minus connected components); for three or more, the
levels minus the components of the first two, a conservative count (the
classical standard error is then slightly larger than exact).
"""
function _absorbed(groups)
    isempty(groups) && return 1
    coded = [_codes(g) for g in groups]
    length(coded) == 1 && return coded[1][2]
    (c1, L1), (c2, L2) = coded[1], coded[2]
    return L1 + L2 - _components(c1, L1, c2, L2) + sum((L for (_, L) in coded[3:end]); init = 0)
end

function _effect_labels(panel, e::Symbol)
    e in _MOBILITY_EFFECTS || throw(ArgumentError("unknown effect :$e; use one of $(_MOBILITY_EFFECTS)"))
    e == :geo && return panel.geo
    e == :section && return panel.section
    e == :year && return panel.year
    e == :geo_section && return tuple.(panel.geo, panel.section)
    e == :geo_year && return tuple.(panel.geo, panel.year)
    return tuple.(panel.section, panel.year)
end

"""
Driscoll–Kraay "meat" of a regression with demeaned regressors `X` (n × k)
and residuals `u`: the year sums `hₜ = Σ xᵢₜuᵢₜ` (pooled over countries and
sectors) and their autocovariances up to `lags` calendar years, Bartlett
weights. k × k.
"""
function _driscoll_kraay_meat(X::AbstractMatrix, u, years; lags::Integer)
    ys = sort(unique(years))
    idx = Dict(y => k for (k, y) in enumerate(ys))
    h = zeros(length(ys), size(X, 2))
    for i in eachindex(u)
        @views h[idx[years[i]], :] .+= X[i, :] .* u[i]
    end
    M = h'h
    for l in 1:lags, k in eachindex(ys), k2 in eachindex(ys)
        if ys[k2] - ys[k] == l
            w = 1 - l / (lags + 1)
            @views M .+= w .* (h[k, :] * h[k2, :]' .+ h[k2, :] * h[k, :]')
        end
    end
    return M
end

"""
    estimate_fe_ols(panel, y, X; effects = (:geo_section, :geo_year), lags = 2)

OLS of `y` on the columns of `X` (a vector or an n × k matrix, one row per
row of `panel`) with the fixed effects `effects` swept out (`demean_fe`;
same effect names as `estimate_mobility`). Returns `(β, se, se_DK,
se_cluster, ssr, n, countries)`: coefficients; classical standard errors
(degrees of freedom net of the absorbed effects, `_absorbed`);
Driscoll–Kraay errors (any correlation within a year, serial correlation up
to `lags` years, Bartlett kernel); errors clustered by country (`G/(G−1)`
factor, `NaN` with fewer than 2 countries); and the residual sum of squares.
Also `V_cluster`, the clustered covariance matrix of `β` (for functions of
several coefficients).
"""
function estimate_fe_ols(panel::AbstractDataFrame, y::AbstractVector, X::AbstractVecOrMat;
                         effects = (:geo_section, :geo_year), lags::Integer = 2)
    n = nrow(panel)
    Xm = X isa AbstractVector ? reshape(X, :, 1) : X
    (length(y) == n && size(Xm, 1) == n) ||
        throw(DimensionMismatch("y and X need one row per row of the panel ($n)"))
    k = size(Xm, 2)
    n > k + 1 || throw(ArgumentError("panel too small ($n rows)"))
    groups = [_effect_labels(panel, e) for e in effects]
    yd = demean_fe(y, groups...)
    Xd = reduce(hcat, [demean_fe(Xm[:, j], groups...) for j in 1:k])
    # a scale-free rank test: Cholesky's own check depends on rounding and
    # can pass an exactly singular X'X
    norms = [norm(Xd[:, j]) for j in 1:k]
    all(norms[j] > 1e-8 * max(norm(Xm[:, j]), floatmin()) for j in 1:k) ||
        error("a regressor is absorbed by the fixed effects")
    sv = svdvals(Xd ./ norms')
    sv[end] > 1e-8 * sv[1] || error("the regressors are collinear after the fixed effects")
    XX = Symmetric(Xd'Xd)
    F = cholesky(XX)
    β = F \ (Xd'yd)
    u = yd .- Xd * β
    ssr = sum(abs2, u)
    dof = n - _absorbed(groups) - k
    dof > 0 || error("no degrees of freedom left")
    XXi = inv(F)
    se = sqrt.(diag(XXi) .* (ssr / dof))
    se_DK = sqrt.(diag(XXi * _driscoll_kraay_meat(Xd, u, panel.year; lags = lags) * XXi))
    gc, G = _codes(panel.geo)
    V_cl = if G >= 2
        hg = zeros(G, k)
        for i in eachindex(u)
            @views hg[gc[i], :] .+= Xd[i, :] .* u[i]
        end
        XXi * (G / (G - 1) .* (hg'hg)) * XXi
    else
        fill(NaN, k, k)
    end
    se_cl = sqrt.(diag(V_cl))
    return (β = β, se = se, se_DK = se_DK, se_cluster = se_cl, ssr = ssr, n = n, countries = G,
            V_cluster = V_cl)
end

"""
    estimate_mobility(panel; effects = (:geo_section, :geo_year), lags = 2)

Fixed-effects estimate of μ in `y = μ·gap + effects + u` on a panel from
`compute_mobility_panel`. `effects` is any tuple of `:geo, :section, :year,
:geo_section, :geo_year, :section_year`; the default (country × sector and
country × year effects) absorbs each sector's permanent position and each
country's credit cycle, and adding `:section_year` also absorbs shocks
common to a sector across countries. For one country, `(:geo_section,
:geo_year)` is the same as `(:section, :year)`.

Returns `(μ, se, se_DK, se_cluster, n, countries)`: the slope, its classical
standard error (degrees of freedom net of the absorbed effects, see
`_absorbed`), the Driscoll–Kraay standard error (robust to any correlation
across countries and sectors within a year and to serial correlation up to
`lags` years; Bartlett kernel, no small-sample factor) and the standard
error clustered by country (`G/(G−1)` factor; `NaN` with fewer than 2
countries).
"""
function estimate_mobility(panel::AbstractDataFrame; effects = (:geo_section, :geo_year), lags::Integer = 2)
    nrow(panel) >= 3 || throw(ArgumentError("panel too small ($(nrow(panel)) rows)"))
    e = estimate_fe_ols(panel, panel.y, panel.gap; effects = effects, lags = lags)
    return (μ = e.β[1], se = e.se[1], se_DK = e.se_DK[1], se_cluster = e.se_cluster[1], n = e.n,
            countries = e.countries)
end

"""
    estimate_mobility_between(panel; within_country = false)

Between estimate of μ: OLS of the mean `y` on the mean `gap` of each
country × sector over its years, with a constant (or, with `within_country
= true`, with country effects, so only differences between the sectors of
a country count). Returns `(μ, se, n)`, `se` classical.
"""
function estimate_mobility_between(panel::AbstractDataFrame; within_country::Bool = false)
    m = combine(groupby(panel, [:geo, :section]), :y => mean => :y, :gap => mean => :gap)
    n = nrow(m)
    if within_country
        yd, xd = demean_fe(m.y, m.geo), demean_fe(m.gap, m.geo)
        k = length(unique(m.geo)) + 1
    else
        yd, xd = m.y .- mean(m.y), m.gap .- mean(m.gap)
        k = 2
    end
    n > k || throw(ArgumentError("too few units ($n)"))
    b = dot(xd, yd) / dot(xd, xd)
    u = yd .- b .* xd
    return (μ = b, se = sqrt(sum(abs2, u) / (n - k) / dot(xd, xd)), n = n)
end

"""
    compute_investment_panel(raw; sections, countries = nothing, self_employed = :excluded)

The panel of `compute_mobility_panel` (same rows; `own = :current`) with the
flows the model's investment function needs, per country, section and year:
`gk = 100·GFCFₜ/Kₜ₋₁` (gross investment rate, %), `sk = 100·Sₜ/Kₜ₋₁` (%),
`rbar` (the capital-weighted mean profit rate of the country in t−1, so that
`gap = 100·(r − rbar)`), `σbar` (the gross reinvestment share
`ΣGFCF/ΣS` of the country × sector over its valid years, the data's
analogue of a department's `σ_c`) and `valid` (`r > 0`, `rbar > 0`, `S > 0`: rows the
elasticity form `(rbar/r)^η` can use). `self_employed = :imputed` imputes
the self-employed in `S` as in `compute_mobility_panel`.

For the linear form of the investment function (`estimate_investment_function`
with `form = :linear`): `kv = 100·(Kₜ₋₂ + Vₜ₋₁)/Kₜ₋₁`, the capital that the
profit rate `r` of t−1 divides by, as % of this year's stock; `rbar_K =
ΣSₜ₋₁/Σ(Kₜ₋₂ + Vₜ₋₁)`, the country's aggregate profit rate (the `r̄` of
`_linear_reinvestment`); and `valid_linear`, rows of country × sectors with
a positive `σbar`, whatever the sign of their profit rate. `dk =
100·CFCₜ/Kₜ₋₁`, the depreciation rate (%), for the investment floor
(`estimate_investment_floor`).
"""
function compute_investment_panel(raw::AbstractDataFrame; sections, countries = nothing,
                                  self_employed::Symbol = :excluded)
    P = compute_mobility_panel(raw; sections = sections, countries = countries,
                               self_employed = self_employed)
    has_geo = "geo" in names(raw)
    geo = has_geo ? String.(raw.geo) : fill("", nrow(raw))
    V = Float64.(raw.compensation)
    self_employed == :imputed && (V = V .* raw.employment ./ raw.employees)
    flows = Dict((geo[i], String(raw.section[i]), Int(raw.year[i])) =>
                 (Float64(raw.GFCF[i]), Float64(raw.GVA[i]) - V[i] - Float64(raw.CFC[i]))
                 for i in 1:nrow(raw))
    F = [flows[(P.geo[i], P.section[i], P.year[i])] for i in 1:nrow(P)]
    P.gk = 100 .* first.(F) ./ P.K
    P.sk = 100 .* last.(F) ./ P.K
    P.rbar = P.r .- P.gap ./ 100
    P.valid = (P.r .> 0) .& (P.rbar .> 0) .& (last.(F) .> 0)
    gross, surplus = Dict{Tuple{String, String}, Float64}(), Dict{Tuple{String, String}, Float64}()
    for i in 1:nrow(P)
        P.valid[i] || continue
        u = (P.geo[i], P.section[i])
        gross[u] = get(gross, u, 0.0) + first(F[i])
        surplus[u] = get(surplus, u, 0.0) + last(F[i])
    end
    P.σbar = [haskey(gross, u) ? gross[u] / surplus[u] : NaN for u in zip(P.geo, P.section)]
    P.valid .&= .!isnan.(P.σbar)

    # the linear form: the denominator of r and the aggregate profit rate
    stock = Dict((geo[i], String(raw.section[i]), Int(raw.year[i])) => Float64(raw.capital_stock[i])
                 for i in 1:nrow(raw))
    wages = Dict((geo[i], String(raw.section[i]), Int(raw.year[i])) => V[i] for i in 1:nrow(raw))
    D = [stock[(P.geo[i], P.section[i], P.year[i] - 2)] + wages[(P.geo[i], P.section[i], P.year[i] - 1)]
         for i in 1:nrow(P)]
    Slag = [last(flows[(P.geo[i], P.section[i], P.year[i] - 1)]) for i in 1:nrow(P)]
    P.kv = 100 .* D ./ P.K
    agg = Dict{Tuple{String, Int}, Tuple{Float64, Float64}}()
    for i in 1:nrow(P)
        a = get(agg, (P.geo[i], P.year[i]), (0.0, 0.0))
        agg[(P.geo[i], P.year[i])] = (a[1] + Slag[i], a[2] + D[i])
    end
    P.rbar_K = [(a = agg[(P.geo[i], P.year[i])]; a[1] / a[2]) for i in 1:nrow(P)]
    P.valid_linear = .!isnan.(P.σbar) .& (P.σbar .> 0) .& isfinite.(P.gk) .& isfinite.(P.sk)
    cfc = Dict((geo[i], String(raw.section[i]), Int(raw.year[i])) => Float64(raw.CFC[i]) for i in 1:nrow(raw))
    P.dk = [100 * cfc[(P.geo[i], P.section[i], P.year[i])] / P.K[i] for i in 1:nrow(P)]
    return P
end

"""
    compute_labor_panel(raw; sections, countries = nothing, self_employed = :excluded)

The panel of the model's equation for variable capital,

    dVᵢ/dt = σ_v·Sᵢ + μ_v·(rᵢ − r̄_V)·Vᵢ,

with `r̄_V` the V-weighted mean profit rate (`system_Ndept_io!`,
`cross_dual_system!`, `_mobility_flow`), on the rows of
`compute_mobility_panel`. Adds, per row (year `t`):

- `vg = 100·(Vₜ − Vₜ₋₁)/Vₜ₋₁`: growth of the wage bill (%);
- `eg = 100·(Eₜ − Eₜ₋₁)/Eₜ₋₁`: growth of employment (persons), the wage bill
  at a constant wage, which strips out wage-rate growth;
- `sv = 100·Sₜ₋₁/Vₜ₋₁`: last year's surplus over the wage bill (the rate of
  exploitation, in %), so that `σ_v·S/V` is not mechanically tied to this
  year's wages through `S = GVA − V − CFC`;
- `gap_V = 100·(rₜ₋₁ − r̄_V,ₜ₋₁)`: the profit-rate gap to the V-weighted
  mean of the country-year (pp), which sums to zero weighted by `Vₜ₋₁`;
- `Vlag` (`Vₜ₋₁`) and `valid_V` (finite flows and `Vₜ₋₁ > 0`, `Eₜ₋₁ > 0`).

`self_employed = :imputed` counts the self-employed at the average
employee's compensation, as in `compute_mobility_panel`.
"""
function compute_labor_panel(raw::AbstractDataFrame; sections, countries = nothing,
                             self_employed::Symbol = :excluded)
    P = compute_mobility_panel(raw; sections = sections, countries = countries,
                               self_employed = self_employed)
    geo = "geo" in names(raw) ? String.(raw.geo) : fill("", nrow(raw))
    V = Float64.(raw.compensation)
    self_employed == :imputed && (V = V .* raw.employment ./ raw.employees)
    key(i) = (geo[i], String(raw.section[i]), Int(raw.year[i]))
    wages = Dict(key(i) => V[i] for i in 1:nrow(raw))
    surplus = Dict(key(i) => Float64(raw.GVA[i]) - V[i] - Float64(raw.CFC[i]) for i in 1:nrow(raw))
    jobs = Dict(key(i) => Float64(raw.employment[i]) for i in 1:nrow(raw))
    at(d, i, lag) = d[(P.geo[i], P.section[i], P.year[i] - lag)]
    Vt, Vl = [at(wages, i, 0) for i in 1:nrow(P)], [at(wages, i, 1) for i in 1:nrow(P)]
    Et, El = [at(jobs, i, 0) for i in 1:nrow(P)], [at(jobs, i, 1) for i in 1:nrow(P)]
    Sl = [at(surplus, i, 1) for i in 1:nrow(P)]
    P.vg = 100 .* (Vt .- Vl) ./ Vl
    P.eg = 100 .* (Et .- El) ./ El
    P.sv = 100 .* Sl ./ Vl
    P.Vlag = Vl
    agg = Dict{Tuple{String, Int}, Tuple{Float64, Float64}}()
    for i in 1:nrow(P)
        a = get(agg, (P.geo[i], P.year[i]), (0.0, 0.0))
        agg[(P.geo[i], P.year[i])] = (a[1] + P.r[i] * Vl[i], a[2] + Vl[i])
    end
    P.gap_V = [100 * (P.r[i] - (a = agg[(P.geo[i], P.year[i])]; a[1] / a[2])) for i in 1:nrow(P)]
    P.valid_V = (Vl .> 0) .& (El .> 0) .& isfinite.(P.vg) .& isfinite.(P.eg) .& isfinite.(P.sv) .&
                isfinite.(P.gap_V)
    return P
end

"""
    estimate_variable_mobility(P; dependent = :vg, effects = (:geo_section, :geo_year), lags = 2)

The mobility of variable capital `μ_v` (`simulate_Ndept_custom(...; μ_v)`) on
a `compute_labor_panel` panel:

    dependent = λ_v·sv + μ_v·gap_V + effects + u,

with `dependent` either `:vg` (growth of the wage bill, the model's `V`) or
`:eg` (growth of employment, which leaves out wage-rate growth that is not
common to the country-year). In the model's units `λ_v` is `σ_v`, the share
of surplus spent on hiring, and `μ_v` is the coefficient of `_mobility_flow`.
Country × year effects absorb common wage inflation and the business cycle;
country × sector effects each sector's trend.

Returns `(μ_v, se, se_DK, se_cluster, λ_v, se_λ_v, n, countries)`, with
the standard errors of `estimate_fe_ols`; `se_λ_v` is clustered by country.
"""
function estimate_variable_mobility(P::AbstractDataFrame; dependent::Symbol = :vg,
                                    effects = (:geo_section, :geo_year), lags::Integer = 2)
    dependent in (:vg, :eg) || throw(ArgumentError("dependent must be :vg or :eg, got :$dependent"))
    Q = P[P.valid_V, :]
    nrow(Q) >= 4 || throw(ArgumentError("panel too small ($(nrow(Q)) valid rows)"))
    e = estimate_fe_ols(Q, Q[!, dependent], hcat(Q.sv, Q.gap_V); effects = effects, lags = lags)
    return (μ_v = e.β[2], se = e.se[2], se_DK = e.se_DK[2], se_cluster = e.se_cluster[2],
            λ_v = e.β[1], se_λ_v = e.se_cluster[1], n = e.n, countries = e.countries)
end

"""
    estimate_investment_floor(P; below = 0.0)

The floor on gross investment (`investment_floor` of `simulate_Ndept_custom`,
`_investment_floor`) from the rows of a `compute_investment_panel` panel
whose profit rate is at most `below` times the country's mean (`r ≤
below·rbar`; with the default 0, the years with losses): the slope `θ` of
gross investment on depreciation through the origin,

    gk = θ·dk + u,

the share of what wears out that a sector replaces when its own investment
function would invest little or nothing. Returns `(θ, se, median_ratio, n,
countries)`: `θ̂`, its country-clustered standard error, the median of
`gk/dk` in those rows, and their number.
"""
function estimate_investment_floor(P::AbstractDataFrame; below::Real = 0.0)
    isfinite(below) || throw(ArgumentError("below must be finite, got $below"))
    Q = P[(P.r .<= below .* P.rbar) .& isfinite.(P.gk) .& isfinite.(P.dk) .& (P.dk .> 0), :]
    n = nrow(Q)
    n >= 2 || throw(ArgumentError("fewer than 2 rows with r ≤ $(below)·rbar"))
    dd = sum(abs2, Q.dk)
    θ = sum(Q.gk .* Q.dk) / dd
    u = Q.gk .- θ .* Q.dk
    gc, G = _codes(Q.geo)
    se = if G >= 2
        h = zeros(G)
        for i in 1:n
            h[gc[i]] += Q.dk[i] * u[i]
        end
        sqrt(G / (G - 1) * sum(abs2, h)) / dd
    else
        NaN
    end
    return (θ = θ, se = se, median_ratio = median(Q.gk ./ Q.dk), n = n, countries = G)
end

"""
    estimate_investment_function(P; η_grid = 0:0.1:1.0, form = :power, ratio_bounds = nothing,
                                 exit_hurdle = nothing, effects = (:geo_section, :geo_year), lags = 2)

The model's investment function in data terms, on a `compute_investment_panel`
panel. `form = :power` (`_reinvestment_share`):

    gk = λ·σbarᵢ·(rbar/rᵢ)^η·sk + μ·gap + effects + u,

on the valid rows (`r > 0`) with `rᵢ/rbar` inside `ratio_bounds` (default
`(0, Inf)`; trimming the years in which a sector's profit rate is close to 0,
where `(rbar/rᵢ)^η` explodes). `form = :linear` (`_linear_reinvestment`):

    gk = λ·σbarᵢ·[(1−η)·sk + η·rbar_K·kv] + μ·gap + effects + u,

which is defined for profit rates of any sign, so it uses every row with a
positive `σbar` (`valid_linear`; `ratio_bounds` default `(-Inf, Inf)`).
`exit_hurdle = h` adds the exit of unprofitable capital (`_exit_flow`), the
regressor `100·max(h·rbar − r, 0)` with coefficient `−φ`. Depreciation is in
the country × sector effects. `λ = 1` is the model's own level (each
department reinvests its share `σ_c`); `λ < 1` means investment follows own
surplus less than the average share implies.

The panel identifies `η` poorly (notebook 11), so this returns the whole
profile over `η_grid`, for `η` to be calibrated and `μ` read off at it. The
linear form is also linear in `(λ(1−η), λη)`, so it is estimated freely as
well: `unrestricted` gives `λ̂`, `η̂ = λη/λ` and their clustered errors
(delta method).

Returns `(profile, n, dropped, unrestricted)`: `profile` a DataFrame with,
per `η`, `λ` and `μ`, their country-clustered standard errors `se_λ`, `se_μ`,
the Driscoll–Kraay error `se_DK_μ`, the residual sum of squares `ssr`, and
`φ`, `se_φ` with an exit hurdle; `n` the rows used; `dropped` the rows left
out; `unrestricted` a NamedTuple for the linear form (`nothing` for the
power form).
"""
function estimate_investment_function(P::AbstractDataFrame; η_grid = 0:0.1:1.0, form::Symbol = :power,
                                      ratio_bounds = nothing, exit_hurdle = nothing,
                                      effects = (:geo_section, :geo_year), lags::Integer = 2)
    form in (:power, :linear) || throw(ArgumentError("form must be :power or :linear, got :$form"))
    isempty(η_grid) && throw(ArgumentError("empty η_grid"))
    all(η -> isfinite(η) && η >= 0, η_grid) || throw(ArgumentError("η_grid must hold finite values ≥ 0"))
    isnothing(exit_hurdle) || (exit_hurdle isa Real && isfinite(exit_hurdle) && exit_hurdle >= 0) ||
        throw(ArgumentError("exit_hurdle must be a finite number ≥ 0, got $exit_hurdle"))
    lo, hi = isnothing(ratio_bounds) ? (form === :power ? (0.0, Inf) : (-Inf, Inf)) : ratio_bounds
    lo < hi || throw(ArgumentError("ratio_bounds must satisfy lower < upper"))
    (form === :power && lo < 0) && throw(ArgumentError("the power form needs ratio_bounds ≥ 0"))
    keep = (form === :power ? P.valid : P.valid_linear) .& (lo .<= P.r ./ P.rbar .<= hi)
    Q = P[keep, :]
    z = isnothing(exit_hurdle) ? nothing : 100 .* max.(exit_hurdle .* Q.rbar .- Q.r, 0)
    with_exit(X) = isnothing(z) ? X : hcat(X, z)
    term(η) = form === :power ? Q.σbar .* (Q.rbar ./ Q.r) .^ η .* Q.sk :
                                Q.σbar .* ((1 - η) .* Q.sk .+ η .* Q.rbar_K .* Q.kv)
    rows = map(collect(η_grid)) do η
        e = estimate_fe_ols(Q, Q.gk, with_exit(hcat(term(η), Q.gap)); effects = effects, lags = lags)
        row = (η = Float64(η), λ = e.β[1], se_λ = e.se_cluster[1], μ = e.β[2], se_μ = e.se_cluster[2],
               se_DK_μ = e.se_DK[2], ssr = e.ssr)
        isnothing(z) ? row : merge(row, (φ = -e.β[3], se_φ = e.se_cluster[3]))
    end
    unrestricted = nothing
    if form === :linear
        e = estimate_fe_ols(Q, Q.gk, with_exit(hcat(Q.σbar .* Q.sk, Q.σbar .* Q.rbar_K .* Q.kv, Q.gap));
                            effects = effects, lags = lags)
        a, b = e.β[1], e.β[2]
        Vab = e.V_cluster[1:2, 1:2]
        g_λ, g_η = [1.0, 1.0], [-b, a] ./ (a + b)^2
        unrestricted = (λ = a + b, se_λ = sqrt(g_λ' * Vab * g_λ), η = b / (a + b), se_η = sqrt(g_η' * Vab * g_η),
                        μ = e.β[3], se_μ = e.se_cluster[3], ssr = e.ssr)
        isnothing(z) || (unrestricted = merge(unrestricted, (φ = -e.β[4], se_φ = e.se_cluster[4])))
    end
    return (profile = DataFrame(rows), n = nrow(Q), dropped = nrow(P) - nrow(Q), unrestricted = unrestricted)
end

"""
    compute_incremental_panel(raw; sections, countries = nothing, self_employed = :excluded,
                              window = 1, real = true)

The panel of `compute_mobility_panel` with Shaikh's incremental rate of
profit beside the average rate (Shaikh 2016, ch. 7, eq. 7.7): the return on
new investment, approximated by the change in gross profit over the gross
investment that preceded it,

    r_I,t = (Πₜ − Πₜ₋w) / Σₖ₌₁…w Iₜ₋ₖ,

with gross profit `Π = GVA − V` (the self-employed imputed in `V` with
`self_employed = :imputed`) and `I` gross fixed capital formation. With
`real = true` (the default) both are real: `Π` is deflated by the sector's
GVA deflator `GVA/GVA_volume` and `I` is `GFCF_volume` (the extract's
chain-linked volumes); `real = false` uses current prices. `window = w`
sums over `w` years, which smooths the rate; the sum looks only backwards,
so the rate can be a regressor.

The rate is dated like the average-rate gap, in t−1, so both can explain
the transfer `y` of year t. Adds the columns `rI` (r_I of t−1), `I_lag` (its
denominator, the investment sum), `rIbar` (the country's investment-weighted
mean `ΣΔΠ/ΣI` in t−1, so the gaps weighted by `I_lag` sum to zero) and
`gap_I = 100·(rI − rIbar)` (pp). Rows without the earlier
years the rate needs, or whose lagged investment sum is not positive, are
dropped; returns `(panel, dropped)`.
"""
function compute_incremental_panel(raw::AbstractDataFrame; sections, countries = nothing,
                                   self_employed::Symbol = :excluded, window::Integer = 1,
                                   real::Bool = true)
    window >= 1 || throw(ArgumentError("window must be ≥ 1, got $window"))
    real && !all(c -> c in names(raw), ("GVA_volume", "GFCF_volume")) &&
        throw(ArgumentError("real = true needs the columns GVA_volume and GFCF_volume"))
    P = compute_mobility_panel(raw; sections = sections, countries = countries,
                               self_employed = self_employed)
    geo = "geo" in names(raw) ? String.(raw.geo) : fill("", nrow(raw))
    V = Float64.(raw.compensation)
    self_employed == :imputed && (V = V .* raw.employment ./ raw.employees)
    Π = Float64.(raw.GVA) .- V
    I = Float64.(raw.GFCF)
    if real
        Π = Π .* Float64.(raw.GVA_volume) ./ Float64.(raw.GVA)
        I = Float64.(raw.GFCF_volume)
    end
    flows = Dict((geo[i], String(raw.section[i]), Int(raw.year[i])) => (Π[i], I[i]) for i in 1:nrow(raw))

    keep = falses(nrow(P))
    dΠ, ΣI = fill(NaN, nrow(P)), fill(NaN, nrow(P))
    for i in 1:nrow(P)
        g, s, t = P.geo[i], P.section[i], P.year[i] - 1         # the rate is dated t−1
        ks = [(g, s, t - k) for k in 0:window]
        all(haskey(flows, k) for k in ks) || continue
        inv = sum(last(flows[(g, s, t - k)]) for k in 1:window)
        inv > 0 || continue
        keep[i] = true
        dΠ[i] = first(flows[(g, s, t)]) - first(flows[(g, s, t - window)])
        ΣI[i] = inv
    end
    Q = P[keep, :]
    Q.rI = dΠ[keep] ./ ΣI[keep]
    Q.I_lag = ΣI[keep]
    w = Q.I_lag
    num, den = Dict{Tuple{String, Int}, Float64}(), Dict{Tuple{String, Int}, Float64}()
    for i in 1:nrow(Q)
        u = (Q.geo[i], Q.year[i])
        num[u] = get(num, u, 0.0) + Q.rI[i] * w[i]
        den[u] = get(den, u, 0.0) + w[i]
    end
    Q.rIbar = [num[u] / den[u] for u in zip(Q.geo, Q.year)]
    Q.gap_I = 100 .* (Q.rI .- Q.rIbar)
    return (panel = Q, dropped = nrow(P) - nrow(Q))
end

"""
    hp_filter(x; λ = 100)

The Hodrick–Prescott trend of the series `x`: the `τ` minimizing
`Σ(xₜ − τₜ)² + λ·Σ(Δ²τₜ)²`, i.e. `(I + λD'D)τ = x` with `D` the second
difference. For display only: the trend of year t uses later years, so it
cannot be a regressor. Series of fewer than 3 points are returned as they
are.
"""
function hp_filter(x::AbstractVector{<:Real}; λ::Real = 100)
    λ >= 0 || throw(ArgumentError("λ must be ≥ 0, got $λ"))
    n = length(x)
    n < 3 && return Float64.(x)
    D = zeros(n - 2, n)
    for t in 1:(n - 2)
        D[t, t], D[t, t + 1], D[t, t + 2] = 1.0, -2.0, 1.0
    end
    return Symmetric(Matrix(1.0I, n, n) .+ λ .* (D'D)) \ Float64.(x)
end

"""
    estimate_persistence(panel, col)

The persistence-of-profits regression of the literature (Mueller; Vaona) for
the gap in column `col` (e.g. `:gap` or `:gap_I`):

    gapᵢₜ = aᵢ + ρ·gapᵢ,ₜ₋₁ + uᵢₜ,

one `aᵢ` per country × sector, over the rows whose previous year is in the
panel. `ρ` measures how fast gaps close; `pᵢ = aᵢ/(1−ρ)` is the gap a
sector keeps in the long run, its permanent position. Competition that
equalizes the rate gives `pᵢ ≈ 0`. With about 25 years per unit the
Nickell bias in `ρ` (downward, of order `(1+ρ)/T`) is small.

Returns `(ρ, se_ρ, permanent, sd_permanent, between_share, n)`: `se_ρ`
clustered by country; `permanent`, a DataFrame of `geo, section, p`;
`sd_permanent`, the standard deviation of `p` across units; and
`between_share`, the share of the gap's variance that is between units
(the variance of the unit means over the total), a measure free of the
dynamic specification.
"""
function estimate_persistence(panel::AbstractDataFrame, col::Symbol)
    z = Float64.(panel[!, col])
    idx = Dict((panel.geo[i], panel.section[i], panel.year[i]) => i for i in 1:nrow(panel))
    rows = [i for i in 1:nrow(panel) if haskey(idx, (panel.geo[i], panel.section[i], panel.year[i] - 1))]
    length(rows) > 3 || throw(ArgumentError("too few rows with a previous year ($(length(rows)))"))
    lag = [z[idx[(panel.geo[i], panel.section[i], panel.year[i] - 1)]] for i in rows]
    Q = panel[rows, :]
    e = estimate_fe_ols(Q, z[rows], lag; effects = (:geo_section,))
    ρ = e.β[1]
    units = tuple.(Q.geo, Q.section)
    sums = Dict{eltype(units), Tuple{Float64, Int}}()
    for (k, u) in enumerate(units)
        a, m = get(sums, u, (0.0, 0))
        sums[u] = (a + z[rows[k]] - ρ * lag[k], m + 1)
    end
    us = sort(collect(keys(sums)))
    p = [first(sums[u]) / last(sums[u]) / (1 - ρ) for u in us]
    allunits = tuple.(panel.geo, panel.section)
    means = Dict(u => mean(z[allunits .== Ref(u)]) for u in unique(allunits))
    between = var([means[u] for u in allunits]; corrected = false) / var(z; corrected = false)
    return (ρ = ρ, se_ρ = e.se_cluster[1],
            permanent = DataFrame(geo = first.(us), section = last.(us), p = p),
            sd_permanent = std(p), between_share = between, n = length(rows))
end
