# MarxKapital — Estado do projeto

*[🇬🇧 Read this in English](PROJECT_STATUS.md)*

Onde o projeto está na versão **1.2.0** (2026-11-13). O que continua em
aberto, item a item, está em [`docs/LIMITATIONS.pt.md`](LIMITATIONS.pt.md);
a história de cada alteração está no [`CHANGELOG.pt.md`](../CHANGELOG.pt.md).

Última atualização: 2026-11-13. Autor do projeto: Nigel Randsley.

## Resumo

O MarxKapital é um modelo em Julia da economia marxista: acumulação de
capital, exploração, composição orgânica do capital, tendência da taxa de
lucro, transformação de valores em preços de produção e dinâmica setorial
da reprodução ampliada. É calibrado com dados do Eurostat e da AMECO
através das suas APIs SDMX oficiais, e os parâmetros de acumulação são
estimados nas contas setoriais da UE.

- **Estado:** funcional e testado (639 testes em CI, mais uma execução de
  verificação de todos os notebooks). Os dados por omissão são sintéticos;
  os dados reais são opcionais.
- **Artigo:** `paper/main.tex`, com todos os números gerados pelos scripts
  `paper/*.jl`. Publicado no Zenodo,
  [10.5281/zenodo.21705608](https://doi.org/10.5281/zenodo.21705608)
  (versão atual de novembro de 2026).
- **DOI do software:**
  [10.5281/zenodo.21705369](https://doi.org/10.5281/zenodo.21705369).
- **Website:** <https://randsley.github.io/MarxKapital/>, em inglês e
  português, com a documentação e os notebooks renderizados.

## O que o modelo faz

| Área | O que existe | Código |
|---|---|---|
| Núcleo do modelo | Departamentos com invariantes validados; 2 e N departamentos; matriz técnica `A` (aleatória, triangular, por blocos), sempre produtiva; integração das EDOs | `types.jl`, `core.jl` |
| Acoplamento setorial (opcional) | Mobilidade de capital, pressão de realização, racionamento de quantidades exato por setor; output bruto reconstruído a partir do estado do modelo; inputs importados, procura final, desconto da reposição intermédia com uma matriz de bens de capital | `core.jl` |
| Valores e preços | Valores-trabalho, taxa de lucro máxima, preços de produção de Sraffa, o problema da transformação, a fronteira salário-lucro, uma pontuação de validação da calibração | `analysis.jl`, `distribution.jl` |
| Choques | Choques salariais, base e choque sobre a mesma matriz | `shocks.jl` |
| Preços de mercado e crescimento (opcional) | Dinâmica cruzada com preços de mercado; raios de crescimento equilibrado, a sua estabilidade, varrimentos de parâmetros | `cross_dual.jl`, `growth.jl` |
| Comportamento do investimento (opcional) | Elasticidade do reinvestimento `η` (forma de potência ou linear), calendário de reinvestimento, piso do investimento, saída do capital não rentável, atrito de saída, mobilidade do capital variável `μ_v` | `core.jl` |
| TSSI | Valorização temporal de sistema único sobre trajetórias; dinâmica conduzida pela TSSI, com valores contabilísticos a custo histórico (opcional) | `tssi.jl` |
| Diferenciação automática e bifurcações | Jacobianas e hessianas exatas, também através do ponto fixo do racionamento; continuação de pontos fixos e do crescimento equilibrado (BifurcationKit); pontos de Hopf, ciclos-limite, expoentes de Lyapunov, histerese | `differentiation.jl`, `bifurcation.jl` |
| Estimação | Mobilidade do capital `μ`, a função de investimento (`η`), o piso do investimento `θ`, a saída, taxas de lucro incrementais, `μ_v` e `σ_v`, em painéis com efeitos fixos e erros de Driscoll–Kraay | `mobility_estimation.jl` |

## Dados

- **Eurostat (opcional):** 19 secções NACE, agregadas a 10 ou 3; a matriz
  `A` real a partir da tabela input-output simétrica (`NAIO_10_CP1700`, uso
  doméstico), com procura final e coeficientes de importação da mesma
  tabela; stock de capital reportado ou por inventário permanente (uma taxa
  por setor, ou ativo a ativo); trabalhadores por conta própria imputados
  por pessoa ou por hora; só setores de mercado; `e` sobre vários anos.
- **AMECO (opcional):** todos os países da base, através da API SDMX
  oficial; três valorizações das séries temporais (mista a preços
  correntes, deflacionada pelo PIB, custo corrente, a de referência);
  trabalhadores por conta própria imputados; os anos de previsão da
  Comissão retirados.
- **Extratos estáticos, offline:** `data/ameco_eu27.csv` (notebooks 7–8,
  Secção 6.1 do artigo) e `data/eurostat_eu_sectors.csv` (notebooks 9–14,
  Secção 5.8 do artigo), cada um reconstruído pelo seu script em `data/`.
- **Por omissão:** dados sintéticos e pesos setoriais fixos, para que os
  testes corram offline.

## Notebooks

Catorze notebooks Jupyter, guardados já executados (`notebooks/jupyter/`):

1–6, o modelo: acumulação, valores e preços, calibração e choques, setores
acoplados e diferenciação automática, valorização TSSI, crescimento, ciclos
e caos. 7–8, a UE a partir da AMECO: taxas de lucro na UE27 e mobilidade
do capital entre países. 9–14, o painel setorial da UE: mobilidade setorial
em Portugal e na UE, reinvestimento, taxas de lucro incrementais, o piso do
investimento com preços de mercado, e a mobilidade do capital variável com
dinâmica conduzida pela TSSI.

Três notebooks Pluto (`notebooks/pluto/`) exploram de forma interativa a
acumulação, os ciclos e a fronteira salário-lucro.

## Testes

`test/runtests.jl` (639 testes) corre offline, localmente e em CI (GitHub
Actions, Julia 1.10 e 1, em cada push e pull request para `main`). A CI
executa também todos os notebooks (`test/notebooks.jl`). Os caminhos com
rede (`data_source = :eurostat`, `sector_data = :eurostat`,
`method = :sdmx`) verificam-se à mão com `check_ameco_sdmx()`,
`check_eurostat_sectoral()` e `paper/matrix_audit.jl`.

## Ainda em aberto

A lista completa, com o estado de cada item, é a tabela no início de
[`docs/LIMITATIONS.pt.md`](LIMITATIONS.pt.md). Os pontos principais:

- O balanço de reprodução com desconto só se aguenta com tabelas reais
  durante alguns anos, porque nada no sistema acoplado mantém as
  proporções setoriais alinhadas com `A`; os preços de mercado, que o
  fariam, não se combinam com o racionamento.
- O racionamento converge localmente (provado), mas a convergência global
  e a unicidade do ponto fixo não estão provadas.
- Os ciclos de acumulação só aparecem muito fora do intervalo estimado de
  `μ_v`; o caos assenta em evidência numérica.
- Alguns setores têm `e ≤ 0` nos dados, o que o modelo não admite, pelo que
  o seu `e` fica no piso.
- As tabelas input-output só existem para anos de referência, e os inputs
  importados não estão disponíveis no modelo cruzado nem na camada TSSI.

## Plano

- Um mecanismo que mantenha as proporções setoriais alinhadas com `A` sob
  racionamento (capital variável conduzido pela procura, ou preços de
  mercado combinados com racionamento).
- Extensões a médio prazo: financeirização (crédito e capital fictício),
  ecologia (fluxos de energia e materiais), troca desigual entre economias,
  e empresas heterogéneas dentro de cada setor.
