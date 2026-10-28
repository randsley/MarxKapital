# MarxKapital — Estado do Projeto

*[🇬🇧 Read this in English](PROJECT_STATUS.md)*

Documento de acompanhamento, iniciado na versão 0.3.0 e atualizado desde
então; o trabalho descrito nas secções seguintes corresponde à versão
**0.6.0**, incluindo a correção do dataflow real do Eurostat para a
matriz técnica, a reconstrução de output bruto genuíno no modelo dinâmico,
a conservação exata do termo de mobilidade, e o artigo académico em
`paper/`. Descreve o que está feito, o que falta resolver e recomendações
concretas de implementação. Destina-se a ficar em
`docs/PROJECT_STATUS.pt.md`, ao lado de `docs/LIMITATIONS.pt.md`.

Data: última atualização, 2026-07-30. Autor do projeto: Nigel Randsley.

---

## 1. Sumário

O MarxKapital é um sistema em Julia para modelação matemática da teoria
económica marxista: acumulação de capital, exploração, composição orgânica,
tendência da taxa de lucro, transformação de valores em preços de produção,
fronteira distributiva salário-lucro, e calibração empírica com dados
nacionais (INE) e europeus (AMECO). Funcional para demonstração e
desenvolvimento metodológico, com testes automáticos em CI. Os dados por
omissão continuam sintéticos/pesos fixos e não servem para análise empírica
publicável nesse modo — dados setoriais e da AMECO **reais** estão
disponíveis como opção, via APIs SDMX oficiais (ver `docs/LIMITATIONS.pt.md`).

O código foi reorganizado de um ficheiro monolítico para um repositório
modular, com testes, exemplos e documentação. A integração AMECO abrange todos
os países da base, com calibração, comparação internacional e séries
temporais.

---

## 2. O que foi feito

### 2.1 Núcleo do modelo (`src/core.jl`, `src/types.jl`)

- Tipo `Department` com invariantes validadas no construtor: `c`, `v`,
  `e`, `k = c/v`, quotas de reinvestimento (`σ_c`, `σ_v`, `γ`) que somam 1, e
  depreciação `δ`. Métodos auxiliares: `profit_rate`, `surplus_value`,
  `total_capital`, `product_value`.
- Modelo clássico de 2 departamentos (meios de produção e bens de consumo) e
  modelo generalizado de N departamentos.
- Construção de matriz técnica `A` com três estruturas (`:random`,
  `:triangular`, `:blocks`), sempre normalizada para raio espectral inferior a
  1 (economia produtiva). Argumento `seed` para reprodutibilidade.
- Integração da dinâmica de acumulação com `DifferentialEquations.jl` (Tsit5),
  para 2 e N departamentos.

### 2.2 Análise de valor e preço (`src/analysis.jl`)

- Taxas de lucro, composições orgânicas e taxa média ao longo do tempo.
- Valores-trabalho `λ = (I − A)⁻¹ l`.
- Taxa máxima de lucro `R_max = 1/λ_max(Aᵀ) − 1`.
- Preços de produção de Sraffa `p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ l`, com rejeição de
  taxas que tornem o sistema singular.
- Problema da transformação com visualização comparativa (valores contra
  preços, desvios percentuais, divergência em função da taxa de lucro,
  correlação).

### 2.3 Análise distributiva e validação (`src/distribution.jl`)

- Fronteira de possibilidades distributivas (curva w-r), com elasticidade e
  evolução de preços relativos.
- Validação de taxas de lucro calibradas: viabilidade face a `R_max`,
  dispersão, consistência com a exploração implícita, posição na fronteira, e
  pontuação de qualidade em [0, 100]. Usa histogramas robustos, sem dependência
  dura de boxplot.

### 2.4 Política e choques (`src/shocks.jl`)

- Simulação de choque salarial: aumento de `Δw` sobe `V`, reduz `e`
  proporcionalmente, e ajusta `r`. Compara cenário base contra choque, com a
  mesma `seed` nos dois, garantindo comparabilidade.
- Comparação de múltiplos cenários de choque.

### 2.5 Calibração nacional (`src/calibration_pt.jl`)

- Geração de dados sintéticos com a estrutura setorial portuguesa (19 setores
  CAE Rev.3): VAB, remunerações, EBE, CCF, emprego, FBCF e stock de capital.
- Processamento dos Quadros de Recursos e Empregos, com indicadores marxianos
  por setor.
- Estimação de parâmetros setoriais e pipeline `calibrate_portugal_model`.

### 2.6 Integração AMECO (`src/ameco.jl`, `src/ameco_download.jl`)

- Estruturas de dados (`AMECOData`, 29 campos) e dicionários de países e de
  mnemónicos de variáveis.
- Geração de séries sintéticas plausíveis (tendência mais ciclo) calibradas por
  perfis de país.
- Download automático da base TXT completa (`download_ameco_auto`),
  com tentativa de várias URLs e registo da data.
- Parser de largura fixa (`read_ameco_txt_file`), com offsets
  parametrizáveis.
- Processador de CSV exportado (`parse_ameco_csv`).
- Ponto de entrada unificado `fetch_ameco_data` com métodos `:auto`,
  `:download`, `:local`, `:csv`, `:synthetic` e `:manual`.
- Calibração a partir de dados AMECO, comparação internacional entre países, e
  análise de séries temporais dos indicadores marxianos.

### 2.7 Empacotamento e documentação

- Estrutura de repositório: `src/`, `test/`, `examples/`, `data/`, `docs/`.
- Carregador `src/MarxKapital.jl` (estilo script, carregado por `include`,
  evitando UUIDs fixos).
- `install_deps.jl`, `Project.toml`, `.gitignore`, `LICENSE` (MIT),
  `README.md`, `CHANGELOG.pt.md`.
- Suite de testes (`test/runtests.jl`) e demonstração (`examples/demo.jl`).
- `docs/LIMITATIONS.pt.md` com as limitações conhecidas.

### 2.8 Correções aplicadas nesta fase

- Importação explícita de `Statistics` (`mean`, `std`, `median`, `var`, `cor`,
  `quantile`).
- Parâmetros da EDO passados como `NamedTuple` (type-stable) em vez de `Dict`,
  eliminando o aviso de performance do SciMLBase.
- Substituição dos usos incorretos da constante `I` do LinearAlgebra por
  `identity_matrix(N)`.
- Validação de calibração com histogramas robustos, sem boxplot obrigatório.
- Eliminação do bug do `match_obj` não definido no antigo fluxo de atualização
  AMECO.
- `seed` opcional e partilhada entre base e choque.

### 2.9 Verificação por execução (histórico: só estática até aqui)

Nas fases iniciais deste documento, sem Julia disponível no ambiente de
empacotamento, a verificação era só estática (delimitadores equilibrados,
nenhuma função chamada sem definição, contagem de argumentos nos
construtores posicionais). Desde então, a suite de testes corre por
compilação real — localmente e em CI (GitHub Actions, Julia 1.10 e 1, em
cada push a `main`, ver `.github/workflows/test.yml`) — 111 testes, todos a
passar. Os caminhos de dados reais (rede) são verificados manualmente com
`check_ameco_sdmx()`/`check_eurostat_sectoral()`, fora da suite
automática por design (ver `docs/LIMITATIONS.pt.md`).

---

## 3. O que falta resolver

Ordenado por prioridade. O detalhe completo está em `docs/LIMITATIONS.pt.md`.

### 3.1 Resolvido: a matriz A não realimenta a dinâmica de N departamentos

Em `system_Ndept!`, a acumulação de cada setor depende apenas da sua própria
mais-valia; a matriz `A` é transportada nos parâmetros mas não entra nas
equações. Os setores comportam-se como independentes, o que contradiz a lógica
da reprodução ampliada (o output de um setor é o capital constante de outro).

**Corrigido, com três mecanismos opcionais em `system_Ndept_io!`
(`coupled=true`), independentes entre si:**
1. Mobilidade de capital: `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ` valorizado a preços de
   produção de Sraffa e `r̄` a média de `r` ponderada por `C` — a única
   escolha para a qual o termo conserva capital constante agregado
   exatamente (`Σμ(rᵢ-r̄)Cᵢ=0` por construção, verificado por teste).
2. Pressão de realização agregada (`realization=true`):
   `ρ_real = Σmin(xᵢ,(A·x)ᵢ)/Σ(A·x)ᵢ` trava o reinvestimento quando a
   estrutura técnica não sustenta os outputs correntes.
3. Racionamento de quantidades exato por setor (`rationing=true`, tem
   precedência sobre `realization`): resolve o racionamento à
   Bénassy/Barro-Grossman por iteração de ponto fixo — cada setor limitado
   pelo input mais escasso (tecnologia Leontief), sem precisar de expor o
   sistema como DAE nem de uma nova dependência de solver. Verificado com um
   exemplo de solução fechada e por robustez num sweep sistemático de 270
   combinações (N∈{6,12,19}, densidade∈{0.2,0.4,0.6}), 270/270 convergências.

Em ambos os mecanismos com restrição de oferta, `xᵢ` é o output bruto
**genuíno**, reconstruído a partir do próprio estado do modelo
(`xⱼ=Wⱼ/(1-Σᵢ A[i,j])`, `Wⱼ=δⱼCⱼ+Vⱼ+Sⱼ`) — não o fluxo tipo
valor-acrescentado `W` usado numa correção anterior, que omitia consumo
intermédio circulante. A procura de investimento no racionamento usa
`Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` (expansão de output desejada, via o rácio
capital-output corrente), não a despesa `σ_c,ⱼSⱼ` diretamente.

`system_Ndept!` mantém-se como omissão (setores independentes).
`check_equilibrium_Ndept` generaliza a verificação a posteriori do
modelo de 2 departamentos — ver `docs/LIMITATIONS.pt.md` item 1 para os
detalhes de cada mecanismo e das correções mais recentes.

### 3.2 Resolvido: `R_max` no choque salarial era ilustrativo

Em `simulate_wage_shock`, o `R_max` reportado usava uma matriz auxiliar
`A_ref` e `l = ones(N)`, não a matriz nem os coeficientes de trabalho da
simulação. **Corrigido:** passou a usar `p_base.A` (devolvida por
`simulate_Ndept_custom`) e `l = [d.v for d in depts]`, refletindo o
cenário simulado.

### 3.3 Resolvido: download AMECO passou a usar a API SDMX oficial

O antigo ficheiro TXT estático foi descontinuado pela Comissão (URLs
confirmadas mortas em 2026-07). **Corrigido:** `src/ameco_sdmx.jl` usa a API
REST SDMX oficial da AMECO (`webgate.ec.europa.eu/ecfin/redisstat`), agora o
caminho automático por omissão (`fetch_ameco_data`, métodos `:auto`/`:sdmx`).
Verificado com dados reais de Portugal (PIB, emprego, remunerações, FBCF,
stock de capital). **Quase totalmente resolvido:** `AMECO_SDMX_MAP` mapeia
agora 24 variáveis mais 2 calculadas (deflator do PIB, balança comercial) —
26 séries no total, incluindo `GFCF_deflator` e `CFC` (consumo de capital
fixo), acrescentadas para corrigir um problema de valorização na série
temporal de exploração (ver `docs/LIMITATIONS.pt.md` item 9); só o stock de
capital bruto ficou confirmado indisponível nesta API (não "pendente") —
ver `docs/LIMITATIONS.pt.md` item 3 para a lista exata.

### 3.4 Resolvido: calibração AMECO só macro, com pesos fixos por omissão

`calibrate_with_ameco_data` só implementa a agregação `:macro` (Primário,
Secundário, Terciário). Por omissão, repartição do VAB, emprego e stock de
capital por pesos fixos por país; países sem perfil específico caem num
perfil médio da UE. **Corrigido (opcional):** `sector_data=:eurostat`
usa dados setoriais reais do Eurostat em vez dos pesos fixos, com fallback
automático para países fora da cobertura UE/EEE, **incluindo agora a matriz
`A`**: construída aos 19 setores finos (real, não-negativa, dataflow
`NAIO_10_CP1700` — ver `docs/LIMITATIONS.pt.md` item 4-bis para o bug do
dataflow anterior, encontrado e corrigido) e agregada aos
3 setores macro pela fórmula de Leontief (`aggregate_io_matrix`), em vez de
agregar os fluxos brutos do IOT diretamente.

### 3.5 Resolvido: agregação INE incompleta

`calibrate_portugal_model` aceitava o argumento `aggregation`, mas só
`:detailed` (19 setores) estava ligada. **Corrigido:** `:macro` (3 setores,
mesma agregação do caminho AMECO) e `:medium` (10 setores, nível NACE Rev.2
"A10") implementados via `aggregate_sectors`, funcionando tanto com dados
sintéticos como reais.

### 3.6 Resolvido (opcional): stock de capital por inventário perpétuo; depreciação AMECO corrigida

O capital constante é aproximado pelo stock de capital reportado por
omissão; `perpetual_inventory=true` substitui isso por uma série própria
(PIM, `Kₜ=(1-δ)Kₜ₋₁+FBCFₜ`, δ estimado por setor a partir de CCF/stock,
não fixo) — ver `docs/LIMITATIONS.pt.md` item 7. Separadamente, a série
temporal AMECO (`analyze_time_series_with_data`) usava uma dedução
fixa de 10% do stock como "depreciação"; corrigida para usar CCF real da
AMECO, deflacionada de forma consistente com os restantes termos — ver
`docs/LIMITATIONS.pt.md` item 9. Ainda por diferenciar: taxas de depreciação
por tipo de ativo (estruturas, máquinas, TIC), que o Eurostat não publica
diretamente.

### 3.7 Transversal: dados sintéticos por omissão

Tanto o caminho INE como o AMECO usam, por omissão, dados gerados. Servem para
demonstração e testes, não para análise empírica.

### 3.8 Resolvido: testes agora executados em CI

A suite `test/runtests.jl` (111 testes) corre localmente e em CI (GitHub
Actions, Julia 1.10 e 1, `.github/workflows/test.yml`) em cada push a
`main`. Cobre os caminhos sintéticos/opt-in por omissão; os caminhos de
dados reais (rede) ficam de fora por design — ver §3.3/§4.3.

### 3.9 Resolvido: matriz técnica A usava o dataflow errado do Eurostat

Encontrado durante uma auditoria pedida em revisão externa do artigo em
`paper/`: `NAIO_10_CP1620` não é a tabela IOT simétrica (é uma tabela
satélite de margens de comércio/transporte), o que subavaliava fluxos
intersetoriais por mais de uma ordem de grandeza e explicava um raio
espectral e `R_max` implausíveis reportados até esta correção. Corrigido
com `NAIO_10_CP1700` (a tabela real), `stk_flow=DOM` (só uso doméstico) —
ver `docs/LIMITATIONS.pt.md` item 4-bis para o histórico completo.

### 3.10 Resolvido: output bruto do modelo dinâmico e procura de investimento

O output usado pelos mecanismos de acoplamento (`realization`,
`rationing`) era um fluxo tipo valor-acrescentado (`W=δC+V+S`), que
omite consumo intermédio circulante — não gross output no sentido usado
para construir `A`. Corrigido reconstruindo o output bruto genuíno a
partir da própria identidade custo-output do modelo, sem novo estado; a
procura de investimento no racionamento converte despesa planeada para
escala de output via o rácio capital-output, em vez de aplicar `A`
diretamente à despesa. Ver `docs/LIMITATIONS.pt.md` item 1.

---

## 4. Recomendações de implementação

### 4.1 Acoplar A à acumulação — feito (ambos os passos)

Objetivo: tornar o modelo N-dept coerente com o de 2 departamentos, onde o
equilíbrio intersetorial já é imposto.

Abordagem recomendada, em dois passos:

1. **Consistência de reprodução.** Trabalhar com outputs brutos por setor. O
   output de valor do setor `i` é `Q_i = C_i + V_i + S_i`, com `S_i = e_i V_i`.
   A procura de capital constante do setor `j` é `A[:, j]` aplicada ao seu
   nível de atividade. A condição de realização exige que a oferta de cada bem
   iguale o uso intermédio mais o uso final (consumo dos trabalhadores e dos
   capitalistas, mais investimento líquido). No modelo de 2 departamentos isto
   reduz-se à condição já verificada em `check_equilibrium_2dept`.

2. **Mobilidade de capital.** Introduzir um termo de realocação que desloque
   investimento para setores com taxa de lucro acima da média:

   ```
   dC_i/dt = σ_c,i · S_i − δ_i · C_i + μ · (r_i − r̄) · C_i
   ```

   onde `μ` é o coeficiente de mobilidade e `r̄` a taxa média de lucro. Para que
   o sinal `(r_i − r̄)` reflita a estrutura input-output, calcular `r_i` sobre
   capital valorizado a preços de produção (que dependem de `A`), e não apenas
   por `e/(k+1)`. Assim `A` entra na dinâmica através da valorização.

Sugestão prática: manter `system_Ndept!` como está (documentado como versão
"setores independentes") e adicionar `system_Ndept_io!` com o acoplamento,
selecionável por argumento. Validar exigindo que, no limite estacionário, as
taxas de lucro convirjam para `r̄` e que os balanços setoriais fechem.

**Passo 2 (mobilidade) — feito**, exatamente como recomendado acima.
**Passo 1 (consistência de reprodução) — feito**, com dois mecanismos: uma
pressão agregada (`realization=true`) e um racionamento de quantidades exato
por setor (`rationing=true`, resolvido por ponto fixo, sem precisar de
DAE) — ver `docs/LIMITATIONS.pt.md` item 1.

### 4.2 Corrigir `R_max` no choque

Fazer `simulate_Ndept_custom` devolver a matriz `A` efetivamente usada.
Reutilizá-la em `simulate_wage_shock` para calcular `R_max` com os
coeficientes de trabalho reais dos departamentos (por exemplo `l_i`
proporcional ao emprego ou a `V_i`), em vez de `ones(N)`. Assim o limite de
viabilidade reportado passa a corresponder ao cenário simulado.

### 4.3 Robustecer o acesso à AMECO (parcialmente feito)

- ~~Descoberta dinâmica do ficheiro / preferir ZIP oficial / validar parser
  TXT por round-trip~~ — **obsoleto**: o ficheiro TXT foi descontinuado pela
  Comissão; substituído pela API SDMX oficial (`src/ameco_sdmx.jl`), que
  devolve dados estruturados diretamente, sem parsing de largura fixa. A
  verificação "valor conhecido" (PIB de Portugal) foi feita — ver
  `check_ameco_sdmx()` e `docs/LIMITATIONS.pt.md` item 3.
- **Confirmar mnemónicos** — feito para 24 das 25 variáveis (22 mapeadas
  diretamente mais 2 calculadas); só o stock de capital bruto confirmado
  indisponível nesta API. Alguns mnemónicos antigos (nunca verificados)
  revelaram-se incorretos — ver `docs/LIMITATIONS.pt.md` item 3.
- ~~Mapear capítulo SDMX por variável~~ — feito (ver acima).
- ~~Alternativa via Eurostat~~ — **feito**: `src/eurostat_sdmx.jl` usa
  `NAMA_10_A64`/`_E`/`_P5` para VAB/remunerações/CCF/emprego/FBCF,
  `NAMA_10_NFA_ST` para stock de capital, e `NAIO_10_CP1700` (a tabela IOT
  simétrica real — ver item 3.9 e `docs/LIMITATIONS.pt.md` item 4-bis para a
  correção do dataflow) para a matriz `A`.

### 4.4 Calibração setorial real (feito para 19, 10 e 3 setores; A real em ambos os caminhos)

- ~~Substituir os pesos fixos por dados reais de contas nacionais por
  ramo~~ — feito, `src/eurostat_sdmx.jl` (VAB, remunerações, CCF, emprego,
  FBCF, stock de capital via `NAMA_10_A64`/`NAMA_10_A64_E`/`NAMA_10_A64_P5`/
  `NAMA_10_NFA_ST`), opt-in em ambos os caminhos (`data_source=:eurostat` no
  INE, `sector_data=:eurostat` no AMECO).
- ~~Construir a matriz `A` a partir das tabelas do Eurostat~~ — feito para
  ambos os caminhos. INE: 19 setores, `build_eurostat_io_matrix` via
  `NAIO_10_CP1700` (a tabela IOT simétrica real, `stk_flow=DOM` — uma
  correção posterior substituiu `NAIO_10_CP1620`, que afinal era uma tabela
  satélite de margens, não o IOT em si; ver `docs/LIMITATIONS.pt.md` item 4-bis).
  AMECO (3 setores macro): agregar a matriz de 19 setores já limpa
  (não os fluxos brutos) pela fórmula padrão de agregação de Leontief
  (`aggregate_io_matrix`) dá uma matriz real, não-negativa, sem a ressalva de
  Terciário que constava aqui antes da correção do dataflow — verificado
  com reconciliação exata contra o output publicado pela própria tabela.
- ~~Estimar stock de capital por setor pelo método do inventário
  perpétuo~~ — feito (opcional, `perpetual_inventory=true`;
  `compute_pim_capital_stock`, `src/eurostat_sdmx.jl`). Usa uma taxa de
  depreciação única por setor (estimada, não fixa) — um PIM diferenciado por
  tipo de ativo exigiria perfis de depreciação que o Eurostat não publica
  diretamente, ficou por fazer (ver `docs/LIMITATIONS.pt.md` item 7).
- ~~Implementar de facto as agregações `:medium` e `:macro` no caminho
  INE~~ — feito, `aggregate_sectors` (`src/calibration_pt.jl`).

### 4.5 Testes e integração contínua — feito

- ~~Correr localmente~~ — feito, `julia install_deps.jl` seguido de
  `julia --project=. test/runtests.jl`, 111 testes a passar.
- ~~Execução sem ecrã~~ — feito, via `GKSwstype=100` (variável de ambiente,
  não argumento por função) antes de carregar `Plots`; usado tanto localmente
  como em CI.
- ~~Adicionar workflow de CI~~ — feito, `.github/workflows/test.yml`
  (GitHub Actions, matriz Julia 1.10/1, cache de pacotes, modo headless), em
  cada push a `main`.

Não coberto por CI (rede necessária, opt-in por design — ver
`docs/LIMITATIONS.pt.md`): `method=:sdmx`, `data_source=:eurostat`,
`sector_data=:eurostat`. Verificação manual via
`check_ameco_sdmx()`/`check_eurostat_sectoral()`.

### 4.6 Direções de médio prazo

Extensões já esboçadas em sessões anteriores, como roadmap depois de estabilizar
o núcleo:

- **Financeirização:** camada de crédito e capital fictício, com taxa de juro a
  separar lucro de empresa de rendimento financeiro.
- **Ecologia:** contabilização de fluxos de energia e materiais, e de um limite
  biofísico à acumulação.
- **Imperialismo e troca desigual:** transferências de valor entre economias com
  composições orgânicas distintas, ligando ao módulo de comparação internacional.
- **Agentes heterogéneos:** dispersão intra-setorial de produtividades e
  concorrência, em vez de setores representativos.

---

## 5. Roadmap sugerido

Sequência proposta, do mais estruturante ao mais exploratório:

1. ~~Executar a suite localmente e corrigir o que a compilação revelar.
   Adicionar CI headless.~~ — feito.
2. ~~Corrigir o `R_max` do choque~~ — feito.
3. ~~Acoplar `A` à dinâmica N-dept com mobilidade de capital~~ — feito
   (opcional, `coupled=true`), mais pressão de realização agregada
   (`realization=true`) e racionamento de quantidades exato por setor
   (`rationing=true`, ponto fixo, sem DAE); convergência de dispersão e
   amortecimento validados por teste.
4. ~~Robustecer o acesso à AMECO~~ — feito (API SDMX oficial, 26 séries
   obtidas — 24 mapeadas diretamente + 2 calculadas; 1 confirmada
   indisponível).
5. ~~Ligar dados setoriais reais (Eurostat)~~ — feito, opt-in, com matriz
   `A` real em ambos os caminhos (INE 19/10/3 setores; AMECO 3 setores,
   ver §4.4). Comportamento por omissão continua
   sintético/pesos fixos.
6. ~~Estimar stock de capital por inventário perpétuo~~ — feito, opcional
   (`perpetual_inventory=true`).
7. ~~Corrigir o dataflow errado da matriz técnica A~~ — feito
   (`NAIO_10_CP1700`, `stk_flow=DOM` — ver §3.9).
8. ~~Reconstruir output bruto genuíno no modelo dinâmico~~ — feito, sem
   novo estado (ver §3.10).
9. ~~Conservação exata do termo de mobilidade de capital~~ — feito (`r̄`
   ponderado por `C` — ver §3.1).
10. ~~Escrever artigo académico (metodologia + aplicação empírica)~~ —
    feito, `paper/main.tex`, reproduzível a partir de dados reais
    (`paper/generate_results.jl`, `paper/monte_carlo.jl`,
    `paper/matrix_audit.jl`).
11. Extensões de médio prazo (financeirização, ecologia, troca desigual, agentes
   heterogéneos) — ainda por fazer.

---

## 6. Lista de verificação

- [x] Testes executados localmente sem erros
- [x] CI headless configurada
- [x] `R_max` do choque calculado com A e l reais
- [x] `system_Ndept_io!` com acoplamento via A e mobilidade de capital (opcional, `coupled=true`)
- [x] Pressão de realização agregada opcional (`realization=true`) e `check_equilibrium_Ndept` (verificação a posteriori)
- [x] Racionamento de quantidades exato por setor (`rationing=true`, ponto fixo, sem DAE nem `NonlinearSolve.jl`)
- [x] Download AMECO via API SDMX oficial (substitui o ficheiro TXT descontinuado)
- [x] API SDMX validada com valor conhecido (`check_ameco_sdmx()`)
- [x] Mnemónicos AMECO confirmados (26 séries obtidas; 1 confirmada indisponível)
- [x] Matriz A a partir de tabelas de recursos e empregos reais (INE 19/10/3 setores; AMECO 3 setores, agregada — ver LIMITATIONS item 4-bis)
- [x] Calibração setorial com contas nacionais por ramo (ambos os caminhos, opt-in)
- [x] Stock de capital por inventário perpétuo (opcional, `perpetual_inventory=true`; taxa de depreciação única por setor, não diferenciada por tipo de ativo)
- [x] Agregações `:medium` e `:macro` do INE implementadas
- [x] Matriz técnica A corrigida para o dataflow real (`NAIO_10_CP1700`, `stk_flow=DOM`, zero células negativas, reconciliação exata contra P1)
- [x] Output bruto genuíno reconstruído no modelo dinâmico (sem novo estado); procura de investimento em escala de output (`Δx`), não despesa
- [x] Condição de admissibilidade da reconstrução verificada e corrigida uma única vez por simulação (`_ensure_output_admissibility`), não reclamada a cada avaliação
- [x] Termo de mobilidade conserva capital constante agregado exatamente (`r̄` ponderado por `C`)
- [x] Série temporal AMECO usa CCF real (não uma dedução fixa de 10%); `e` invariante sob deflator comum, verificado
- [x] Piso `e=0.1` na calibração setorial reportado explicitamente (contagem de setores saturados)
- [x] Artigo académico (`paper/main.tex`) — metodologia + aplicação empírica a Portugal, reproduzível
