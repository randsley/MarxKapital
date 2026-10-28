# ============================================================================
# Audit of the real 19-sector technical matrix A (Portugal), per external
# review. This script documents the investigation that found and fixed the
# root cause of an implausibly low spectral radius (rho(A)~=0.13): the
# codebase was pulling from NAIO_10_CP1620 ("Table of trade and transport
# margins", a small satellite table), not the actual symmetric input-output
# table (NAIO_10_CP1700). It also reports the diagnostics the review asked
# for on the corrected construction: reconciliation against the table's own
# published output, and the domestic-use vs. total-use question checked
# directly against the live API rather than assumed.
#
# Run with:  julia --project=. paper/matrix_audit.jl
# Requires network access (Eurostat SDMX API).
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

const COUNTRY = "PT"
const YEAR = 2022

println("\n" * "="^70)
println("AUDIT OF THE TECHNICAL MATRIX A — Portugal")
println("="^70)

# ----------------------------------------------------------------------------
# 1. stk_flow: confirm directly whether the real symmetric IOT
#    (NAIO_10_CP1700) offers anything other than the combined
#    domestic+imports ("TOTAL") table.
# ----------------------------------------------------------------------------

println("\n[1/3] stk_flow (domestic-use vs. total-use) — checking directly...")
url_stkflow = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR..CPA_A01.CPA_A01.$COUNTRY" *
              "?format=SDMX-CSV"
resp = HTTP.get(url_stkflow, ["Accept-Encoding" => "identity"], status_exception = false)
df_stk = CSV.read(IOBuffer(resp.body), DataFrame)
stk_flow_values = unique(df_stk.stk_flow)
println("  ✓ stk_flow values returned (dimension not fixed): ", stk_flow_values)
if "DOM" in stk_flow_values
    println("  ✓ NAIO_10_CP1700 publishes DOM (domestic use), IMP (imported) and TOTAL, ",
            "unlike NAIO_10_CP1620 (TOTAL only). The production construction uses DOM: ",
            "matrix A represents domestic productive interdependence, without treating ",
            "imported inputs as if they were supplied by a domestic sector.")
end

# ----------------------------------------------------------------------------
# 2. Available reference years (this is a benchmark table, not annual)
# ----------------------------------------------------------------------------

println("\n[2/3] Available reference years (NAIO_10_CP1700 is not annual)...")
url_years = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.TOTAL.CPA_A01.B1G.$COUNTRY" *
           "?format=SDMX-CSV"
resp = HTTP.get(url_years, ["Accept-Encoding" => "identity"], status_exception = false)
df_years = CSV.read(IOBuffer(resp.body), DataFrame)
available_years = sort(Int.(df_years.TIME_PERIOD))
year_used = _nearest_iot_year(COUNTRY, YEAR)
println("  ✓ years available for $COUNTRY: ", available_years)
println("  ✓ for the request year=$YEAR, the nearest reference year is used: $year_used")
if year_used != YEAR
    println("  ⚠ This means that matrix A of the $YEAR sectoral profile (Table 1) in ",
            "practice has a $year_used vintage: an explicit lag, not a genuinely ",
            "consistent single-year profile. See Section 6.2 of the paper.")
end

# ----------------------------------------------------------------------------
# 3. Reconciliation of the corrected construction against the IOT's own
#    published P1 (gross output) row — the diagnostic the review asked for.
# ----------------------------------------------------------------------------

println("\n[3/3] Reconciliation: corrected A vs. the table's own P1 (gross output)...")
sections = NACE_SECTIONS
G = length(sections)
section_idx = Dict(s => i for (i, s) in enumerate(sections))

url = "$EUROSTAT_SDMX_BASE_URL/data/ESTAT,NAIO_10_CP1700,1.0/A.MIO_EUR.DOM...$COUNTRY" *
      "?format=SDMX-CSV&startPeriod=$year_used&endPeriod=$year_used"
resp = HTTP.get(url, ["Accept-Encoding" => "identity"], retry = true, readtimeout = 60,
                status_exception = false)
df = CSV.read(IOBuffer(resp.body), DataFrame)

F = zeros(G, G)
P1 = zeros(G)
negatives = 0
for row in eachrow(df)
    ismissing(row.OBS_VALUE) && continue
    v = Float64(row.OBS_VALUE)
    pu, pa = String(row.prd_use), String(row.prd_ava)
    if pa == "P1" && startswith(pu, "CPA_")
        sj = _section_of_a64_code(pu)
        haskey(section_idx, sj) && (P1[section_idx[sj]] += v)
        continue
    end
    (startswith(pa, "CPA_") && startswith(pu, "CPA_")) || continue
    si, sj = _section_of_a64_code(pa), _section_of_a64_code(pu)
    (haskey(section_idx, si) && haskey(section_idx, sj)) || continue
    v < 0 && (negatives += 1)
    F[section_idx[si], section_idx[sj]] += max(v, 0.0)
end
println("  ✓ negative product×industry cells: $negatives ",
        "(the margins table used before this fix had 272-317; the real table should have none)")

gva_s, _, _ = fetch_eurostat_gva_compensation_cfc(COUNTRY, year_used)
gross_output_via_gva = [sum(F[:, j]) + get(gva_s, sections[j], 0.0) for j in 1:G]

residuals = Float64[]
for j in 1:G
    if P1[j] > 0
        residual_pct = 100 * (gross_output_via_gva[j] - P1[j]) / P1[j]
        push!(residuals, residual_pct)
        println("  $(sections[j]): via-GVA=$(round(gross_output_via_gva[j],digits=1))  ",
                "P1(table)=$(round(P1[j],digits=1))  residual=$(round(residual_pct,digits=1))%")
    end
end
println("  ✓ mean absolute residual (via-GVA vs. the table's own P1): ",
        "$(round(mean(abs.(residuals)), digits = 1))%, maximum: $(round(maximum(abs.(residuals)), digits = 1))%")
println("  ✓ note: the production construction uses P1 directly when available ",
        "(reconciliation by construction); this residual only measures the fallback ",
        "path (Σflows+external GVA), for diagnosis.")

A_production = build_eurostat_io_matrix(COUNTRY, YEAR, [[s] for s in sections], gva_s)
println("\n  ✓ ρ(A) of the production construction (uses P1 directly): ",
        round(maximum(abs.(eigvals(A_production))), digits = 4))

println("\n" * "="^70)
println("Done.")
println("="^70)
