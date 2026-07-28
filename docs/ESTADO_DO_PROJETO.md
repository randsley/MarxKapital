# MarxKapital — Estado do Projeto

Documento de acompanhamento da versão **0.3.0**. Descreve o que está feito, o
que falta resolver e recomendações concretas de implementação. Destina-se a
ficar em `docs/ESTADO_DO_PROJETO.md`, ao lado de `docs/LIMITACOES.md`.

Data: julho de 2026. Autor do projeto: Nigel Randsley.

---

## 1. Sumário

O MarxKapital é um sistema em Julia para modelação matemática da teoria
económica marxista: acumulação de capital, exploração, composição orgânica,
tendência da taxa de lucro, transformação de valores em preços de produção,
fronteira distributiva salário-lucro, e calibração empírica com dados
nacionais (INE) e europeus (AMECO). A versão 0.3.0 está funcional para
demonstração e desenvolvimento metodológico. Os dados por omissão são
sintéticos e não servem para análise empírica publicável.

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

### 2.9 Verificação estática realizada

Como o ambiente de empacotamento não tinha Julia instalado, a verificação foi
estática, não por compilação: delimitadores equilibrados em todos os ficheiros;
nenhuma função chamada sem definição; contagem de argumentos confirmada em
todos os construtores posicionais (`DadosAMECO` com 29 campos e 29 argumentos
nas três chamadas; `ParâmetrosCalibrados` com 17 campos e 17 argumentos).

---

## 3. O que falta resolver

Ordenado por prioridade. O detalhe completo está em `docs/LIMITACOES.md`.

### 3.1 Crítico: a matriz A não realimenta a dinâmica de N departamentos

Em `sistema_Ndept!`, a acumulação de cada setor depende apenas da sua própria
mais-valia; a matriz `A` é transportada nos parâmetros mas não entra nas
equações. Os setores comportam-se como independentes, o que contradiz a lógica
da reprodução ampliada (o output de um setor é o capital constante de outro).
Consequência: os ciclos e a convergência das taxas de lucro na simulação N-dept
refletem apenas heterogeneidade de parâmetros iniciais, não interdependência
setorial real.

### 3.2 Importante: `R_max` no choque salarial é ilustrativo

Em `simular_choque_salarial`, o `R_max` reportado usa uma matriz auxiliar
`A_ref` e `l = ones(N)`, não a matriz nem os coeficientes de trabalho da
simulação. Serve de referência grosseira de viabilidade, não de limite exato do
cenário.

### 3.3 Importante: download e parsing AMECO são heurísticos

A AMECO não tem API REST oficial. As URLs testadas podem estar desatualizadas;
os offsets do parser de largura fixa (país, variável, sub, valores de 15
caracteres a partir da coluna 21, a começar em 1960) são um palpite razoável,
por confirmar contra o ficheiro real; os mnemónicos das variáveis seguem a
convenção habitual, mas devem ser validados. Em caso de falha, o sistema recorre
silenciosamente a dados sintéticos (verificar sempre o campo `fonte`).

### 3.4 Médio: calibração AMECO só macro, com pesos fixos

`calibrar_com_dados_ameco` só implementa a agregação `:macro` (Primário,
Secundário, Terciário), com repartição do VAB, emprego e stock de capital por
pesos fixos por país. Países sem perfil específico caem num perfil médio da UE.

### 3.5 Médio: agregação INE incompleta

`calibrar_modelo_portugal` aceita o argumento `agregação`, mas só `:detalhada`
(19 setores) está ligada. Os modos `:média` e `:macro` não estão implementados.

### 3.6 Médio: stock de capital e depreciação aproximados

O capital constante é aproximado pelo stock de capital e a depreciação é fixada
perto de 10% em vários pontos. Falta uma abordagem de inventário perpétuo e
taxas de depreciação diferenciadas.

### 3.7 Transversal: dados sintéticos por omissão

Tanto o caminho INE como o AMECO usam, por omissão, dados gerados. Servem para
demonstração e testes, não para análise empírica.

### 3.8 Verificação: testes nunca executados

A suite `test/runtests.jl` foi escrita mas não foi corrida no ambiente de
empacotamento (sem Julia). Falta uma execução local limpa e, idealmente,
integração contínua.

---

## 4. Recomendações de implementação

### 4.1 Acoplar A à acumulação (prioridade máxima)

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

### 4.2 Corrigir `R_max` no choque

Fazer `simular_Ndept_customizado` devolver a matriz `A` efetivamente usada.
Reutilizá-la em `simular_choque_salarial` para calcular `R_max` com os
coeficientes de trabalho reais dos departamentos (por exemplo `l_i`
proporcional ao emprego ou a `V_i`), em vez de `ones(N)`. Assim o limite de
viabilidade reportado passa a corresponder ao cenário simulado.

### 4.3 Robustecer o acesso à AMECO

- **Descoberta dinâmica do ficheiro.** Em vez de URLs fixas, descarregar a
  página do portal e extrair por parsing o link atual do ficheiro (ZIP ou TXT).
  Isto resiste às mudanças semestrais de localização.
- **Preferir o ZIP oficial** de ficheiros TXT quando disponível, descomprimindo
  localmente.
- **Validar o parser** com um valor conhecido: escolher um par país-variável-ano
  de referência (por exemplo PIB de Portugal num ano recente) e confirmar que o
  valor extraído bate com o publicado, antes de confiar nos offsets. Parametrizar
  largura de campo e ano inicial já está feito; falta o teste de round-trip.
- **Confirmar mnemónicos** contra a lista de variáveis da versão vigente.
- **Alternativa via Eurostat.** Para séries setoriais reais, a API SDMX do
  Eurostat (`nama_10_a64` para contas por indústria, tabelas de recursos e
  empregos para `A`, `nama_10_nfa` para stock de capital) é mais estável do que
  a AMECO e tem interface programática.

### 4.4 Calibração setorial real

- Substituir os pesos fixos por dados reais de contas nacionais por ramo
  (VAB, remunerações, EBE, emprego por setor).
- Construir a matriz `A` a partir das tabelas de recursos e empregos (SUT) do
  Eurostat ou do INE, em vez de a gerar aleatoriamente.
- Estimar stock de capital por setor pelo método do inventário perpétuo, com
  séries de FBCF e taxas de depreciação por tipo de ativo.
- Implementar de facto as agregações `:média` e `:macro` no caminho INE.

### 4.5 Testes e integração contínua

- Correr localmente: `julia install_deps.jl` seguido de
  `julia --project=. test/runtests.jl`.
- Para execução sem ecrã (testes e CI), definir `ENV["GKSwstype"] = "100"`
  antes de carregar `Plots`, evitando que as chamadas a `display` tentem abrir
  uma janela. Em alternativa, adicionar um argumento `plotar=false` às funções
  que hoje desenham sempre (`problema_transformacao`,
  `validar_taxas_lucro_calibradas`), para as tornar silenciosas em teste.
- Adicionar workflow de CI (por exemplo GitHub Actions) com matriz de versões
  de Julia, cache de pacotes e execução dos testes em modo headless.

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

1. Executar a suite localmente e corrigir o que a compilação revelar. Adicionar
   CI headless.
2. Corrigir o `R_max` do choque (baixo custo, remove uma inconsistência
   reportada).
3. Acoplar `A` à dinâmica N-dept com mobilidade de capital, validando os
   balanços e a convergência para `r̄`. É a peça que falta para coerência
   teórica.
4. Robustecer o acesso à AMECO (descoberta dinâmica do ficheiro, teste de
   round-trip do parser, confirmação de mnemónicos).
5. Ligar dados setoriais reais (Eurostat ou INE) e substituir os pesos fixos e
   os dados sintéticos.
6. Estimar stock de capital por inventário perpétuo.
7. Extensões de médio prazo (financeirização, ecologia, troca desigual, agentes
   heterogéneos).

---

## 6. Lista de verificação

- [ ] Testes executados localmente sem erros
- [ ] CI headless configurada
- [ ] `R_max` do choque calculado com A e l reais
- [ ] `sistema_Ndept_io!` com acoplamento via A e mobilidade de capital
- [ ] Convergência para `r̄` e fecho dos balanços validados
- [ ] Download AMECO com descoberta dinâmica do ficheiro
- [ ] Parser AMECO validado por round-trip com valor conhecido
- [ ] Mnemónicos AMECO confirmados
- [ ] Matriz A a partir de tabelas de recursos e empregos reais
- [ ] Calibração setorial com contas nacionais por ramo
- [ ] Stock de capital por inventário perpétuo
- [ ] Agregações `:média` e `:macro` do INE implementadas
