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
Driscoll–Kraay variance numerator of a slope: the year sums `hₜ = Σ xᵢₜuᵢₜ`
(pooled over countries and sectors), with a Bartlett kernel over `lags`
calendar years.
"""
function _driscoll_kraay_S(x, u, years; lags::Integer)
    ys = sort(unique(years))
    idx = Dict(y => k for (k, y) in enumerate(ys))
    h = zeros(length(ys))
    for i in eachindex(x)
        h[idx[years[i]]] += x[i] * u[i]
    end
    S = sum(abs2, h)
    for l in 1:lags, k in eachindex(ys), k2 in eachindex(ys)
        ys[k2] - ys[k] == l && (S += 2 * (1 - l / (lags + 1)) * h[k] * h[k2])
    end
    return S
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
    n = nrow(panel)
    n >= 3 || throw(ArgumentError("panel too small ($n rows)"))
    groups = [_effect_labels(panel, e) for e in effects]
    yd = demean_fe(panel.y, groups...)
    xd = demean_fe(panel.gap, groups...)
    xx = dot(xd, xd)
    xx > 0 || error("the gap has no variation left after the fixed effects")
    b = dot(xd, yd) / xx
    u = yd .- b .* xd
    dof = n - _absorbed(groups) - 1
    dof > 0 || error("no degrees of freedom left")
    se = sqrt(sum(abs2, u) / dof / xx)
    se_DK = sqrt(_driscoll_kraay_S(xd, u, panel.year; lags = lags)) / xx
    gc, G = _codes(panel.geo)
    se_cl = if G >= 2
        hg = zeros(G)
        for i in eachindex(u)
            hg[gc[i]] += xd[i] * u[i]
        end
        sqrt(G / (G - 1) * sum(abs2, hg)) / xx
    else
        NaN
    end
    return (μ = b, se = se, se_DK = se_DK, se_cluster = se_cl, n = n, countries = G)
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
