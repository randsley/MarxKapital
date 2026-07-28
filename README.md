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

# Calibração INE (Portugal, sintético)
params, validação = exemplo_portugal()

# AMECO — qualquer país da base
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
| `:auto`      | ficheiro local recente → download → sintético (fallback com aviso)   |
| `:download`  | força o download da base TXT completa                                |
| `:local`     | exige `dados_ameco/ameco_completo.txt` já descarregado               |
| `:csv`       | processa um CSV exportado (`ficheiro="..."`)                          |
| `:sintético` | gera séries sintéticas plausíveis                                    |
| `:manual`    | mostra instruções de download e devolve sintético                    |

O download automático tenta URLs conhecidas da Comissão Europeia; se falharem,
descarregue manualmente a partir do
[portal AMECO](https://economy-finance.ec.europa.eu/economic-research-and-databases/economic-databases/ameco-database_en)
para `dados_ameco/` e use `método = :local`. **As URLs e o formato do parser
são heurísticos — ver limitação 3.**

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
│   ├── calibracao_pt.jl    # calibração INE (Portugal)
│   ├── ameco.jl            # AMECO: sintético, calibração, comparação, séries
│   ├── ameco_download.jl   # download automático + parser TXT/CSV
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
