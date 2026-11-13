# ============================================================================
# Section 6.1: profit rates across the EU27, from the static AMECO extract.
#
# Run with:  julia --project=. paper/eu_profit_rates.jl
#
# Offline: reads data/ameco_eu27.csv (built by data/build_ameco_eu.jl). The
# computations are those of notebooks/jupyter/07_eu_profit_rates.ipynb, on the
# reference valuation of the paper (:current_cost) as well as notebook 7's
# (:consistent). Writes figures/eu_stats.tex.
# ============================================================================

ENV["GKSwstype"] = "100"

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))
using Printf

const FIG_DIR = joinpath(@__DIR__, "figures")
mkpath(FIG_DIR)

const EU = "European Union (27)"

raw = CSV.read(joinpath(@__DIR__, "..", "data", "ameco_eu27.csv"), DataFrame)
areas = String.(unique(raw.country))
countries = filter(!=(EU), areas)

function load_area(area)
    d = sort(raw[raw.country .== area, :], :year)
    s = Dict(String(n) => [ismissing(x) ? NaN : Float64(x) for x in d[!, n]] for n in names(raw)[4:end])
    return build_ameco_data(_resolve_country_code(area), collect(Int, d.year), s,
                            "AMECO extract (data/ameco_eu27.csv)")
end
data = Dict(a => load_area(a) for a in areas)

series(valuation; self_employed = :imputed) =
    Dict(a => analyze_time_series_with_data(data[a]; valuation, self_employed) for a in areas)

at(ts, a, f, y) = getfield(ts[a], f)[findfirst(==(y), ts[a].years)]

function trend(ts, a, f, lo, hi)
    ys = ts[a].years
    m = (ys .>= lo) .& (ys .<= hi) .& isfinite.(getfield(ts[a], f))
    t, v = ys[m], getfield(ts[a], f)[m]
    return sum((t .- mean(t)) .* (v .- mean(v))) / sum(abs2, t .- mean(t))
end

# r = e/(1+k): Δ ln r = Δ ln e − Δ ln(1+k), exactly.
function decompose(ts, a, lo, hi)
    e0, e1 = at(ts, a, :e, lo), at(ts, a, :e, hi)
    k0, k1 = at(ts, a, :k, lo), at(ts, a, :k, hi)
    return (dln_r = log(e1 / e0) - log((1 + k1) / (1 + k0)),
            from_e = log(e1 / e0), from_k = -log((1 + k1) / (1 + k0)))
end

macros = Pair{String, String}[]
put!(name, x::AbstractString) = push!(macros, name => x)
put!(name, x::Integer) = put!(name, string(x))
put!(name, x::Real, d) = put!(name, @sprintf("%.*f", d, x))

ref = series(:current_cost)
lo = maximum(minimum(ref[a].years[isfinite.(ref[a].r)]) for a in areas)
hi = minimum(maximum(ref[a].years[isfinite.(ref[a].r)]) for a in areas)
put!("EuFirstYear", lo); put!("EuLastYear", hi)
put!("EuCountries", length(countries))

for (tag, v) in (("Cc", :current_cost), ("Gdp", :consistent))
    ts = v == :current_cost ? ref : series(v)
    eu = ts[EU]
    w = (eu.years .>= lo) .& (eu.years .<= hi)
    imin = findall(w)[argmin(eu.r[w])]
    put!("Eu$(tag)RFirst", 100at(ts, EU, :r, lo), 2)
    put!("Eu$(tag)RLast", 100at(ts, EU, :r, hi), 2)
    put!("Eu$(tag)RLow", 100eu.r[imin], 2); put!("Eu$(tag)RLowYear", eu.years[imin])
    put!("Eu$(tag)KFirst", at(ts, EU, :k, lo), 2); put!("Eu$(tag)KLast", at(ts, EU, :k, hi), 2)
    put!("Eu$(tag)EFirst", at(ts, EU, :e, lo), 2); put!("Eu$(tag)ELast", at(ts, EU, :e, hi), 2)
    put!("Eu$(tag)Trend", 1000trend(ts, EU, :r, lo, hi), 2)          # pp per decade
    slopes = [1000trend(ts, a, :r, lo, hi) for a in countries]
    put!("Eu$(tag)Falling", count(<(0), slopes))
    dec = Dict(a => decompose(ts, a, lo, hi) for a in areas)
    put!("Eu$(tag)RFell", count(a -> dec[a].dln_r < 0, countries))
    put!("Eu$(tag)KRose", count(a -> dec[a].from_k < 0, countries))
    put!("Eu$(tag)EDominates", count(a -> abs(dec[a].from_e) > abs(dec[a].from_k), countries))
    put!("Eu$(tag)DlnR", dec[EU].dln_r, 3); put!("Eu$(tag)FromE", dec[EU].from_e, 3)
    put!("Eu$(tag)FromK", -dec[EU].from_k, 3)                         # reported as a drag
    es = [at(ts, a, :e, hi) for a in countries]; ks = [at(ts, a, :k, hi) for a in countries]
    rs = [at(ts, a, :r, hi) for a in countries]
    put!("Eu$(tag)CorrRE", cor(es, rs), 2); put!("Eu$(tag)CorrRK", cor(ks, rs), 2)
    put!("Eu$(tag)RIreland", 100at(ts, "Ireland", :r, hi), 1)
    put!("Eu$(tag)RPortugal", 100at(ts, "Portugal", :r, hi), 1)
    others = filter(!=("Ireland"), countries)
    rs_o = [100at(ts, a, :r, hi) for a in others]
    put!("Eu$(tag)RTop", others[argmax(rs_o)]); put!("Eu$(tag)RTopValue", maximum(rs_o), 1)
    put!("Eu$(tag)RBottom", others[argmin(rs_o)]); put!("Eu$(tag)RBottomValue", minimum(rs_o), 1)
    @printf("  %-3s EU27 r %.2f%% -> %.2f%% (low %.2f%% in %d), trend %+.2f pp/decade; falling in %d of %d; e dominates in %d; corr(r,e) %.2f corr(r,k) %.2f\n",
            tag, 100at(ts, EU, :r, lo), 100at(ts, EU, :r, hi), 100eu.r[imin], eu.years[imin],
            1000trend(ts, EU, :r, lo, hi), count(<(0), slopes), length(countries),
            count(a -> abs(dec[a].from_e) > abs(dec[a].from_k), countries),
            cor(es, rs), cor(ks, rs))
end

# The valuation decides the trend in k: the mixed :current series against both
# consistent ones, EU27 aggregate.
for (tag, v) in (("Cur", :current), ("Gdp", :consistent), ("Cc", :current_cost))
    k = analyze_time_series_with_data(data[EU]; valuation = v, self_employed = :imputed)
    put!("EuK$(tag)First", at(Dict(EU => k), EU, :k, lo), 2)
    put!("EuK$(tag)Last", at(Dict(EU => k), EU, :k, hi), 2)
end

# The self-employed adjustment, member states, last common year.
raw_e = series(:current_cost; self_employed = :excluded)
gr = "Greece"
put!("EuSelfEmpGreece", 100 * (1 - (i = findfirst(==(hi), data[gr].years);
                                    data[gr].employees[i] / data[gr].employment[i])), 1)
put!("EuEPubGreece", at(raw_e, gr, :e, hi), 2); put!("EuEAdjGreece", at(ref, gr, :e, hi), 2)
put!("EuEPubEU", at(raw_e, EU, :e, hi), 2); put!("EuEAdjEU", at(ref, EU, :e, hi), 2)

open(joinpath(FIG_DIR, "eu_stats.tex"), "w") do io
    println(io, "% Generated by paper/eu_profit_rates.jl from data/ameco_eu27.csv. Do not edit by hand.")
    for (k, v) in macros
        println(io, "\\newcommand{\\$k}{$v}")
    end
end
println("  ✓ figures/eu_stats.tex ($(length(macros)) macros)")
