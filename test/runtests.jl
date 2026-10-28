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
        @test all(isfinite.(sol_com.u[end]))
        eq = verificar_equilibrio_Ndept(sol_com, p_com)
        N = 6
        estado_final = sol_com.u[end]
        C = estado_final[1:N]; V = estado_final[N+1:2N]
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

    # Diferenças finitas centrais, referência independente para a diferenciação automática.
    function jacobiana_df(f, x; h = 1e-6)
        f0 = f(x)
        J = zeros(length(f0), length(x))
        for j in eachindex(x)
            δx = zeros(length(x)); δx[j] = h
            J[:, j] = (f(x .+ δx) .- f(x .- δx)) ./ (2h)
        end
        return J
    end

    @testset "Jacobiana exata da EDO (AD vs. diferenças finitas)" begin
        for (realização, racionamento) in ((false, false), (true, false), (false, true))
            Random.seed!(5)
            sol, _, p = simular_Ndept(6, T = 50.0, seed = 5, acoplado = true, μ = 0.5,
                                      realização = realização, racionamento = racionamento)
            X = sol.u[end]
            J = jacobiana_sistema(p, X)
            J_df = jacobiana_df(_rhs(p), X; h = 1e-4 * maximum(X))
            @test size(J) == (12, 12)
            @test maximum(abs.(J .- J_df)) / maximum(abs.(J)) < 1e-2
        end
        Random.seed!(3)
        sol, _, p = simular_Ndept(5, T = 20.0, seed = 3)
        X = sol.u[end]   # sistema linear: diferenças finitas exatas a menos de arredondamento
        @test jacobiana_sistema(p, X) ≈ jacobiana_df(_rhs(p), X; h = 1e-3 * maximum(X)) rtol = 1e-8
        @test size(jacobiana_parametro(p, X, :e)) == (10, 5)
    end

    @testset "Hessiana da EDO" begin
        Random.seed!(5)
        sol, _, p = simular_Ndept(4, T = 20.0, seed = 5, acoplado = true, μ = 0.5)
        X = sol.u[end]
        H = hessiana_sistema(p, X)
        @test size(H) == (8, 8, 8)
        @test maximum(abs.(H .- permutedims(H, (1, 3, 2)))) < 1e-8 * max(1, maximum(abs.(H)))
        # linha k da hessiana = jacobiana de ∂f_k/∂X
        H_df = jacobiana_df(x -> jacobiana_sistema(p, x)[1, :], X; h = 1e-4 * maximum(X))
        @test maximum(abs.(H[1, :, :] .- H_df)) <= 1e-3 * max(1e-12, maximum(abs.(H[1, :, :])))
    end

    @testset "Jacobiana do racionamento — exemplo de 2 setores" begin
        # Secção 3.3 do artigo: um único valor próprio ativo λ = −1. O setor 2 não é
        # racionado (λ = 0), donde α_max = 1 (flip na iteração sem amortecimento) e o
        # α minimax é 2/3 = RELAXAÇÃO_PADRÃO (não 1/2: o modo λ = 0 decai a |1−α|).
        jr = jacobiana_racionamento([0.0 0.5; 0.0 0.0], [0.5, 0.5], [10.0, 10.0], [2.0, 100.0])
        @test jr.ρ[1] ≈ sqrt(0.8) atol = 1e-9
        @test sort(real.(jr.valores_próprios)) ≈ [-1.0, 0.0] atol = 1e-9
        @test jr.antítona
        @test jr.α_max ≈ 1.0 atol = 1e-9
        @test jr.α_ótimo ≈ 2 / 3 atol = 1e-6
        @test jr.α_ótimo ≈ RELAXAÇÃO_PADRÃO atol = 1e-6
        @test jr.raio_espectral ≈ 1 / 3 atol = 1e-9    # max(|1−α|, |1−2α|) com α = 2/3
        # α = 0.5 anula o modo λ = −1, mas o modo λ = 0 fica a 0.5
        @test raio_espectral_amortecido(jr.valores_próprios, 0.5) ≈ 0.5 atol = 1e-9
        @test jr.convergência_local
    end

    @testset "Racionamento — λ = −1 estrutural e forma fechada" begin
        Random.seed!(11)
        N = 12
        A = criar_matriz_tecnica(N, densidade = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        jr = jacobiana_racionamento(A, σ_c, S, O)
        @test jr.antítona
        @test minimum(abs.(jr.valores_próprios .+ 1)) < 1e-9
        k = argmin(jr.ρ)
        @test jr.J[k, :] ≈ -[i == k ? 1.0 : 0.0 for i in 1:N] atol = 1e-9
        L_k = sum(A[k, :] .* σ_c .* S)
        @test jr.ρ[k] ≈ sqrt(O[k] / L_k) atol = 1e-9
        @test jr.α_max <= 1 + 1e-9
        # J é triangular com os setores ordenados por ρ* (J_ik ≠ 0 só se ρ_k ≤ ρ_i):
        # valores próprios = diagonal, reais e em [−1, 0].
        ordem = sortperm(jr.ρ)
        Jo = jr.J[ordem, ordem]
        @test all(abs(Jo[i, j]) < 1e-10 for i in 1:N, j in 1:N if j > i)
        @test sort(real.(jr.valores_próprios)) ≈ sort(diag(jr.J)) atol = 1e-10
        @test all(-1 - 1e-10 .<= real.(jr.valores_próprios) .<= 1e-10)
        @test jr.raio_espectral ≈ 1 / 3 atol = 1e-9
    end

    @testset "Derivada do ponto fixo de racionamento (função implícita)" begin
        Random.seed!(11)
        N = 12
        A = criar_matriz_tecnica(N, densidade = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        f(o) = _resolver_racionamento(A, σ_c, S, o; tol = 1e-13, max_iter = 10_000)
        J = ForwardDiff.jacobian(f, O)
        @test J ≈ jacobiana_df(f, O) rtol = 1e-6
    end

    @testset "Curvatura da fronteira salário-lucro (forma fechada)" begin
        # Se l é vetor próprio de Aᵀ com valor próprio λ, w(r) = (1/(1+r) − λ)/l₁,
        # donde w''(r) = 2/((1+r)³·l₁).
        A = [0.20 0.10 0.05; 0.10 0.30 0.10; 0.05 0.10 0.20]   # irredutível: vetor de PF > 0
        vals, vecs = eigen(Matrix(A'))
        k = argmax(real.(vals))
        l = abs.(real.(vecs[:, k]))
        λ = real(vals[k])
        c = curvatura_fronteira(A, l, 0.2)
        @test c.w ≈ (1 / 1.2 - λ) / l[1]
        @test c.dw ≈ -1 / (1.2^2 * l[1])
        @test c.d2w ≈ 2 / (1.2^3 * l[1])
        @test c.forma == :convexa
    end

    @testset "TSSI — invariantes e convergência" begin
        Random.seed!(5)
        sol, _, p = simular_Ndept(6, T = 60.0, seed = 5, acoplado = true, μ = 0.5,
                                  realização = true)
        v = valorizar_tssi(sol, p; τ = 1.0, h = 0.5)
        @test v.erro_invariantes < 1e-12
        @test length(v.r_tssi) == length(v.t)
        @test all(v.r_tssi .> 0)
        # τ tem de ser múltiplo de h
        @test_throws ErrorException valorizar_tssi(sol, p; τ = 0.7, h = 0.5)

        # Com dados congelados, os preços TSSI convergem para os simultaneístas,
        # à taxa dada pelo raio espectral da jacobiana exata.
        d = dados_tssi(sol.u[end], p)
        est = estabilidade_tssi(d; τ = 2.0)
        @test est.estável
        @test est.taxa_convergência ≈ log(est.raio_espectral) / 2.0
        q = ones(6)
        for _ in 1:300
            q = mapa_tssi(q, d).p
        end
        @test q ≈ est.p★ rtol = 1e-10
        # J em forma fechada: [(1+r)I − r·c·xᵀ/(xᵀc)]·Aᵀ
        c = d.A' * est.p★ .+ d.d .+ d.v
        J_fechada = ((1 + est.r★) .* matriz_identidade(6) .- est.r★ .* (c * d.x') ./ sum(d.x .* c)) * d.A'
        @test est.J ≈ J_fechada rtol = 1e-10
        # Ponto fixo ⇒ TSSI e simultaneísmo coincidem.
        passo = mapa_tssi(est.p★, d)
        @test passo.r ≈ est.r★
    end

    @testset "Bifurcações — racionamento" begin
        Random.seed!(11)
        N = 12
        A = criar_matriz_tecnica(N, densidade = 0.5)
        σ_c = fill(0.5, N)
        S = 5.0 .+ 10 * rand(N)
        O = 0.3 .+ rand(N) * 0.5
        br = bifurcacao_racionamento(A, σ_c, S, O; escala = (0.005, 2.0))
        @test isempty(br.pontos)                        # α = 2/3 estável em todo o ramo
        @test all(br.raio .< 1)
        @test br.α_max[1] ≈ 2.0                          # sem racionamento: F constante
        @test all(br.α_max[br.fração_racionada .> 0] .<= 1 + 1e-9)
        @test br.fração_racionada[end] == 1.0
        k = length(br.θ)
        diag = _resolver_racionamento(A, ones(N), br.θ[k] .* σ_c .* S, O; tol = 1e-12,
                                      max_iter = 10_000, devolver_diagnóstico = true)
        @test diag.ρ ≈ br.z[:, k] atol = 1e-8

        # α > 1: flip (duplicação de período) no início do racionamento, em
        # s_c = minᵢ Oᵢ/Lᵢ (Lᵢ = procura sem racionamento) — colisão de fronteira,
        # localizada à resolução do passo de continuação (dsmax = 0.05).
        s_c = minimum(O ./ (A * (σ_c .* S)))
        @test br.θ[findfirst(br.fração_racionada .> 0)] >= s_c - 1e-9
        br_flip = bifurcacao_racionamento(A, σ_c, S, O; escala = (0.005, 2.0), relaxação = 1.1)
        @test !isempty(br_flip.pontos)
        @test br_flip.pontos[1].tipo == :flip
        @test br_flip.pontos[1].θ ≈ s_c atol = 0.05
    end

    @testset "Bifurcações — preços TSSI (τ fixo)" begin
        Random.seed!(5)
        sol, _, p = simular_Ndept(6, T = 60.0, seed = 5, acoplado = true, μ = 0.5,
                                  realização = true)
        bt = bifurcacao_tssi(sol.u[end], p; τ = 1.0, escala = (0.05, 10.0))
        @test bt.θ[end] ≈ 10.0
        @test all(bt.raio .< 1)
        @test isempty(bt.pontos)
        @test issorted(bt.r★)                            # r★ cresce com a mais-valia
        @test all(bt.r★ .< p.R_max)
    end

    @testset "Mobilidade do capital variável (μ_v)" begin
        Random.seed!(3)
        sol0, _, p0 = simular_Ndept(4, T = 5.0, seed = 3, acoplado = true, μ = 0.5)
        Random.seed!(3)
        sol1, _, _ = simular_Ndept(4, T = 5.0, seed = 3, acoplado = true, μ = 0.5, μ_v = 0.0)
        @test sol0.u[end] == sol1.u[end]                 # μ_v = 0: sem alteração
        X = sol0.u[end]
        N = 4
        f0 = similar(X); sistema_Ndept_io!(f0, X, p0, 0.0)
        f1 = similar(X); sistema_Ndept_io!(f1, X, merge(p0, (μ_v = 0.7,)), 0.0)
        @test sum(f1[N+1:2N]) ≈ sum(f0[N+1:2N]) rtol = 1e-12   # o termo soma 0
        @test f1[1:N] == f0[1:N]
        # homogeneidade de grau 1 (Euler): J·X = f(X)
        pv = merge(p0, (μ_v = 0.7,))
        @test jacobiana_sistema(pv, X) * X ≈ f1 rtol = 1e-9
    end

    @testset "Sistema cruzado — identidades" begin
        Random.seed!(2)
        sol, _, p = simular_Ndept(3, T = 1.0, seed = 2, acoplado = true, μ = 0.5,
                                  preços_mercado = true)
        X = sol.u[end] .+ [zeros(6); [0.1, -0.2, 0.05]]
        C, V, q = X[1:3], X[4:6], X[7:9]
        ec = estado_cruzado(C, V, q, p)
        @test sum(ec.P .* ec.procura) ≈ sum(ec.P .* ec.x) rtol = 1e-12   # lei de Walras
        @test sum(ec.Π) ≈ sum(p.e .* V) rtol = 1e-12                      # ΣΠ = ΣS
        ec2 = estado_cruzado(C, V, q .+ 0.3, p)
        @test ec2.P ≈ ec.P rtol = 1e-12                                     # só preços relativos
        f = similar(X); sistema_cruzado!(f, X, p, 0.0)
        f2 = similar(X); sistema_cruzado!(f2, [2 .* X[1:6]; q], p, 0.0)
        @test f2 ≈ [2 .* f[1:6]; f[7:9]] rtol = 1e-12                      # homogeneidade
        @test_throws ErrorException simular_Ndept(3, T = 1.0, seed = 2, acoplado = true,
                                                  preços_mercado = true, realização = true)
    end

    @testset "Crescimento equilibrado" begin
        Random.seed!(2)
        sol, _, p = simular_Ndept(3, T = 1.0, seed = 2, acoplado = true, μ = 0.5,
                                  preços_mercado = true)
        eq = crescimento_equilibrado(p, sol.u[1])
        @test eq.convergiu && eq.estável
        @test minimum(eq.X[1:6]) > 0
        # o raio cresce exatamente a g★ na EDO em níveis
        s = solve(ODEProblem(sistema_cruzado!, eq.X, (0.0, 20.0), p), Tsit5(),
                  abstol = 1e-11, reltol = 1e-11)
        @test log(sum(s.u[end][1:6]) / sum(s.u[1][1:6])) / 20 ≈ eq.g rtol = 1e-7
        @test s.u[end][1:6] ./ sum(s.u[end][1:6]) ≈ eq.X[1:6] rtol = 1e-7
        # e é o limite de uma simulação longa
        ys = simular_normalizado(p, sol.u[1]; T = 1500.0, saveat = 1500.0)
        @test ys.u[end][1:6] ≈ eq.X[1:6] rtol = 1e-5
        # TSSI = simultaneísmo no raio de crescimento equilibrado
        v = valorizar_tssi(s, p; τ = 1.0, h = 0.5)
        @test v.r_tssi[end] ≈ v.r_simultâneo[end] rtol = 1e-10
        # parcela salarial: g e r caem com ω
        vs = varrimento_salarial(p, sol.u[1]; valores = 0.3:0.1:0.6)
        @test all(vs.convergiu) && all(vs.estável)
        @test vs.ω ≈ collect(0.3:0.1:0.6)
        @test issorted(vs.g; rev = true) && issorted(vs.r; rev = true)
    end

    @testset "Bifurcação de Hopf e ciclos-limite da acumulação" begin
        Random.seed!(2)
        sol, _, p0 = simular_Ndept(3, T = 1.0, seed = 2, acoplado = true, μ = 0.5,
                                   preços_mercado = true)
        p = merge(p0, (β = 0.1,))
        r = bifurcacao_acumulação(p, sol.u[1], :μ_v; intervalo = (0.0, 2.0),
                                  intervalo_órbitas = (0.0, 1.3), Ntst = 20)
        @test r.parte_real_máx[1] < 0
        H = r.hopf[1]
        @test H.supercrítico && H.transversalidade > 0
        # dois Hopf próximos (≈ 1.220 e 1.232): ambos detetados com dsmax = 0.01
        @test count(pt -> pt.tipo == :hopf && pt.θ < 1.24, r.pontos) == 2
        k = findfirst(>(H.θ), r.θ)
        @test r.parte_real_máx[k-2] < 0 < r.parte_real_máx[k+1]
        o = r.órbitas
        @test o.θ[1] ≈ H.θ atol = 1e-6
        @test o.amplitude[1] < 1e-2                          # nasce com amplitude 0
        @test o.período[1] ≈ H.período rtol = 1e-3
        @test o.estável[2]                                   # supercrítico: ciclo estável
        # ciclo confirmado por simulação direta
        θ = 1.225
        k = argmin(abs.(o.θ .- θ))
        cs = ciclo_simulado(p, :μ_v, o.θ[k], sol.u[1]; T = 6000.0)
        @test cs.dispersão_secção < 1e-2
        @test cs.T_min ≈ o.período[k] rtol = 1e-2
        @test cs.amplitude ≈ o.amplitude[k] rtol = 0.1    # colocação grosseira (Ntst = 20)
        # e convergência para o equilíbrio antes do Hopf
        @test ciclo_simulado(p, :μ_v, H.θ - 0.1, sol.u[1]; T = 3000.0).amplitude < 1e-4
    end

    @testset "Expoentes de Lyapunov e histerese" begin
        Random.seed!(5)
        sol, _, p0 = simular_Ndept(6, T = 1.0, seed = 5, acoplado = true, μ = 0.5,
                                   preços_mercado = true)
        p = merge(p0, (β = 0.1,))
        # ciclo-limite: (0, −, −)
        ciclo = expoentes_lyapunov(p, :μ_v, 1.1, sol.u[1]; T_transiente = 2000.0, T = 4000.0)
        @test abs(ciclo.λ[1]) < 1e-3
        @test ciclo.λ[2] < -3e-3
        # regime irregular: um expoente positivo e o do fluxo ≈ 0 (caos)
        caos = expoentes_lyapunov(p, :μ_v, 1.9, sol.u[1]; T_transiente = 2000.0, T = 6000.0)
        @test caos.λ[1] > 0.015
        @test abs(caos.λ[2]) < 6e-3                 # estimativa finita, sensível ao CPU
        # coexistência: a subir chega-se ao toro, a descer fica o ciclo
        hs = histerese_simulada(p, :μ_v, [1.40, 1.46], sol.u[1]; T_transiente = 2000.0,
                                T = 1500.0)
        @test hs.subir.classe == [:irregular, :ciclo]
        @test hs.descer.classe == [:ciclo, :ciclo]
        @test hs.coexistência == [1.40]
    end

    @testset "Bateria interna" begin
        @test testar_modelo()
    end
end
