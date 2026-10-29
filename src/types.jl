# ============================================================================
# DATA STRUCTURES AND CONSTANTS
# ============================================================================
# Loaded first: defines the types and the constant dictionaries used by all
# the other files of the package.
# ============================================================================

# ----------------------------------------------------------------------------
# Department produtivo
# ----------------------------------------------------------------------------

"""
    Department

A productive department of the Marxian economy.

# Basic fields
- `name::String`: department identifier
- `c::Float64`: constant capital (means of production)
- `v::Float64`: variable capital (labor power / wages)
- `e::Float64`: rate of exploitation / surplus value (s/v)
- `k::Float64`: organic composition of capital (c/v)

# Behavioral parameters
- `σ_c::Float64`: share of surplus value reinvested in constant capital
- `σ_v::Float64`: share of surplus value reinvested in variable capital
- `γ::Float64`: share of surplus value consumed by capitalists
- `δ::Float64`: depreciation rate of constant capital

# Invariantes
- σ_c + σ_v + γ = 1.0 (all surplus value is allocated)
- e > 0 (positive exploitation)
- k = c/v (consistency)
"""
struct Department
    name::String
    c::Float64
    v::Float64
    e::Float64
    k::Float64
    σ_c::Float64
    σ_v::Float64
    γ::Float64
    δ::Float64

    function Department(name, c, v, e, k, σ_c, σ_v, γ, δ)
        @assert c > 0 "Constant capital must be positive"
        @assert v > 0 "Variable capital must be positive"
        @assert e > 0 "Rate of exploitation must be positive"
        @assert 0 ≤ σ_c ≤ 1 "σ_c must be in [0,1]"
        @assert 0 ≤ σ_v ≤ 1 "σ_v must be in [0,1]"
        @assert 0 ≤ γ ≤ 1 "γ must be in [0,1]"
        @assert abs(σ_c + σ_v + γ - 1.0) < 1e-6 "σ_c + σ_v + γ must sum to 1"
        @assert abs(k - c / v) < 1e-6 "k must equal c/v"
        @assert δ ≥ 0 "Depreciation rate cannot be negative"
        new(name, c, v, e, k, σ_c, σ_v, γ, δ)
    end
end

"""Simplified outer constructor with default values."""
function Department(name::String; c = 100.0, v = 50.0, e = 1.5,
                      σ_c = 0.5, σ_v = 0.2, δ = 0.05)
    γ = 1.0 - σ_c - σ_v
    k = c / v
    return Department(name, c, v, e, k, σ_c, σ_v, γ, δ)
end

# Helper methods
"""Profit rate r = e/(k+1)."""
profit_rate(d::Department) = d.e / (d.k + 1)

"""Surplus value s = e·v."""
surplus_value(d::Department) = d.e * d.v

"""Total (advanced) capital K = c + v. `d.c` is the advanced stock of constant
capital (used in accumulation and in the organic composition k=c/v), not the
value transferred/used up in one period."""
total_capital(d::Department) = d.c + d.v

"""Constant capital transferred/used up in one period, c_transferred = δ·c
(depreciation of the advanced stock). Distinct from `d.c` (advanced stock):
this is the right magnitude to add to annual flows (v, s) to get the value of
one period's product; see `product_value`."""
transferred_capital(d::Department) = d.δ * d.c

"""Value of one period's product, W = c_transferred + v + s (not c + v + s:
`d.c` is a stock while `v` and `s` are annual flows, so adding them directly
would mix magnitudes of different time dimensions)."""
product_value(d::Department) = transferred_capital(d) + d.v + surplus_value(d)

function Base.show(io::IO, d::Department)
    print(io, "Department(\"$(d.name)\": ")
    print(io, "K=$(round(total_capital(d), digits=1)), ")
    print(io, "k=$(round(d.k, digits=2)), ")
    print(io, "e=$(round(d.e, digits=2)), ")
    print(io, "r=$(round(profit_rate(d), digits=3)))")
end

# ----------------------------------------------------------------------------
# Calibrated parameters
# ----------------------------------------------------------------------------

"""
    CalibratedParameters

Holds the result of a calibration (INE or AMECO), ready to feed a
simulation.
"""
struct CalibratedParameters
    N::Int
    sector_names::Vector{String}
    nace_codes::Vector{String}

    C::Vector{Float64}
    V::Vector{Float64}
    GVA::Vector{Float64}  # actual gross value added (from the data source), not C+V+e·V

    e::Vector{Float64}
    e_raw::Vector{Float64}  # e before the 0.1 floor (docs/LIMITATIONS.md item 8); equals e where the floor does not bind
    k::Vector{Float64}
    r::Vector{Float64}

    A::Matrix{Float64}
    l::Vector{Float64}

    σ_c::Vector{Float64}
    σ_v::Vector{Float64}
    δ::Vector{Float64}

    source::String
    base_year::Int
    calibration_date::DateTime
    fit_quality::Float64

    # Real final demand by sector (`final_demand_from_iot`, `src/eurostat_sdmx.jl`)
    # on the Eurostat paths; `nothing` with synthetic data or fixed weights.
    final_demand::Union{Nothing, NamedTuple}
end

# ----------------------------------------------------------------------------
# INE data (Portuguese national source)
# ----------------------------------------------------------------------------

"""
    INEData

Container for data from Statistics Portugal (Instituto Nacional de Estatística).
"""
struct INEData
    year::Int
    supply_use::DataFrame
    sector_accounts::DataFrame
    employment::DataFrame
    gfcf::DataFrame
    metadata::Dict{String, Any}
end

# ----------------------------------------------------------------------------
# AMECO data (European Commission)
# ----------------------------------------------------------------------------

"""
    AMECOData

Macroeconomic time series for one country from the European Commission's
AMECO database (Annual Macro-Economic Database).
"""
struct AMECOData
    country::String
    country_code::String
    years::Vector{Int}

    # National accounts
    GDP::Vector{Float64}
    real_GDP::Vector{Float64}
    private_consumption::Vector{Float64}
    public_consumption::Vector{Float64}
    GFCF::Vector{Float64}
    exports::Vector{Float64}
    imports::Vector{Float64}

    # Labor market
    employment::Vector{Float64}
    employees::Vector{Float64}
    unemployment::Vector{Float64}
    labor_force::Vector{Float64}

    # Compensation and productivity
    compensation::Vector{Float64}
    productivity::Vector{Float64}
    unit_labor_costs::Vector{Float64}

    # Prices
    GDP_deflator::Vector{Float64}
    GFCF_deflator::Vector{Float64}
    CPI::Vector{Float64}
    CFC::Vector{Float64}  # consumption of fixed capital, current prices (item UKCT)

    # Public finances
    government_revenue::Vector{Float64}
    government_expenditure::Vector{Float64}
    budget_balance::Vector{Float64}
    public_debt::Vector{Float64}

    # External sector
    current_account::Vector{Float64}
    trade_balance::Vector{Float64}

    # Capital stock
    total_capital_stock::Vector{Float64}

    # Metadados
    source::String
    download_date::DateTime
    notes::Dict{String, String}
end

# ----------------------------------------------------------------------------
# AMECO country codes
# ----------------------------------------------------------------------------

const AMECO_COUNTRY_CODES = Dict(
    "Austria" => "AT", "Belgium" => "BE", "Bulgaria" => "BG",
    "Croatia" => "HR", "Cyprus" => "CY", "Czechia" => "CZ",
    "Denmark" => "DK", "Estonia" => "EE", "Finland" => "FI",
    "France" => "FR", "Germany" => "DE", "Greece" => "EL",
    "Hungary" => "HU", "Ireland" => "IE", "Italy" => "IT",
    "Latvia" => "LV", "Lithuania" => "LT", "Luxembourg" => "LU",
    "Malta" => "MT", "Netherlands" => "NL", "Poland" => "PL",
    "Portugal" => "PT", "Romania" => "RO", "Slovakia" => "SK",
    "Slovenia" => "SI", "Spain" => "ES", "Sweden" => "SE",
    "Euro Area" => "EA", "Euro Area (19)" => "EA19",
    "United Kingdom" => "UK", "Norway" => "NO", "Switzerland" => "CH",
    "Iceland" => "IS", "Turkey" => "TR",
    "European Union (27)" => "EU27", "European Union (28)" => "EU28",
    "United States" => "US", "Japan" => "JP",
)

# ----------------------------------------------------------------------------
# AMECO variable codes
# ----------------------------------------------------------------------------
# NOTE: used only by the legacy TXT parser (`read_ameco_txt_file`,
# `src/ameco_download.jl`), which no longer has an automatic download path
# (see docs/LIMITATIONS.md item 3). Corrected against the real SDMX API where
# that could be checked (`government_revenue`/`government_expenditure` were
# swapped; `private_consumption`/`exports`/`imports`/
# `unit_labor_costs`/`labor_productivity` used mnemonics that no longer
# exist, or never existed, in the API). `GDP_deflator` and
# `gross_capital_stock` remain unconfirmed: they have no direct equivalent
# in the SDMX API (the deflator is computed, the gross stock is not
# published; see `docs/LIMITATIONS.md` item 3) and are kept as they were,
# with no invented correction. For the current source of truth (SDMX API),
# see `AMECO_SDMX_MAP` in `src/ameco_sdmx.jl`.

const AMECO_VARIABLE_CODES = Dict(
    "GDP_current" => "UVGD",
    "GDP_constant" => "OVGD",
    "private_consumption" => "UCPH",
    "public_consumption" => "UCTG",
    "GFCF" => "UIGT",
    "exports" => "UXGS",
    "imports" => "UMGS",
    "employment_total" => "NETD",
    "employees" => "NWTD",
    "unemployment_rate" => "ZUTN",
    "labor_force" => "NLTN",
    "compensation" => "UWCD",
    "compensation_per_employee" => "HWCDW",
    "labor_productivity" => "ZVGDE",
    "unit_labor_costs" => "PLCD",
    "GDP_deflator" => "PVGD",
    "CPI" => "ZCPIH",
    "government_revenue" => "URTG",
    "government_expenditure" => "UUTG",
    "budget_balance" => "UBLG",
    "public_debt" => "UDGGL",
    "current_account" => "UBCA",
    "trade_balance" => "UBTB",
    "net_capital_stock" => "OKND",
    "gross_capital_stock" => "OKCD",
)
