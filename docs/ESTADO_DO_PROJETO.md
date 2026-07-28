# MarxKapital — Estado do Projeto

Documento de acompanhamento, iniciado na versão 0.3.0 e atualizado desde
então; o trabalho descrito nas secções seguintes corresponde à versão
**0.4.0**. Descreve o que está feito, o que falta resolver e recomendações
concretas de implementação. Destina-se a ficar em
`docs/ESTADO_DO_PROJETO.md`, ao lado de `docs/LIMITACOES.md`.

Data: julho de 2026. Autor do projeto: Nigel Randsley.

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
disponíveis como opção, via APIs SDMX oficiais (ver `docs/LIMITACOES.md`).

O código foi reorganizado de um ficheiro monolítico para um repositório
modular, com testes, exemplos e documentação. A integração AMECO abrange todos
os países da base, com calibração, comparação internacional e séries
temporais.

---

## 2. O que foi feito

### 2.1 Núcleo do modelo (`src/nucleo.jl`, `src/estruturas.jl`)

- Tipo `Departamento` com invariantes validadas no construtor: `c`, `v`,
  `e`, `k = c/v`, quotas de reinvestimento (`σ_c`, `σ_v`, `γ`) que somam 1, e
  depreciação `δ`. Métodos auxiliares: `taxa_lucro`, `mais_valia`,
  `capital_total`, `valor_produto`.
- Modelo clássico de 2 departamentos (meios de produção e bens de consumo) e
  modelo generalizado de N departamentos.
- Construção de matriz técnica `A` com três estruturas (`:aleatoria`,
  `:triangular`, `:blocos`), sempre normalizada para raio espectral inferior a
  1 (economia produtiva). Argumento `seed` para reprodutibilidade.
- Integração da dinâmica de acumulação com `DifferentialEquations.jl` (Tsit5),
  para 2 e N departamentos.

### 2.2 Análise de valor e preço (`src/analise.jl`)

- Taxas de lucro, composições orgânicas e taxa média ao longo do tempo.
- Valores-trabalho `λ = (I − A)⁻¹ l`.
- Taxa máxima de lucro `R_max = 1/λ_max(Aᵀ) − 1`.
- Preços de produção de Sraffa `p = w(1+r̄)[I − (1+r̄)Aᵀ]⁻¹ l`, com rejeição de
  taxas que tornem o sistema singular.
- Problema da transformação com visualização comparativa (valores contra
  preços, desvios percentuais, divergência em função da taxa de lucro,
  correlação).

### 2.3 Análise distributiva e validação (`src/distributiva.jl`)

- Fronteira de possibilidades distributivas (curva w-r), com elasticidade e
  evolução de preços relativos.
- Validação de taxas de lucro calibradas: viabilidade face a `R_max`,
  dispersão, consistência com a exploração implícita, posição na fronteira, e
  pontuação de qualidade em [0, 100]. Usa histogramas robustos, sem dependência
  dura de boxplot.

### 2.4 Política e choques (`src/choques.jl`)

- Simulação de choque salarial: aumento de `Δw` sobe `V`, reduz `e`
  proporcionalmente, e ajusta `r`. Compara cenário base contra choque, com a
  mesma `seed` nos dois, garantindo comparabilidade.
- Comparação de múltiplos cenários de choque.

### 2.5 Calibração nacional (`src/calibracao_pt.jl`)

- Geração de dados sintéticos com a estrutura setorial portuguesa (19 setores
  CAE Rev.3): VAB, remunerações, EBE, CCF, emprego, FBCF e stock de capital.
- Processamento dos Quadros de Recursos e Empregos, com indicadores marxianos
  por setor.
- Estimação de parâmetros setoriais e pipeline `calibrar_modelo_portugal`.

### 2.6 Integração AMECO (`src/ameco.jl`, `src/ameco_download.jl`)

- Estruturas de dados (`DadosAMECO`, 29 campos) e dicionários de países e de
  mnemónicos de variáveis.
- Geração de séries sintéticas plausíveis (tendência mais ciclo) calibradas por
  perfis de país.
- Download automático da base TXT completa (`descarregar_ameco_automatico`),
  com tentativa de várias URLs e registo da data.
- Parser de largura fixa (`ler_ficheiro_ameco_txt`), com offsets
  parametrizáveis.
- Processador de CSV exportado (`processar_csv_ameco`).
- Ponto de entrada unificado `obter_dados_ameco` com métodos `:auto`,
  `:download`, `:local`, `:csv`, `:sintético` e `:manual`.
- Calibração a partir de dados AMECO, comparação internacional entre países, e
  análise de séries temporais dos indicadores marxianos.

### 2.7 Empacotamento e documentação

- Estrutura de repositório: `src/`, `test/`, `examples/`, `data/`, `docs/`.
- Carregador `src/MarxKapital.jl` (estilo script, carregado por `include`,
  evitando UUIDs fixos).
- `install_deps.jl`, `Project.toml`, `.gitignore`, `LICENSE` (MIT),
  `README.md`, `CHANGELOG.md`.
- Suite de testes (`test/runtests.jl`) e demonstração (`examples/demo.jl`).
- `docs/LIMITACOES.md` com as limitações conhecidas.

### 2.8 Correções aplicadas nesta fase

- Importação explícita de `Statistics` (`mean`, `std`, `median`, `var`, `cor`,
  `quantile`).
- Parâmetros da EDO passados como `NamedTuple` (type-stable) em vez de `Dict`,
  eliminando o aviso de performance do SciMLBase.
- Substituição dos usos incorretos da constante `I` do LinearAlgebra por
  `matriz_identidade(N)`.
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
cada push a `main`, ver `.github/workflows/test.yml`) — 39 testes, todos a
passar. Os caminhos de dados reais (rede) são verificados manualmente com
`verificar_sdmx_ameco()`/`verificar_eurostat_setorial()`, fora da suite
automática por design (ver `docs/LIMITACOES.md`).

---

## 3. O que falta resolver

Ordenado por prioridade. O detalhe completo está em `docs/LIMITACOES.md`.

### 3.1 Parcialmente resolvido: a matriz A não realimenta a dinâmica de N departamentos

Em `sistema_Ndept!`, a acumulação de cada setor depende apenas da sua própria
mais-valia; a matriz `A` é transportada nos parâmetros mas não entra nas
equações. Os setores comportam-se como independentes, o que contradiz a lógica
da reprodução ampliada (o output de um setor é o capital constante de outro).

**Corrigido (opcional):** `sistema_Ndept_io!` (`acoplado=true`) acopla A à
dinâmica via um termo de mobilidade de capital `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ`
valorizado a preços de produção de Sraffa. `sistema_Ndept!` mantém-se como
omissão. **Corrigido em parte (segundo mecanismo, `realização=true`):** uma
pressão de realização agregada (`ρ_real = Σmin(Oᵢ,(A·O)ᵢ)/Σ(A·O)ᵢ`) trava o
reinvestimento quando a estrutura técnica não sustenta os outputs
correntes; `verificar_equilibrio_Ndept` generaliza a verificação a
posteriori do modelo de 2 departamentos. Um tratamento exato (restrições
algébricas por setor a cada instante, exigindo transformar o sistema numa
DAE) continua fora de alcance — ver `docs/LIMITACOES.md` item 1 para a
fronteira explícita.

### 3.2 Resolvido: `R_max` no choque salarial era ilustrativo

Em `simular_choque_salarial`, o `R_max` reportado usava uma matriz auxiliar
`A_ref` e `l = ones(N)`, não a matriz nem os coeficientes de trabalho da
simulação. **Corrigido:** passou a usar `p_base.A` (devolvida por
`simular_Ndept_customizado`) e `l = [d.v for d in depts]`, refletindo o
cenário simulado.

### 3.3 Resolvido: download AMECO passou a usar a API SDMX oficial

O antigo ficheiro TXT estático foi descontinuado pela Comissão (URLs
confirmadas mortas em 2026-07). **Corrigido:** `src/ameco_sdmx.jl` usa a API
REST SDMX oficial da AMECO (`webgate.ec.europa.eu/ecfin/redisstat`), agora o
caminho automático por omissão (`obter_dados_ameco`, métodos `:auto`/`:sdmx`).
Verificado com dados reais de Portugal (PIB, emprego, remunerações, FBCF,
stock de capital). **Quase totalmente resolvido:** `MAPA_AMECO_SDMX` mapeia
agora 22/25 variáveis mais 2 calculadas (deflator do PIB, balança comercial)
— 24/25; só o stock de capital bruto ficou confirmado indisponível nesta
API (não "pendente") — ver `docs/LIMITACOES.md` item 3 para a lista exata.

### 3.4 Resolvido: calibração AMECO só macro, com pesos fixos por omissão

`calibrar_com_dados_ameco` só implementa a agregação `:macro` (Primário,
Secundário, Terciário). Por omissão, repartição do VAB, emprego e stock de
capital por pesos fixos por país; países sem perfil específico caem num
perfil médio da UE. **Corrigido (opcional):** `dados_setoriais=:eurostat`
usa dados setoriais reais do Eurostat em vez dos pesos fixos, com fallback
automático para países fora da cobertura UE/EEE, **incluindo agora a matriz
`A`**: construída aos 19 setores finos (real, não-negativa) e agregada aos
3 setores macro pela fórmula de Leontief (`agregar_matriz_io`), em vez de
agregar os fluxos brutos do IOT diretamente — ver `docs/LIMITACOES.md`
item 4 para a ressalva conhecida (linha do Terciário conservadora).

### 3.5 Resolvido: agregação INE incompleta

`calibrar_modelo_portugal` aceitava o argumento `agregação`, mas só
`:detalhada` (19 setores) estava ligada. **Corrigido:** `:macro` (3 setores,
mesma agregação do caminho AMECO) e `:média` (10 setores, nível NACE Rev.2
"A10") implementados via `agregar_setores`, funcionando tanto com dados
sintéticos como reais.

### 3.6 Médio: stock de capital e depreciação aproximados

O capital constante é aproximado pelo stock de capital e a depreciação é fixada
perto de 10% em vários pontos. Falta uma abordagem de inventário perpétuo e
taxas de depreciação diferenciadas.

### 3.7 Transversal: dados sintéticos por omissão

Tanto o caminho INE como o AMECO usam, por omissão, dados gerados. Servem para
demonstração e testes, não para análise empírica.

### 3.8 Resolvido: testes agora executados em CI

A suite `test/runtests.jl` (39 testes) corre localmente e em CI (GitHub
Actions, Julia 1.10 e 1, `.github/workflows/test.yml`) em cada push a
`main`. Cobre os caminhos sintéticos/opt-in por omissão; os caminhos de
dados reais (rede) ficam de fora por design — ver §3.3/§4.3.

---

## 4. Recomendações de implementação

### 4.1 Acoplar A à acumulação (prioridade máxima) — passo 2 feito, passo 1 parcial

Objetivo: tornar o modelo N-dept coerente com o de 2 departamentos, onde o
equilíbrio intersetorial já é imposto.

Abordagem recomendada, em dois passos:

1. **Consistência de reprodução.** Trabalhar com outputs brutos por setor. O
   output de valor do setor `i` é `Q_i = C_i + V_i + S_i`, com `S_i = e_i V_i`.
   A procura de capital constante do setor `j` é `A[:, j]` aplicada ao seu
   nível de atividade. A condição de realização exige que a oferta de cada bem
   iguale o uso intermédio mais o uso final (consumo dos trabalhadores e dos
   capitalistas, mais investimento líquido). No modelo de 2 departamentos isto
   reduz-se à condição já verificada em `verificar_equilibrio_2dept`.

2. **Mobilidade de capital.** Introduzir um termo de realocação que desloque
   investimento para setores com taxa de lucro acima da média:

   ```
   dC_i/dt = σ_c,i · S_i − δ_i · C_i + μ · (r_i − r̄) · C_i
   ```

   onde `μ` é o coeficiente de mobilidade e `r̄` a taxa média de lucro. Para que
   o sinal `(r_i − r̄)` reflita a estrutura input-output, calcular `r_i` sobre
   capital valorizado a preços de produção (que dependem de `A`), e não apenas
   por `e/(k+1)`. Assim `A` entra na dinâmica através da valorização.

Sugestão prática: manter `sistema_Ndept!` como está (documentado como versão
"setores independentes") e adicionar `sistema_Ndept_io!` com o acoplamento,
selecionável por argumento. Validar exigindo que, no limite estacionário, as
taxas de lucro convirjam para `r̄` e que os balanços setoriais fechem.

**Passo 2 (mobilidade) — feito**, exatamente como recomendado acima.
**Passo 1 (consistência de reprodução) — feito em parte**, como pressão
agregada opcional (`realização=true`) em vez de restrição exata por setor
(essa exigiria uma DAE, fora de alcance) — ver `docs/LIMITACOES.md` item 1.

### 4.2 Corrigir `R_max` no choque

Fazer `simular_Ndept_customizado` devolver a matriz `A` efetivamente usada.
Reutilizá-la em `simular_choque_salarial` para calcular `R_max` com os
coeficientes de trabalho reais dos departamentos (por exemplo `l_i`
proporcional ao emprego ou a `V_i`), em vez de `ones(N)`. Assim o limite de
viabilidade reportado passa a corresponder ao cenário simulado.

### 4.3 Robustecer o acesso à AMECO (parcialmente feito)

- ~~Descoberta dinâmica do ficheiro / preferir ZIP oficial / validar parser
  TXT por round-trip~~ — **obsoleto**: o ficheiro TXT foi descontinuado pela
  Comissão; substituído pela API SDMX oficial (`src/ameco_sdmx.jl`), que
  devolve dados estruturados diretamente, sem parsing de largura fixa. A
  verificação "valor conhecido" (PIB de Portugal) foi feita — ver
  `verificar_sdmx_ameco()` e `docs/LIMITACOES.md` item 3.
- **Confirmar mnemónicos** — feito para 24 das 25 variáveis (22 mapeadas
  diretamente mais 2 calculadas); só o stock de capital bruto confirmado
  indisponível nesta API. Alguns mnemónicos antigos (nunca verificados)
  revelaram-se incorretos — ver `docs/LIMITACOES.md` item 3.
- ~~Mapear capítulo SDMX por variável~~ — feito (ver acima).
- **Alternativa via Eurostat.** Para séries setoriais reais, a API SDMX do
  Eurostat (`nama_10_a64` para contas por indústria, tabelas de recursos e
  empregos para `A`, `nama_10_nfa` para stock de capital) continua relevante
  e ainda por explorar — não coberta por este trabalho.

### 4.4 Calibração setorial real (feito para 19, 10 e 3 setores; A real em ambos os caminhos)

- ~~Substituir os pesos fixos por dados reais de contas nacionais por
  ramo~~ — feito, `src/eurostat_sdmx.jl` (VAB, remunerações, CCF, emprego,
  FBCF, stock de capital via `NAMA_10_A64`/`NAMA_10_A64_E`/`NAMA_10_A64_P5`/
  `NAMA_10_NFA_ST`), opt-in em ambos os caminhos (`fonte_dados=:eurostat` no
  INE, `dados_setoriais=:eurostat` no AMECO).
- ~~Construir a matriz `A` a partir das tabelas do Eurostat~~ — feito para
  ambos os caminhos. INE: 19 setores, `construir_matriz_io_eurostat` via
  `NAIO_10_CP1620`. AMECO (3 setores macro): a agregação direta dos fluxos
  brutos do IOT falhou (margens de comércio/transporte, ver
  `docs/LIMITACOES.md` item 4), mas agregar a matriz de 19 setores **já
  limpa** (não os fluxos brutos) pela fórmula padrão de agregação de
  Leontief (`agregar_matriz_io`) resultou numa matriz real, não-negativa —
  com a ressalva de que a linha do Terciário fica conservadora (herda o
  mesmo subdimensionamento da matriz de 19 setores, só que sem produzir
  valores inválidos). Combinar tabelas de oferta e utilização em vez do IOT
  simétrico continua por explorar como melhoria futura mais trabalhosa.
- Estimar stock de capital por setor pelo método do inventário perpétuo —
  ainda não feito; usa-se o stock líquido reportado diretamente pelo
  Eurostat (`NAMA_10_NFA_ST`), não um inventário perpétuo próprio.
- ~~Implementar de facto as agregações `:média` e `:macro` no caminho
  INE~~ — feito, `agregar_setores` (`src/calibracao_pt.jl`).

### 4.5 Testes e integração contínua — feito

- ~~Correr localmente~~ — feito, `julia install_deps.jl` seguido de
  `julia --project=. test/runtests.jl`, 39 testes a passar.
- ~~Execução sem ecrã~~ — feito, via `GKSwstype=100` (variável de ambiente,
  não argumento por função) antes de carregar `Plots`; usado tanto localmente
  como em CI.
- ~~Adicionar workflow de CI~~ — feito, `.github/workflows/test.yml`
  (GitHub Actions, matriz Julia 1.10/1, cache de pacotes, modo headless), em
  cada push a `main`.

Não coberto por CI (rede necessária, opt-in por design — ver
`docs/LIMITACOES.md`): `método=:sdmx`, `fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`. Verificação manual via
`verificar_sdmx_ameco()`/`verificar_eurostat_setorial()`.

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
   (opcional, `acoplado=true`), mais uma pressão de realização opcional
   (`realização=true`); convergência de dispersão e amortecimento validados
   por teste, restrição exata por setor (DAE) fora de alcance.
4. ~~Robustecer o acesso à AMECO~~ — feito (API SDMX oficial, 24/25
   variáveis mapeadas ou calculadas; 1 confirmada indisponível).
5. ~~Ligar dados setoriais reais (Eurostat)~~ — feito, opt-in, com matriz
   `A` real em ambos os caminhos (INE 19/10/3 setores; AMECO 3 setores,
   ver §4.4 para a ressalva). Comportamento por omissão continua
   sintético/pesos fixos.
6. Estimar stock de capital por inventário perpétuo — ainda por fazer.
7. Extensões de médio prazo (financeirização, ecologia, troca desigual, agentes
   heterogéneos) — ainda por fazer.

---

## 6. Lista de verificação

- [x] Testes executados localmente sem erros
- [x] CI headless configurada
- [x] `R_max` do choque calculado com A e l reais
- [x] `sistema_Ndept_io!` com acoplamento via A e mobilidade de capital (opcional, `acoplado=true`)
- [x] Pressão de realização opcional (`realização=true`) e `verificar_equilibrio_Ndept` (verificação a posteriori)
- [ ] Consistência de reprodução exata por setor (restrição algébrica/DAE) — fora de alcance, só a pressão agregada acima
- [x] Download AMECO via API SDMX oficial (substitui o ficheiro TXT descontinuado)
- [x] API SDMX validada com valor conhecido (`verificar_sdmx_ameco()`)
- [x] Mnemónicos AMECO confirmados (24/25 variáveis; 1 confirmada indisponível)
- [x] Matriz A a partir de tabelas de recursos e empregos reais (INE 19/10/3 setores; AMECO 3 setores, agregada — ver LIMITACOES item 4)
- [x] Calibração setorial com contas nacionais por ramo (ambos os caminhos, opt-in)
- [ ] Stock de capital por inventário perpétuo (usa-se o stock líquido reportado pelo Eurostat diretamente)
- [x] Agregações `:média` e `:macro` do INE implementadas
