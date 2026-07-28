# ============================================================================
# Demonstração do MarxKapital
# ----------------------------------------------------------------------------
# Executar (a partir da raiz do repositório):
#     julia --project=. examples/demo.jl
# ============================================================================

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

ajuda_modelo()

println("\n>>> 1. Modelo de 2 departamentos")
exemplo_2dept()

println("\n>>> 2. Modelo de 8 departamentos")
exemplo_Ndept(8)

println("\n>>> 3. Problema da transformação")
exemplo_transformacao()

println("\n>>> 4. Calibração INE (Portugal)")
exemplo_portugal()

println("\n>>> 5. Portugal via AMECO (sintético)")
calibrar_com_ameco_v2("Portugal", ano = 2022, método = :sintético)

println("\n>>> 6. Comparação Sul da Europa (AMECO sintético)")
comparar_países_ameco(["Portugal", "Espanha", "Itália", "Grécia"], ano = 2022)

println("\n>>> 7. Série temporal Portugal 2000-2022")
analisar_série_temporal_ameco("Portugal", anos = 2000:2022)

println("\n>>> 8. Choque salarial +10%")
depts = criar_departamentos(6)
simular_choque_salarial(depts, 0.10)

println("\n>>> Demo concluída.")
