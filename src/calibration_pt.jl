# ============================================================================
# CALIBRATION WITH PORTUGUESE DATA (INE)
# ============================================================================
# Generates synthetic data with the sectoral structure (CAE Rev.3) of the
# Portuguese economy and calibrates the model. The values are approximations
# for demonstration; do NOT use them for official analysis. See
# `fetch_portugal_eurostat_data` for the real-data path (opt-in,
# `data_source=:eurostat`).
# ============================================================================

"""The 19 CAE Rev.3 / NACE Rev.2 sections (code, name), used by both the synthetic and the real path."""
const PT_SECTORS = [
    ("A", "Agriculture, forestry and fishing"),
    ("B", "Mining and quarrying"),
    ("C", "Manufacturing"),
    ("D", "Electricity, gas, steam"),
    ("E", "Water supply, sewerage, waste"),
    ("F", "Construction"),
    ("G", "Wholesale and retail trade"),
    ("H", "Transportation and storage"),
    ("I", "Accommodation and food service"),
    ("J", "Information and communication"),
    ("K", "Financial and insurance activities"),
    ("L", "Real estate activities"),
    ("M", "Professional, scientific and technical"),
    ("N", "Administrative and support"),
    ("O", "Public administration"),
    ("P", "Education"),
    ("Q", "Human health and social work"),
    ("R", "Arts, entertainment and recreation"),
    ("S", "Other service activities"),
]

"""Generates synthetic data based on the Portuguese sectoral structure (19 NACE sections)."""
function generate_synthetic_portugal_data(year::Int)
    println("\n🔬 Generating synthetic data for Portugal ($year)...")

    sectors = PT_SECTORS
    N = length(sectors)
    codes = [s[1] for s in sectors]
    name_list = [s[2] for s in sectors]

    GVA = Float64[2_800, 800, 18_500, 3_200, 1_200, 8_500, 19_000, 7_800,
                  7_200, 8_500, 11_500, 19_000, 12_000, 9_500, 17_000,
                  13_500, 15_000, 2_200, 3_800]

    pct_compensation = [0.35, 0.40, 0.52, 0.35, 0.45, 0.60, 0.48, 0.50,
                        0.58, 0.55, 0.38, 0.15, 0.62, 0.65, 0.72, 0.75,
                        0.70, 0.60, 0.55]
    compensation = GVA .* pct_compensation
    GOS = GVA .- compensation

    pct_depreciation = [0.08, 0.12, 0.10, 0.15, 0.10, 0.06, 0.08, 0.12,
                       0.08, 0.15, 0.05, 0.02, 0.10, 0.08, 0.06, 0.05,
                       0.08, 0.10, 0.08]
    CFC = GVA .* pct_depreciation
    business_income = GOS .- CFC

    employment = Float64[180, 15, 650, 35, 45, 380, 850, 240, 380, 150,
                      110, 35, 320, 420, 680, 430, 520, 85, 180]

    pct_investment = [0.18, 0.25, 0.20, 0.30, 0.22, 0.15, 0.18, 0.22,
                        0.16, 0.25, 0.12, 0.35, 0.20, 0.18, 0.15, 0.12,
                        0.18, 0.20, 0.18]
    GFCF = GVA .* pct_investment

    capital_multiple = [2.5, 5.0, 1.8, 8.0, 6.0, 1.5, 1.2, 3.5, 1.8, 2.0,
                        1.5, 15.0, 1.0, 1.2, 2.5, 2.0, 2.5, 2.0, 1.5]
    capital_stock = GVA .* capital_multiple

    df = DataFrame(nace_code = codes, sector = name_list, GVA = GVA,
                   compensation = compensation, GOS = GOS, CFC = CFC,
                   business_income = business_income,
                   employment = employment, GFCF = GFCF, capital_stock = capital_stock)

    metadata = Dict{String, Any}(
        "source" => "Synthetic data (structure based on INE)",
        "year" => year, "GDP_total" => sum(GVA), "employment_total" => sum(employment))

    return INEData(year, df, df, df, df, metadata)
end

"""
Recomputes the capital stock per section by the perpetual inventory method
(`compute_pim_capital_stock`, `src/eurostat_sdmx.jl`) instead of using the
value Eurostat reports for `year` directly. Falls back per section (not
globally) to the reported value if the section does not have enough GFCF
history for the recursion to reach `year`, or if the estimated `δ` is not
valid. It never fails outright, like the other real-data paths in this file.
"""
function _pim_capital_stock_by_section(area_code::String, year::Int, codes::Vector{String},
                                       stock_reported::Dict{String, Float64})
    gfcf_series = fetch_eurostat_sector_gfcf_series(area_code)
    stock_series = fetch_eurostat_sector_capital_stock_series(area_code)
    cfc_series = fetch_eurostat_sector_cfc_series(area_code)

    result = Dict{String, Float64}()
    for c in codes
        (haskey(gfcf_series, c) && haskey(stock_series, c) && haskey(cfc_series, c)) || continue
        possible_years = [k for k in keys(stock_series[c]) if haskey(gfcf_series[c], k)]
        isempty(possible_years) && continue
        benchmark_year = minimum(possible_years)
        benchmark_value = stock_series[c][benchmark_year]
        δ = get(cfc_series[c], benchmark_year, 0.0) / benchmark_value
        (isfinite(δ) && δ > 0) || continue
        K = compute_pim_capital_stock(gfcf_series[c], δ, benchmark_year, benchmark_value,
                                       collect(benchmark_year:year))
        haskey(K, year) && (result[c] = K[year])
    end
    for c in codes
        haskey(result, c) || (result[c] = stock_reported[c])
    end
    return result
end

"""
    fetch_portugal_eurostat_data(year; perpetual_inventory=false)

Builds the same `INEData` format as `generate_synthetic_portugal_data`, but
with real sectoral data from Eurostat (`src/eurostat_sdmx.jl`): GVA,
compensation of employees and consumption of fixed capital (NAMA_10_A64),
employment (NAMA_10_A64_E), GFCF (NAMA_10_A64_P5) and the net capital stock
(NAMA_10_NFA_ST), for the 19 NACE sections. Only the sections with complete
data in all 6 series are used; it throws an error if too few remain (fewer
than 10 of 19), which signals a network failure or unavailability, not a
normal case to degrade silently.

`perpetual_inventory=true` replaces the net stock reported directly by
Eurostat with an own series computed by the perpetual inventory method
(`_pim_capital_stock_by_section`); see `docs/LIMITATIONS.md` item 7.
"""
function fetch_portugal_eurostat_data(year::Int; perpetual_inventory::Bool = false)
    println("\n🌐 Fetching real sectoral data (Eurostat) for Portugal ($year)...")

    gva, comp, cfc = fetch_eurostat_gva_compensation_cfc("PT", year)
    employment = fetch_eurostat_sector_employment("PT", year)
    gfcf = fetch_eurostat_sector_gfcf("PT", year)
    stock = fetch_eurostat_sector_capital_stock("PT", year)

    complete_sections = filter(s -> haskey(gva, s) && haskey(comp, s) && haskey(cfc, s) &&
                                    haskey(employment, s) && haskey(gfcf, s) && haskey(stock, s),
                               [s[1] for s in PT_SECTORS])
    length(complete_sections) < 10 &&
        error("Incomplete Eurostat data for Portugal/$year: only $(length(complete_sections))/19 " *
              "sections have all 6 series.")

    names_by_code = Dict(s[1] => s[2] for s in PT_SECTORS)
    codes = complete_sections
    name_list = [names_by_code[c] for c in codes]

    if perpetual_inventory
        stock = _pim_capital_stock_by_section("PT", year, codes, stock)
        println("  ✓ capital stock recomputed by perpetual inventory.")
    end

    GVA = [gva[c] for c in codes]
    compensation = [comp[c] for c in codes]
    CFC = [cfc[c] for c in codes]
    GOS = GVA .- compensation
    business_income = GOS .- CFC
    employment_v = [employment[c] for c in codes]
    GFCF = [gfcf[c] for c in codes]
    capital_stock = [stock[c] for c in codes]

    df = DataFrame(nace_code = codes, sector = name_list, GVA = GVA,
                   compensation = compensation, GOS = GOS, CFC = CFC,
                   business_income = business_income,
                   employment = employment_v, GFCF = GFCF, capital_stock = capital_stock)

    println("  ✓ $(length(codes))/19 sections with complete real data.")

    metadata = Dict{String, Any}(
        "source" => "Eurostat (real data)",
        "year" => year, "GDP_total" => sum(GVA), "employment_total" => sum(employment_v))

    return INEData(year, df, df, df, df, metadata)
end

"""Processes the supply and use tables, adding Marxian indicators."""
function process_supply_use(data::INEData)
    println("\n🔄 Processing supply and use tables...")
    df = data.supply_use
    df.mean_wage        = df.compensation ./ df.employment
    df.productivity        = df.GVA ./ df.employment
    df.capital_intensity  = df.capital_stock ./ df.employment
    df.surplus_value_rate      = df.business_income ./ df.compensation
    df.organic_composition  = df.capital_stock ./ df.compensation
    df.profit_rate           = df.business_income ./ (df.capital_stock .+ df.compensation)
    return df
end

"""
Estimates the Marxian parameters per sector from the processed supply and use
table.

`e` has a floor of 0.1: sectors whose business income (after CFC) is close to
zero or negative relative to compensation (typically because of thin margins
or high depreciation relative to the gross surplus) would produce a zero or
negative `e`, which the model does not accept (`Department` requires
`e>0`). The floor is an imposed value, not a pure empirical observation, and
it is reported explicitly below."""
function estimate_sector_parameters(df::DataFrame, A::Matrix{Float64})
    println("\n📐 Estimating parameters...")
    N = nrow(df)
    C = df.capital_stock
    V = df.compensation
    e = max.(0.1, df.surplus_value_rate)
    n_saturated = count(df.surplus_value_rate .< 0.1)
    n_saturated > 0 && println("  ⚠ e saturated at the 0.1 floor in $n_saturated/$N sectors " *
                                "(surplus_value_rate < 0.1 before the floor)")
    k = C ./ V
    r = e ./ (k .+ 1)

    l = df.employment ./ df.GVA .* 1800
    l = l ./ maximum(l)

    σ_c = clamp.(df.GFCF ./ df.business_income, 0.1, 0.7)
    σ_v = fill(0.15, N)
    δ = df.CFC ./ df.capital_stock

    γ = 1.0 .- σ_c .- σ_v
    for i in 1:N
        if γ[i] < 0
            σ_c[i] = 0.6; σ_v[i] = 0.2; γ[i] = 0.2
        end
    end

    println("  ✓ mean e: $(round(mean(e), digits=2)) | mean k: $(round(mean(k), digits=2)) | mean r: $(round(mean(r)*100, digits=1))%")
    return (C = C, V = V, e = e, k = k, r = r, l = l, σ_c = σ_c, σ_v = σ_v, δ = δ)
end

"""Names of the 10 groups of `NACE_MEDIUM_GROUPS` (same order)."""
const MEDIUM_GROUP_NAMES = [
    "Agriculture, forestry and fishing", "Industry (incl. energy)", "Construction",
    "Trade, transport, accommodation and food service", "Information and communication",
    "Financial and insurance activities", "Real estate activities",
    "Professional, scientific and administrative activities",
    "Public administration, education and health", "Arts and other services",
]
const MEDIUM_GROUP_CODES = ["A", "BCDE", "F", "GHI", "J", "K", "L", "MN", "OPQ", "RS"]

"""
    aggregate_sectors(df, A, groups, group_codes, group_names)

Aggregates a DataFrame of sectors (columns `nace_code, sector, GVA,
compensation, GOS, CFC, business_income, employment, GFCF, capital_stock`,
the format produced by `generate_synthetic_portugal_data`/
`fetch_portugal_eurostat_data`) and the matching technical matrix `A` into a
smaller number of groups (each element of `groups` is a list of 1-letter
`nace_code`s to merge). Returns `(df_aggregated, A_aggregated)`.

Works with both a real `A` (`build_eurostat_io_matrix`) and a random one
(`create_technical_matrix`): it reuses `aggregate_io_matrix`
(`src/eurostat_sdmx.jl`), which only assumes `A ≥ 0` and weights (GVA) `≥ 0`,
whatever the origin of the data.
"""
function aggregate_sectors(df::DataFrame, A::Matrix{Float64}, groups::Vector{Vector{String}},
                         group_codes::Vector{String}, group_names::Vector{String})
    gva_by_section = Dict(zip(df.nace_code, df.GVA))
    A_aggregated = aggregate_io_matrix(A, df.nace_code, groups, gva_by_section)

    total_sum(col) = [sum(df[in.(df.nace_code, Ref(sections)), col]) for sections in groups]

    df_aggregated = DataFrame(
        nace_code = group_codes, sector = group_names,
        GVA = total_sum(:GVA), compensation = total_sum(:compensation), GOS = total_sum(:GOS),
        CFC = total_sum(:CFC), business_income = total_sum(:business_income),
        employment = total_sum(:employment), GFCF = total_sum(:GFCF), capital_stock = total_sum(:capital_stock))

    return df_aggregated, A_aggregated
end

"""
    calibrate_portugal_model(; year=2022, aggregation=:detailed, data_source=:synthetic)

Calibration pipeline with INE data. `aggregation`:
- `:detailed` (default): 19 NACE sections, no aggregation.
- `:macro`: 3 sectors (Primary/Secondary/Tertiary, `NACE_MACRO_GROUPS`,
  `src/eurostat_sdmx.jl`), the same aggregation used in the AMECO path.
- `:medium`: 10 sectors (the standard NACE Rev.2 "A10" level,
  `NACE_MEDIUM_GROUPS`).

In both aggregated modes the technical matrix `A` is aggregated by the
Leontief formula (`aggregate_io_matrix`), which works with a synthetic
(random) or real (`data_source=:eurostat`) `A`, with no difference in code
between the two cases.

`data_source`:
- `:synthetic` (default): synthetic structure, random `A` (the historical
  behavior, unchanged).
- `:eurostat`: real sectoral data (`fetch_portugal_eurostat_data`) and a real
  technical matrix `A`, built from Eurostat's symmetric IOT
  (`build_eurostat_io_matrix`). Needs the network; throws an error if it is
  unavailable (no silent fallback, since real data were explicitly
  requested). `perpetual_inventory=true` (only has an effect with
  `data_source=:eurostat`) replaces the net stock reported by Eurostat with an
  own series computed by the perpetual inventory method; see
  `fetch_portugal_eurostat_data` and `docs/LIMITATIONS.md` item 7.
"""
function calibrate_portugal_model(; year = 2022, aggregation = :detailed,
                                  data_source = :synthetic, perpetual_inventory = false)
    println("\n" * "="^70)
    println("CALIBRATION FOR PORTUGAL (INE)  |  Year: $year  |  Aggregation: $aggregation  |  Source: $data_source")
    println("="^70)

    data = data_source == :eurostat ?
        fetch_portugal_eurostat_data(year; perpetual_inventory = perpetual_inventory) :
        generate_synthetic_portugal_data(year)
    df19 = process_supply_use(data)
    N19 = nrow(df19)
    A19 = data_source == :eurostat ?
        build_eurostat_io_matrix("PT", year, [[c] for c in df19.nace_code],
                                     Dict(zip(df19.nace_code, df19.GVA))) :
        create_technical_matrix(N19, density = 0.4)

    df, A = if aggregation == :detailed
        df19, A19
    elseif aggregation == :macro
        aggregate_sectors(df19, A19, NACE_MACRO_GROUPS, ["PRIM", "SEC", "TER"],
                        ["Primary", "Secondary", "Tertiary"])
    elseif aggregation == :medium
        aggregate_sectors(df19, A19, NACE_MEDIUM_GROUPS, MEDIUM_GROUP_CODES, MEDIUM_GROUP_NAMES)
    else
        error("unknown aggregation '$aggregation' (use :detailed, :macro or :medium)")
    end
    aggregation == :detailed || (df = process_supply_use(INEData(data.year, df, df, df, df, data.metadata)))
    N = nrow(df)
    p = estimate_sector_parameters(df, A)

    source = data_source == :eurostat ? "INE/Eurostat (real data)" : "INE (synthetic)"
    result = CalibratedParameters(N, df.sector, df.nace_code,
        p.C, p.V, df.GVA, p.e, p.k, p.r, A, p.l, p.σ_c, p.σ_v, p.δ,
        source, year, now(), 0.85)

    println("\n✅ CALIBRATION COMPLETE — $N sectors | GDP: €$(round(sum(df.GVA)/1000, digits=1)) bn")
    return result
end
