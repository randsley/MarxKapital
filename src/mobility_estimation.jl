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
# country-clustered standard errors. Used by notebooks 09 and 10.
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
    XX = Symmetric(Xd'Xd)
    F = cholesky(XX; check = false)
    issuccess(F) || error("the regressors are collinear after the fixed effects")
    β = F \ (Xd'yd)
    u = yd .- Xd * β
    ssr = sum(abs2, u)
    dof = n - _absorbed(groups) - k
    dof > 0 || error("no degrees of freedom left")
    XXi = inv(F)
    se = sqrt.(diag(XXi) .* (ssr / dof))
    se_DK = sqrt.(diag(XXi * _driscoll_kraay_meat(Xd, u, panel.year; lags = lags) * XXi))
    gc, G = _codes(panel.geo)
    se_cl = if G >= 2
        hg = zeros(G, k)
        for i in eachindex(u)
            @views hg[gc[i], :] .+= Xd[i, :] .* u[i]
        end
        sqrt.(diag(XXi * (G / (G - 1) .* (hg'hg)) * XXi))
    else
        fill(NaN, k)
    end
    return (β = β, se = se, se_DK = se_DK, se_cluster = se_cl, ssr = ssr, n = n, countries = G)
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
    return P
end

"""
    estimate_investment_function(P; η_grid = 0:0.1:1.0, ratio_bounds = (0.0, Inf),
                                 effects = (:geo_section, :geo_year), lags = 2)

The model's investment function in data terms (`_reinvestment_share`),

    gk = λ·σbarᵢ·(rbar/rᵢ)^η·sk + μ·gap + effects + u,

estimated at each elasticity `η` of `η_grid`, on the valid rows of a
`compute_investment_panel` panel with `rᵢ/rbar` inside `ratio_bounds`
(trimming the years in which a sector's profit rate is close to 0, where
`(rbar/rᵢ)^η` explodes). Depreciation is in the country × sector effects.
`λ = 1` is the model's own level (each department reinvests its share
`σ_c`); `λ < 1` means investment follows own surplus less than the average
share implies.

The EU sectoral panel does not identify `η` by itself (notebook 11): the fit
is nearly flat in `η`, so this returns the whole profile rather than an
estimate of `η`, for `η` to be calibrated and `μ` read off at it.

Returns `(profile, n, dropped)`: `profile` a DataFrame with, per `η`, `λ`
and `μ`, their country-clustered standard errors `se_λ`, `se_μ`, the
Driscoll–Kraay error `se_DK_μ` and the residual sum of squares `ssr`; `n`
the rows used; `dropped` the rows left out (invalid or outside the bounds).
"""
function estimate_investment_function(P::AbstractDataFrame; η_grid = 0:0.1:1.0,
                                      ratio_bounds = (0.0, Inf),
                                      effects = (:geo_section, :geo_year), lags::Integer = 2)
    isempty(η_grid) && throw(ArgumentError("empty η_grid"))
    all(η -> isfinite(η) && η >= 0, η_grid) || throw(ArgumentError("η_grid must hold finite values ≥ 0"))
    lo, hi = ratio_bounds
    0 <= lo < hi || throw(ArgumentError("ratio_bounds must satisfy 0 ≤ lower < upper"))
    keep = P.valid .& (lo .<= P.r ./ P.rbar .<= hi)
    Q = P[keep, :]
    rows = map(collect(η_grid)) do η
        e = estimate_fe_ols(Q, Q.gk, hcat(Q.σbar .* (Q.rbar ./ Q.r) .^ η .* Q.sk, Q.gap);
                            effects = effects, lags = lags)
        (η = Float64(η), λ = e.β[1], se_λ = e.se_cluster[1], μ = e.β[2], se_μ = e.se_cluster[2],
         se_DK_μ = e.se_DK[2], ssr = e.ssr)
    end
    return (profile = DataFrame(rows), n = nrow(Q), dropped = nrow(P) - nrow(Q))
end
