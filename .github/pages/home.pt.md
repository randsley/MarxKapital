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
deflacionado.

<div class="fig-banner"><img src="assets/figures/fig1_time_series.png" alt="Taxa de exploração, composição orgânica e taxa de lucro, Portugal, ao longo do tempo"></div>

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

Exemplos trabalhados (em inglês), com os resultados. Correm offline com os
valores sintéticos por omissão.

@@GALLERY@@

## Citar

<div class="cite" markdown="1">
@@AUTHORS@@ (@@YEAR@@). *@@TITLE@@* (versão @@VERSION@@).
Zenodo. [https://doi.org/@@DOI@@](https://doi.org/@@DOI@@)

O artigo que acompanha o software tem o seu próprio DOI:
[@@PAPER_DOI@@](https://doi.org/@@PAPER_DOI@@).
[`CITATION.cff`](https://github.com/randsley/MarxKapital/blob/main/CITATION.cff)
</div>
