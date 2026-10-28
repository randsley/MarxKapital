# ============================================================================
# AUTOMATIC AMECO DOWNLOAD (LEGACY) AND TXT FILE PARSER
# ============================================================================
# LEGACY: the European Commission withdrew the static TXT file that this file
# used to download; the URLs below no longer return real data (confirmed
# 2026-07: 404 or a redirect to the portal's HTML page). The default
# automatic path is now the official SDMX API, in `src/ameco_sdmx.jl` (see
# `fetch_ameco_data`, methods `:auto`/`:sdmx`). `read_ameco_txt_file`/
# `parse_ameco_csv` stay here as a manual workflow for anyone who already
# has a TXT/CSV file downloaded some other way.
# See docs/LIMITATIONS.md (item 3).
# ============================================================================

"""Candidate URLs for AMECO's full TXT file. LEGACY, known not to work since
2026-07 (the Commission discontinued this distribution). Kept only as a
historical reference/starting point for anyone looking for a manual download."""
const AMECO_URLS_TO_TRY = [
    "https://ec.europa.eu/economy_finance/db_indicators/ameco/documents/ameco0.txt",
    "https://economy-finance.ec.europa.eu/system/files/2024-05/ameco0.txt",
    "https://economy-finance.ec.europa.eu/system/files/2023-11/ameco0.txt",
]

"""AMECO's official page (starting point for a manual download)."""
const AMECO_PORTAL_URL =
    "https://economy-finance.ec.europa.eu/economic-research-and-databases/economic-databases/ameco-database_en"

"""
    download_ameco_auto(; force_redownload=false, directory="./ameco_data")

Tries to download AMECO's full TXT file automatically. If every URL fails, it
throws an error with instructions for a manual download.
"""
function download_ameco_auto(; force_redownload = false,
                                      directory = "./ameco_data")
    println("\n" * "="^70)
    println("AUTOMATIC DOWNLOAD — AMECO DATABASE")
    println("="^70)
    mkpath(directory)
    destination = joinpath(directory, "ameco_full.txt")

    if isfile(destination) && !force_redownload
        println("✓ Already present: $destination (force_redownload=true to refresh)")
        return destination
    end

    for (i, url) in enumerate(AMECO_URLS_TO_TRY)
        println("\n  Attempt $i: $url")
        try
            resp = HTTP.get(url, redirect = true, retry = true, readtimeout = 60)
            if resp.status == 200 && length(resp.body) > 1000
                open(destination, "w") do f; write(f, resp.body); end
                mb = round(filesize(destination) / 1024 / 1024, digits = 2)
                println("  ✓ Success! ($mb MB)")
                _log_download(directory, destination)
                return destination
            else
                println("  ✗ Unexpected response (status $(resp.status), $(length(resp.body)) bytes)")
            end
        catch e
            println("  ✗ Failed: $(sprint(showerror, e))")
        end
    end

    println("\n⚠️  AUTOMATIC DOWNLOAD FAILED")
    println("Download it manually from: $AMECO_PORTAL_URL")
    println("Save the TXT in: $directory and use read_ameco_txt_file(...)")
    error("Automatic download failed; see the instructions above.")
end

"""Records the date of the last download in an info file."""
function _log_download(directory, file)
    open(joinpath(directory, "info_download.txt"), "w") do f
        write(f, "Date: $(today())\nFile: $file\n")
    end
end

"""
    read_ameco_txt_file(file, country_code)

Reads AMECO's (fixed-width) TXT file and extracts the series for the given
country.

ASSUMED FORMAT (heuristic; check it against the real file):
- pos 1-2   country code
- pos 4-8   variable code
- pos 10-19 sub-category
- pos 21+   annual values, 15 characters each, starting in 1960
"""
function read_ameco_txt_file(file::String, country_code::String;
                                start_year = 1960, field_width = 15, data_pos = 21)
    println("\n📂 Reading AMECO TXT: $file (country $country_code)")
    isfile(file) || error("File not found: $file")

    data = Dict{String, Dict{Int, Float64}}()
    years_avail = Set{Int}()
    code_to_name = Dict(v => k for (k, v) in AMECO_VARIABLE_CODES)

    records, country_rows = 0, 0
    open(file, "r") do f
        for record in eachline(f)
            records += 1
            length(record) < 20 && continue
            strip(record[1:2]) == country_code || continue
            country_rows += 1
            var_code = strip(record[4:min(8, length(record))])
            haskey(code_to_name, var_code) || continue
            var_name = code_to_name[var_code]
            get!(data, var_name, Dict{Int, Float64}())

            pos = data_pos
            while pos <= length(record)
                pos_end = min(pos + field_width - 1, length(record))
                s = strip(record[pos:pos_end])
                if !isempty(s) && s != ":" && s != "."
                    v = tryparse(Float64, replace(s, "," => "."))
                    if !isnothing(v)
                        year = start_year + (pos - data_pos) ÷ field_width
                        data[var_name][year] = v
                        push!(years_avail, year)
                    end
                end
                pos += field_width
            end
        end
    end

    isempty(years_avail) && error("No data extracted for $country_code (check the format/code).")

    years = sort(collect(years_avail))
    println("  ✓ $records rows | $country_rows for the country | $(length(data)) variables | years $(years[1])-$(years[end])")

    series(name) = [get(get(data, name, Dict{Int,Float64}()), a, NaN) for a in years]

    country_name = something(findfirst(==(country_code), AMECO_COUNTRY_CODES), country_code)
    return AMECOData(country_name, country_code, years,
        series("GDP_current"), series("GDP_constant"), series("private_consumption"),
        series("public_consumption"), series("GFCF"), series("exports"), series("imports"),
        series("employment_total"), series("employees"), series("unemployment_rate"),
        series("labor_force"), series("compensation"), series("labor_productivity"),
        series("unit_labor_costs"), series("GDP_deflator"), series("GFCF_deflator"), series("CPI"),
        series("CFC"),
        series("government_revenue"), series("government_expenditure"), series("budget_balance"),
        series("public_debt"), series("current_account"), series("trade_balance"),
        series("net_capital_stock"),
        "AMECO TXT: $(basename(file))", now(),
        Dict("rows" => string(records), "country_rows" => string(country_rows)))
end

"""
    parse_ameco_csv(file, country_code, years)

Processes an AMECO CSV (columns Code/Country/Y<year>). The format may vary
with the export; adjust the column names if needed.
"""
function parse_ameco_csv(file::String, country_code::String, years)
    println("\n📂 Processing AMECO CSV: $file")
    isfile(file) || error("File not found: $file")
    df = CSV.read(file, DataFrame)

    cols = names(df)
    col_country = "Country" in cols ? "Country" : first(filter(c -> occursin("ountry", c), cols))
    col_code = "Code" in cols ? "Code" : first(filter(c -> occursin("ode", c), cols))

    df_country = filter(row -> string(row[col_country]) == country_code, df)
    nrow(df_country) == 0 && error("No data for $country_code in $file")

    years_vec = collect(years)
    extracted = Dict{String, Vector{Float64}}()
    for (name, code) in AMECO_VARIABLE_CODES
        record = findfirst(r -> string(r[col_code]) == code, eachrow(df_country))
        if !isnothing(record)
            vals = Float64[]
            for a in years_vec
                cn = "Y$a"
                push!(vals, cn in cols && !ismissing(df_country[record, cn]) ?
                            Float64(df_country[record, cn]) : NaN)
            end
            extracted[name] = vals
        end
    end
    return build_ameco_data(country_code, years_vec, extracted, "CSV: $(basename(file))")
end

"""
    fetch_ameco_data(country; years=1995:2023, method=:auto, directory="./ameco_data")

Unified entry point. `method`:
- `:auto`      — tries the official SDMX API; then a recent local file; then synthetic data
- `:sdmx`      — forces fetching through the official SDMX API (see `src/ameco_sdmx.jl`)
- `:download`  — alias of `:sdmx` (the automatic TXT download is discontinued: the
                 Commission withdrew that distribution; see docs/LIMITATIONS.md item 3)
- `:local`     — requires a local TXT file (legacy workflow, for anyone who already has one)
- `:csv`       — processes a CSV (requires `file`; legacy workflow)
- `:synthetic` — generates synthetic data
- `:manual`    — shows instructions and returns synthetic data
"""
function fetch_ameco_data(country::String; years = 1995:2023, method = :auto,
                           directory = "./ameco_data", file = nothing)
    code = _resolve_country_code(country)
    sdmx_code = get(AMECO_SDMX_COUNTRY_CODES, country, code)

    if method == :synthetic
        return generate_synthetic_ameco_data(code, collect(years))
    elseif method == :manual
        println("\n📋 Manual download: $AMECO_PORTAL_URL")
        println("Save the TXT in $directory and use method=:local.")
        return generate_synthetic_ameco_data(code, collect(years))
    elseif method == :csv
        isnothing(file) && error("Method :csv requires the file=... argument")
        return parse_ameco_csv(file, code, years)
    elseif method in (:sdmx, :download)
        return build_ameco_data(code, collect(years),
            download_ameco_sdmx(sdmx_code, years), "AMECO SDMX (official)")
    end

    local_txt = joinpath(directory, "ameco_full.txt")

    if method == :local
        isfile(local_txt) || error("No local file: $local_txt (use method=:sdmx)")
        return read_ameco_txt_file(local_txt, code)
    end

    # :auto: official SDMX API first; then a recent local file; then synthetic data
    try
        return build_ameco_data(code, collect(years),
            download_ameco_sdmx(sdmx_code, years), "AMECO SDMX (official)")
    catch e
        @warn "AMECO SDMX API failed: $(sprint(showerror, e))"
        if isfile(local_txt)
            age = (now() - unix2datetime(mtime(local_txt))) / Day(1)
            println("📂 Using the local file ($(round(age)) days old) as a fallback.")
            return read_ameco_txt_file(local_txt, code)
        end
        @warn "Using SYNTHETIC data as a last resort."
        return generate_synthetic_ameco_data(code, collect(years))
    end
end
