# MarxKapital

*[🇬🇧 Read this in English](README.md)*

Modelação matemática da teoria económica marxista em Julia: acumulação,
exploração, composição orgânica, lei tendencial da queda da taxa de lucro,
problema da transformação valores→preços, fronteira distributiva salário-lucro,
e calibração empírica com dados nacionais (INE) e europeus (**AMECO**, todos os
países da base).

> Estado: **v0.6.1** — funcional para demonstração,
> desenvolvimento metodológico e um artigo académico em `paper/`, com
> testes automáticos em CI
> ([![Testes](https://github.com/randsley/MarxKapital/actions/workflows/test.yml/badge.svg)](https://github.com/randsley/MarxKapital/actions/workflows/test.yml))
> ([![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705369.svg)](https://doi.org/10.5281/zenodo.21705369))
> ([![Artigo DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705608.svg)](https://doi.org/10.5281/zenodo.21705608)).
> Dados setoriais e da AMECO **reais** estão disponíveis como opção (via
> APIs SDMX oficiais), mas os valores por omissão continuam **sintéticos**.
> Antes de qualquer uso empírico sério, leia
> [`docs/LIMITACOES.md`](docs/LIMITACOES.md).

## Instalação

```bash
git clone <este-repositório> marxkapital
cd marxkapital
julia install_deps.jl        # instala DifferentialEquations, Plots, DataFrames, CSV, HTTP, StatsPlots, ForwardDiff, BifurcationKit
```

## Uso rápido

```julia
include("src/MarxKapital.jl")
ajuda_modelo()

# Modelo clássico e generalizado
exemplo_2dept()
exemplo_Ndept(10)

# N departamentos acoplados via A: mobilidade de capital, pressão de realização
# agregada, ou racionamento de quantidades exato por setor (opcionais, independentes)
simular_Ndept(10, acoplado = true, μ = 0.3)
simular_Ndept(10, acoplado = true, realização = true)
simular_Ndept(10, acoplado = true, racionamento = true)

# Valores → preços de produção
exemplo_transformacao()

# Calibração INE (Portugal, sintético por omissão; fonte_dados=:eurostat para dados reais)
params, validação = exemplo_portugal()
params_real = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat)

# AMECO — qualquer país da base (dados_setoriais=:eurostat para dados setoriais reais, países UE/EEE)
listar_países_ameco()
params, dados = calibrar_com_ameco_v2("Alemanha", ano = 2022)   # método = :auto

# Comparação internacional
comparar_países_ameco(["Portugal", "Espanha", "Alemanha", "França"], ano = 2022)

# Série temporal
analisar_série_temporal_ameco("Portugal", anos = 2000:2022)

# Política salarial
depts = criar_departamentos(6)
simular_choque_salarial(depts, 0.10)   # +10% nos salários
```

Ou corra a demonstração completa:

```bash
julia --project=. examples/demo.jl
```

## Dados AMECO

`obter_dados_ameco("Portugal", método = ...)` aceita:

| método       | comportamento                                                        |
|--------------|----------------------------------------------------------------------|
| `:auto`      | API SDMX oficial → ficheiro local recente → sintético (fallback com aviso) |
| `:sdmx`      | força a obtenção via API SDMX oficial da AMECO                       |
| `:download`  | alias de `:sdmx` (o download do antigo TXT foi descontinuado)        |
| `:local`     | exige `dados_ameco/ameco_completo.txt` já descarregado (fluxo legado) |
| `:csv`       | processa um CSV exportado (`ficheiro="..."`, fluxo legado)            |
| `:sintético` | gera séries sintéticas plausíveis                                    |
| `:manual`    | mostra instruções de download e devolve sintético                    |

Desde 2026-07 a AMECO expõe uma [API REST SDMX
oficial](https://webgate.ec.europa.eu/ecfin/redisstat/api/dissemination/sdmx/2.1)
(a mesma plataforma da nova ferramenta de dados do Eurostat) — o ficheiro TXT
estático que os métodos `:local`/`:csv` ainda suportam foi descontinuado pela
Comissão. Corra `verificar_sdmx_ameco()` para confirmar o acesso antes de uma
análise real; ver `docs/LIMITACOES.md` item 3 para o estado exato de cada
variável.

## Diferenciação automática, TSSI e bifurcações

Jacobianas e hessianas exatas por diferenciação automática em modo direto
(ForwardDiff), uma camada de valorização TSSI (interpretação temporal de
sistema único) e continuação numérica de pontos fixos (BifurcationKit):

```julia
Random.seed!(5)
sol, depts, p = simular_Ndept(6, T = 60.0, seed = 5, acoplado = true, realização = true)
X = sol.u[end]

jacobiana_sistema(p, X)          # ∂f/∂X exata do lado direito da EDO (também com racionamento=true)
jacobiana_parametro(p, X, :μ)    # ∂f/∂μ (qualquer campo de p, escalar ou vetorial)
hessiana_sistema(p, X)           # H[k,i,j] = ∂²f_k/∂X_i∂X_j
curvatura_fronteira(p.A, p.l, 0.2)   # w(r), w'(r), w''(r) da fronteira salário-lucro

# Mapa de racionamento: jacobiana exata no ponto fixo, espetro, limite de
# estabilidade α_max e a relaxação α que minimiza o raio espectral
A = criar_matriz_tecnica(12, densidade = 0.5); σ_c = fill(0.5, 12)
S = 5 .+ 10rand(12); O = 0.3 .+ 0.5rand(12)
jacobiana_racionamento(A, σ_c, S, O)

# TSSI: inputs comprados em t−τ custam os preços de t−τ (desfasamento τ fixo),
# comparado com a valorização simultaneísta (preços correntes)
v = valorizar_tssi(sol, p; τ = 1.0, h = 0.5)
estabilidade_tssi(dados_tssi(X, p))   # a TSSI converge para os preços simultaneístas?

# Bifurcações: iteração amortecida do racionamento na escala da procura s, e
# o mapa de preços TSSI na escala da mais-valia (τ fixo)
bifurcacao_racionamento(A, σ_c, S, O; escala = (0.005, 2.0))
bifurcacao_tssi(X, p; τ = 1.0, escala = (0.05, 10.0))
```

O ponto fixo do racionamento é diferenciado pelo teorema da função
implícita (não iteração a iteração), pelo que `jacobiana_sistema` funciona
com `racionamento=true`. Um resultado desta análise: com os setores
ordenados pela severidade do racionamento, a jacobiana do mapa de
racionamento é triangular, com espetro em `[−1, 0]`, e `−1` é valor próprio
assim que algum setor é racionado. A iteração amortecida converge, por
isso, localmente para toda a relaxação `α ∈ (0, 1)`, e a iteração sem
amortecimento (`α = 1`) fica exatamente numa fronteira de flip (ver
`paper/main.tex`, Proposição 1). A relaxação por omissão é `α = 2/3`
(`RELAXAÇÃO_PADRÃO`), que minimiza a taxa de contração local: cerca de
30% menos iterações do que o anterior 0.5, com convergência nas 6870
execuções de teste (`paper/main.tex`, Tabela 2). A camada TSSI é só de valorização: a
dinâmica não muda.

## Crescimento equilibrado e ciclos de acumulação

Com a dinâmica cruzada opcional (`preços_mercado=true`), os preços de
mercado respondem ao excesso de procura setorial e o capital desloca-se
pelas taxas de lucro a esses preços (Flaschel–Semmler). Assim, o modelo
acoplado tem raios interiores de crescimento equilibrado. Sem preços de
mercado não tem: o capital concentra-se num setor. A EDO é homogénea de
grau 1, pelo que o crescimento equilibrado é um ponto fixo do sistema
normalizado no simplex, e pode ser continuado e as suas bifurcações
analisadas:

```julia
Random.seed!(5)
sol, _, p = simular_Ndept(6, T = 1.0, seed = 5, acoplado = true, μ = 0.5,
                          preços_mercado = true)          # β = 0.5 por omissão
X0 = sol.u[1]

eq = crescimento_equilibrado(p, X0)       # g★, r★, k★, quotas, valores próprios, estabilidade
varrimento_salarial(p, X0; variante = :uniforme)          # g★, r★ contra a parcela salarial ω

# Hopf na mobilidade do capital variável μ_v (desligada por omissão), com a
# forma normal e o ramo de ciclos-limite (colocação, Floquet)
pb = merge(p, (β = 0.1,))
res = bifurcacao_acumulação(pb, X0, :μ_v; intervalo = (0.0, 2.5))
res.hopf[1]                               # θ, frequência, período, coeficiente de Lyapunov
ciclo_simulado(pb, :μ_v, 1.1, X0)         # verificar o ciclo por simulação direta
curva_hopf(pb, X0)                        # fronteira de Hopf μ_v,H(ω)
```

Em todas as economias aleatórias testadas, o crescimento equilibrado perde
estabilidade num Hopf supercrítico em `μ_v`. Uma parcela salarial mais
alta sobe a fronteira. Ver `paper/main.tex`, Secções 3.6 e 5.6, e
`docs/LIMITACOES.md`, item 11.

## Dados setoriais reais (Eurostat)

Ambos os caminhos de calibração usam, por omissão, estrutura sintética ou
pesos fixos por setor. Dados setoriais reais do Eurostat estão disponíveis
como opção (`src/eurostat_sdmx.jl`):

```julia
# INE — 19 (:detalhada), 10 (:média) ou 3 (:macro) setores, com matriz A real (IOT do Eurostat)
params_real = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat, agregação = :detalhada)

# AMECO (3 setores macro), com matriz A real (agregada a partir da matriz de 19 setores)
params_real, dados = calibrar_com_ameco_v2("Portugal", ano = 2022, dados_setoriais = :eurostat)

# Stock de capital por inventário perpétuo em vez do valor reportado diretamente (opcional)
params_pim = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat, inventário_perpétuo = true)

# Verificação manual do acesso ao Eurostat (não corre nos testes automáticos)
verificar_eurostat_setorial()
```

Só cobre países da UE/EEE; fora dessa cobertura, ou se o pedido falhar, o
caminho AMECO cai automaticamente para os pesos fixos e matriz `A` aleatória
(com aviso) — o caminho INE (só Portugal) lança erro em vez de degradar
silenciosamente, por ser um pedido explícito de dados reais. A matriz `A`
real usa `NAIO_10_CP1700` (o IOT simétrico verdadeiro — `NAIO_10_CP1620`,
usado antes, era uma tabela satélite de margens de comércio/transporte, não
o IOT em si; ver `docs/LIMITACOES.md` item 4-bis) em fluxos só de uso
doméstico (`stk_flow=DOM`), sem células negativas e reconciliada
diretamente contra o output bruto publicado pela própria tabela (`P1`).
Como esta tabela é de referência (não anual — Portugal: 2010/2013/2015/
2017/2020), um pedido para um ano sem tabela publicada cai para o ano mais
próximo disponível, com aviso. Ver `docs/LIMITACOES.md` itens 4 e 4-bis
para o estado exato.

## Estrutura do repositório

```
marxkapital/
├── src/
│   ├── MarxKapital.jl      # carregador (using + includes)
│   ├── estruturas.jl       # tipos e constantes (AMECO)
│   ├── nucleo.jl           # matrizes, departamentos, EDOs, simulação
│   ├── analise.jl          # taxas de lucro, valores-trabalho, preços, transformação
│   ├── distributiva.jl     # curva w-r e validação de calibração
│   ├── choques.jl          # choques salariais
│   ├── diferenciacao.jl    # diferenciação automática: jacobianas, hessianas, espetro do racionamento
│   ├── tssi.jl             # valorização TSSI (sistema único temporal), desfasamento τ fixo
│   ├── cruzado.jl          # dinâmica cruzada: preços de mercado e mobilidade de capital
│   ├── crescimento.jl      # crescimento equilibrado: sistema normalizado, parcela salarial
│   ├── bifurcacao.jl       # continuação e bifurcações: mapas, Hopf, ciclos-limite (BifurcationKit)
│   ├── calibracao_pt.jl    # calibração INE (Portugal), sintética e real (Eurostat)
│   ├── ameco.jl            # AMECO: sintético, calibração, comparação, séries
│   ├── ameco_sdmx.jl       # API SDMX oficial da AMECO
│   ├── ameco_download.jl   # download automático + parser TXT/CSV (legado)
│   ├── eurostat_sdmx.jl    # API SDMX do Eurostat: dados setoriais reais + IOT
│   ├── visualizacao.jl     # gráficos
│   └── exemplos.jl         # exemplos prontos + ajuda + testar_modelo
├── test/runtests.jl
├── examples/demo.jl
├── docs/LIMITACOES.md      # leitura obrigatória (+ .en.md em inglês)
├── paper/                  # artigo académico (LaTeX), reproduzível a partir de dados reais
│   ├── main.tex            # metodologia + aplicação empírica (Portugal)
│   ├── gerar_resultados.jl # gera todas as figuras/tabelas do artigo
│   ├── matrix_audit.jl     # auditoria da matriz técnica A (verificação manual)
│   ├── monte_carlo.jl      # sweeps sistemáticos (convergência, dispersão)
│   ├── jacobiana_bifurcacao.jl # jacobiana exata, bifurcações, TSSI (offline)
│   ├── acumulacao_bifurcacao.jl # crescimento equilibrado, Hopf, ciclos (offline)
│   └── figures/
├── data/                   # (vazio; dados descarregados ficam aqui, não versionados)
├── install_deps.jl
├── Project.toml
├── CHANGELOG.md
├── LICENSE
├── README.md               # inglês (versão por omissão)
└── README.pt.md            # português
```

## Fundamentos

Categorias: `c` (capital constante), `v` (capital variável), `s = e·v`
(mais-valia), `k = c/v` (composição orgânica), `r = e/(k+1)` (taxa de lucro).
A dinâmica de acumulação é integrada com `DifferentialEquations.jl` (Tsit5).
Valores-trabalho `λ = (I − A)⁻¹ l` e preços de produção de Sraffa
`p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ l`, com a taxa máxima de lucro `R_max` derivada do
raio espectral de `Aᵀ`.

## Testes

```bash
julia --project=. test/runtests.jl
```

168 testes, executados automaticamente em CI (GitHub Actions, Julia 1.10 e 1)
em cada push a `main` — ver `.github/workflows/test.yml`. A suite cobre os
caminhos sintéticos/opt-in por omissão e corre totalmente offline; os
caminhos de dados reais (`método=:sdmx`, `fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`) exigem rede e não estão em CI — verifique-os
manualmente com `verificar_sdmx_ameco()`, `verificar_eurostat_setorial()` e
`paper/matrix_audit.jl`.

## Limitações

Leia [`docs/LIMITACOES.md`](docs/LIMITACOES.md). Em resumo: (1) a matriz A só
realimenta a simulação N-dept opcionalmente (`acoplado=true`), com três
mecanismos disponíveis — mobilidade de capital (conserva capital constante
agregado exatamente, por construção), pressão de realização
agregada (`realização=true`) e racionamento de quantidades exato por setor
(`racionamento=true`, resolvido por ponto fixo, sem precisar de DAE);
ambos os mecanismos com restrição de oferta reconstroem o output bruto
genuíno a partir do próprio estado do modelo (não uma aproximação tipo
valor-acrescentado), e a procura de investimento é convertida para escala
de output antes de A ser aplicada; (2)
`R_max` do choque salarial usa a matriz e os coeficientes reais da
simulação; (3) o download AMECO usa a API SDMX oficial (26 séries obtidas,
24 mapeadas diretamente + 2 calculadas); (4)-(5) calibração setorial real (Eurostat),
incluindo matriz A real em ambos os caminhos (`NAIO_10_CP1700`, fluxos só de
uso doméstico, sem células negativas, reconciliada exatamente contra o
output publicado pela própria tabela — tabela de referência, não anual),
disponível como opção, mas
com pesos fixos/matriz A aleatória por omissão;
(6) dados sintéticos continuam a ser o comportamento por omissão; (7) o
stock de capital pode ser calculado por inventário perpétuo
(`inventário_perpétuo=true`) em vez do valor reportado diretamente, também
opcional.

## Artigo académico

[`paper/main.tex`](paper/main.tex) apresenta uma componente metodológica
(o modelo, os três mecanismos de acoplamento, o mecanismo de racionamento
como ponto fixo) e uma aplicação empírica a Portugal, com todas as
figuras/tabelas geradas de forma reproduzível a partir de dados reais
(`paper/gerar_resultados.jl`, `paper/monte_carlo.jl`, `paper/matrix_audit.jl`
— nenhum número inserido manualmente). Compilar com `latexmk -pdf
paper/main.tex`.

Publicado no Zenodo com DOI próprio, independente do DOI do software:
[10.5281/zenodo.21705608](https://doi.org/10.5281/zenodo.21705608).

## Licença

MIT — ver [`LICENSE`](LICENSE).
