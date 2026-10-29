# ============================================================================
# AMECO INTEGRATION — CORE
# ============================================================================
# Synthetic data, calibration, international comparison and time series.
# The real download is in ameco_download.jl.
# ============================================================================

"""Lists, by category, all the countries available in AMECO."""
function list_ameco_countries()
    println("\n" * "="^70)
    println("COUNTRIES AVAILABLE IN THE AMECO DATABASE")
    println("="^70)
    categories = Dict(
        "European Union (27)" => ["Germany", "Austria", "Belgium", "Bulgaria",
            "Cyprus", "Croatia", "Denmark", "Slovakia", "Slovenia", "Spain",
            "Estonia", "Finland", "France", "Greece", "Hungary", "Ireland",
            "Italy", "Latvia", "Lithuania", "Luxembourg", "Malta", "Netherlands",
            "Poland", "Portugal", "Czechia", "Romania", "Sweden"],
        "Euro Area" => ["Euro Area", "Euro Area (19)"],
        "Other European" => ["United Kingdom", "Norway", "Switzerland", "Iceland"],
        "Candidates" => ["Turkey"],
        "International comparison" => ["United States", "Japan"],
        "Aggregates" => ["European Union (27)", "European Union (28)"],
    )
    for (cat, countries) in sort(collect(categories))
        println("\n📍 $cat"); println("-"^70)
        for p in sort(countries)
            println("  $p ($(AMECO_COUNTRY_CODES[p]))")
        end
    end
    println("\n💡 Usage: fetch_ameco_data(\"Portugal\"); calibrate_with_ameco_v2(\"Portugal\")")
    println("="^70 * "\n")
end

"""Resolves a country name or code to the AMECO ISO code."""
function _resolve_country_code(country::String)
    haskey(AMECO_COUNTRY_CODES, country) && return AMECO_COUNTRY_CODES[country]
    country in values(AMECO_COUNTRY_CODES) && return country
    error("Country '$country' not found. Use list_ameco_countries().")
end

"""
    generate_synthetic_ameco_data(country_code, years)

Synthetic but plausible time series (trend + cycle) calibrated by base
parameters for each country. For demonstration only; not for official use.
"""
function generate_synthetic_ameco_data(country_code::String, years::Vector{Int})
    println("\n🔬 Generating synthetic AMECO data for $country_code...")
    n = length(years)

    country_params = Dict(
        "PT" => (GDP_base = 234_000, employment_base = 4_900),
        "ES" => (GDP_base = 1_400_000, employment_base = 20_500),
        "DE" => (GDP_base = 3_900_000, employment_base = 44_900),
        "FR" => (GDP_base = 2_800_000, employment_base = 29_600),
        "IT" => (GDP_base = 2_000_000, employment_base = 25_600),
        "NL" => (GDP_base = 1_000_000, employment_base = 9_700),
        "BE" => (GDP_base = 580_000, employment_base = 5_000),
        "EL" => (GDP_base = 215_000, employment_base = 4_100),
        "IE" => (GDP_base = 500_000, employment_base = 2_500),
        "EA19" => (GDP_base = 14_000_000, employment_base = 165_000),
        "US" => (GDP_base = 25_000_000, employment_base = 160_000),
    )
    if !haskey(country_params, country_code)
        @warn "Country $country_code has no specific parameters; using the PT profile."
    end
    base = get(country_params, country_code, country_params["PT"])

    g_nom, g_real, infl = 0.015, 0.012, 0.02
    t = 1:n
    cycle = sin.(2π * t / 8) * 0.02

    GDP       = base.GDP_base .* (1 + g_nom).^(t .- n) .* (1 .+ cycle)
    real_GDP  = base.GDP_base .* (1 + g_real).^(t .- n) .* (1 .+ cycle * 0.8)
    deflator  = GDP ./ real_GDP * 100
    CPI       = 100 .* (1 + infl).^(t .- 1) .* (1 .+ rand(n) * 0.005 .- 0.0025)

    private_consumption = GDP * 0.65
    public_consumption = GDP * 0.18
    GFCF            = GDP * 0.20
    exports     = GDP * 0.45
    imports     = GDP * 0.43

    employment = base.employment_base .* (1 + 0.005).^(t .- n) .* (1 .+ cycle * 0.3)
    employees = employment * 0.85

    unemp_base = country_code == "PT" ? 7.0 : country_code == "DE" ? 3.5 :
                  country_code == "ES" ? 13.0 : country_code == "EL" ? 12.0 : 6.0
    unemployment = max.(unemp_base .+ cycle * (-20) .+ rand(n) * 2 .- 1, 2.0)
    labor_force = employment ./ (1 .- unemployment / 100)

    compensation = GDP * 0.52
    productivity = real_GDP ./ employment
    unit_costs = (compensation ./ employment) ./ productivity * 100

    revenue = GDP * 0.43
    expenditure = GDP * 0.46
    balance = (revenue .- expenditure) ./ GDP * 100
    debt_base = country_code == "PT" ? 120.0 : country_code == "EL" ? 180.0 :
                  country_code == "IT" ? 140.0 : country_code == "DE" ? 60.0 : 80.0
    debt = debt_base .+ cumsum(balance) * 0.1

    trade_bal = (exports .- imports) ./ GDP * 100
    current_bal = trade_bal .+ rand(n) * 2 .- 1

    capital_stock = GDP * 3.0 .+ cumsum(GFCF) * 0.1
    cfc = 0.05 .* capital_stock

    println("  ✓ $n years ($(years[1])-$(years[end])) | mean GDP $(round(mean(GDP)/1000, digits=1)) bn | mean unemployment $(round(mean(unemployment), digits=1))%")

    country_name = something(findfirst(==(country_code), AMECO_COUNTRY_CODES), country_code)
    notes = Dict("type" => "Synthetic data", "based_on" => "Real AMECO patterns",
                 "warning" => "Demonstration only; do not use for official analysis")

    return AMECOData(country_name, country_code, years,
        GDP, real_GDP, private_consumption, public_consumption, GFCF, exports, imports,
        employment, employees, unemployment, labor_force,
        compensation, productivity, unit_costs, deflator, deflator, CPI, cfc,
        revenue, expenditure, balance, debt, current_bal, trade_bal,
        capital_stock, "AMECO (synthetic)", now(), notes)
end

"""Builds an AMECOData from extracted series (name → vector dictionary)."""
function build_ameco_data(country_code, years, data::Dict, source;
                          notes = Dict{String, String}())
    country_name = something(findfirst(==(country_code), AMECO_COUNTRY_CODES), country_code)
    g(key, d = 0.0) = get(data, key, fill(d, length(years)))
    return AMECOData(country_name, country_code, years,
        g("GDP_current"), g("GDP_constant"), g("private_consumption"), g("public_consumption"),
        g("GFCF"), g("exports"), g("imports"), g("employment_total"),
        g("employees"), g("unemployment_rate"), g("labor_force"),
        g("compensation"), g("labor_productivity"), g("unit_labor_costs"),
        g("GDP_deflator"), g("GFCF_deflator"), g("CPI"), g("CFC"), g("government_revenue"), g("government_expenditure"),
        g("budget_balance"), g("public_debt"), g("current_account"),
        g("trade_balance", NaN), g("net_capital_stock"),
        source, now(), notes)
end

# ----------------------------------------------------------------------------
# Calibration from AMECO data
# ----------------------------------------------------------------------------

"""Sectoral distribution (macro: 3 sectors) of GVA by country."""
function _sector_gva_shares(country_code)
    country_code == "PT" ? [0.02, 0.22, 0.76] :
    country_code == "DE" ? [0.01, 0.30, 0.69] :
    country_code == "EL" ? [0.04, 0.16, 0.80] : [0.02, 0.25, 0.73]
end

"""Sectoral distribution (macro: 3 sectors) of employment by country."""
function _sector_employment_shares(country_code)
    country_code == "PT" ? [0.04, 0.24, 0.72] : [0.03, 0.26, 0.71]
end

"""Sectoral distribution (macro: 3 sectors) of the net capital stock.
Eurostat shares for Portugal (`NAMA_10_NFA_ST`, 2019/2022: ≈ 0.016 /
0.16 / 0.82), used for every country: the Tertiary sector includes housing."""
_sector_stock_shares(country_code) = [0.02, 0.16, 0.82]

"""Sums sectoral values (NACE section → value) by group of sections."""
function _sum_by_group(values::Dict{String, Float64}, groups::Vector{Vector{String}})
    [sum(get(values, s, 0.0) for s in sections) for sections in groups]
end

"""
    calibrate_with_ameco_data(data::AMECOData, year, aggregation; sector_data=:fixed)

Calibrates the model from an already loaded AMECOData structure. Only the
`:macro` aggregation (Primary/Secondary/Tertiary) is implemented at present.
If the requested year has no valid GDP, the closest valid year is used.

`sector_data`:
- `:fixed` (default): splits the AMECO totals by fixed weights
  (`_sector_gva_shares`/`_sector_employment_shares`), as before.
- `:eurostat`: uses real sectoral GVA, compensation, CFC, employment, GFCF
  and capital stock from Eurostat (`src/eurostat_sdmx.jl`), aggregated to the
  3 macro sectors, and a real technical matrix `A`: built at the 19 fine
  sectors (`build_eurostat_io_matrix`, already non-negative) and aggregated
  to the 3 macro sectors by the Leontief formula (`aggregate_io_matrix`),
  not directly from the raw IOT flows, which would reintroduce the
  trade/transport margins problem (see `docs/LIMITATIONS.md` item 4, now
  solved this way, with the caveat that the Tertiary row is conservative).
  It only covers EU/EEA countries; without coverage, or if the request (data
  or matrix) fails, it falls back to `:fixed` with a warning. It never throws
  on this path: unlike the INE path, the request here is not necessarily an
  explicit request for real data, since `calibrate_with_ameco_v2` can be
  called for any AMECO country, including those outside Eurostat's coverage.

`perpetual_inventory=true` (only has an effect with `sector_data=:eurostat`)
replaces the net stock reported by Eurostat with an own series computed by
the perpetual inventory method at the 19 fine sectors
(`_pim_capital_stock_by_section`, `src/calibration_pt.jl`), aggregated to the
3 macro sectors only afterwards: aggregating the already computed series is
more correct than recomputing from GFCF already summed into 3 groups. See
`docs/LIMITATIONS.md` item 7.
"""
function calibrate_with_ameco_data(data::AMECOData, year::Int, aggregation::Symbol;
                                  sector_data::Symbol = :fixed,
                                  perpetual_inventory::Bool = false)
    if year > data.years[end] && haskey(data.notes, "last_actual_year")
        @warn "Year $year is beyond the last actual AMECO year; using $(data.years[end])."
        year = data.years[end]
    end
    println("\n" * "="^70)
    println("CALIBRATION WITH AMECO DATA — $(data.country) | Year: $year")
    println("Source: $(data.source)")
    println("="^70)

    aggregation == :macro || error("Only the :macro aggregation is implemented")

    idx = findfirst(==(year), data.years)
    isnothing(idx) && error("Year $year unavailable. Years: $(data.years[1])-$(data.years[end])")

    if isnan(data.GDP[idx]) || data.GDP[idx] <= 0
        valid = findall(x -> !isnan(x) && x > 0, data.GDP)
        isempty(valid) && error("No valid GDP in the data")
        idx = valid[argmin(abs.(data.years[valid] .- year))]
        year = data.years[idx]
        @warn "GDP unavailable; using year $year (the closest with data)."
    end

    sectors = ["Primary", "Secondary", "Tertiary"]
    codes = ["PRIM", "SEC", "TER"]
    N = 3

    GDP_total    = data.GDP[idx]
    employment_total  = data.employment[idx]
    comp_total    = data.compensation[idx]
    GFCF_total   = data.GFCF[idx]
    stock_total    = data.total_capital_stock[idx]

    println("\n📊 Data ($year): GDP $(round(GDP_total/1000, digits=1)) bn | " *
            "Employment $(round(employment_total/1000, digits=2)) M | " *
            "Stock K $(round(stock_total/1000, digits=1)) bn")

    GVA = employment = compensation = capital_stock = GFCF_sectoral = CFC = Float64[]
    A_real = zeros(0, 0)
    final_demand = nothing
    real_sectoral = false

    if sector_data == :eurostat
        try
            gva_s, comp_s, cfc_s = fetch_eurostat_gva_compensation_cfc(data.country_code, year)
            employment_s = fetch_eurostat_sector_employment(data.country_code, year)
            gfcf_s = fetch_eurostat_sector_gfcf(data.country_code, year)
            stock_s = fetch_eurostat_sector_capital_stock(data.country_code, year)
            complete_sections = [s for s in NACE_SECTIONS if haskey(gva_s, s) && haskey(comp_s, s) &&
                                 haskey(cfc_s, s) && haskey(employment_s, s) && haskey(gfcf_s, s) && haskey(stock_s, s)]
            length(complete_sections) < 10 &&
                error("insufficient coverage ($(length(complete_sections))/19 sections)")

            if perpetual_inventory
                stock_s = _pim_capital_stock_by_section(data.country_code, year, complete_sections, stock_s)
                println("  ✓ capital stock recomputed by perpetual inventory (19 fine sectors).")
            end

            GVA           = _sum_by_group(gva_s, NACE_MACRO_GROUPS)
            compensation  = _sum_by_group(comp_s, NACE_MACRO_GROUPS)
            CFC           = _sum_by_group(cfc_s, NACE_MACRO_GROUPS)
            employment       = _sum_by_group(employment_s, NACE_MACRO_GROUPS)
            GFCF_sectoral = _sum_by_group(gfcf_s, NACE_MACRO_GROUPS)
            capital_stock = _sum_by_group(stock_s, NACE_MACRO_GROUPS)

            # Real matrix A: built at the 19 fine sectors (clean, non-negative;
            # see build_eurostat_io_matrix) and aggregated to the 3 macro sectors
            # by the Leontief formula (aggregate_io_matrix), not directly from the
            # raw IOT flows, which would reintroduce the trade/transport margins
            # problem (see docs/LIMITATIONS.md item 4).
            A19 = build_eurostat_io_matrix(data.country_code, year,
                [[s] for s in NACE_SECTIONS], gva_s)
            A_real = aggregate_io_matrix(A19, NACE_SECTIONS, NACE_MACRO_GROUPS, gva_s)
            final_demand = aggregate_final_demand(fetch_eurostat_final_demand(data.country_code, year),
                                                  NACE_MACRO_GROUPS, codes)

            real_sectoral = true
            println("  ✓ real sectoral data (Eurostat, $(length(complete_sections))/19 sections), real matrix A.")
        catch e
            @warn "Eurostat sectoral data/matrix A unavailable for $(data.country_code) ($e); using fixed weights and a random A."
        end
    end

    if !real_sectoral
        dist_GVA = _sector_gva_shares(data.country_code)
        dist_emp = _sector_employment_shares(data.country_code)
        GVA           = GDP_total * dist_GVA
        employment       = employment_total * dist_emp
        compensation  = comp_total * dist_GVA
        capital_stock = stock_total * _sector_stock_shares(data.country_code)
        GFCF_sectoral = GFCF_total * dist_GVA
        # Real AMECO CFC (UKCT), split like GVA (the real sectoral CFC shares
        # track the GVA shares closely); only without the series does it fall
        # back to a typical depreciation rate on the stock.
        CFC_total = data.CFC[idx]
        if isfinite(CFC_total) && CFC_total > 0
            CFC = CFC_total * dist_GVA
        else
            @warn "AMECO CFC unavailable in $year; using 6% of the capital stock."
            CFC = capital_stock * 0.06
        end
    end

    V = compensation
    C = capital_stock
    GOS = GVA .- compensation
    income = GOS .- CFC

    # Floor on e, as in estimate_sector_parameters (docs/LIMITATIONS.md item 8),
    # and r = e/(k+1) from the floored e, so that the parameters stay consistent.
    e_raw = income ./ compensation
    e = max.(e_raw, 0.1)
    n_saturated = count(e_raw .< 0.1)
    n_saturated > 0 && println("  ⚠ e saturated at the 0.1 floor in $n_saturated/$N sectors " *
                               "(surplus-value rate < 0.1 before the floor)")
    k = C ./ V
    r = e ./ (k .+ 1)

    println("\n📐 Marxian parameters:")
    for i in 1:N
        println("  $(sectors[i]): e=$(round(e[i], digits=2)) k=$(round(k[i], digits=2)) r=$(round(r[i]*100, digits=2))%")
    end

    A = real_sectoral ? A_real : create_technical_matrix(N, density = 0.3)
    l = employment ./ GVA; l = l / maximum(l)
    σ_c = clamp.(GFCF_sectoral ./ income, 0.2, 0.7)
    σ_v = fill(0.15, N)
    δ = CFC ./ capital_stock

    sector_source = real_sectoral ? " + Eurostat (real sectoral)" : ""
    result = CalibratedParameters(N, sectors, codes, C, V, GVA, e, e_raw, k, r, A, l,
        σ_c, σ_v, δ, "AMECO — $(data.source)$sector_source", year, now(), 0.80, final_demand)

    println("\n✅ CALIBRATION COMPLETE — mean e $(round(mean(e), digits=2)) | mean r $(round(mean(r)*100, digits=2))%")
    println("="^70 * "\n")
    return result, data
end

"""
    calibrate_with_ameco_v2(country; year=2022, method=:auto, sector_data=:fixed, perpetual_inventory=false, include_forecasts=false)

Fetches AMECO data (see `fetch_ameco_data`) and calibrates the model. A
`year` that is still a Commission forecast falls back, with a warning, to
the last actual year, unless `include_forecasts=true`.
`method` ∈ (:auto, :sdmx, :download, :local, :csv, :synthetic, :manual).
`sector_data` ∈ (:fixed, :eurostat), `perpetual_inventory`: see
`calibrate_with_ameco_data`.
"""
function calibrate_with_ameco_v2(country::String; year = 2022, method = :auto,
                               sector_aggregation = :macro, sector_data = :fixed,
                               perpetual_inventory = false, include_forecasts = false)
    data = fetch_ameco_data(country, years = 1995:year, method = method,
                            include_forecasts = include_forecasts)
    return calibrate_with_ameco_data(data, year, sector_aggregation;
                                    sector_data = sector_data,
                                    perpetual_inventory = perpetual_inventory)
end

# ----------------------------------------------------------------------------
# International comparison
# ----------------------------------------------------------------------------

"""
    compare_ameco_countries(countries; year=2022, method=:synthetic)

Calibrates several countries and produces a comparison table and plots of
the Marxian indicators.
"""
function compare_ameco_countries(countries::Vector{String}; year = 2022, method = :synthetic)
    println("\n" * "="^70)
    println("INTERNATIONAL COMPARISON — AMECO | Year: $year")
    println("Countries: $(join(countries, ", "))")
    println("="^70)

    results = []
    for country in countries
        println("\n🌍 $country...")
        params, data = calibrate_with_ameco_v2(country, year = year, method = method)
        push!(results, (country = country, params = params, data = data))
    end

    df = DataFrame(
        Country = [r.country for r in results],
        GDP = [round(sum(r.params.GVA) / 1000, digits = 1) for r in results],   # billions
        Exploitation_Rate = [round(mean(r.params.e), digits = 2) for r in results],
        Organic_Composition = [round(mean(r.params.k), digits = 2) for r in results],
        Profit_Rate = [round(mean(r.params.r) * 100, digits = 2) for r in results],
        Wage_Share = [round(sum(r.params.V) / sum(r.params.GVA) * 100, digits = 1) for r in results],
    )
    println("\n", df)

    p1 = bar(df.Country, df.Exploitation_Rate, title = "Rate of Exploitation (e)",
             legend = false, color = :steelblue, alpha = 0.7)
    p2 = bar(df.Country, df.Organic_Composition, title = "Organic Composition (k)",
             legend = false, color = :coral, alpha = 0.7)
    p3 = bar(df.Country, df.Profit_Rate, title = "Profit Rate (%)",
             legend = false, color = :green, alpha = 0.7)
    p4 = bar(df.Country, df.Wage_Share, title = "Wage Share (% GDP)",
             legend = false, color = :purple, alpha = 0.7)
    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "International Comparison ($year)")
    display(plt)

    return (results = results, table = df, plot = plt)
end

# ----------------------------------------------------------------------------
# Time series
# ----------------------------------------------------------------------------

"""
    analyze_time_series_with_data(data; valuation=:current)

Computes Marxian indicators year by year from `AMECOData`.

`total_capital_stock` (AMECO item `OKND`) is reported at **constant 2020
prices** ("Net capital stock at 2020 prices"), not at current prices, as
confirmed with the SDMX codelist (`CL_AMECO_ITEM`), which has no
current-price capital stock equivalent. `compensation` (`UWCD`) and `GDP`
(`UVGD`), on the other hand, are current-price series.

- `valuation=:current` (default, compatible with earlier versions): uses `V`
  and `GVA` at current prices as reported, even though this mixes the
  valuation of `C` (constant) with that of `V`/`GVA` (current). That mismatch
  alone can push `k=C/V` down over decades of nominal wage inflation without
  any change in the real organic composition.
- `valuation=:consistent`: deflates `V` by the `GDP_deflator`
  (= `GDP_current/GDP_constant×100`) and uses `real_GDP` (constant) instead of
  `GDP` (current), putting `C`, `V` and `GVA` on the same constant-price
  basis. This is the right comparison to tell whether the fall in `k` is a
  real effect or a valuation artifact.
- `valuation=:consistent_gfcf`: a variant of `:consistent` that deflates `V`
  by the `GFCF_deflator` (item `PIGT`, "Price deflator gross fixed capital
  formation", also indexed to 2020=100) instead of the GDP deflator.
  `total_capital_stock` is built by accumulating GFCF at constant prices
  (AMECO's implicit perpetual inventory), so the investment deflator, not
  the general GDP deflator, is what actually sets the price basis of `C`.
  This variant tests whether the conclusion of `:consistent` is sensitive to
  that choice (capital goods prices have historically tended to fall
  relative to the general GDP deflator).

A period's surplus/surplus value uses `inc = GVA - V - CFC`, where `CFC`
(AMECO item `UKCT`, "Consumption of fixed capital... total economy") is the
constant capital actually \\emph{transferred/used up} in the period, not an
arbitrary fixed fraction of the stock `C`. (An earlier version of this code
used `C*0.10`, an approximation that, by mixing a stock at constant 2020
prices with current flows, broke the algebraic invariance that
`e=(GVA-V)/V` should have under a common deflator; see `docs/` for the
check.) `CFC` is deflated with the same index used for `V`/`GVA` in each
convention, which preserves that invariance for the `(GVA-V)/V` part and
correctly isolates the effect of the depreciation deduction. The profit rate
`r=inc/(C+V)` still divides by `C` (the advanced stock), Marx's classic
formula (profit on capital advanced), which is distinct from the
composition of the numerator `inc`.
"""
function analyze_time_series_with_data(data::AMECOData; valuation::Symbol = :current)
    n = length(data.years)
    e_t = fill(NaN, n); k_t = fill(NaN, n); r_t = fill(NaN, n); q_t = fill(NaN, n)
    for i in 1:n
        C = data.total_capital_stock[i]
        if valuation == :current
            V, GVA, CFC = data.compensation[i], data.GDP[i], data.CFC[i]
        elseif valuation == :consistent
            def = data.GDP_deflator[i]
            factor = (!isnan(def) && def > 0) ? 100 / def : NaN
            V, GVA, CFC = data.compensation[i] * factor, data.real_GDP[i], data.CFC[i] * factor
        elseif valuation == :consistent_gfcf
            def = data.GFCF_deflator[i]
            factor = (!isnan(def) && def > 0) ? 100 / def : NaN
            V, GVA, CFC = data.compensation[i] * factor, data.real_GDP[i], data.CFC[i] * factor
        else
            error("unknown valuation: $valuation (use :current, :consistent or :consistent_gfcf)")
        end
        if !isnan(V) && !isnan(C) && !isnan(GVA) && !isnan(CFC) && V > 0 && C > 0
            inc = GVA - V - CFC
            e_t[i] = inc / V
            k_t[i] = C / V
            r_t[i] = inc / (C + V)
            q_t[i] = V / GVA
        end
    end
    return (years = data.years, e = e_t, k = k_t, r = r_t, wage_share = q_t)
end

"""
    analyze_ameco_time_series(country; years=1995:2023, method=:synthetic)

Fetches the data and produces the time-series analysis (4 panels) of the Marxian indicators.
"""
function analyze_ameco_time_series(country::String; years = 1995:2023,
                                       method = :synthetic, file = nothing,
                                       valuation::Symbol = :current,
                                       include_forecasts = false)
    println("\n" * "="^70)
    println("TIME-SERIES ANALYSIS — $country | $(first(years))-$(last(years))")
    println("="^70)

    data = fetch_ameco_data(country, years = years, method = method,
                              file = file, include_forecasts = include_forecasts)
    st = analyze_time_series_with_data(data; valuation = valuation)

    p1 = plot(st.years, st.e, xlabel = "Year", ylabel = "e",
              title = "Rate of Exploitation", lw = 2, label = "", color = :blue)
    p2 = plot(st.years, st.k, xlabel = "Year", ylabel = "k",
              title = "Organic Composition", lw = 2, label = "", color = :red)
    p3 = plot(st.years, st.r * 100, xlabel = "Year", ylabel = "r (%)",
              title = "Profit Rate", lw = 2, label = "", color = :green)
    p4 = plot(st.years, st.wage_share * 100, xlabel = "Year", ylabel = "% GDP",
              title = "Wage Share", lw = 2, label = "", color = :purple)
    plt = plot(p1, p2, p3, p4, layout = (2, 2), size = (1400, 1000),
               plot_title = "Time-Series Analysis: $country")
    display(plt)

    v(x) = filter(!isnan, x)
    println("\n📈 PERIOD AVERAGES:")
    println("  e: $(round(mean(v(st.e)), digits=2)) | k: $(round(mean(v(st.k)), digits=2)) | " *
            "r: $(round(mean(v(st.r))*100, digits=2))% | wage share: $(round(mean(v(st.wage_share))*100, digits=1))%")
    println("="^70 * "\n")

    return (data = data, e = st.e, k = st.k, r = st.r,
            wage_share = st.wage_share, plot = plt)
end

"""Creates a vector of Department from CalibratedParameters."""
function departments_from_params(params::CalibratedParameters)
    depts = Department[]
    for i in 1:params.N
        push!(depts, Department(params.sector_names[i], c = params.C[i],
                                  v = params.V[i], e = params.e[i], σ_c = params.σ_c[i],
                                  σ_v = params.σ_v[i], δ = params.δ[i]))
    end
    return depts
end
