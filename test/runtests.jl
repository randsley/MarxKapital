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

    @testset "Bateria interna" begin
        @test testar_modelo()
    end
end
