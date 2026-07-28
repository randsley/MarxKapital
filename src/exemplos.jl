# ============================================================================
# EXEMPLOS PRONTOS E AJUDA
# ============================================================================

"""Exemplo: modelo de 2 departamentos."""
function exemplo_2dept()
    println("\n" * "="^70)
    println("MODELO DE DOIS DEPARTAMENTOS")
    println("="^70)
    sol, depts, p = simular_2dept(T = 50.0)
    for (i, d) in enumerate(depts)
        println("  Dept $i — $(d.nome): C=$(d.c) V=$(d.v) k=$(round(d.k, digits=2)) e=$(d.e)")
    end
    plotar_2dept(sol, depts, p)
    return sol, depts, p
end

"""Exemplo: modelo de N departamentos."""
function exemplo_Ndept(N = 5; seed = 42)
    println("\n" * "="^70)
    println("MODELO DE $N DEPARTAMENTOS")
    println("="^70)
    nomes = ["Energia", "Indústria", "Manufatura", "Serviços", "Consumo"]
    N > 5 && append!(nomes, ["Dept_$i" for i in 6:N])
    sol, depts, p = simular_Ndept(N, T = 100.0, nomes = nomes[1:N], seed = seed)
    for (i, d) in enumerate(depts)
        println("  $i. $(d.nome): k=$(round(d.k, digits=2)) e=$(round(d.e, digits=2)) r=$(round(taxa_lucro(d), digits=3))")
    end
    println("\nρ(A) = $(round(maximum(abs.(eigvals(p.A))), digits=4))")
    plotar_Ndept(sol, depts, p)
    return sol, depts, p
end

"""Exemplo: problema da transformação."""
exemplo_transformacao() = problema_transformacao(5)

"""Exemplo: calibração INE (Portugal) + validação."""
function exemplo_portugal()
    params = calibrar_modelo_portugal(ano = 2022)
    validação = validar_taxas_lucro_calibradas(params)
    return params, validação
end

# --- Exemplos AMECO ---

"""Exemplo: Portugal via AMECO (sintético) + validação + série temporal."""
function exemplo_ameco_portugal()
    listar_países_ameco()
    params, dados = calibrar_com_ameco_v2("Portugal", ano = 2022, método = :sintético)
    validação = validar_taxas_lucro_calibradas(params)
    temporal = analisar_série_temporal_ameco("Portugal", anos = 2000:2022)
    return (params = params, dados = dados, validação = validação, temporal = temporal)
end

"""Exemplo: comparação do Sul da Europa."""
exemplo_comparação_sul_europa() =
    comparar_países_ameco(["Portugal", "Espanha", "Itália", "Grécia"], ano = 2022)

"""Exemplo: comparação de grandes economias europeias."""
exemplo_comparação_grandes_economias() =
    comparar_países_ameco(["Alemanha", "França", "Itália", "Espanha", "Países Baixos"], ano = 2022)

"""Exemplo: workflow AMECO completo (auto → calibração → validação → choque)."""
function exemplo_workflow_completo_ameco(país = "Portugal"; método = :auto)
    println("\n" * "="^80)
    println("WORKFLOW COMPLETO AMECO — $país")
    println("="^80)
    dados = obter_dados_ameco(país, método = método)
    params, _ = calibrar_com_dados_ameco(dados, 2022, :macro)
    validação = validar_taxas_lucro_calibradas(params)
    depts = criar_departamentos_de_params(params)
    choque = simular_choque_salarial(depts, 0.10, plotar = false)
    println("\n✅ Concluído — qualidade $(round(validação.pontuação, digits=1))% | " *
            "impacto choque $(round(choque.impacto_r_final, digits=2))pp")
    return (dados = dados, params = params, validação = validação, choque = choque)
end

# --- Ajuda ---

"""Guia de uso resumido."""
function ajuda_modelo()
    println("""
    ╔═══════════════════════════════════════════════════════════════════════╗
    ║  MarxKapital — MODELO MARXIANO DE N DEPARTAMENTOS                      ║
    ╚═══════════════════════════════════════════════════════════════════════╝

    BÁSICO
      exemplo_2dept()                       Modelo clássico de 2 departamentos
      exemplo_Ndept(10)                     Modelo de N departamentos
      exemplo_transformacao()               Valores → preços de produção
      exemplo_portugal()                    Calibração INE (sintético)

    AMECO (todos os países da UE + comparação)
      listar_países_ameco()                 Países disponíveis
      calibrar_com_ameco_v2("Portugal")     Calibrar via AMECO (:auto)
      obter_dados_ameco("Alemanha")         Obter séries (auto/download/local/csv/sintético)
      comparar_países_ameco([...])          Comparação internacional
      analisar_série_temporal_ameco("PT")   Evolução histórica
      descarregar_ameco_automatico()        Descarregar base TXT completa

    ANÁLISE
      curva_salario_lucro(A, l)             Fronteira distributiva w-r
      simular_choque_salarial(depts, 0.10)  Choque de +10% nos salários

    TESTES / AJUDA
      testar_modelo()                       Bateria de validação
      ajuda_modelo()                        Este guia

    Detalhe de qualquer função: ?nome_da_função
    """)
end

"""Bateria mínima de testes de sanidade."""
function testar_modelo()
    println("\n" * "="^70)
    println("TESTES DE VALIDAÇÃO")
    println("="^70)
    passados = 0; total = 0

    total += 1
    try
        d = Departamento("Teste", c = 100, v = 50, e = 1.5)
        @assert abs(d.σ_c + d.σ_v + d.γ - 1.0) < 1e-6
        println("✓ Teste 1: Departamento válido"); passados += 1
    catch e; println("✗ Teste 1: $e"); end

    total += 1
    try
        A = criar_matriz_tecnica(5, seed = 1)
        ρ = maximum(abs.(eigvals(A)))
        @assert ρ < 1.0
        println("✓ Teste 2: Matriz produtiva (ρ=$(round(ρ, digits=3)))"); passados += 1
    catch e; println("✗ Teste 2: $e"); end

    total += 1
    try
        sol, _, _ = simular_Ndept(3, T = 10.0, seed = 1)
        @assert all(isfinite.(sol[end]))
        println("✓ Teste 3: Simulação converge"); passados += 1
    catch e; println("✗ Teste 3: $e"); end

    total += 1
    try
        A = criar_matriz_tecnica(3, seed = 1)
        λ = calcular_valores_trabalho(A, [0.5, 0.4, 0.3])
        @assert all(λ .> 0)
        println("✓ Teste 4: Valores-trabalho positivos"); passados += 1
    catch e; println("✗ Teste 4: $e"); end

    total += 1
    try
        params = calibrar_modelo_portugal(ano = 2022)
        @assert params.N == 19
        println("✓ Teste 5: Calibração INE (19 setores)"); passados += 1
    catch e; println("✗ Teste 5: $e"); end

    total += 1
    try
        params, _ = calibrar_com_ameco_v2("Portugal", ano = 2022, método = :sintético)
        @assert params.N == 3
        println("✓ Teste 6: Calibração AMECO (sintético)"); passados += 1
    catch e; println("✗ Teste 6: $e"); end

    println("\n" * "="^70)
    println("RESULTADO: $passados/$total testes passaram")
    println("="^70 * "\n")
    return passados == total
end
