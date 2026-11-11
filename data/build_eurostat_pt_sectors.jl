# ============================================================================
# Builds data/eurostat_pt_sectors.csv: a static Eurostat extract of the
# annual sectoral accounts of Portugal (19 NACE sections, every year
# published), so that notebooks/jupyter/09_sectoral_mobility runs offline.
# Uses the package's own Eurostat fetcher (`_fetch_eurostat_sections`,
# src/eurostat_sdmx.jl), so the dataflows, keys and units are the ones the
# calibration uses.
#
#     julia --project=. data/build_eurostat_pt_sectors.jl
#
# Needs network. Writes eurostat_pt_sectors.csv and
# eurostat_pt_sectors_PROVENANCE.md next to this file, and refuses to write
# either if a series is missing for any section.
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf

const COUNTRY = "PT"

# column => (dataflow, key, description)
const SERIES = [
    "GVA"           => ("NAMA_10_A64",    "A.CP_MEUR..B1G.$COUNTRY",       "gross value added, current prices, million euros"),
    "compensation"  => ("NAMA_10_A64",    "A.CP_MEUR..D1.$COUNTRY",        "compensation of employees, current prices, million euros"),
    "CFC"           => ("NAMA_10_A64",    "A.CP_MEUR..P51C.$COUNTRY",      "consumption of fixed capital, current prices, million euros"),
    "GFCF"          => ("NAMA_10_A64_P5", "A.CP_MEUR..N11G.P51G.$COUNTRY", "gross fixed capital formation, all fixed assets, current prices, million euros"),
    "capital_stock" => ("NAMA_10_NFA_ST", "A.CRC_MEUR..N11N.$COUNTRY",     "net fixed capital stock, current replacement cost, million euros (end of year)"),
    "employment"    => ("NAMA_10_A64_E",  "A.THS_PER..EMP_DC.$COUNTRY",    "total employment, domestic concept, thousand persons"),
    "employees"     => ("NAMA_10_A64_E",  "A.THS_PER..SAL_DC.$COUNTRY",    "employees, domestic concept, thousand persons"),
]

function main()
    data = Dict{String, Dict{String, Dict{Int, Float64}}}()
    for (col, (flow, key, _)) in SERIES
        d = _fetch_eurostat_sections(flow, key)
        missing_s = setdiff(NACE_SECTIONS, keys(d))
        isempty(missing_s) || error("$col ($flow): no data for sections $(join(missing_s, ","))")
        data[col] = d
    end
    # years in which every series is published for every section
    years = sort(collect(reduce(intersect, (Set(keys(data[col][s])) for (col, _) in SERIES
                                                                     for s in NACE_SECTIONS))))
    isempty(years) && error("no year with every series for every section")
    gaps = [y for y in first(years):last(years) if !(y in years)]
    isempty(gaps) || error("years missing inside the range: $gaps")

    csv = joinpath(@__DIR__, "eurostat_pt_sectors.csv")
    cols = first.(SERIES)
    names_by_code = Dict(PT_SECTORS)
    open(csv, "w") do io
        println(io, join(vcat("section", "sector", "year", cols), ","))
        for s in NACE_SECTIONS, y in years
            vals = [@sprintf("%.6g", data[c][s][y]) for c in cols]
            println(io, join(vcat(s, "\"$(names_by_code[s])\"", string(y), vals), ","))
        end
    end

    prov = joinpath(@__DIR__, "eurostat_pt_sectors_PROVENANCE.md")
    open(prov, "w") do io
        print(io, """
        # Eurostat sectoral accounts of Portugal: provenance

        > Source: Eurostat, national accounts (ESA 2010) by industry, extracted
        > $(Dates.today()) from the SDMX dissemination API.

        Eurostat data are reusable under the Commission's reuse policy
        (Decision 2011/833/EU) and licensed CC BY 4.0: credit the source and
        indicate changes. The changes made here are listed below.

        `eurostat_pt_sectors.csv` holds the 19 NACE Rev. 2 sections A–S of
        Portugal, $(first(years))–$(last(years)), one row per section and year: the years
        in which every series below is published for every section. It is
        built by `data/build_eurostat_pt_sectors.jl` with the package's own
        fetcher (`_fetch_eurostat_sections`, `src/eurostat_sdmx.jl`), so the
        dataflows and keys are the ones `calibrate_portugal_model(...;
        data_source = :eurostat)` uses. Values are stored to six significant
        figures. Read it with `CSV.read` (see notebook 09).

        **Prices.** Flows are at current prices and the capital stock at
        current replacement cost, so ratios such as the rate of profit compare
        like with like (the `:current_cost` valuation of the AMECO time
        series). Recent years are provisional and may be revised.

        | column | dataflow | key | content |
        |---|---|---|---|
        """)
        for (col, (flow, key, desc)) in SERIES
            println(io, "| `$col` | `$flow` | `$key` | $desc |")
        end
    end
    @info "wrote" csv prov years = (first(years), last(years))
end

main()
