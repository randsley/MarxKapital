# ============================================================================
# Builds data/eurostat_eu_sectors.csv: a static Eurostat extract of the
# annual sectoral accounts of the EU countries (19 NACE sections, every year
# published), so that notebooks/jupyter/09_sectoral_mobility and
# 10_eu_sectoral_mobility run offline. Uses the package's own Eurostat parser
# (`_fetch_eurostat_sections_by_geo`, src/eurostat_sdmx.jl), so the dataflows,
# keys and units are the ones the calibration uses.
#
#     julia --project=. data/build_eurostat_sectors.jl
#
# Needs network. Writes eurostat_eu_sectors.csv and
# eurostat_eu_sectors_PROVENANCE.md next to this file. A country is kept
# only if every series is published for every section over a run of
# consecutive years; otherwise it is dropped with a warning, and the
# provenance file records why.
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf

# EU27 except Malta, which publishes no capital stock for sections B and D
const COUNTRIES = ["AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "EL", "ES", "FI", "FR", "HR",
                   "HU", "IE", "IT", "LT", "LU", "LV", "NL", "PL", "PT", "RO", "SE", "SI", "SK"]
const GEO = join(COUNTRIES, "+")

# column => (dataflow, key, description)
const SERIES = [
    "GVA"           => ("NAMA_10_A64",    "A.CP_MEUR..B1G.$GEO",       "gross value added, current prices, million euros"),
    "compensation"  => ("NAMA_10_A64",    "A.CP_MEUR..D1.$GEO",        "compensation of employees, current prices, million euros"),
    "CFC"           => ("NAMA_10_A64",    "A.CP_MEUR..P51C.$GEO",      "consumption of fixed capital, current prices, million euros"),
    "GFCF"          => ("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$GEO", "gross fixed capital formation, all fixed assets, current prices, million euros"),
    "capital_stock" => ("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$GEO",     "net fixed capital stock, current replacement cost, million euros (end of year)"),
    "employment"    => ("NAMA_10_A64_E",  "A.THS_PER..EMP_DC.$GEO",    "total employment, domestic concept, thousand persons"),
    "employees"     => ("NAMA_10_A64_E",  "A.THS_PER..SAL_DC.$GEO",    "employees, domestic concept, thousand persons"),
]

"""Years in which every series is published for every section of `geo`, or a reason it is dropped."""
function country_years(data, geo)
    for (col, _) in SERIES
        d = get(data[col], geo, nothing)
        d === nothing && return "no $col"
        miss = setdiff(NACE_SECTIONS, keys(d))
        isempty(miss) || return "no $col for sections $(join(miss, ","))"
    end
    years = sort(collect(reduce(intersect, (Set(keys(data[col][geo][s])) for (col, _) in SERIES
                                                                          for s in NACE_SECTIONS))))
    isempty(years) && return "no year with every series for every section"
    gaps = [y for y in first(years):last(years) if !(y in years)]
    isempty(gaps) || return "years missing inside the range: $(join(gaps, ","))"
    return years
end

function main()
    data = Dict{String, Dict{String, Dict{String, Dict{Int, Float64}}}}()
    for (col, (flow, key, _)) in SERIES
        d = _fetch_eurostat_sections_by_geo(flow, key; readtimeout = 600)
        isempty(d) && error("$col ($flow): no data returned")
        data[col] = d
        @info "fetched" col countries = length(d)
    end

    kept, dropped = Pair{String, Vector{Int}}[], Pair{String, String}[]
    for geo in COUNTRIES
        ys = country_years(data, geo)
        if ys isa String
            @warn "dropping $geo: $ys"
            push!(dropped, geo => ys)
        else
            push!(kept, geo => ys)
        end
    end
    isempty(kept) && error("no country with complete data")

    csv = joinpath(@__DIR__, "eurostat_eu_sectors.csv")
    cols = first.(SERIES)
    names_by_code = Dict(PT_SECTORS)
    open(csv, "w") do io
        println(io, join(vcat("geo", "section", "sector", "year", cols), ","))
        for (geo, years) in kept, s in NACE_SECTIONS, y in years
            vals = [@sprintf("%.6g", data[c][geo][s][y]) for c in cols]
            println(io, join(vcat(geo, s, "\"$(names_by_code[s])\"", string(y), vals), ","))
        end
    end

    prov = joinpath(@__DIR__, "eurostat_eu_sectors_PROVENANCE.md")
    open(prov, "w") do io
        print(io, """
        # Eurostat sectoral accounts of the EU countries: provenance

        > Source: Eurostat, national accounts (ESA 2010) by industry, extracted
        > $(Dates.today()) from the SDMX dissemination API.

        Eurostat data are reusable under the Commission's reuse policy
        (Decision 2011/833/EU) and licensed CC BY 4.0: credit the source and
        indicate changes. The changes made here are listed below.

        `eurostat_eu_sectors.csv` holds the 19 NACE Rev. 2 sections A–S of
        $(length(kept)) EU countries, one row per country (`geo`, Eurostat code),
        section and year. For each country it keeps the years in which every
        series below is published for every section; the panel is therefore
        balanced within a country and unbalanced across countries. Malta is
        left out (no capital stock for sections B and D). It is built by
        `data/build_eurostat_sectors.jl` with the package's own parser
        (`_fetch_eurostat_sections_by_geo`, `src/eurostat_sdmx.jl`), so the
        dataflows and keys are the ones `calibrate_portugal_model(...;
        data_source = :eurostat)` uses. Values are stored to six significant
        figures. Read it with `CSV.read` (see notebooks 09 and 10).

        **Prices.** Flows are at current prices and the capital stock at
        current replacement cost, so ratios such as the rate of profit compare
        like with like (the `:current_cost` valuation of the AMECO time
        series). Recent years are provisional and may be revised.

        | country | years |
        |---|---|
        """)
        for (geo, years) in kept
            println(io, "| $geo | $(first(years))–$(last(years)) |")
        end
        if !isempty(dropped)
            println(io, "\nDropped:\n")
            for (geo, why) in dropped
                println(io, "- $geo: $why")
            end
        end
        print(io, """

        | column | dataflow | key | content |
        |---|---|---|---|
        """)
        for (col, (flow, key, desc)) in SERIES
            println(io, "| `$col` | `$flow` | `$(replace(key, GEO => "<geo>"))` | $desc |")
        end
    end
    @info "wrote" csv prov countries = length(kept) dropped = first.(dropped)
end

main()
