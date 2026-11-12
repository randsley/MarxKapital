# MarxKapital
{: .fs-9 }

<p class="hero">Um modelo em Julia da economia marxista: acumulação,
exploração, composição orgânica, taxa de lucro, transformação de valores
em preços de produção e fronteira salário–lucro. Calibrado com as contas
nacionais portuguesas e dados europeus (AMECO, Eurostat).</p>

[Começar](overview.pt.html#instalação){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Ler o artigo (PDF, EN)](paper/main.pdf){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Notebooks (EN)](notebooks/index.html){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Ver no GitHub](https://github.com/randsley/MarxKapital){: .btn .fs-5 .mb-4 .mb-md-0 }

Versão **@@VERSION@@** · [![DOI](https://zenodo.org/badge/DOI/@@DOI@@.svg)](https://doi.org/@@DOI@@)
· [![Tests](https://github.com/randsley/MarxKapital/actions/workflows/test.yml/badge.svg)](https://github.com/randsley/MarxKapital/actions/workflows/test.yml)

---

## Calibrado com dados reais

Taxa de exploração, composição orgânica e taxa de lucro em Portugal, a
partir das contas nacionais, com o capital variável a preços correntes e
deflacionado. Como as contas nacionais se traduzem em capital constante,
capital variável e mais-valia, e que setores ficam de fora, está em
[Das contas nacionais a C, V e S](national-accounts.pt.html).

<div class="fig-banner"><img src="assets/figures/fig1_time_series.png" alt="Taxa de exploração, composição orgânica e taxa de lucro, Portugal, ao longo do tempo"></div>

## Resultados empíricos: mobilidade do capital e reinvestimento

O coeficiente de mobilidade do capital $$\mu$$ e a função de investimento
do modelo, estimados com as contas do Eurostat para os 15 setores
mercantis de 26 países da UE (notebooks 9–13, em inglês).

<div class="fig-grid">
<figure><img src="assets/figures/nb10_mobility.png" alt="Capital recebido além do excedente próprio contra o diferencial da taxa de lucro, 26 países da UE">
<figcaption><strong>Uma parte reinvestida fixa falha.</strong> Se cada
setor reinveste uma parte fixa do seu excedente, o capital parece fugir
do lucro: \(\hat\mu = -0{,}14\), negativo em 21 de 26 países. A culpa é
da parte fixa (<a href="notebooks/jupyter/10_eu_sectoral_mobility.html">notebook 10</a>).</figcaption></figure>
<figure><img src="assets/figures/nb11_mobility_eta.png" alt="Mu estimado contra a elasticidade de reinvestimento eta">
<figcaption><strong>A mobilidade passa a positiva.</strong> Quando a parte
reinvestida pode cair com a rentabilidade relativa (elasticidade
\(\eta\)), \(\hat\mu\) é positivo para qualquer \(\eta\), de 0,05 a 0,13
(<a href="notebooks/jupyter/11_reinvestment_and_mobility.html">notebook 11</a>).</figcaption></figure>
<figure><img src="assets/figures/nb13_eta_profile.png" alt="Ajustamento da função de investimento contra eta">
<figcaption><strong>Primeiro o excedente próprio.</strong> Em todas as
linhas, incluindo os anos de prejuízo, \(\hat\eta = 0{,}15\) (erro 0,18)
e \(\hat\mu = 0{,}06\). O investimento não para quando o lucro para: tem
um piso de cerca de 0,7 das amortizações
(<a href="notebooks/jupyter/13_investment_floor_and_market_prices.html">notebook 13</a>).</figcaption></figure>
<figure><img src="assets/figures/nb13_balanced_growth.png" alt="Maior parte real dos valores próprios no crescimento equilibrado contra eta">
<figcaption><strong>Uma economia estável nas estimativas.</strong> Com
preços de mercado, os setores mercantis de Portugal têm um crescimento
equilibrado interior estável para todo \(\eta\) até 0,9; só
\(\eta = 1\) não o tem
(<a href="notebooks/jupyter/13_investment_floor_and_market_prices.html">notebook 13</a>).</figcaption></figure>
</div>

O notebook 12 testa a tese de Shaikh de que a concorrência iguala as taxas
de lucro incrementais, e não as médias: os diferenciais da taxa
incremental são sobretudo transitórios mas não se igualam, e o capital
segue o diferencial da taxa média. As
[limitações conhecidas](limitations.pt.html) registam o que estes
resultados resolvem e o que não resolvem.

## O que o modelo faz

<div class="fig-grid">
<figure><img src="assets/figures/fig2_matrix_A.png" alt="Mapa de calor da matriz técnica real A de Portugal">
<figcaption><strong>Estrutura input–output.</strong> A matriz técnica real
\(A\) da economia portuguesa (quadros input–output do Eurostat, 19 setores)
acopla os setores.</figcaption></figure>
<figure><img src="assets/figures/fig3_transformation.png" alt="Desvio dos preços de produção em relação aos valores-trabalho por setor">
<figcaption><strong>Valores e preços.</strong> Valores-trabalho
\(\lambda = (I-A)^{-1} l\) contra preços de produção sraffianos, setor a
setor, a três taxas de lucro.</figcaption></figure>
<figure><img src="assets/figures/fig10b_accumulation_cycles.png" alt="Diagrama de bifurcação dos ciclos de acumulação contra a mobilidade do capital variável">
<figcaption><strong>Ciclos de acumulação.</strong> Com preços de mercado, o
crescimento equilibrado dá lugar a ciclos-limite numa bifurcação de Hopf,
e depois a movimento quase-periódico e caótico.</figcaption></figure>
<figure><img src="assets/figures/fig11b_hopf_boundary.png" alt="Fronteira de Hopf contra a parcela salarial agregada">
<figcaption><strong>Distribuição e estabilidade.</strong> Uma parcela
salarial mais alta torna o crescimento equilibrado mais robusto à
mobilidade do capital.</figcaption></figure>
</div>

- **Esquemas de reprodução:** o modelo clássico de dois departamentos e
  $$N$$ departamentos, opcionalmente acoplados por $$A$$ através da
  mobilidade de capital, da pressão de realização ou do racionamento de
  quantidades por setor.
- **Valores, preços, distribuição:** valores-trabalho, preços de produção,
  o problema da transformação, a fronteira salário–lucro e choques
  salariais.
- **Calibração:** dados INE/Eurostat para Portugal (19, 10 ou 3 setores) e
  qualquer país da AMECO, pelas APIs SDMX oficiais. Os valores por omissão
  são sintéticos; os dados reais são opcionais.
- **Estimação:** mobilidade do capital e função de investimento a partir
  de painéis setoriais, com efeitos fixos e erros agrupados ou de
  Driscoll–Kraay.
- **Dinâmica:** jacobianos exatos por diferenciação automática, valorização
  TSSI, crescimento equilibrado, continuação de bifurcações, expoentes de
  Lyapunov.

## Início rápido

```bash
git clone https://github.com/randsley/MarxKapital.git marxkapital
cd marxkapital
julia install_deps.jl
```

```julia
include("src/MarxKapital.jl")
model_help()                                   # visão geral do modelo
example_Ndept(10)                              # exemplo com N departamentos
simulate_Ndept(10, coupled = true, μ = 0.3)    # setores acoplados por A
example_transformation()                       # valores → preços de produção
params = calibrate_portugal_model(year = 2022, data_source = :eurostat)
```

A [visão geral](overview.pt.html) cobre toda a API; leia as
[limitações conhecidas](limitations.pt.html) antes de qualquer uso empírico.

## Notebooks

Exemplos trabalhados (em inglês), com os resultados. Correm offline: os
notebooks 1–6 com os valores sintéticos por omissão, os 7–13 com extratos
estáticos de dados do AMECO e do Eurostat.

@@GALLERY@@

## Citar

<div class="cite" markdown="1">
@@AUTHORS@@ (@@YEAR@@). *@@TITLE@@* (versão @@VERSION@@).
Zenodo. [https://doi.org/@@DOI@@](https://doi.org/@@DOI@@)

O artigo que acompanha o software tem o seu próprio DOI:
[@@PAPER_DOI@@](https://doi.org/@@PAPER_DOI@@).
[`CITATION.cff`](https://github.com/randsley/MarxKapital/blob/main/CITATION.cff)
</div>
