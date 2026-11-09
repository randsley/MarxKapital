# ============================================================================
# Builds data/ameco_eu27.csv: a static AMECO extract for the 27 EU member
# states and the EU27 aggregate, so that notebooks/jupyter/07_eu_profit_rates
# runs offline. Uses the package's own SDMX downloader (src/ameco_sdmx.jl),
# so the series, scales and forecast rule are the ones the model uses.
#
#     julia --project=. data/build_ameco_eu.jl
#
# Needs network. Writes ameco_eu27.csv and ameco_eu27_PROVENANCE.md next to
# this file and refuses to write either if a core series is missing for any
# area, or if the release year (and so the forecast cut) cannot be read.
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf

const EU27 = ["Austria", "Belgium", "Bulgaria", "Croatia", "Cyprus", "Czechia",
              "Denmark", "Estonia", "Finland", "France", "Germany", "Greece",
              "Hungary", "Ireland", "Italy", "Latvia", "Lithuania", "Luxembourg",
              "Malta", "Netherlands", "Poland", "Portugal", "Romania", "Slovakia",
              "Slovenia", "Spain", "Sweden"]
const AREAS = vcat(EU27, "European Union (27)")
const YEARS = 1995:2026

# The series the Marxian measures need (analyze_time_series_with_data and
# calibrate_with_ameco_data). An area missing any of them stops the build.
const CORE = ["GDP_current", "GDP_constant", "compensation", "CFC", "net_capital_stock",
              "GFCF", "GFCF_deflator", "employment_total", "employees"]

function main()
    out = Dict{String, Tuple{Vector{Int}, Dict{String, Vector{Float64}}}}()
    releases = Int[]
    for area in AREAS
        code = AMECO_SDMX_COUNTRY_CODES[area]
        release = Ref(0)
        series = download_ameco_sdmx(code, YEARS; release = release)
        missing_core = setdiff(CORE, keys(series))
        isempty(missing_core) || error("$area ($code): missing core series $(join(missing_core, ", "))")
        release[] > 0 || error("$area ($code): no release year in LAST UPDATE")
        yrs, kept, _ = _apply_forecast_rule(collect(YEARS), series, release[], false)
        out[area] = (yrs, kept)
        push!(releases, release[])
    end
    length(unique(releases)) == 1 || error("areas come from different releases: $(unique(releases))")
    release = only(unique(releases))

    names_ = sort(unique(vcat([collect(keys(s)) for (_, s) in values(out)]...)))
    csv = joinpath(@__DIR__, "ameco_eu27.csv")
    open(csv, "w") do io
        println(io, join(vcat("country", "code", "year", names_), ","))
        for area in AREAS
            yrs, s = out[area]
            for (k, y) in enumerate(yrs)
                vals = [haskey(s, n) && isfinite(s[n][k]) ? @sprintf("%.6g", s[n][k]) : "" for n in names_]
                println(io, join(vcat("\"$area\"", AMECO_SDMX_COUNTRY_CODES[area], string(y), vals), ","))
            end
        end
    end

    first_year, last_year = first(YEARS), release - 1
    prov = joinpath(@__DIR__, "ameco_eu27_PROVENANCE.md")
    open(prov, "w") do io
        print(io, """
        # AMECO extract for the EU27: provenance

        > Source: European Commission, DG ECFIN, AMECO database, $release release,
        > extracted $(Dates.today()).

        AMECO is Commission content, reusable under Commission Decision
        2011/833/EU and licensed CC BY 4.0: credit the source and indicate
        changes. The changes made here are the ones listed below.

        `ameco_eu27.csv` holds $(length(AREAS)) areas (the 27 member states and the
        EU27 aggregate), $first_year-$last_year, one row per area and year. It is
        built by `data/build_ameco_eu.jl` with the package's own SDMX downloader
        (`download_ameco_sdmx`), so the series and the scale factors are those of
        `AMECO_SDMX_MAP` in `src/ameco_sdmx.jl`. Load a country with
        `build_ameco_data` (see notebook 07).

        **Forecasts removed.** AMECO series carry the Commission's forecasts for
        the release year and the next, unmarked. Every year from $release on is
        dropped (`_apply_forecast_rule`), so $last_year is the last actual year.

        **Units.** Monetary series use AMECO's UNIT code 0, national currency:
        euros for euro-area members, the national currency elsewhere (zloty,
        forint, koruna, krona, krone, lev, leu), and euros for the EU27
        aggregate. Compare countries only through ratios, such as the rate of
        profit or the wage share, never through levels. `net_capital_stock`
        (`OKND`) is at constant prices of AMECO's reference year; every other
        monetary series is at current prices.
        `analyze_time_series_with_data(...; valuation = :consistent)` puts them on
        one basis. Values are stored to six significant figures.

        **The EU27 aggregate** uses AMECO's standard aggregation where the series
        has one, and otherwise the euro-weighted mean of national growth rates
        (`_select_agg_method`), as `OVGD` and `PIGT` have no standard aggregation.

        | column | AMECO item | dataflow |
        |---|---|---|
        """)
        for n in names_
            if haskey(AMECO_SDMX_MAP, n)
                df, item, _, _ = AMECO_SDMX_MAP[n]
                println(io, "| `$n` | `$item` | `$df` |")
            elseif n == "GDP_deflator"
                println(io, "| `$n` | computed: `UVGD / OVGD × 100` | |")
            elseif n == "trade_balance"
                println(io, "| `$n` | computed: `DXGT − DMGT`, goods only | `AMECO_CHAPTER11-01` |")
            end
        end
    end
    @info "wrote" csv prov release
end

main()
