# ============================================================================
# MarxKapital demo
# ----------------------------------------------------------------------------
# Run (from the repository root):
#     julia --project=. examples/demo.jl
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

model_help()

println("\n>>> 1. Two-department model")
example_2dept()

println("\n>>> 2. Eight-department model")
example_Ndept(8)

println("\n>>> 3. Transformation problem")
example_transformation()

println("\n>>> 4. INE calibration (Portugal)")
example_portugal()

println("\n>>> 5. Portugal via AMECO (synthetic)")
calibrate_with_ameco_v2("Portugal", year = 2022, method = :synthetic)

println("\n>>> 6. Southern Europe comparison (synthetic AMECO)")
compare_ameco_countries(["Portugal", "Spain", "Italy", "Greece"], year = 2022)

println("\n>>> 7. Portugal time series 2000-2022")
analyze_ameco_time_series("Portugal", years = 2000:2022)

println("\n>>> 8. Wage shock +10%")
depts = create_departments(6)
simulate_wage_shock(depts, 0.10)

println("\n>>> Demo complete.")
