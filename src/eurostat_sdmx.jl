# ============================================================================
# EUROSTAT SDMX API — REAL SECTORAL DATA
# ============================================================================
# Supplies real sectoral data (GVA, compensation, employment, GFCF, capital
# stock, and intersectoral flows for the technical matrix A) to replace the
# fixed weights/synthetic data in `calibration_pt.jl` and `ameco.jl`. Uses
# Eurostat's SDMX REST API (ec.europa.eu/eurostat/api/dissemination/sdmx), a
# platform separate from the AMECO API (ameco_sdmx.jl) but with the same
# request/response format (SDMX-CSV).
#
# Checked against real data for Portugal (2026-07):
#   GVA (B1G), compensation (D1), CFC (P51C)    → dataflow NAMA_10_A64
#   Employment (EMP_DC)                         → dataflow NAMA_10_A64_E
#   GFCF (P51G, asset10=N11G)                   → dataflow NAMA_10_A64_P5
#   Net capital stock (asset10=N11N)            → dataflow NAMA_10_NFA_ST
#   Intersectoral flows (symmetric IOT)         → dataflow NAIO_10_CP1700 (stk_flow=DOM)
#
# The `nace_r2` dimension accepts 1-letter NACE section codes (A-U)
# directly: the same 19 letters (A-S) already used as `nace_code` in
# `calibration_pt.jl`. A single request with `nace_r2` left blank returns
# every section at once (confirmed). The symmetric IOT does not accept
# sections directly and uses finer codes (A64 level, e.g. "A01",
# "CPA_C10-12"); the matching section is always the first letter of the code
# (after removing the "CPA_" prefix, when present).
#
# Coverage: Eurostat only covers EU/EEA/candidate countries. Countries
# outside that coverage (e.g. the United States, Japan) return empty series,
# so callers of these functions must provide a fallback path (see
# `ameco.jl`, `sector_data=:fixed`).
# ============================================================================

const EUROSTAT_SDMX_BASE_URL = "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1"

"""The 19 NACE Rev.2 sections used as `nace_code` in `calibration_pt.jl`."""
const NACE_SECTIONS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                      "L", "M", "N", "O", "P", "Q", "R", "S"]

"""Sections left out by `sectors=:market` in `calibrate_portugal_model`: real
estate (L, dominated by the imputed rents of owner-occupied dwellings) and the
non-market services of public administration, education and health (O, P, Q),
whose operating surplus is by convention only depreciation, so that their
rate of exploitation is ≈ 0 by construction. The same 15 market sectors as
notebooks 9–12. See `docs/NATIONAL_ACCOUNTS.md`."""
const NON_MARKET_SECTIONS = ["L", "O", "P", "Q"]

"""
    drop_sections(groups, outside = NON_MARKET_SECTIONS)

`groups` (a list of lists of sections, e.g. `NACE_MEDIUM_GROUPS`) without the
sections in `outside`, dropping the groups left empty. Returns
`(groups, kept)`, `kept` the indices of the surviving groups, so that the
groups' codes and names can be filtered the same way.
"""
function drop_sections(groups::Vector{Vector{String}}, outside::Vector{String} = NON_MARKET_SECTIONS)
    filtered = [filter(s -> !(s in outside), g) for g in groups]
    kept = findall(!isempty, filtered)
    return filtered[kept], kept
end

"""Macro aggregation (3 sectors: Primary/Secondary/Tertiary), used by the
AMECO path (`src/ameco.jl`) and by `aggregation=:macro` in the INE path
(`src/calibration_pt.jl`)."""
const NACE_MACRO_GROUPS = [["A"], ["B", "C", "D", "E", "F"],
                           ["G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S"]]

"""Intermediate aggregation: the standard NACE Rev.2 "A10" level (10 groups),
restricted to the sections A-S already used in this project (no T/U,
household and extraterritorial activities, irrelevant here). Used by
`aggregation=:medium` in the INE path (`src/calibration_pt.jl`)."""
const NACE_MEDIUM_GROUPS = [
    ["A"],                  # Agriculture, forestry and fishing
    ["B", "C", "D", "E"],   # Industry, incl. energy
    ["F"],                  # Construction
    ["G", "H", "I"],        # Trade, transport, accommodation and food service
    ["J"],                  # Information and communication
    ["K"],                  # Financial and insurance activities
    ["L"],                  # Real estate activities
    ["M", "N"],             # Professional, scientific, administrative activities
    ["O", "P", "Q"],        # Public administration, education, health
    ["R", "S"],             # Arts, other service activities
]

"""
Calls Eurostat's SDMX API for `dataflow`/`key_` and returns a
Dict{String,Dict{String,Dict{Int,Float64}}} country (`geo`) → NACE section →
(year → value). The key may name several countries (`…AT+BE+PT`) or leave
`geo` open. Filters the response to rows whose `nace_r2` is a 1-letter section
(A-S); ignores the finer A64 subdivisions and the T/U sections (household and
extraterritorial activities, irrelevant here). A failure (network, format, no
data) returns an empty dictionary; it never throws.
"""
function _fetch_eurostat_sections_by_geo(dataflow::String, key_::String; readtimeout = 30)
    _fetch_eurostat_sections_by(dataflow, key_, "geo"; readtimeout = readtimeout)
end

"""
Like `_fetch_eurostat_sections_by_geo`, grouped by the dimension `column` of
the response instead of `geo` (for example `"asset10"`, for a key naming one
country and several asset types).
"""
function _fetch_eurostat_sections_by(dataflow::String, key_::String, column::String; readtimeout = 30)
    none = Dict{String, Dict{String, Dict{Int, Float64}}}()
    url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,$dataflow,1.0/$key_?format=SDMX-CSV"
    try
        resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                        retry = true, readtimeout = readtimeout, status_exception = false)
        resp.status == 200 || return none
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        (nrow(df) == 0 || !all(c -> c in names(df), ("nace_r2", column, "TIME_PERIOD", "OBS_VALUE"))) &&
            return none

        result = none
        for row in eachrow(df)
            section = String(row.nace_r2)
            (length(section) == 1 && section in NACE_SECTIONS) || continue
            ismissing(row.OBS_VALUE) && continue
            d = get!(get!(result, String(row[column]), Dict{String, Dict{Int, Float64}}()),
                     section, Dict{Int, Float64}())
            d[Int(row.TIME_PERIOD)] = Float64(row.OBS_VALUE)
        end
        return result
    catch
        return none
    end
end

"""
Like `_fetch_eurostat_sections_by_geo`, for a key naming a single country:
returns a Dict{String,Dict{Int,Float64}} NACE section → (year → value), empty
on any failure.
"""
function _fetch_eurostat_sections(dataflow::String, key_::String)
    by_geo = _fetch_eurostat_sections_by_geo(dataflow, key_)
    length(by_geo) == 1 ? only(values(by_geo)) : Dict{String, Dict{Int, Float64}}()
end

"""Like `_fetch_eurostat_sections`, but already reduced to a single year (Dict{String,Float64})."""
function _eurostat_sector_values(dataflow::String, key_::String, year::Int)
    sections = _fetch_eurostat_sections(dataflow, key_)
    Dict(s => v[year] for (s, v) in sections if haskey(v, year))
end

"""GVA, compensation of employees and consumption of fixed capital per section (million euros)."""
function fetch_eurostat_gva_compensation_cfc(country_code::String, year::Int)
    gva   = _eurostat_sector_values("NAMA_10_A64", "A.CP_MEUR..B1G.$country_code", year)
    comp = _eurostat_sector_values("NAMA_10_A64", "A.CP_MEUR..D1.$country_code", year)
    cfc   = _eurostat_sector_values("NAMA_10_A64", "A.CP_MEUR..P51C.$country_code", year)
    return gva, comp, cfc
end

"""Employment per section (thousand persons, domestic concept)."""
function fetch_eurostat_sector_employment(country_code::String, year::Int)
    _eurostat_sector_values("NAMA_10_A64_E", "A.THS_PER..EMP_DC.$country_code", year)
end

"""
    fetch_eurostat_sector_hours(country_code, year; who = :employed)

Hours worked per section (thousand hours, domestic concept, `THS_HW`): by
everyone employed (`who = :employed`, `EMP_DC`) or by employees only
(`who = :employees`, `SAL_DC`). Used by `self_employed = :imputed_hours`.
"""
function fetch_eurostat_sector_hours(country_code::String, year::Int; who::Symbol = :employed)
    item = who == :employed ? "EMP_DC" : who == :employees ? "SAL_DC" :
           throw(ArgumentError("who must be :employed or :employees, got :$who"))
    _eurostat_sector_values("NAMA_10_A64_E", "A.THS_HW..$item.$country_code", year)
end

"""Employees per section (thousand persons, domestic concept): `SAL_DC`, the
part of `EMP_DC` (`fetch_eurostat_sector_employment`) that earns compensation
of employees; the rest are the self-employed."""
function fetch_eurostat_sector_employees(country_code::String, year::Int)
    _eurostat_sector_values("NAMA_10_A64_E", "A.THS_PER..SAL_DC.$country_code", year)
end

# ----------------------------------------------------------------------------
# Self-employment (shared by the INE/Eurostat and AMECO paths)
# ----------------------------------------------------------------------------

"""
Checks the `self_employed` keyword: `:excluded` or `:imputed`, and also
`:imputed_hours` where `hours_ok` (only the Portuguese sectoral calibration,
which fetches hours worked; the AMECO path and the EU sectoral extract have
no hours series).
"""
function _check_self_employed(self_employed::Symbol; hours_ok::Bool = false)
    if self_employed == :imputed_hours && !hours_ok
        throw(ArgumentError("self_employed=:imputed_hours is only available in calibrate_portugal_model " *
                            "(data_source=:eurostat); this path has no hours-worked series"))
    end
    allowed = hours_ok ? (:excluded, :imputed, :imputed_hours) : (:excluded, :imputed)
    self_employed in allowed ||
        throw(ArgumentError("self_employed must be one of $(join(":" .* string.(allowed), ", ")), got :$self_employed"))
    return self_employed
end

"""
    _self_employed_ratio(employment, employees)

`employment / employees`, the factor that counts each self-employed worker at
the average employee's compensation (the imputation of AMECO's adjusted wage
share), in persons. `NaN` when the ratio is not finite or is below 1 (more
employees than employed persons): callers decide whether that is an error.
"""
function _self_employed_ratio(employment::Real, employees::Real)
    ratio = employment / employees
    return (isfinite(ratio) && ratio >= 1) ? Float64(ratio) : NaN
end

"""
    impute_self_employed(compensation, employment, employees, sections)

Compensation per section with the self-employed imputed,
`Vᵢ × employmentᵢ / employeesᵢ`, for each code in `sections` (the arguments
are `Dict{String,Float64}` section → value, as returned by the Eurostat
fetchers). Imputed at the 19 fine sections, before any aggregation, since the
share of self-employment differs widely between sections (in Portugal, 2022,
two thirds of those working in agriculture but 5% in manufacturing). Throws
if a section's ratio is invalid (see `_self_employed_ratio`). `employment` and
`employees` can be persons (`self_employed = :imputed`) or hours worked
(`:imputed_hours`, `fetch_eurostat_sector_hours`): by hours, a self-employed
worker who works part of the year counts for less. Pure (no network).
"""
function impute_self_employed(compensation::Dict{String, Float64}, employment::Dict{String, Float64},
                              employees::Dict{String, Float64}, sections::Vector{String})
    result = Dict{String, Float64}()
    for s in sections
        ratio = _self_employed_ratio(employment[s], employees[s])
        isnan(ratio) && error("self_employed=:imputed needs employment ≥ employees > 0 in " *
                              "section $s (employment $(employment[s]), employees $(employees[s]))")
        result[s] = compensation[s] * ratio
    end
    return result
end

"""GFCF (gross fixed capital formation) per section, all asset types (million euros)."""
function fetch_eurostat_sector_gfcf(country_code::String, year::Int)
    _eurostat_sector_values("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$country_code", year)
end

"""Net capital stock per section, all asset types (million euros, replacement cost)."""
function fetch_eurostat_sector_capital_stock(country_code::String, year::Int)
    _eurostat_sector_values("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$country_code", year)
end

"""Full series (all available years) of GFCF per section, used by the perpetual inventory (`compute_pim_capital_stock`)."""
function fetch_eurostat_sector_gfcf_series(country_code::String)
    _fetch_eurostat_sections("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$country_code")
end

"""Full series (all available years) of the net capital stock per section, used as the benchmark by the perpetual inventory."""
function fetch_eurostat_sector_capital_stock_series(country_code::String)
    _fetch_eurostat_sections("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$country_code")
end

"""Full series (all available years) of CFC per section, used to estimate δ in the perpetual inventory."""
function fetch_eurostat_sector_cfc_series(country_code::String)
    _fetch_eurostat_sections("NAMA_10_A64", "A.CP_MEUR..P51C.$country_code")
end

"""
    compute_pim_capital_stock(gfcf_series, δ, benchmark_year, benchmark_value, years)

Builds a capital stock series by the perpetual inventory method (PIM):
`Kₜ = (1-δ)·Kₜ₋₁ + GFCFₜ`, from a benchmark year (`benchmark_year`,
`benchmark_value`, typically the net stock Eurostat reports in the earliest
available year) and a GFCF series (`gfcf_series`, a `Dict{Int,Float64}`
year→value). `δ` is a single depreciation rate (not broken down by asset
type, which would be a higher-fidelity extension; see `docs/LIMITATIONS.md`
item 7), typically estimated as `CFC/stock` in the benchmark year, not a
fixed ~10%.

Returns a `Dict{Int,Float64}` year→stock, only for the years the recursion
can reach without a break (it stops if GFCF is missing in some intermediate
year: the series is truncated at that point, not extrapolated).
"""
function compute_pim_capital_stock(gfcf_series::Dict{Int, Float64}, δ::Float64,
                                    benchmark_year::Int, benchmark_value::Float64,
                                    years::Vector{Int})
    K = Dict{Int, Float64}(benchmark_year => benchmark_value)
    for a in (benchmark_year + 1):maximum(years)
        (haskey(gfcf_series, a) && haskey(K, a - 1)) || continue
        K[a] = (1 - δ) * K[a - 1] + gfcf_series[a]
    end
    return K
end

# ----------------------------------------------------------------------------
# Perpetual inventory by asset type
# ----------------------------------------------------------------------------

"""
Asset types of the perpetual inventory by asset (`ESA 2010` codes without
the trailing `G`/`N`): dwellings, other buildings and structures, transport
equipment, other machinery and equipment (`N11M − N1131`, published as
`N11O` only from 2010), cultivated biological resources and intellectual
property products. Their net stocks add up to `N11N`.
"""
const PIM_ASSETS = ["N111", "N112", "N1131", "N11O", "N115", "N117"]

"""
Series by asset type and section, `asset → section → (year → value)`, from
the asset codes Eurostat publishes (`N111`, `N112`, `N1131`, `N11M`, `N115`,
`N117` plus a suffix), with other machinery derived as `N11M − N1131` where
both are present. Empty on any failure.
"""
function _assets_from_published(raw)
    out = Dict{String, Dict{String, Dict{Int, Float64}}}()
    for (code, sections) in raw
        a = code[1:end-1]
        a in ("N111", "N112", "N1131", "N115", "N117", "N11M") && (out[a] = sections)
    end
    if haskey(out, "N11M")
        M = pop!(out, "N11M")
        T = get(out, "N1131", Dict{String, Dict{Int, Float64}}())
        out["N11O"] = Dict(s => Dict(y => v - get(get(T, s, Dict{Int, Float64}()), y, 0.0) for (y, v) in ys)
                           for (s, ys) in M)
    end
    return out
end

"""
    fetch_eurostat_sector_gfcf_by_asset_series(country; unit = "CLV15_MEUR")

GFCF per asset type (`PIM_ASSETS`) and section, all years:
`asset → section → (year → value)`. `unit` is `"CLV15_MEUR"` (chain-linked
volumes) or `"CP_MEUR"` (current prices). `NAMA_10_A64_P5`.
"""
function fetch_eurostat_sector_gfcf_by_asset_series(country_code::String; unit::String = "CLV15_MEUR")
    assets = join(("N111G", "N112G", "N1131G", "N11MG", "N115G", "N117G"), "+")
    _assets_from_published(_fetch_eurostat_sections_by("NAMA_10_A64_P5",
        "A.$unit..$assets.P51G.$country_code", "asset10"))
end

"""
    fetch_eurostat_sector_capital_stock_by_asset_series(country; unit = "CLV15_MEUR")

Net fixed capital stock per asset type (`PIM_ASSETS`) and section, all
years (end of year), as `fetch_eurostat_sector_gfcf_by_asset_series`.
`unit` is `"CLV15_MEUR"` or `"CRC_MEUR"` (current replacement cost).
`NAMA_10_NFA_ST`.
"""
function fetch_eurostat_sector_capital_stock_by_asset_series(country_code::String; unit::String = "CLV15_MEUR")
    assets = join(("N111N", "N112N", "N1131N", "N11MN", "N115N", "N117N"), "+")
    _assets_from_published(_fetch_eurostat_sections_by("NAMA_10_NFA_ST",
        "A.$unit..$assets.$country_code", "asset10"))
end

"""
    estimate_asset_depreciation(gfcf, stock)

Depreciation rate of one asset type from its volume series (`year → value`,
the same chain-linked unit for both), backed out of the stock identity
`Kₜ = (1 − δ)Kₜ₋₁ + Iₜ`: the median over years of `(Kₜ₋₁ + Iₜ − Kₜ)/Kₜ₋₁`.
Volumes have no revaluation, so this is the rate the national accountants'
own depreciation profile implies. Returns `nothing` if no year has
`Kₜ₋₁ > 0` and both flows, or if the median is not in (0, 1).
"""
function estimate_asset_depreciation(gfcf::Dict{Int, Float64}, stock::Dict{Int, Float64})
    rates = [(stock[t-1] + gfcf[t] - stock[t]) / stock[t-1]
             for t in keys(stock) if haskey(stock, t - 1) && haskey(gfcf, t) && stock[t-1] > 0]
    isempty(rates) && return nothing
    δ = median(rates)
    return 0 < δ < 1 ? δ : nothing
end

"""
    _asset_deflator(Icur, Ivol, year)

Price index of an asset's investment in `year`, `GFCF at current prices /
GFCF in volumes`, taken from the nearest year in which both flows are
positive (a year of net disposals, with negative GFCF, carries no usable
ratio). `nothing` if there is no such year.
"""
function _asset_deflator(Icur, Ivol, year::Int)
    ok = [t for t in keys(Ivol) if get(Ivol, t, 0.0) > 0 && get(Icur, t, 0.0) > 0]
    isempty(ok) && return nothing
    t = ok[argmin(abs.(ok .- year))]
    return Icur[t] / Ivol[t]
end

"""
    _asset_volumes(Ivol, Icur, years, deflator)

Volume GFCF of one asset over `years`, filling the gaps of the published
volume series: a year with no volume and zero or no current-price GFCF (an
asset the section holds but does not buy) counts as zero; a year with a
current-price value but no published volume gets `Icur/deflator`.
"""
function _asset_volumes(Ivol, Icur, years, deflator)
    I = Dict{Int, Float64}(Ivol)
    for t in years
        haskey(I, t) && continue
        c = get(Icur, t, 0.0)
        if c == 0
            I[t] = 0.0
        elseif !isnothing(deflator)
            I[t] = c / deflator
        end
    end
    return I
end

"""
    compute_pim_capital_stock_by_asset(gfcf_vol, gfcf_cur, stock_vol, year; δ_fallback = Dict())

Net capital stock of one section in `year`, at current prices, by the
perpetual inventory per asset type. Each argument maps asset → (year →
value): GFCF in chain-linked volumes and at current prices, and the net
stock in volumes. For each asset:

1. the volume GFCF series, with its gaps filled (`_asset_volumes`);
2. `δₐ` from the volume series (`estimate_asset_depreciation`), or, where
   the section's own series give none (a small holding that barely moves,
   or grows only by reclassification), `δ_fallback[a]`, the same asset type's
   rate in the other sections;
3. the recursion `Kₐ,ₜ = (1 − δₐ)Kₐ,ₜ₋₁ + Iₐ,ₜ` in volumes
   (`compute_pim_capital_stock`), seeded with the reported volume stock in
   the earliest year with stock and GFCF;
4. revaluation to current prices by the asset's own GFCF deflator
   (`_asset_deflator`: current prices over volumes, in `year` or the nearest
   year with positive flows); an asset the section never buys (dwellings
   held by a construction firm, say) has no investment price, and is
   revalued by the deflator of the section's total GFCF instead.

Then summed over assets. An asset with no positive stock and no GFCF in
`year` contributes nothing. Returns `nothing` if some asset with a positive
stock still cannot be computed, so that the caller can fall back.
"""
function compute_pim_capital_stock_by_asset(gfcf_vol, gfcf_cur, stock_vol, year::Int;
                                            δ_fallback = Dict{String, Float64}())
    total = 0.0
    years_all = union(Int[], (keys(v) for v in values(gfcf_vol))...)
    section_deflator = _asset_deflator(
        Dict(t => sum(get(v, t, 0.0) for v in values(gfcf_cur)) for t in years_all),
        Dict(t => sum(get(v, t, 0.0) for v in values(gfcf_vol)) for t in years_all), year)
    for a in union(keys(stock_vol), keys(gfcf_vol))
        K = get(stock_vol, a, Dict{Int, Float64}())
        Icur = get(gfcf_cur, a, Dict{Int, Float64}())
        Ivol = get(gfcf_vol, a, Dict{Int, Float64}())
        if !any(v -> v > 0, values(K))
            get(Ivol, year, 0.0) == 0 && continue
            return nothing
        end
        own = _asset_deflator(Icur, Ivol, year)
        P = isnothing(own) ? section_deflator : own
        I = _asset_volumes(Ivol, Icur, minimum(keys(K)):max(year, maximum(keys(K))), P)
        δ = estimate_asset_depreciation(I, K)
        isnothing(δ) && (δ = get(δ_fallback, a, nothing))
        isnothing(δ) && return nothing
        possible = [t for t in keys(K) if haskey(I, t) && K[t] > 0]
        isempty(possible) && return nothing
        b = minimum(possible)
        Kv = compute_pim_capital_stock(I, δ, b, K[b], collect(b:year))
        haskey(Kv, year) || return nothing
        Kv[year] == 0 && continue
        isnothing(P) && return nothing
        total += Kv[year] * P
    end
    return total
end

"""
    asset_depreciation_rates(gfcf_vol, gfcf_cur, stock_vol)

`δₐ` of every asset type in every section (`asset → section → δ`), from
series `asset → section → (year → value)`, with the volume gaps filled as in
`compute_pim_capital_stock_by_asset`. Sections without a valid rate are left
out; the median over the others is the `δ_fallback` of that asset type.
"""
function asset_depreciation_rates(gfcf_vol, gfcf_cur, stock_vol)
    out = Dict{String, Dict{String, Float64}}()
    for (a, by_section) in stock_vol, (c, K) in by_section
        any(v -> v > 0, values(K)) || continue
        Ivol = get(get(gfcf_vol, a, Dict()), c, Dict{Int, Float64}())
        Icur = get(get(gfcf_cur, a, Dict()), c, Dict{Int, Float64}())
        I = _asset_volumes(Ivol, Icur, minimum(keys(K)):maximum(keys(K)), _asset_deflator(Icur, Ivol, maximum(keys(K))))
        δ = estimate_asset_depreciation(I, K)
        isnothing(δ) || (get!(out, a, Dict{String, Float64}())[c] = δ)
    end
    return out
end

"""NACE section (1 letter) of an IOT A64 code (e.g. "A01"→"A", "CPA_C10-12"→"C")."""
function _section_of_a64_code(code::String)
    s = startswith(code, "CPA_") ? code[5:end] : code
    isempty(s) && return ""
    return string(uppercase(s[1]))
end

"""Known benchmark years in which Eurostat publishes NAIO_10_CP1700 (the full
symmetric table). This table is a benchmark product, not an annual series
like NAMA_10_A64; a real query (2026-07) confirmed that it only returns data
for Portugal in these years. `_nearest_iot_year` picks the available year
closest to the one requested, without assuming the list stays fixed: it
tries a live query first (see `build_eurostat_io_matrix`)."""
const KNOWN_IOT_YEARS = [2010, 2013, 2015, 2017, 2020]

"""Picks, among the available years the API returns for
NAIO_10_CP1700/`country_code`, the one closest to `year`. Returns `nothing`
if the query fails or there is no available year."""
function _nearest_iot_year(country_code::String, year::Int)
    url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.DOM.CPA_A01.B1G.$country_code" *
          "?format=SDMX-CSV"
    resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                    retry = true, readtimeout = 30, status_exception = false)
    resp.status == 200 || return nothing
    df = CSV.read(IOBuffer(resp.body), DataFrame)
    nrow(df) == 0 && return nothing
    years = Int.(df.TIME_PERIOD)
    isempty(years) && return nothing
    return years[argmin(abs.(years .- year))]
end

"""IOT DataFrames already downloaded in this session, by (country, year)."""
const _IOT_CACHE = Dict{Tuple{String, Int}, DataFrame}()

"""
    _fetch_iot(country_code, iot_year)

Downloads the domestic-use symmetric IOT (`NAIO_10_CP1700`, `stk_flow=DOM`)
for one benchmark year, caching it for the session: the technical matrix
(`build_eurostat_io_matrix`), final demand (`fetch_eurostat_final_demand`)
and the import coefficients (`fetch_eurostat_import_coefficients`) read the
same table.
"""
function _fetch_iot(country_code::String, iot_year::Int)
    get!(_IOT_CACHE, (country_code, iot_year)) do
        url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.DOM...$country_code" *
              "?format=SDMX-CSV&startPeriod=$iot_year&endPeriod=$iot_year"
        resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                        retry = true, readtimeout = 60, status_exception = false)
        resp.status == 200 || error("Eurostat IOT unavailable for $country_code/$iot_year (status $(resp.status)).")
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        nrow(df) == 0 && error("Eurostat IOT has no data for $country_code/$iot_year.")
        df
    end
end

"""
    final_demand_from_iot(df, sections = NACE_SECTIONS)

Final demand for domestic output by product, read from the final-use columns
of the domestic-use IOT (`prd_use`), summed from A64 products to NACE
sections (million euros). Returns a NamedTuple of vectors in the order of
`sections`:

- `household`: final consumption of households and NPISH (`P3_S14 + P3_S15`);
- `government`: government final consumption (`P3_S13`);
- `investment`: gross capital formation (`P5`: fixed capital, inventories
  and valuables);
- `exports` (`P6`);
- `output`: total use of the product (`TU`, intermediate plus final use),
  which equals its domestic output.

Pure (no network), so that it can be tested on a small DataFrame.
"""
function final_demand_from_iot(df::DataFrame, sections::Vector{String} = NACE_SECTIONS)
    idx = Dict(s => i for (i, s) in enumerate(sections))
    G = length(sections)
    columns = Dict("P3_S14" => :household, "P3_S15" => :household, "P3_S13" => :government,
                   "P5" => :investment, "P6" => :exports, "TU" => :output)
    totals = Dict(k => zeros(G) for k in (:household, :government, :investment, :exports, :output))
    for row in eachrow(df)
        ismissing(row.OBS_VALUE) && continue
        pu, pa = String(row.prd_use), String(row.prd_ava)
        (haskey(columns, pu) && startswith(pa, "CPA_")) || continue
        s = _section_of_a64_code(pa)
        haskey(idx, s) && (totals[columns[pu]][idx[s]] += Float64(row.OBS_VALUE))
    end
    return (sections = copy(sections), household = totals[:household],
            government = totals[:government], investment = totals[:investment],
            exports = totals[:exports], output = totals[:output])
end

"""
    fetch_eurostat_final_demand(country_code, year)

Final demand by NACE section (see `final_demand_from_iot`) from the IOT of
the benchmark year nearest to `year` (the same vintage rule as
`build_eurostat_io_matrix`). Needs the network.
"""
function fetch_eurostat_final_demand(country_code::String, year::Int)
    iot_year = _nearest_iot_year(country_code, year)
    isnothing(iot_year) && error("Eurostat IOT (NAIO_10_CP1700) unavailable for $country_code.")
    return final_demand_from_iot(_fetch_iot(country_code, iot_year))
end

"""
    aggregate_final_demand(fd, groups, codes)

Sums final demand (see `final_demand_from_iot`) over groups of sections
(e.g. `NACE_MACRO_GROUPS`); final demand is additive, unlike the technical
coefficients (`aggregate_io_matrix`). `codes` names the groups.
"""
function aggregate_final_demand(fd, groups::Vector{Vector{String}}, codes::Vector{String})
    idx = Dict(s => i for (i, s) in enumerate(fd.sections))
    agg(v) = [sum(v[idx[s]] for s in g if haskey(idx, s); init = 0.0) for g in groups]
    return (sections = copy(codes), household = agg(fd.household),
            government = agg(fd.government), investment = agg(fd.investment),
            exports = agg(fd.exports), output = agg(fd.output))
end

"""
    import_coefficients_from_iot(df, sections = NACE_SECTIONS)

Imported intermediate inputs per unit of gross output, by buying industry:
`mⱼ = IMPⱼ / P1ⱼ`, from two rows of the domestic-use IOT (`df`, as returned
by `_fetch_iot`): `IMP`, the total of imported products the industry uses
as inputs, and `P1`, its gross output. Both are summed from A64 codes to
NACE sections. Returns a `Dict{String,Float64}` section → `mⱼ`, for the
sections with positive gross output.

The `IMP` row equals the sum of the industry's column in the imported-use
table (`stk_flow=IMP`, checked for PT 2020), so no second download is
needed; that table also has a `CPA_TOTAL` row, which a sum over its
`CPA_*` rows would count twice. With `IMP`, domestic inputs plus imports
plus GVA reconcile to `P1` within about 1% (PT 2020).

The domestic matrix `A` leaves imported inputs out by design (see
`build_eurostat_io_matrix`), so the gross output rebuilt from value added
must add them back: `xⱼ = Wⱼ/(1 − Σᵢ A[i,j] − mⱼ)` (see `_gross_output`,
`src/core.jl`). Pure (no network).
"""
function import_coefficients_from_iot(df::DataFrame, sections::Vector{String} = NACE_SECTIONS)
    P1 = Dict(s => 0.0 for s in sections)
    M = Dict(s => 0.0 for s in sections)
    for row in eachrow(df)
        ismissing(row.OBS_VALUE) && continue
        pa, pu = String(row.prd_ava), String(row.prd_use)
        (pa in ("P1", "IMP") && startswith(pu, "CPA_")) || continue
        sj = _section_of_a64_code(pu)
        haskey(P1, sj) || continue
        pa == "P1" ? (P1[sj] += Float64(row.OBS_VALUE)) : (M[sj] += max(Float64(row.OBS_VALUE), 0.0))
    end
    return Dict(s => M[s] / P1[s] for s in sections if P1[s] > 0)
end

"""
    fetch_eurostat_import_coefficients(country_code, year)

Import coefficients by NACE section (see `import_coefficients_from_iot`)
from the IOT of the benchmark year nearest to `year` (the same vintage rule
as `build_eurostat_io_matrix`). Needs the network.
"""
function fetch_eurostat_import_coefficients(country_code::String, year::Int)
    iot_year = _nearest_iot_year(country_code, year)
    isnothing(iot_year) && error("Eurostat IOT (NAIO_10_CP1700) unavailable for $country_code.")
    return import_coefficients_from_iot(_fetch_iot(country_code, iot_year))
end

"""
    outside_input_coefficients(A, sections, outside = NON_MARKET_SECTIONS)

Inputs that each kept section buys from the sections in `outside`, per unit
of its gross output: `Σᵢ∈outside A[i,j]` for every `j` not in `outside`, as a
Dict section → coefficient. When `sectors=:market` drops those sections,
these purchases come from outside the modelled economy, like imports, and are
added to the import coefficients so that `_gross_output` (`src/core.jl`)
still rebuilds gross output from value added. Pure (no network).
"""
function outside_input_coefficients(A::AbstractMatrix{<:Real}, sections::Vector{String},
                                    outside::Vector{String} = NON_MARKET_SECTIONS)
    out = [i for (i, s) in enumerate(sections) if s in outside]
    Dict(s => sum(A[i, j] for i in out; init = 0.0)
         for (j, s) in enumerate(sections) if !(s in outside))
end

"""
    outside_purchases_from_iot(df, outside = NON_MARKET_SECTIONS, sections = NACE_SECTIONS)

What the industries in `outside` buy from each section as intermediate input
(million euros), from the product × industry cells of the domestic-use IOT
(`df`, as returned by `_fetch_iot`), summed from A64 codes to sections, in the
order of `sections`. When `sectors=:market` drops those industries, these
purchases become exogenous demand for the kept sections and are added to
government final demand (public administration, education and health are
paid for out of revenue). Pure (no network).
"""
function outside_purchases_from_iot(df::DataFrame, outside::Vector{String} = NON_MARKET_SECTIONS,
                                    sections::Vector{String} = NACE_SECTIONS)
    idx = Dict(s => i for (i, s) in enumerate(sections))
    total = zeros(length(sections))
    for row in eachrow(df)
        ismissing(row.OBS_VALUE) && continue
        pu, pa = String(row.prd_use), String(row.prd_ava)
        (startswith(pa, "CPA_") && startswith(pu, "CPA_")) || continue
        _section_of_a64_code(pu) in outside || continue
        si = _section_of_a64_code(pa)
        haskey(idx, si) && (total[idx[si]] += max(Float64(row.OBS_VALUE), 0.0))
    end
    return total
end

"""
    aggregate_import_coefficients(m, groups, weights)

Aggregates import coefficients (section → `mⱼ`) to `groups` as the weighted
mean over each group's sections, with the same weights (`weights`, GVA by
section) that `aggregate_io_matrix` uses for the columns of `A`. Then
`Σᵢ A_coarse[i,J] + m_J` is the same weighted mean of `Σᵢ A[i,j] + mⱼ`, so the
admissibility of the gross-output reconstruction survives aggregation.
Sections missing from `m` count as `mⱼ = 0`.
"""
function aggregate_import_coefficients(m::Dict{String, Float64}, groups::Vector{Vector{String}},
                                       weights::Dict{String, Float64})
    map(groups) do g
        w = sum(get(weights, s, 0.0) for s in g)
        w > 0 ? sum(get(m, s, 0.0) * get(weights, s, 0.0) for s in g) / w : 0.0
    end
end

"""
    consumption_basket(fd)

Consumption basket of the cross-dual model (`basket` in `simulate_Ndept`)
from real final demand: each sector's share of household and NPISH final
consumption of domestic output. Replaces `basket_initial`, which assumes
shares of initial net output.
"""
consumption_basket(fd) = fd.household ./ sum(fd.household)

"""
    capital_goods_composition(fd; A = nothing, cap = 0.95, min_share = 0.001)

Composition of the capital goods investment buys (`capital_goods` in
`simulate_Ndept_custom`), from real final demand.

- Without `A`: each sector's share of gross capital formation of domestic
  output (`P5`, fixed capital and inventories; a fall in inventories counts
  as 0).
- With the table's `A` (`params.A`): each sector's share of the row
  residual `max(x − A·x − φ·x, 0)` of the table, with `x = fd.output` and
  `φ = exogenous_demand_share(fd; cap)`. That is gross capital formation
  plus the small items the row balance leaves over, and it is the
  composition the netted rationing balance (`net_intermediate`) nets
  against: a sector with a share of `P5` but no residual (D in Portugal's
  table) would otherwise ration every buyer to zero.

Shares below `min_share` are set to 0 before normalizing. Rationing takes
the minimum over every good a sector buys, so a good worth 10⁻⁸ of
investment (or a floating-point remnant of the residual) would otherwise
decide it.
"""
function capital_goods_composition(fd; A = nothing, cap = 0.95, min_share = 0.001)
    b = if isnothing(A)
        max.(fd.investment, 0.0)
    else
        x = fd.output
        max.(x .- A * x .- exogenous_demand_share(fd; cap = cap) .* x, 0.0)
    end
    sum(b) > 0 || throw(ArgumentError("final demand has no gross capital formation"))
    b = b ./ sum(b)
    b[b .< min_share] .= 0.0
    return b ./ sum(b)
end

"""
    exogenous_demand_share(fd; cap = 0.95)

Share of each sector's output that goes to final consumption (households,
NPISH, government) and exports, `φᵢ = (P3ᵢ + P6ᵢ)/TUᵢ`, capped at `cap`.
The rationing step (`final_demand_share` in `simulate_Ndept_custom`) nets
it out of the supply available to investment, `O = (1 − φ)·x`. Gross
capital formation is left out, because rationing models investment demand
itself. Unit-free, so it carries over to the model's value units.
"""
function exogenous_demand_share(fd; cap = 0.95)
    φ = (fd.household .+ fd.government .+ fd.exports) ./ max.(fd.output, 1e-12)
    return clamp.(φ, 0.0, cap)
end

"""
    build_eurostat_io_matrix(country_code, year, groups, gva_by_section)

Builds a G×G technical matrix from Eurostat's real symmetric IOT
(**NAIO_10_CP1700**, "Symmetric input-output table at basic prices, product
by product"), aggregating the A64 codes into `groups` (each element is a list
of NACE sections: `[["A"],["B"],...]` for 19 sectors, or
`[["A"],["B","C","D","E","F"],[...]]` for 3 macro sectors). `gva_by_section`
(from `fetch_eurostat_gva_compensation_cfc`) supplies the GVA that completes
the supply-use identity; it is used only as a fallback when the IOT itself
does not return its `P1` (gross output) row for a section.

**Important historical note:** an earlier version of this code used
`NAIO_10_CP1620`, which, as confirmed with Eurostat, is not the symmetric
table itself but the "Table of trade and transport margins", a small
satellite table used to break the *use table at purchasers' prices* down
into its components (table at basic prices + margins + taxes less
subsidies). Using that table as if it were the symmetric IOT gave
intersectoral flows underestimated by more than an order of magnitude
(total intermediate consumption ≈ €11 bn against the true ≈ €262 bn implied
by P1-GVA, PT/2022), and all the negative cells observed were just the
margin-reallocation mechanics of that satellite table, not a feature of the
real IOT. That in turn explained the implausibly sparse matrix (ρ(A)≈0.13)
and the implausibly high R_max (≈691%) reported before this fix. With
NAIO_10_CP1700, PT/2020: zero negative cells, reconciliation residual
typically <5% (`paper/matrix_audit.jl`), ρ(A)≈0.52 (stk_flow=DOM) or ≈0.60
(stk_flow=TOTAL).

**Note on imports:** NAIO_10_CP1700 publishes three variants by `stk_flow`:
`DOM` (domestic use only), `IMP` (imported only) and `TOTAL` (the sum of the
two), as confirmed by a real query, unlike `NAIO_10_CP1620` (which only
published `TOTAL`). `DOM` is used: the matrix A should represent
\emph{domestic} productive interdependence (which sector supplies which
sector within the modeled economy); imported intermediate inputs are not
produced by any domestic sector, so including them in `A` would imply a
domestic supply relation that does not exist. This choice directly
addresses the concern, raised in an external review, that the matrix mixed
domestic and imported supply without distinction. The imported inputs are
not dropped from the model, though: `fetch_eurostat_import_coefficients`
reads them from the table's `IMP` row as coefficients per unit of output, which
the gross-output reconstruction adds back (`_gross_output`, `src/core.jl`).

**Note on vintage:** NAIO_10_CP1700 is a benchmark table published for
specific base years (not annual like the other series used in this
package). `_nearest_iot_year` picks the available year closest to `year`,
so the returned matrix may have a different vintage from the rest of the
calibration (e.g. A from 2020 combined with GVA/e/k/r from 2022), which
should be read explicitly as such, not as a coherent single-year profile.

Technical coefficient: `A[i,j] = flow(i→j) / gross_output(j)`, with
`gross_output(j)` read directly from the IOT's own `P1` row when available
(reconciliation by construction), and `Σᵢ flow(i→j) + GVA(j)` as the
fallback otherwise. Productivity (ρ(A)<1) is enforced with the same rule as
`create_technical_matrix` (`src/core.jl`).

Throws an error if the IOT has no data for the country (no available year).
Unlike the sectoral series (which degrade section by section), without the
IOT no real matrix is possible; callers should treat this as a failure of
the `:eurostat` path and fall back to the fallback path
(`create_technical_matrix`).
"""
function build_eurostat_io_matrix(country_code::String, year::Int,
                                      groups::Vector{Vector{String}},
                                      gva_by_section::Dict{String, Float64})
    G = length(groups)
    section_to_group = Dict{String, Int}()
    for (gi, sections) in enumerate(groups), s in sections
        section_to_group[s] = gi
    end

    iot_year = _nearest_iot_year(country_code, year)
    isnothing(iot_year) && error("Eurostat IOT (NAIO_10_CP1700) unavailable for $country_code.")
    iot_year != year && @warn "NAIO_10_CP1700 does not publish $year for $country_code; using the " *
                            "nearest benchmark year, $iot_year (see the docstring on vintage)."

    df = _fetch_iot(country_code, iot_year)

    F = zeros(G, G)
    P1 = zeros(G)
    for row in eachrow(df)
        ismissing(row.OBS_VALUE) && continue
        v = Float64(row.OBS_VALUE)
        pu, pa = String(row.prd_use), String(row.prd_ava)
        # The IOT's own `P1` row (gross output), by buying industry
        # (`prd_use`), used for direct reconciliation without relying on
        # external GVA. See `paper/matrix_audit.jl` for the checked reconciliation.
        if pa == "P1" && startswith(pu, "CPA_")
            sj = _section_of_a64_code(pu)
            haskey(section_to_group, sj) && (P1[section_to_group[sj]] += v)
            continue
        end
        # Only product×industry cells (both prefixed `CPA_`) are
        # intersectoral flows; `prd_ava` also has rows for value-added
        # components (B1G, D1, ...) and `prd_use` has final-demand
        # categories (P3, P5, P6, ...) and totals (T, U, TOTAL), excluded.
        (startswith(pa, "CPA_") && startswith(pu, "CPA_")) || continue
        si, sj = _section_of_a64_code(pa), _section_of_a64_code(pu)
        (haskey(section_to_group, si) && haskey(section_to_group, sj)) || continue
        # Unlike the margins table used before this fix, the real symmetric
        # IOT should have no negative product×industry flows; `max(v,0.0)`
        # stays as a safeguard (never triggered in the real data checked),
        # not as the expected handling of a national-accounts convention.
        F[section_to_group[si], section_to_group[sj]] += max(v, 0.0)
    end

    GVA_group = [sum(get(gva_by_section, s, 0.0) for s in sections) for sections in groups]
    gross_output = [P1[j] > 0 ? P1[j] : sum(F[:, j]) + GVA_group[j] for j in 1:G]

    A = zeros(G, G)
    for i in 1:G, j in 1:G
        gross_output[j] > 0 && (A[i, j] = F[i, j] / gross_output[j])
    end

    ρ_A = maximum(abs.(eigvals(A)))
    ρ_A >= 1.0 && (A = A / ρ_A * 0.8)
    return A
end

"""
    aggregate_io_matrix(A_fine, fine_sections, groups, weights)

Aggregates an N×N technical matrix (`A_fine`, whose rows/columns correspond,
in order, to `fine_sections`) into a set of G groups (`groups`, each element
a list of identifiers from `fine_sections`), by the standard Leontief
matrix aggregation formula: each aggregated column is the mean of the fine
columns in the group, weighted by the weight of each fine sector (typically
GVA or gross output, in `weights`), not a simple mean:

    A_coarse[gi,gj] = Σ_{i∈Gi} Σ_{j∈Gj} A_fine[i,j]·weights[j]  /  Σ_{j∈Gj} weights[j]

It preserves non-negativity (a weighted sum/mean of non-negative values).
Unlike aggregating the raw IOT flows directly (see the note in
`build_eurostat_io_matrix` on trade/transport margins), aggregating
already-clean coefficients avoids reintroducing that problem. It assumes
nothing about where `A_fine` comes from: it works for a real matrix
(`build_eurostat_io_matrix`) as well as a random one
(`create_technical_matrix`, `src/core.jl`), which is useful for sectoral
aggregation independent of the data source (`aggregate_sectors`,
`src/calibration_pt.jl`). Sectors of `fine_sections` with no matching group
in `groups` are ignored (so `groups` can be partial).
"""
function aggregate_io_matrix(A_fine::Matrix{Float64}, fine_sections::Vector{String},
                           groups::Vector{Vector{String}}, weights::Dict{String, Float64})
    N = length(fine_sections)
    G = length(groups)
    idx = Dict(s => i for (i, s) in enumerate(fine_sections))
    group_of = Dict{Int, Int}()
    for (gi, sections) in enumerate(groups), s in sections
        haskey(idx, s) && (group_of[idx[s]] = gi)
    end
    fine_weight = [get(weights, s, 0.0) for s in fine_sections]

    A_coarse = zeros(G, G)
    denom = zeros(G)
    for j in 1:N
        haskey(group_of, j) || continue
        denom[group_of[j]] += fine_weight[j]
    end
    for i in 1:N, j in 1:N
        (haskey(group_of, i) && haskey(group_of, j)) || continue
        A_coarse[group_of[i], group_of[j]] += A_fine[i, j] * fine_weight[j]
    end
    for gj in 1:G
        denom[gj] > 0 && (A_coarse[:, gj] ./= denom[gj])
    end
    return A_coarse
end

"""
    check_eurostat_sectoral()

Manual check (not run by the automated tests): confirms access to Eurostat's
sectoral series and IOT for Portugal, with plausible values.
Run with:  `include("src/MarxKapital.jl"); check_eurostat_sectoral()`
"""
function check_eurostat_sectoral()
    println("\n" * "="^70)
    println("MANUAL CHECK — EUROSTAT SECTORAL DATA")
    println("="^70)
    year = 2022
    ok = true

    gva, comp, cfc = fetch_eurostat_gva_compensation_cfc("PT", year)
    n_gva = length(gva)
    println(n_gva >= 15 ? "✓" : "✗", " GVA: $n_gva/19 sections (expected ≥15)")
    ok &= n_gva >= 15

    employment = fetch_eurostat_sector_employment("PT", year)
    println(length(employment) >= 15 ? "✓" : "✗", " Employment: $(length(employment))/19 sections")
    ok &= length(employment) >= 15

    employees = fetch_eurostat_sector_employees("PT", year)
    both = [s for s in NACE_SECTIONS if haskey(employment, s) && haskey(employees, s)]
    valid = count(s -> !isnan(_self_employed_ratio(employment[s], employees[s])), both)
    plausible = length(both) >= 15 && valid == length(both)
    println(plausible ? "✓" : "✗", " Employees: $(length(both))/19 sections, ",
            "$valid with employees ≤ employment")
    ok &= plausible

    try
        A = build_eurostat_io_matrix("PT", year, [[s] for s in NACE_SECTIONS], gva)
        ρ_A = maximum(abs.(eigvals(A)))
        plausible = size(A) == (19, 19) && ρ_A < 1.0
        println(plausible ? "✓" : "✗", " Real matrix A: $(size(A)), ρ(A)=$(round(ρ_A, digits=3))")
        ok &= plausible
    catch e
        println("✗ Real matrix A: failed ($e)")
        ok = false
    end

    try
        stock_reported = fetch_eurostat_sector_capital_stock("PT", year)
        pim_sections = [s for s in NACE_SECTIONS if haskey(stock_reported, s)][1:min(3, end)]
        stock_pim = _pim_capital_stock_by_section("PT", year, pim_sections, stock_reported)
        deviations = [abs(stock_pim[s] - stock_reported[s]) / stock_reported[s] for s in pim_sections]
        plausible = maximum(deviations) < 0.5   # same order of magnitude, not equal (different methods)
        println(plausible ? "✓" : "✗", " Perpetual-inventory stock vs. reported (",
                join(pim_sections, ","), "): max. deviation $(round(maximum(deviations)*100, digits=1))%")
        ok &= plausible
    catch e
        println("✗ Perpetual-inventory stock: failed ($e)")
        ok = false
    end

    println("="^70 * "\n")
    return ok
end
