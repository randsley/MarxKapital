# MarxKapital

Modelação matemática da teoria económica marxista em Julia: acumulação,
exploração, composição orgânica, lei tendencial da queda da taxa de lucro,
problema da transformação valores→preços, fronteira distributiva salário-lucro,
e calibração empírica com dados nacionais (INE) e europeus (**AMECO**, todos os
países da base).

> Estado: **v0.3.0** — funcional para demonstração e desenvolvimento
> metodológico. Antes de qualquer uso empírico sério, leia
> [`docs/LIMITACOES.md`](docs/LIMITACOES.md). Os dados por omissão são
> **sintéticos**.

## Instalação

```bash
git clone <este-repositório> marxkapital
cd marxkapital
julia install_deps.jl        # instala DifferentialEquations, Plots, DataFrames, CSV, HTTP, StatsPlots
```

## Uso rápido

```julia
include("src/MarxKapital.jl")
ajuda_modelo()

# Modelo clássico e generalizado
exemplo_2dept()
exemplo_Ndept(10)

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

## Dados setoriais reais (Eurostat)

Ambos os caminhos de calibração usam, por omissão, estrutura sintética ou
pesos fixos por setor. Dados setoriais reais do Eurostat estão disponíveis
como opção (`src/eurostat_sdmx.jl`):

```julia
# INE (19 setores CAE), incluindo matriz técnica A real (IOT do Eurostat)
params_real = calibrar_modelo_portugal(ano = 2022, fonte_dados = :eurostat)

# AMECO (3 setores macro), matriz A mantém-se aleatória — ver LIMITACOES item 4
params_real, dados = calibrar_com_ameco_v2("Portugal", ano = 2022, dados_setoriais = :eurostat)

# Verificação manual do acesso ao Eurostat (não corre nos testes automáticos)
verificar_eurostat_setorial()
```

Só cobre países da UE/EEE; fora dessa cobertura, ou se o pedido falhar, o
caminho AMECO cai automaticamente para os pesos fixos (com aviso) — o
caminho INE (só Portugal) lança erro em vez de degradar silenciosamente, por
ser um pedido explícito de dados reais. Ver `docs/LIMITACOES.md` itens 4 e
4-bis para o estado exato, incluindo a razão por que a matriz `A` real não
se estende ao caminho AMECO de 3 setores.

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
│   ├── calibracao_pt.jl    # calibração INE (Portugal), sintética e real (Eurostat)
│   ├── ameco.jl            # AMECO: sintético, calibração, comparação, séries
│   ├── ameco_sdmx.jl       # API SDMX oficial da AMECO
│   ├── ameco_download.jl   # download automático + parser TXT/CSV (legado)
│   ├── eurostat_sdmx.jl    # API SDMX do Eurostat: dados setoriais reais + IOT
│   ├── visualizacao.jl     # gráficos
│   └── exemplos.jl         # exemplos prontos + ajuda + testar_modelo
├── test/runtests.jl
├── examples/demo.jl
├── docs/LIMITACOES.md      # leitura obrigatória
├── data/                   # (vazio; dados descarregados ficam aqui, não versionados)
├── install_deps.jl
├── Project.toml
├── CHANGELOG.md
├── LICENSE
└── README.md
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

O ambiente onde este pacote foi montado não tinha Julia instalado, pelo que
**os testes não foram executados aqui** — corra-os localmente antes do
primeiro uso.

## Limitações

Leia [`docs/LIMITACOES.md`](docs/LIMITACOES.md). Em resumo: (1) a matriz A não
realimenta a simulação N-dept; (2) o `R_max` do choque é ilustrativo; (3) o
download/parser AMECO é heurístico; (4)-(7) calibração macro com pesos fixos e
dados sintéticos por omissão.

## Licença

MIT — ver [`LICENSE`](LICENSE).
