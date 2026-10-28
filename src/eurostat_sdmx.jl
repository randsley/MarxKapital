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
Dict{String,Dict{Int,Float64}} NACE section → (year → value). Filters the
response to rows whose `nace_r2` is a 1-letter section (A-S); ignores the
finer A64 subdivisions and the T/U sections (household and extraterritorial
activities, irrelevant here). A failure (network, format, no data) returns
an empty dictionary; it never throws.
"""
function _fetch_eurostat_sections(dataflow::String, key_::String)
    url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,$dataflow,1.0/$key_?format=SDMX-CSV"
    try
        resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                        retry = true, readtimeout = 30, status_exception = false)
        resp.status == 200 || return Dict{String, Dict{Int, Float64}}()
        df = CSV.read(IOBuffer(resp.body), DataFrame)
        (nrow(df) == 0 || !("nace_r2" in names(df)) ||
         !("TIME_PERIOD" in names(df)) || !("OBS_VALUE" in names(df))) &&
            return Dict{String, Dict{Int, Float64}}()

        result = Dict{String, Dict{Int, Float64}}()
        for row in eachrow(df)
            section = String(row.nace_r2)
            (length(section) == 1 && section in NACE_SECTIONS) || continue
            ismissing(row.OBS_VALUE) && continue
            d = get!(result, section, Dict{Int, Float64}())
            d[Int(row.TIME_PERIOD)] = Float64(row.OBS_VALUE)
        end
        return result
    catch
        return Dict{String, Dict{Int, Float64}}()
    end
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
domestic and imported supply without distinction.

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

    url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.DOM...$country_code" *
          "?format=SDMX-CSV&startPeriod=$iot_year&endPeriod=$iot_year"
    resp = HTTP.get(url, ["Accept-Encoding" => "identity"],
                    retry = true, readtimeout = 60, status_exception = false)
    resp.status == 200 || error("Eurostat IOT unavailable for $country_code/$iot_year (status $(resp.status)).")
    df = CSV.read(IOBuffer(resp.body), DataFrame)
    nrow(df) == 0 && error("Eurostat IOT has no data for $country_code/$iot_year.")

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
