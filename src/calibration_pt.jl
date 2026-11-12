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
    _pim_mode(perpetual_inventory)

Normalizes the `perpetual_inventory` keyword: `false`/`:off` → `:off`,
`true`/`:single` → `:single` (one depreciation rate per section),
`:by_asset` → `:by_asset` (`compute_pim_capital_stock_by_asset`).
"""
function _pim_mode(perpetual_inventory)
    perpetual_inventory === false && return :off
    perpetual_inventory === true && return :single
    perpetual_inventory in (:off, :single, :by_asset) && return perpetual_inventory
    throw(ArgumentError("perpetual_inventory must be false, true, :single or :by_asset, " *
                        "got $(repr(perpetual_inventory))"))
end

"""
Recomputes the capital stock per section by the perpetual inventory method
(`compute_pim_capital_stock`, `src/eurostat_sdmx.jl`) instead of using the
value Eurostat reports for `year` directly. Falls back per section (not
globally) to the reported value if the section does not have enough GFCF
history for the recursion to reach `year`, or if the estimated `δ` is not
valid. It never fails outright, like the other real-data paths in this file.

With `by_asset = true`, each section's stock is first computed asset by
asset (`compute_pim_capital_stock_by_asset`: a depreciation rate per asset
type from Eurostat's volume series, or the asset type's median rate over
the other sections for a small holding without one, each asset revalued by
its own GFCF deflator); a section where that fails falls back to the single-rate
recursion, then to the reported value, with a warning naming the sections.
"""
function _pim_capital_stock_by_section(area_code::String, year::Int, codes::Vector{String},
                                       stock_reported::Dict{String, Float64}; by_asset::Bool = false)
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
    if by_asset
        gfcf_vol = fetch_eurostat_sector_gfcf_by_asset_series(area_code; unit = "CLV15_MEUR")
        gfcf_cur = fetch_eurostat_sector_gfcf_by_asset_series(area_code; unit = "CP_MEUR")
        stock_vol = fetch_eurostat_sector_capital_stock_by_asset_series(area_code; unit = "CLV15_MEUR")
        section(series, c) = Dict(a => v[c] for (a, v) in series if haskey(v, c))
        # an asset type's rate in the other sections, for small holdings without their own
        δ_fallback = Dict(a => median(collect(values(d)))
                          for (a, d) in asset_depreciation_rates(gfcf_vol, gfcf_cur, stock_vol) if !isempty(d))
        fallback = String[]
        for c in codes
            K = compute_pim_capital_stock_by_asset(section(gfcf_vol, c), section(gfcf_cur, c),
                                                   section(stock_vol, c), year; δ_fallback = δ_fallback)
            if isnothing(K) || isempty(section(stock_vol, c))
                push!(fallback, c)
            else
                result[c] = K
            end
        end
        isempty(fallback) ||
            @warn "perpetual inventory by asset not possible for sections $(join(fallback, ", ")); " *
                  "they use one depreciation rate per section (or the reported stock)"
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

`perpetual_inventory=true` (or `:single`) replaces the net stock reported
directly by Eurostat with an own series computed by the perpetual inventory
method with one depreciation rate per section; `:by_asset` does it asset by
asset (`_pim_capital_stock_by_section`); see `docs/LIMITATIONS.md` item 7.

`self_employed=:imputed` also fetches the number of employees per section
(`SAL_DC`, a 7th series that then has to be complete too) and counts each
self-employed worker at the average employee's compensation in that section
(`impute_self_employed`), so that their income is no longer counted as
surplus value. The default, `:excluded`, uses compensation of employees as
published. With `:imputed` the df also gets an `employees` column, and its
`compensation` (hence `GOS` and `business_income`) is the imputed one.
`:imputed_hours` imputes per hour worked instead of per person (`THS_HW`,
`fetch_eurostat_sector_hours`; two more series that have to be complete).

`e_years > 1` also requires GVA, compensation and CFC (and, when imputing,
the labor series) for each of the `e_years` years ending in `year`, and adds
the window sums `compensation_e` and `business_income_e`, from which
`process_supply_use` computes `e`; the imputation is done year by year.
"""
function fetch_portugal_eurostat_data(year::Int; perpetual_inventory = false,
                                      self_employed::Symbol = :excluded, e_years::Int = 1)
    _check_self_employed(self_employed; hours_ok = true)
    pim = _pim_mode(perpetual_inventory)
    e_years >= 1 || throw(ArgumentError("e_years must be ≥ 1, got $e_years"))
    println("\n🌐 Fetching real sectoral data (Eurostat) for Portugal ($year)...")

    imputed = self_employed in (:imputed, :imputed_hours)
    by_hours = self_employed == :imputed_hours
    window = (year - e_years + 1):year

    # GVA, compensation and CFC as whole series (one download each), so that
    # `e_years > 1` can sum over a window; `year` alone is the default.
    gva_s  = _fetch_eurostat_sections("NAMA_10_A64", "A.CP_MEUR..B1G.PT")
    comp_s = _fetch_eurostat_sections("NAMA_10_A64", "A.CP_MEUR..D1.PT")
    cfc_s  = _fetch_eurostat_sections("NAMA_10_A64", "A.CP_MEUR..P51C.PT")
    labor_item(item, unit) = _fetch_eurostat_sections("NAMA_10_A64_E", "A.$unit..$item.PT")
    unit = by_hours ? "THS_HW" : "THS_PER"
    labor_all_s = imputed ? labor_item("EMP_DC", unit) : Dict{String, Dict{Int, Float64}}()
    labor_emp_s = imputed ? labor_item("SAL_DC", unit) : Dict{String, Dict{Int, Float64}}()
    at(series, y) = Dict(s => v[y] for (s, v) in series if haskey(v, y))

    gva, comp, cfc = at(gva_s, year), at(comp_s, year), at(cfc_s, year)
    employment = fetch_eurostat_sector_employment("PT", year)
    gfcf = fetch_eurostat_sector_gfcf("PT", year)
    stock = fetch_eurostat_sector_capital_stock("PT", year)
    employees = imputed ? fetch_eurostat_sector_employees("PT", year) : Dict{String, Float64}()
    n_series = 6 + (imputed ? 1 : 0) + (by_hours ? 2 : 0)

    has_window(series, s) = haskey(series, s) && all(y -> haskey(series[s], y), window)
    complete_sections = filter(s -> haskey(gva, s) && haskey(comp, s) && haskey(cfc, s) &&
                                    haskey(employment, s) && haskey(gfcf, s) && haskey(stock, s) &&
                                    (!imputed || haskey(employees, s)) &&
                                    (!by_hours || (has_window(labor_all_s, s) && has_window(labor_emp_s, s))) &&
                                    (e_years == 1 || all(x -> has_window(x, s), (gva_s, comp_s, cfc_s))) &&
                                    (e_years == 1 || !imputed || (has_window(labor_all_s, s) && has_window(labor_emp_s, s))),
                               [s[1] for s in PT_SECTORS])
    length(complete_sections) < 10 &&
        error("Incomplete Eurostat data for Portugal/$year: only $(length(complete_sections))/19 " *
              "sections have all $n_series series" * (e_years > 1 ? " for $(first(window))–$year." : "."))

    names_by_code = Dict(s[1] => s[2] for s in PT_SECTORS)
    codes = complete_sections
    name_list = [names_by_code[c] for c in codes]

    if pim !== :off
        stock = _pim_capital_stock_by_section("PT", year, codes, stock; by_asset = pim === :by_asset)
        println("  ✓ capital stock recomputed by perpetual inventory" *
                (pim === :by_asset ? ", asset by asset." : "."))
    end

    # Compensation of the year `y`, with the self-employed imputed if asked
    # (by persons or by hours worked, `impute_self_employed`).
    compensation_in(y) = imputed ?
        impute_self_employed(at(comp_s, y), at(labor_all_s, y), at(labor_emp_s, y), codes) :
        at(comp_s, y)

    if imputed
        comp_published = comp
        comp = compensation_in(year)
        println("  ✓ self-employed imputed at the average employee's compensation" *
                (by_hours ? " per hour worked" : "") * ", by section:")
        println("    " * join(["$c ×$(round(comp[c] / comp_published[c], digits = 2))" for c in codes], "  "))
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
    imputed && (df.employees = [employees[c] for c in codes])

    if e_years > 1
        # Window sums for `e` only (`process_supply_use`); k, δ and σ_c stay those of `year`.
        comps = [compensation_in(y) for y in window]
        df.compensation_e = [sum(cy[c] for cy in comps) for c in codes]
        df.business_income_e = [sum(gva_s[c][y] - cfc_s[c][y] for y in window) for c in codes] .- df.compensation_e
        println("  ✓ e computed over $(first(window))–$year.")
    end

    println("  ✓ $(length(codes))/19 sections with complete real data.")

    metadata = Dict{String, Any}(
        "source" => "Eurostat (real data)",
        "year" => year, "GDP_total" => sum(GVA), "employment_total" => sum(employment_v),
        "self_employed" => string(self_employed), "e_years" => e_years)

    return INEData(year, df, df, df, df, metadata)
end

"""Processes the supply and use tables, adding Marxian indicators."""
function process_supply_use(data::INEData)
    println("\n🔄 Processing supply and use tables...")
    df = data.supply_use
    df.mean_wage        = df.compensation ./ df.employment
    df.productivity        = df.GVA ./ df.employment
    df.capital_intensity  = df.capital_stock ./ df.employment
    # `e` from the window sums when `e_years > 1` (`fetch_portugal_eurostat_data`)
    df.surplus_value_rate      = "business_income_e" in names(df) ?
                                 df.business_income_e ./ df.compensation_e :
                                 df.business_income ./ df.compensation
    df.organic_composition  = df.capital_stock ./ df.compensation
    df.profit_rate           = df.business_income ./ (df.capital_stock .+ df.compensation)
    return df
end

"""
Estimates the Marxian parameters per sector from the processed supply and use
table.

`e` has a floor, `e_floor` (0.1 by default): sectors whose business income (after CFC) is close to
zero or negative relative to compensation (typically because of thin margins
or high depreciation relative to the gross surplus) would produce a zero or
negative `e`, which the model does not accept (`Department` requires
`e>0`). The floor is an imposed value, not a pure empirical observation, and
it is reported explicitly below."""
function estimate_sector_parameters(df::DataFrame, A::Matrix{Float64}; e_floor::Real = 0.1)
    _check_e_floor(e_floor)
    println("\n📐 Estimating parameters...")
    N = nrow(df)
    C = df.capital_stock
    V = df.compensation
    e = max.(e_floor, df.surplus_value_rate)
    n_saturated = count(df.surplus_value_rate .< e_floor)
    n_saturated > 0 && println("  ⚠ e saturated at the $e_floor floor in $n_saturated/$N sectors " *
                                "(surplus_value_rate < $e_floor before the floor: " *
                                join(df.nace_code[df.surplus_value_rate .< e_floor], ", ") * ")")
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
    return (C = C, V = V, e = e, e_raw = df.surplus_value_rate, k = k, r = r, l = l,
            σ_c = σ_c, σ_v = σ_v, δ = δ)
end

"""`Department` requires `e > 0`, so the floor on `e` must be positive and finite."""
_check_e_floor(e_floor::Real) = (isfinite(e_floor) && e_floor > 0) ||
    throw(ArgumentError("e_floor must be positive and finite (Department requires e > 0), got $e_floor"))

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
    for col in (:employees, :compensation_e, :business_income_e)
        string(col) in names(df) && (df_aggregated[!, col] = total_sum(col))
    end

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
  own series computed by the perpetual inventory method, with one
  depreciation rate per section; `perpetual_inventory=:by_asset` computes it
  asset by asset; see `fetch_portugal_eurostat_data` and
  `docs/LIMITATIONS.md` item 7.

`self_employed`:
- `:excluded` (default): `V` is compensation of employees, as published, so
  the income of the self-employed counts as surplus value, which overstates
  `e` where self-employment is common (agriculture, real estate, personal
  services).
- `:imputed`: each self-employed worker is counted as earning the average
  employee's compensation in their section, `Vᵢ × employmentᵢ / employeesᵢ`,
  imputed at the 19 sections before any aggregation (see
  `impute_self_employed`). Needs `data_source=:eurostat`: the synthetic data
  have no employee counts. More sectors may then hit the 0.1 floor on `e`
  (`docs/LIMITATIONS.md` item 8); `e_raw` keeps the unfloored values.
- `:imputed_hours`: the same, per hour worked instead of per person,
  `Vᵢ × hoursᵢ / employee hoursᵢ` (`fetch_eurostat_sector_hours`), so that a
  self-employed worker who works part of the year counts for less. Needs
  `data_source=:eurostat`.

`sectors`:
- `:all` (default): the 19 sections.
- `:market`: leaves out `NON_MARKET_SECTIONS` (L, O, P, Q: real estate, with
  its imputed rents, and the non-market services, whose `e` is ≈ 0 by
  construction), before any aggregation; groups left empty are dropped
  (`:medium` has 8 groups, `:macro` still 3). `A` keeps the market rows and
  columns. With `data_source=:eurostat`, what the market sectors buy from the
  dropped ones is added to the import coefficients (inputs from outside the
  modelled economy, `outside_input_coefficients`), and what the dropped ones
  buy from the market sectors to government final demand
  (`outside_purchases_from_iot`). See `docs/NATIONAL_ACCOUNTS.md`.

`e_years` (default 1): computes `e` (and `e_raw`) from business income and
compensation summed over the `e_years` years ending in `year`, which smooths
one-off years (electricity in Portugal, 2022). `k`, `δ`, `σ_c` stay those of
`year`. Needs `data_source=:eurostat` when > 1.

`e_floor` (default 0.1): the floor on `e` (`docs/LIMITATIONS.md` item 8); it
must be positive, since `Department` requires `e > 0`.
"""
function calibrate_portugal_model(; year = 2022, aggregation = :detailed,
                                  data_source = :synthetic, perpetual_inventory = false,
                                  self_employed = :excluded, sectors = :all, e_years = 1,
                                  e_floor = 0.1)
    _check_self_employed(self_employed; hours_ok = true)
    _pim_mode(perpetual_inventory)
    (self_employed != :excluded && data_source != :eurostat) &&
        throw(ArgumentError("self_employed=:$self_employed needs employee counts by sector, which only " *
                            "data_source=:eurostat provides"))
    sectors in (:all, :market) ||
        throw(ArgumentError("sectors must be :all or :market, got :$sectors"))
    (e_years isa Integer && e_years >= 1) ||
        throw(ArgumentError("e_years must be an integer ≥ 1, got $e_years"))
    (e_years > 1 && data_source != :eurostat) &&
        throw(ArgumentError("e_years > 1 needs a series of years, which only data_source=:eurostat provides"))
    _check_e_floor(e_floor)
    aggregation in (:detailed, :macro, :medium) ||
        error("unknown aggregation '$aggregation' (use :detailed, :macro or :medium)")
    println("\n" * "="^70)
    println("CALIBRATION FOR PORTUGAL (INE)  |  Year: $year  |  Aggregation: $aggregation  |  Source: $data_source" *
            (sectors == :market ? "  |  Market sectors" : ""))
    println("="^70)

    data = data_source == :eurostat ?
        fetch_portugal_eurostat_data(year; perpetual_inventory = perpetual_inventory,
                                     self_employed = self_employed, e_years = e_years) :
        generate_synthetic_portugal_data(year)
    df19 = process_supply_use(data)
    N19 = nrow(df19)
    A19 = data_source == :eurostat ?
        build_eurostat_io_matrix("PT", year, [[c] for c in df19.nace_code],
                                     Dict(zip(df19.nace_code, df19.GVA))) :
        create_technical_matrix(N19, density = 0.4)
    fd19 = data_source == :eurostat ?
        aggregate_final_demand(fetch_eurostat_final_demand("PT", year),
                               [[c] for c in df19.nace_code], df19.nace_code) : nothing
    m19 = data_source == :eurostat ? fetch_eurostat_import_coefficients("PT", year) : nothing

    # Market sectors: drop the non-market sections at the 19-section level,
    # before any aggregation (see the docstring).
    if sectors == :market
        keep = findall(c -> !(c in NON_MARKET_SECTIONS), df19.nace_code)
        if data_source == :eurostat
            outside = outside_input_coefficients(A19, df19.nace_code)
            m19 = Dict(c => get(m19, c, 0.0) + outside[c] for c in df19.nace_code[keep])
            iot = _fetch_iot("PT", _nearest_iot_year("PT", year))
            bought = outside_purchases_from_iot(iot, NON_MARKET_SECTIONS, df19.nace_code)
            fd19 = merge(fd19, (government = fd19.government .+ bought,))
            fd19 = aggregate_final_demand(fd19, [[c] for c in df19.nace_code[keep]], df19.nace_code[keep])
        end
        A19 = A19[keep, keep]
        df19 = df19[keep, :]
        println("  ✓ market sectors: left out $(join(NON_MARKET_SECTIONS, ", ")); $(nrow(df19)) sections remain.")
    end

    groups, codes, names_ = if aggregation == :macro
        NACE_MACRO_GROUPS, ["PRIM", "SEC", "TER"], ["Primary", "Secondary", "Tertiary"]
    elseif aggregation == :medium
        NACE_MEDIUM_GROUPS, MEDIUM_GROUP_CODES, MEDIUM_GROUP_NAMES
    else
        [[c] for c in df19.nace_code], df19.nace_code, df19.sector
    end
    if sectors == :market
        groups, kept = drop_sections(groups)
        codes, names_ = codes[kept], names_[kept]
    end

    m = isnothing(m19) ? nothing : aggregate_import_coefficients(m19, groups, Dict(zip(df19.nace_code, df19.GVA)))
    fd = (isnothing(fd19) || aggregation == :detailed) ? fd19 : aggregate_final_demand(fd19, groups, codes)

    df, A = aggregation == :detailed ? (df19, A19) : aggregate_sectors(df19, A19, groups, codes, names_)
    aggregation == :detailed || (df = process_supply_use(INEData(data.year, df, df, df, df, data.metadata)))
    N = nrow(df)
    p = estimate_sector_parameters(df, A; e_floor = e_floor)

    source = data_source == :eurostat ? "INE/Eurostat (real data)" : "INE (synthetic)"
    result = CalibratedParameters(N, df.sector, df.nace_code,
        p.C, p.V, df.GVA, p.e, p.e_raw, p.k, p.r, A, p.l, p.σ_c, p.σ_v, p.δ,
        source, year, now(), 0.85, fd, m)

    println("\n✅ CALIBRATION COMPLETE — $N sectors | GDP: €$(round(sum(df.GVA)/1000, digits=1)) bn")
    return result
end
