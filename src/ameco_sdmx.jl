# ============================================================================
# OFFICIAL AMECO SDMX API
# ============================================================================
# The European Commission withdrew the static TXT file used by
# `ameco_download.jl` (the URLs in AMECO_URLS_TO_TRY return 404 or redirect
# to the portal's HTML page, not to data). Instead, AMECO now exposes an
# official SDMX REST API, on the same platform as Eurostat's new data tool:
#
#     https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1
#
# Each AMECO variable group lives in its own "chapter" (dataflow) (e.g.
# AMECO_CHAPTER06-01 = "Gross domestic product"); there is no single
# monolithic dataflow. The mnemonics already used in AMECO_VARIABLE_CODES
# (types.jl) remain valid as ITEM codes in this API, so they did not need
# remapping. Country codes are mostly ISO3, but with real irregularities
# (GRC instead of EL, GBR instead of UK, ROM instead of ROU) and their own
# aggregate codes (EU27, EA21, D_W), so they are not compatible with
# AMECO_COUNTRY_CODES (codes from the old TXT file) and need a mapping of
# their own.
# ============================================================================

const AMECO_SDMX_BASE_URL =
    "https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1"

"""
Country (English name, same keys as `AMECO_COUNTRY_CODES`) → REF_AREA code
used by the AMECO SDMX API. Built from the `CL_AMECO_AREA` codelist (checked
in July 2026). "European Union (28)" has no equivalent in the current
database (code withdrawn after Brexit) and is left out: resolving that
country falls back to the old 2-letter code, which the SDMX API simply does
not recognize (it returns an empty series, with no error).
"""
const AMECO_SDMX_COUNTRY_CODES = Dict(
    "Austria" => "AUT", "Belgium" => "BEL", "Bulgaria" => "BGR",
    "Croatia" => "HRV", "Cyprus" => "CYP", "Czechia" => "CZE",
    "Denmark" => "DNK", "Estonia" => "EST", "Finland" => "FIN",
    "France" => "FRA", "Germany" => "DEU", "Greece" => "GRC",
    "Hungary" => "HUN", "Ireland" => "IRL", "Italy" => "ITA",
    "Latvia" => "LVA", "Lithuania" => "LTU", "Luxembourg" => "LUX",
    "Malta" => "MLT", "Netherlands" => "NLD", "Poland" => "POL",
    "Portugal" => "PRT", "Romania" => "ROM", "Slovakia" => "SVK",
    "Slovenia" => "SVN", "Spain" => "ESP", "Sweden" => "SWE",
    "Euro Area" => "EA21", "Euro Area (19)" => "EA19",
    "United Kingdom" => "GBR", "Norway" => "NOR", "Switzerland" => "CHE",
    "Iceland" => "ISL", "Turkey" => "TUR",
    "European Union (27)" => "EU27",
    "United States" => "USA", "Japan" => "JPN",
)

"""
Internal variable name (same keys as `AMECO_VARIABLE_CODES`) →
`(chapter dataflow, ITEM code, scale factor, TRANSFORMATION)` in the SDMX
API. Every entry was confirmed with a real call during development
(2026-07). Note that several mnemonics here **differ** from the ones that
were (never checked) in `AMECO_VARIABLE_CODES` (`types.jl`): for example,
`government_revenue`/`government_expenditure` had their codes swapped
(`UUTG` was expenditure, not revenue), and
`private_consumption`/`exports`/`imports` used mnemonics that no longer
exist in the current API (`UNCT`/`UXTG`/`UMTG` → `UCPH`/`UXGS`/`UMGS`).

`GDP_deflator` and `trade_balance` have no entry here: they are computed in
`download_ameco_sdmx` from series already mapped (`GDP_current` /
`GDP_constant`, and goods exports/imports from chapter 11-01; the latter is
not the same item as `exports`/`imports` above, which cover goods and
services, and goods trade uses `UNIT=99`, not the default `UNIT=0` of
`_fetch_sdmx_series`). `gross_capital_stock` was confirmed **unavailable**
in this API: only the net stock chapter (`AMECO_CHAPTER08-01`) exists, with
no gross equivalent. It is not pending; it is documented as not published
(see `docs/LIMITATIONS.md` item 3).

The scale factor converts the unit the API returns (confirmed through the
COMMENT/UNIT_MULT column of each response) to the convention already used
in the rest of the code (synthetic data, `calibrate_with_ameco_data`):
million euros for monetary variables, thousand persons for employment, no
scaling for indices/percentages/per-capita values. The monetary variables
checked come in "Mrd EURO" (billions), hence a scale of 1000 to millions
(including those in chapter 16, labeled "National currency" but of the same
order of magnitude, as confirmed by the size: ~107 matches public
revenue/expenditure of ~44% of a GDP of ~€244 bn, not 107% of GDP).
"""
const AMECO_SDMX_MAP = Dict(
    "GDP_current"                 => ("AMECO_CHAPTER06-01", "UVGD",  1000.0, 1),
    "GDP_constant"                => ("AMECO_CHAPTER06-01", "OVGD",  1000.0, 1),
    "employment_total"                => ("AMECO_CHAPTER01-04", "NETD",  1.0,    1),
    "compensation"                 => ("AMECO_CHAPTER07-01", "UWCD",  1000.0, 1),
    "GFCF"                         => ("AMECO_CHAPTER03-01", "UIGT",  1000.0, 1),
    "net_capital_stock"        => ("AMECO_CHAPTER08-01", "OKND",  1000.0, 1),
    "private_consumption"              => ("AMECO_CHAPTER02-01", "UCPH",  1000.0, 1),
    "public_consumption"              => ("AMECO_CHAPTER02-05", "UCTG",  1000.0, 1),
    "exports"                  => ("AMECO_CHAPTER09-01", "UXGS",  1000.0, 1),
    "imports"                  => ("AMECO_CHAPTER09-02", "UMGS",  1000.0, 1),
    "employees"          => ("AMECO_CHAPTER01-07", "NWTD",  1.0,    1),
    "unemployment_rate"              => ("AMECO_CHAPTER01-03", "ZUTN",  1.0,    1),
    "labor_force"              => ("AMECO_CHAPTER01-02", "NLTN",  1.0,    1),
    "compensation_per_employee" => ("AMECO_CHAPTER07-04", "HWCDW", 1.0,    1),
    "labor_productivity"       => ("AMECO_CHAPTER08-02", "ZVGDE", 1.0,    3),
    "CPI"                          => ("AMECO_CHAPTER02-04", "ZCPIH", 1.0,    1),
    "government_revenue"             => ("AMECO_CHAPTER16-01", "URTG",  1000.0, 1),
    "government_expenditure"             => ("AMECO_CHAPTER16-02", "UUTG",  1000.0, 1),
    "budget_balance"             => ("AMECO_CHAPTER16-03", "UBLG",  1000.0, 1),
    "current_account"             => ("AMECO_CHAPTER10-01", "UBCA",  1000.0, 1),
    "unit_labor_costs"         => ("AMECO_CHAPTER07-07", "PLCD",  1.0,    3),
    "public_debt"               => ("AMECO_CHAPTER18-02", "UDGGL", 1000.0, 1),
    "GFCF_deflator"                => ("AMECO_CHAPTER03-01", "PIGT",  1.0,    3),
    "CFC"                          => ("AMECO_CHAPTER03-05", "UKCT",  1000.0, 1),
)

"""
    _release_year(last_update)

Year of an AMECO release, from the `LAST UPDATE` field of the SDMX CSV
(`"dd/mm/yy hh:mm:ss"`, e.g. `"03/06/26 09:37:05"` → 2026; a four-digit year
is also accepted, as is an ISO date, in case CSV.jl parsed the field as a
date). Returns `nothing` if the field cannot be read.
"""
function _release_year(last_update::AbstractString)
    iso = match(r"^\s*(\d{4})-\d{2}-\d{2}", last_update)
    iso === nothing || return parse(Int, iso[1])
    m = match(r"^\s*\d{1,2}/\d{1,2}/(\d{2}|\d{4})\b", last_update)
    m === nothing && return nothing
    y = parse(Int, m[1])
    return y < 100 ? 2000 + y : y
end

"""
    _drop_forecast_years(years, series, release_year)

AMECO publishes the Commission's forecasts in the same series as the
observed data, with nothing marking them (`OBS_STATUS` is `A` for every
year). Each release forecasts its own year and the next one, so the years
`≥ release_year` are forecasts. Returns `(years, series)` without them,
with every vector in `series` cut to the remaining years.
"""
function _drop_forecast_years(years::AbstractVector{Int}, series::Dict, release_year::Integer)
    keep = findall(<(release_year), years)
    return years[keep], Dict(k => v[keep] for (k, v) in series)
end

"""
Calls the SDMX API for one (dataflow, item, area) and returns a
Dict{Int,Float64} year→value. The SDMX key fixes TRANSFORMATION (1 by
default), UNIT (0 by default) and REFERENCE=0 and leaves AGG_METHOD blank
(`.`): without this, the API returns several series per year for the same
item (e.g. UVGD without a fixed UNIT returns current prices, PPS and ECU/EUR
at once) and the year→value dictionary would depend on the order in which
the rows arrive. Most chapters use TRANSFORMATION=1 and UNIT=0; some need
other values (e.g. chapters 07-07/08-02 use TRANSFORMATION=3; chapter 11-01,
external trade, uses UNIT=99), so pass them explicitly when needed
(confirmed by trial: the API returns "incorrect number of filters"/empty if
the wrong value is wildcarded instead of fixed).

If `release` is a `Ref{Int}`, it is raised to the release year read from the
series' `LAST UPDATE` column (see `_release_year`).
"""
function _fetch_sdmx_series(dataflow::String, area_code::String, item::String;
                           transformation::Int = 1, unit::Int = 0,
                           release::Union{Nothing, Base.RefValue{Int}} = nothing)
    url = "$AMECO_SDMX_BASE_URL/data/ECFIN,$dataflow,1.0/A.$area_code.$transformation..$unit.0.$item" *
          "?format=SDMX-CSV"
    try
        resp = HTTP.get(url, retry = true, readtimeout = 30, status_exception = false)
        resp.status == 200 || return Dict{Int, Float64}()
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        (nrow(df) == 0 || !("TIME_PERIOD" in names(df)) || !("OBS_VALUE" in names(df))) &&
            return Dict{Int, Float64}()
        if release !== nothing && "LAST UPDATE" in names(df)
            for u in unique(skipmissing(df[!, "LAST UPDATE"]))
                y = _release_year(string(u))
                y === nothing || (release[] = max(release[], y))
            end
        end
        return Dict(Int(row.TIME_PERIOD) => Float64(row.OBS_VALUE) for row in eachrow(df))
    catch
        return Dict{Int, Float64}()
    end
end

"""
    download_ameco_sdmx(area_code, years)

Downloads, through AMECO's official SDMX API, the series mapped in
`AMECO_SDMX_MAP` for the given area code (see `AMECO_SDMX_COUNTRY_CODES` to
resolve it from the country name), returning a `Dict{String,Vector{Float64}}`
ready for `build_ameco_data` (`src/ameco.jl`). Variables with no mapping, or
whose call fails, are simply missing from the dictionary; `build_ameco_data`
fills in defaults (0.0 or NaN), so a partial failure never throws.

With `release = Ref(0)`, the release year of the data is stored in
`release[]` (see `_release_year`).

Two extra series are computed (they do not come from `AMECO_SDMX_MAP`):
`GDP_deflator` = `GDP_current/GDP_constant × 100` (from series already
fetched, with no extra call); `trade_balance` = goods exports minus goods
imports (`AMECO_CHAPTER11-01`, items `DXGT`/`DMGT`, `UNIT=99`; note that this
is goods trade only, unlike `exports`/`imports` above, which cover goods and
services).
"""
function download_ameco_sdmx(area_code::String, years;
                             release::Union{Nothing, Base.RefValue{Int}} = nothing)
    println("\n🌐 Fetching AMECO data through the official SDMX API ($area_code)...")
    years_vec = collect(years)
    result = Dict{String, Vector{Float64}}()
    for (name, (dataflow, item, scale, transformation)) in AMECO_SDMX_MAP
        series = _fetch_sdmx_series(dataflow, area_code, item; transformation = transformation,
                                    release = release)
        if isempty(series)
            @warn "No AMECO SDMX data for '$name' ($dataflow, $item, $area_code)."
            continue
        end
        result[name] = [get(series, a, NaN) * scale for a in years_vec]
    end

    if haskey(result, "GDP_current") && haskey(result, "GDP_constant")
        result["GDP_deflator"] = result["GDP_current"] ./ result["GDP_constant"] .* 100
    end

    dxgt = _fetch_sdmx_series("AMECO_CHAPTER11-01", area_code, "DXGT"; unit = 99)
    dmgt = _fetch_sdmx_series("AMECO_CHAPTER11-01", area_code, "DMGT"; unit = 99)
    if !isempty(dxgt) && !isempty(dmgt)
        result["trade_balance"] = [(get(dxgt, a, NaN) - get(dmgt, a, NaN)) * 1000.0 for a in years_vec]
    else
        @warn "No AMECO SDMX data for 'trade_balance' (AMECO_CHAPTER11-01, $area_code)."
    end

    isempty(result) && error("No series fetched from the SDMX API for '$area_code'.")
    println("  ✓ $(length(result))/$(length(AMECO_SDMX_MAP) + 2) series fetched.")
    return result
end

"""
    check_ameco_sdmx()

Manual check (not run by the automated tests; see `docs/LIMITATIONS.md`
item 3): confirms that the SDMX API is reachable and that Portugal's GDP
comes in a plausible order of magnitude for a recent year. It does not
compare an exact value, because AMECO revises the data periodically.
Run with:  `include("src/MarxKapital.jl"); check_ameco_sdmx()`
"""
function check_ameco_sdmx()
    println("\n" * "="^70)
    println("MANUAL CHECK — AMECO SDMX API")
    println("="^70)
    series = _fetch_sdmx_series("AMECO_CHAPTER06-01", "PRT", "UVGD")
    if isempty(series)
        println("✗ FAILED: no API response for Portugal's GDP.")
        return false
    end
    recent_year = maximum(k for k in keys(series) if !isnan(series[k]))
    amount = series[recent_year]
    plausible = 50.0 < amount < 500.0
    println(plausible ? "✓" : "✗", " Portugal's GDP ($recent_year): €",
            round(amount, digits = 1), " bn ",
            plausible ? "(plausible)" : "(outside the expected range 50-500)")
    println("="^70 * "\n")
    return plausible
end
