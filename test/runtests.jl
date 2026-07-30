# ============================================================================
# Testes do MarxKapital
# ----------------------------------------------------------------------------
# Executar:  julia --project=. test/runtests.jl
# ============================================================================

using Test

include(joinpath(@__DIR__, "..", "src", "MarxKapital.jl"))

@testset "MarxKapital" begin

    @testset "Estruturas" begin
        d = Departamento("Teste", c = 1000.0, v = 500.0, e = 1.5)
        @test d.k == 2.0
        @test abs(d.σ_c + d.σ_v + d.γ - 1.0) < 1e-6
        @test taxa_lucro(d) ≈ 1.5 / 3.0
        @test capital_total(d) == 1500.0
        @test mais_valia(d) == 750.0
    end

    @testset "Matriz técnica" begin
        for est in (:aleatoria, :triangular, :blocos)
            A = criar_matriz_tecnica(6, estrutura = est, seed = 1)
            @test maximum(abs.(eigvals(A))) < 1.0
        end
    end

    @testset "Simulação 2-dept" begin
        sol, depts, p = simular_2dept(T = 30.0)
        @test length(sol.t) > 0
        @test all(isfinite.(sol[end]))
    end

    @testset "Simulação N-dept" begin
        sol, depts, p = simular_Ndept(7, T = 40.0, seed = 3)
        @test all(isfinite.(sol[end]))
        r = calcular_taxas_lucro(sol, p.e)
        @test size(r) == (7, length(sol.t))
    end

    @testset "Simulação N-dept acoplada" begin
        # `seed` em `simular_Ndept` só fixa a matriz técnica A; `criar_departamentos`
        # usa `rand()` sem semente própria para e/σ_c/σ_v/δ. Fixar aqui o RNG global
        # torna os parâmetros dos departamentos reprodutíveis também.
        Random.seed!(5)
        sol, depts, p = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5)
        @test all(isfinite.(sol[end]))
        r = calcular_taxas_lucro_precos(sol, p)
        @test size(r) == (6, length(sol.t))
        @test std(r[:, end]) < std(r[:, 1])
    end

    @testset "Mobilidade de capital — conservação exata" begin
        # Σᵢ μ(rᵢ-r̄)Cᵢ deve ser exatamente 0 (r̄ ponderado por C, não a razão
        # agregada ΣS/Σ(C+V)) — testado diretamente no lado direito da EDO,
        # isolando o termo de mobilidade dos termos de reinvestimento/depreciação.
        Random.seed!(9)
        N = 8
        A = criar_matriz_tecnica(N, seed = 9)
        depts = criar_departamentos(N)
        l = [d.v for d in depts]
        p = (e = [d.e for d in depts], σ_c = [d.σ_c for d in depts],
             σ_v = [d.σ_v for d in depts], δ = [d.δ for d in depts],
             A = A, l = l, R_max = calcular_taxa_lucro_maxima(A, l),
             μ = 0.5, w = 1.0, realização = false, racionamento = false)
        X0 = [[d.c for d in depts]; [d.v for d in depts]]
        dX_sem_mobilidade = similar(X0)
        dX_com_mobilidade = similar(X0)
        sistema_Ndept_io!(dX_com_mobilidade, X0, p, 0.0)
        sistema_Ndept_io!(dX_sem_mobilidade, X0, merge(p, (μ = 0.0,)), 0.0)
        termo_mobilidade = dX_com_mobilidade[1:N] .- dX_sem_mobilidade[1:N]
        @test abs(sum(termo_mobilidade)) < 1e-10
        @test !all(iszero, termo_mobilidade)  # o termo é ativo, não trivialmente nulo
    end

    @testset "Simulação N-dept com pressão de realização" begin
        Random.seed!(5)
        sol_sem, _, p_sem = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5)
        Random.seed!(5)
        sol_com, _, p_com = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5,
                                          realização = true)
        @test all(isfinite.(sol_com[end]))
        eq = verificar_equilibrio_Ndept(sol_com, p_com)
        @test 0.0 <= eq.ρ_real <= 1.0
        # o fator de realização só pode amortecer o reinvestimento (nunca reforçá-lo),
        # logo a acumulação total não pode exceder a do sistema sem esta pressão
        @test sum(sol_com[end]) <= sum(sol_sem[end])
    end

    @testset "Racionamento de mercado (ponto fixo)" begin
        # exemplo com solução fechada verificada à mão: setor 2 depende de um único
        # fornecedor (setor 1), que está fortemente limitado em oferta (O₁=2 vs
        # procura potencial de 5) — a condição de ponto fixo reduz-se a
        # ρ₁ = O₁/(A[1,2]·ρ₁·D₂) ⟹ ρ₁² = O₁/(A[1,2]·D₂) = 2/2.5 = 0.8 ⟹ ρ₁=√0.8
        A = [0.0 0.5; 0.0 0.0]
        σ_c = [0.5, 0.5]
        S = [10.0, 10.0]
        O = [2.0, 100.0]
        κ = _resolver_racionamento(A, σ_c, S, O)
        @test κ[1] ≈ 1.0                    # setor 1 não depende de ninguém
        @test κ[2] ≈ sqrt(0.8) atol = 1e-6   # setor 2 racionado pelo fornecedor escasso
        @test all(0.0 .<= κ .<= 1.0)
    end

    @testset "Racionamento — sensibilidade a ρ inicial, ordem e tolerância" begin
        # Verifica empiricamente unicidade prática do ponto fixo (a antitonicidade
        # do mapa não a garante em teoria — ver paper/main.tex) num regime com
        # racionamento genuíno (não trivial, κ<1 para todos os setores).
        Random.seed!(11)
        N = 12
        A = criar_matriz_tecnica(N, densidade = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        base = _resolver_racionamento(A, σ_c, S, O)
        @test count(base .< 0.999) == N   # racionamento genuíno em todos os setores

        for _ in 1:20
            ρ0 = rand(N) .* 0.9 .+ 0.1
            κ = _resolver_racionamento(A, σ_c, S, O; ρ_inicial = ρ0)
            @test maximum(abs.(κ .- base)) < 1e-6
        end

        for _ in 1:10
            perm = randperm(N)
            κp = _resolver_racionamento(A[perm, perm], σ_c[perm], S[perm], O[perm])
            @test maximum(abs.(κp[invperm(perm)] .- base)) < 1e-6
        end
    end

    @testset "Simulação N-dept com racionamento" begin
        Random.seed!(5)
        sol_sem, _, p_sem = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5)
        Random.seed!(5)
        sol_com, _, p_com = simular_Ndept(6, T = 200.0, seed = 5, acoplado = true, μ = 0.5,
                                          racionamento = true)
        @test all(isfinite.(sol_com[end]))
        # κ ≤ 1 sempre, logo a acumulação total não pode exceder a do sistema sem racionamento
        @test sum(sol_com[end]) <= sum(sol_sem[end])
    end

    @testset "Output bruto reconstruído (x) vs. fluxo tipo valor-acrescentado (W)" begin
        # x = W/(1-colsum(A)) deve exceder W sempre que a coluna correspondente
        # de A for positiva (há consumo intermédio circulante a explicar), e
        # igualar W exatamente quando a coluna é nula (setor sem inputs).
        Random.seed!(5)
        sol_com, _, p_com = simular_Ndept(6, T = 20.0, seed = 5, acoplado = true, μ = 0.5,
                                          racionamento = true)
        eq = verificar_equilibrio_Ndept(sol_com, p_com)
        N = 6
        C = sol_com[end][1:N]; V = sol_com[end][N+1:2N]
        S = p_com.e .* V
        W = p_com.δ .* C .+ V .+ S
        x = eq.output
        @test all(x .>= W .- 1e-9)
        colsum = vec(sum(p_com.A, dims = 1))
        for j in 1:N
            if colsum[j] ≈ 0.0
                @test x[j] ≈ W[j] atol = 1e-6
            else
                @test x[j] > W[j]
            end
        end
    end

    @testset "Admissibilidade da reconstrução de output bruto" begin
        # Já admissível (todas as somas de coluna < 0.95): devolvida inalterada.
        A_ok = [0.0 0.3; 0.2 0.0]
        A_devolvida, reescalada = _garantir_admissibilidade_output(A_ok)
        @test A_devolvida == A_ok
        @test !reescalada

        # Inadmissível (soma de coluna 2 = 1.3 > 0.95): reescalada até
        # a maior soma de coluna ficar exatamente em 0.95.
        A_má = [0.6 0.9; 0.3 0.4]  # colsums = [0.9, 1.3]
        A_corrigida, reescalada2 = _garantir_admissibilidade_output(A_má)
        @test reescalada2
        @test maximum(vec(sum(A_corrigida, dims = 1))) ≈ 0.95 atol = 1e-9
        # a reescala é uniforme (mesmo fator em toda a matriz)
        fator = A_corrigida[1, 1] / A_má[1, 1]
        @test A_corrigida ≈ A_má .* fator

        # Verificação de ponta a ponta: qualquer simulação acoplada com
        # racionamento/realização montada por simular_Ndept_customizado deve
        # ter, na prática, a condição de admissibilidade já garantida —
        # não só a função auxiliar isolada, mas o pipeline real.
        for seed in 1:10
            Random.seed!(seed)
            _, _, p = simular_Ndept(8, T = 1.0, seed = seed, acoplado = true,
                                    racionamento = true)
            @test maximum(vec(sum(p.A, dims = 1))) < 1.0
        end
    end

    @testset "Agregação de matriz técnica (Leontief)" begin
        A = [0.1 0.2 0.3 0.4; 0.5 0.6 0.7 0.8; 0.1 0.1 0.1 0.1; 0.2 0.2 0.2 0.2]
        secções = ["a", "b", "c", "d"]
        grupos = [["a", "b"], ["c", "d"]]
        pesos = Dict("a" => 1.0, "b" => 1.0, "c" => 1.0, "d" => 1.0)
        A_grossa = agregar_matriz_io(A, secções, grupos, pesos)
        @test size(A_grossa) == (2, 2)
        @test A_grossa ≈ [0.7 1.1; 0.3 0.3]
        @test all(A_grossa .>= 0)
    end

    @testset "Stock de capital por inventário perpétuo" begin
        # FBCF constante=10, δ=0.2, K₀=100 ⟹ K₁=0.8·100+10=90, K₂=0.8·90+10=82
        fbcf = Dict(2000 => 10.0, 2001 => 10.0, 2002 => 10.0)
        K = calcular_stock_capital_pim(fbcf, 0.2, 2000, 100.0, [2000, 2001, 2002])
        @test K[2000] ≈ 100.0
        @test K[2001] ≈ 90.0
        @test K[2002] ≈ 82.0
        # ano sem FBCF disponível trunca a série em vez de extrapolar
        K2 = calcular_stock_capital_pim(Dict(2000 => 10.0), 0.2, 2000, 100.0, [2000, 2001])
        @test !haskey(K2, 2001)
    end

    @testset "Valores e preços" begin
        A = criar_matriz_tecnica(4, seed = 2)
        l = [0.6, 0.5, 0.4, 0.3]
        λ = calcular_valores_trabalho(A, l)
        @test all(λ .> 0)
        @test all(λ .>= l .- 1e-9)          # incluem trabalho indireto
        R_max = calcular_taxa_lucro_maxima(A, l)
        @test R_max > 0
        p = calcular_precos_producao(A, l, 1.0, min(0.2, R_max * 0.5))
        @test all(p .> 0)
        @test_throws ErrorException calcular_precos_producao(A, l, 1.0, R_max * 1.2)
    end

    @testset "Transformação" begin
        res = problema_transformacao(4)
        @test haskey(res, :R_max)
        @test -1 <= res.correlação <= 1
    end

    @testset "Calibração INE" begin
        params = calibrar_modelo_portugal(ano = 2022)
        @test params.N == 19
        @test size(params.A) == (19, 19)
        @test all(params.e .> 0)
    end

    @testset "Fronteira distributiva" begin
        A = criar_matriz_tecnica(6, seed = 5)
        l = fill(0.4, 6) .+ 0.1 .* (1:6) ./ 6
        curva = curva_salario_lucro(A, l, n_pontos = 60, plotar = false)
        @test curva.R_max > 0
        @test all(curva.w .> 0)
        @test curva.w[1] >= curva.w[end]    # salário máximo em r=0 (fronteira descendente)
    end

    @testset "Choque salarial" begin
        depts = criar_departamentos(6)
        res = simular_choque_salarial(depts, 0.15, T = 30.0, plotar = false, seed = 7)
        @test res.impacto_r_inicial < 0     # aumento salarial reduz lucro imediato
    end

    @testset "AMECO sintético" begin
        dados = gerar_dados_sintéticos_ameco("PT", collect(1995:2022))
        @test length(dados.anos) == 28
        @test all(dados.PIB .> 0)
        params, _ = calibrar_com_ameco_v2("Portugal", ano = 2022, método = :sintético)
        @test params.N == 3
    end

    @testset "Série temporal AMECO — valorização consistente vs. corrente" begin
        # Caso de mão: PIB_corrente=200, PIB_real=100 (deflator_PIB=200);
        # remunerações=80, CCF=20 (ambos a preços correntes); C=400 (stock,
        # já a preços constantes). deflator_FBCF=400 (índice distinto, para
        # testar sensibilidade ao deflator escolhido).
        z = fill(0.0, 1)
        dados = DadosAMECO(
            "Teste", "TST", [2020],
            fill(200.0, 1), fill(100.0, 1), z, z, z, z, z,       # PIB, PIB_real, ...
            z, z, z, z,                                          # mercado de trabalho
            fill(80.0, 1), z, z,                                 # remunerações, produtividade, custos
            fill(200.0, 1), fill(400.0, 1), z, fill(20.0, 1),    # deflator_PIB, deflator_FBCF, IPC, CCF
            z, z, z, z,                                          # finanças públicas
            z, z,                                                # setor externo
            fill(400.0, 1),                                      # stock_capital_total
            "teste", now(), Dict{String, String}())

        st_corrente = analisar_série_temporal_com_dados(dados; valorização = :corrente)
        st_consistente = analisar_série_temporal_com_dados(dados; valorização = :consistente)
        st_fbcf = analisar_série_temporal_com_dados(dados; valorização = :consistente_fbcf)

        @test st_corrente.k[1] ≈ 400.0 / 80.0
        @test st_consistente.k[1] ≈ 400.0 / 40.0  # 80 deflacionado por 200/100
        @test st_consistente.k[1] ≈ 2 * st_corrente.k[1]
        @test st_fbcf.k[1] ≈ 400.0 / 20.0          # 80 deflacionado por 400/100
        @test st_fbcf.k[1] ≈ 4 * st_corrente.k[1]

        # A parte (VAB-V)/V de e é algebricamente invariante sob um deflator
        # comum aplicado a V e VAB (CCF é deflacionado pelo mesmo índice que
        # V, preservando essa invariância) — confirma a álgebra: dividir
        # ambos por um fator comum não muda a razão (Y-V)/V.
        @test st_corrente.e[1] ≈ (200.0 - 80.0 - 20.0) / 80.0  # = 1.25
        @test st_consistente.e[1] ≈ st_corrente.e[1]
        # :consistente_fbcf usa um índice diferente (deflator_FBCF) para V e
        # CCF mas mantém PIB_real (deflacionado por deflator_PIB) para VAB —
        # não estão na mesma base, pelo que a invariância NÃO se aplica aqui,
        # de propósito (é precisamente o teste de sensibilidade ao deflator).
        @test !(st_fbcf.e[1] ≈ st_corrente.e[1])
    end

    @testset "Bateria interna" begin
        @test testar_modelo()
    end
end
