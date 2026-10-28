# Registo de alterações

*[🇬🇧 Read this in English](CHANGELOG.en.md)*

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21705369.svg)](https://doi.org/10.5281/zenodo.21705369)

Formato baseado em Keep a Changelog. Versionamento semântico.

## [0.8.0] — 2026-10-28

DOI desta versão (Zenodo): [10.5281/zenodo.23735182](https://doi.org/10.5281/zenodo.23735182). Para citar todas as versões, use o DOI conceptual acima.

### Adicionado
- `expoentes_lyapunov` (`src/bifurcacao.jl`): maiores expoentes de
  Lyapunov do sistema normalizado (método de Benettin, jacobiana exata),
  e `histerese_simulada`: varrimento do parâmetro para cima e para baixo
  por simulação, para detetar atratores coexistentes.
- **Resultado:** o regime irregular dos ciclos de acumulação é caótico
  (maior expoente positivo, robusto à condição inicial, tolerância e
  duração; dois expoentes positivos a `μ_v` alto), e um ciclo estável
  coexiste com o toro numa janela de `μ_v` (histerese). Artigo, Secção
  5.6 e figura nova (expoentes e histerese), atualizados.

## [0.7.0] — 2026-10-28

DOI desta versão (Zenodo): [10.5281/zenodo.23718359](https://doi.org/10.5281/zenodo.23718359). Para citar todas as versões, use o DOI conceptual acima.

### Adicionado
- **Diferenciação automática** (`src/diferenciacao.jl`, ForwardDiff):
  jacobiana exata do lado direito da EDO (`jacobiana_sistema`, também
  com `racionamento=true`), sensibilidade a parâmetros
  (`jacobiana_parametro`), hessianas (`hessiana_sistema`), curvatura
  exata da fronteira salário-lucro (`curvatura_fronteira`) e espetro do
  mapa de racionamento no ponto fixo (`jacobiana_racionamento`: valores
  próprios, `α_max`, `α` ótimo). O ponto fixo do racionamento é
  diferenciado pelo teorema da função implícita (`_racionamento_dual`).
- **Resultado:** a jacobiana do mapa de racionamento é triangular com os
  setores ordenados por ρ*, com espetro real em `[−1, 0]`, e `−1` é valor
  próprio assim que algum setor é racionado. A iteração amortecida
  converge localmente para todo `α ∈ (0, 1)`; `α = 1` está exatamente
  numa fronteira de flip. Verificado nos 270 casos do sweep de
  `paper/monte_carlo.jl` e provado em `paper/main.tex` (Proposição 1).
- **TSSI** (`src/tssi.jl`): valorização temporal de sistema único ao
  longo de trajetórias, com desfasamento de produção τ fixo
  (`valorizar_tssi`, `mapa_tssi`, `preços_simultâneos`,
  `estabilidade_tssi`, `comparar_tssi_simultaneo`). Camada de
  valorização apenas; a dinâmica não muda.
- **Bifurcações** (`src/bifurcacao.jl`, BifurcationKit): continuação de
  pontos fixos de mapas com classificação por multiplicadores (fold,
  flip, Neimark–Sacker) — `continuar_ponto_fixo`,
  `bifurcacao_racionamento`, `bifurcacao_tssi`, `plotar_bifurcacao`.
- `paper/jacobiana_bifurcacao.jl` e as novas Secções 3.4, 3.5 e 5.5 do
  artigo (figuras 7–9). Os números citados são gerados em
  `paper/figures/jacobian_stats.tex`, que o artigo lê diretamente.
- Dependências novas: `ForwardDiff`, `BifurcationKit` (`install_deps.jl`).
- **Dinâmica cruzada** (`src/cruzado.jl`, opcional com
  `preços_mercado=true`): preços de mercado que respondem ao excesso de
  procura (`β`), lucros e mobilidade de capital a esses preços
  (Flaschel–Semmler), lei de Walras exata. Sem ela não há crescimento
  equilibrado interior.
- **Mobilidade do capital variável** `μ_v` (desligada por omissão), no
  sistema acoplado e no cruzado; o termo soma exatamente 0.
- **Crescimento equilibrado** (`src/crescimento.jl`): sistema normalizado
  no simplex (`sistema_normalizado`, `simular_normalizado`), raios de
  crescimento equilibrado por Newton com jacobiana exata
  (`crescimento_equilibrado`), `indicadores_crescimento`, `com_parâmetro`
  e o varrimento da parcela salarial (`varrimento_salarial`, uniforme ou
  proporcional).
- **Bifurcações da acumulação** (`src/bifurcacao.jl`):
  `bifurcacao_acumulação` (Hopf com forma normal, continuação de
  ciclos-limite por colocação com multiplicadores de Floquet),
  `ciclo_simulado` (verificação por simulação, secção de Poincaré) e
  `curva_hopf` (fronteira de Hopf no plano parcela salarial × `μ_v`).
- **Resultado:** o crescimento equilibrado perde estabilidade num Hopf
  supercrítico em `μ_v` em todas as 30 economias aleatórias testadas; a
  fronteira de Hopf sobe com a parcela salarial.
- `paper/acumulacao_bifurcacao.jl` e as novas Secções 3.6 e 5.6 do artigo
  (figuras 10–11), com os números em `paper/figures/acumulacao_stats.tex`.

### Alterado
- **Relaxação por omissão do racionamento: 0.5 → 2/3**
  (`RELAXAÇÃO_PADRÃO`, usada por `_resolver_racionamento`,
  `jacobiana_racionamento` e `bifurcacao_racionamento`). Com espetro em
  `[−1, 0]` e os modos 0 e −1 sempre presentes, 2/3 minimiza o raio
  espectral (1/3 em vez de 1/2): ≈30% menos iterações (média 18.0 vs.
  25.8 no sweep de 270 casos), convergência em todas as 6870 execuções
  por valor de α (pontos iniciais aleatórios e oferta muito escassa
  incluídos; Tabela 2 do artigo). O ponto fixo não muda (diferença
  ≤ 2.4e-9 na trajetória da Figura 4).
- `README.md` passa a ser a versão inglesa (por omissão); a portuguesa
  está em `README.pt.md`.
- `sistema_Ndept_io!` e `_resolver_racionamento` são genéricos no tipo de
  número (aceitam `ForwardDiff.Dual`). O fallback de preços (π = 1)
  passa a apanhar só sistemas singulares (`ErrorException`) e relança
  outros erros, em vez de os mascarar (`_razão_preço_valor`).

## [0.6.1] — 2026-07-30

### Adicionado
- `CITATION.cff` e `.zenodo.json`: metadados de citação e arquivo,
  preparando o repositório para a integração GitHub-Zenodo (release
  sem alterações funcionais, só para acionar o primeiro arquivo
  Zenodo depois de ativada a integração).

## [0.6.0] — 2026-07-30

### Corrigido
- **Matriz técnica A usava o dataflow errado do Eurostat.** Uma auditoria
  pedida em revisão externa do artigo em `paper/` (destinada a quantificar
  o efeito de um passo de "clipping" de margens) revelou que
  `NAIO_10_CP1620` — usado desde a primeira integração da matriz real —
  não é a tabela IOT simétrica, mas sim "Table of trade and transport
  margins", uma tabela satélite pequena. Construir `A` a partir dela
  subavaliava os fluxos intersetoriais em mais de uma ordem de grandeza
  (consumo intermédio total implícito ≈8.8 mil M€ para Portugal 2020,
  contra um verdadeiro ≈177.8 mil M€) e explicava o raio espectral
  implausivelmente baixo (ρ(A)≈0.11-0.15) e o `R_max` implausivelmente
  alto (≈600-700%) reportados até agora. Corrigido com `NAIO_10_CP1700`
  (a tabela real), `stk_flow=DOM` (só uso doméstico — a tabela publica
  também `IMP`/`TOTAL`, ao contrário da anterior). Verificado: zero
  células negativas, reconciliação exata contra o `P1` (output bruto)
  publicado pela própria tabela, ρ(A)≈0.52-0.60, `R_max`≈68-91%. Ver
  `docs/LIMITACOES.md` item 4-bis, `paper/matrix_audit.jl`.
- **Output bruto do modelo dinâmico (`sistema_Ndept_io!`) omitia consumo
  intermédio circulante.** Os mecanismos `realização`/`racionamento`
  usavam `O=W=δC+V+S` (um fluxo tipo valor-acrescentado) como oferta,
  não gross output no sentido usado para construir `A`. Corrigido
  reconstruindo o output bruto genuíno `x=W/(1-Σᵢ A[i,j])` a partir da
  própria identidade custo-output do modelo, sem novo estado — válido
  só para as matrizes sintéticas fechadas usadas nestas simulações
  (nunca aplicado à matriz real do Eurostat, de uso doméstico). A
  condição de admissibilidade (`Σᵢ A[i,j]<1`) é agora verificada e
  corrigida uma única vez quando a simulação é montada
  (`_garantir_admissibilidade_output`), não reclamada a cada avaliação
  do lado direito da EDO.
- **Procura de investimento no racionamento aplicava A à despesa, não ao
  output.** `_resolver_racionamento` recebia `σ_c,ⱼSⱼ` (despesa de
  investimento planeada) diretamente; corrigido para `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ`
  (expansão de output desejada, via o rácio capital-output corrente),
  para que `A` seja aplicada a uma grandeza em escala de output,
  consistente com a sua própria definição.
- **Termo de mobilidade de capital não conservava capital constante
  agregado.** `r̄` era a razão agregada `ΣS/Σ(C+V)`, que não garante
  `Σᵢμ(rᵢ-r̄)Cᵢ=0`. Corrigido usando a média de `r` ponderada por `C` — a
  única escolha para a qual a soma é exatamente zero por construção.
- **Série temporal AMECO (`analisar_série_temporal_com_dados`) deduzia
  uma depreciação fixa de 10% do stock de capital**, em vez de consumo
  de capital fixo (CCF) real — isto quebrava a invariância algébrica que
  `e=(Y-V-CCF)/V` deve ter sob um deflator comum aplicado a `Y`, `V` e
  CCF. Corrigido usando a série real de CCF da AMECO (item `UKCT`);
  `deflator_FBCF` também acrescentado a `MAPA_AMECO_SDMX`, para testar
  sensibilidade à escolha do deflator (`valorização=:consistente_fbcf`).
  Verificado: `e` agora idêntico entre convenções de valorização para
  todos os anos, Portugal e Espanha.
- Tabela de calibração setorial (usada em `paper/gerar_resultados.jl`)
  reconstruía VAB como `C+V+e·V` (uma stock somada a fluxos), em vez de
  reportar o VAB real já calculado pelo pipeline — somava duas ordens de
  grandeza a menos que o total nacional. `ParâmetrosCalibrados` ganhou um
  campo `VAB` real.

### Adicionado
- `capital_transferido(d)`/correção de `valor_produto(d)` em
  `estruturas.jl`: distingue capital constante *avançado* (stock, `d.c`)
  de capital constante *transferido* num período (`δ·c`) — a magnitude
  correta a somar com fluxos anuais.
- `paper/` (novo): artigo académico completo em LaTeX combinando
  metodologia (o modelo, os três mecanismos de acoplamento, o
  racionamento como ponto fixo com prova de existência e antitonicidade)
  e aplicação empírica a Portugal, com todas as figuras/tabelas
  reproduzíveis a partir de dados reais (`gerar_resultados.jl`,
  `monte_carlo.jl` — sweeps sistemáticos de convergência e dispersão,
  `matrix_audit.jl` — auditoria da matriz técnica).
- 63 novos testes em `test/runtests.jl` (48→111): invariância de `e`
  sob deflator, conservação exata da mobilidade, sensibilidade do
  racionamento a condições iniciais/ordem/tolerância, reconstrução de
  output bruto, admissibilidade da reconstrução (caso normal e caso de
  rescala), entre outros.

## [0.5.0] — 2026-07-28

### Adicionado
- `_resolver_racionamento` (`src/nucleo.jl`) e o kwarg `racionamento=true`
  em `sistema_Ndept_io!`/`simular_Ndept`/`simular_Ndept_customizado`
  (tem precedência sobre `realização`): racionamento de quantidades exato
  por setor à Bénassy/Barro-Grossman, com tecnologia Leontief — o
  reinvestimento realizado de cada setor fica limitado pelo input mais
  escasso, e o racionamento propaga-se entre fornecedores/compradores.
  Resolvido por iteração de ponto fixo com sub-relaxação (necessária — a
  versão sem relaxação oscila indefinidamente, confirmado num exemplo de 2
  setores) dentro do cálculo do lado direito da EDO — sem transformar o
  sistema numa DAE nem depender de `NonlinearSolve.jl`. Verificado com um
  exemplo de solução fechada (`ρ₁=√0.8`) e por robustez em 20+ combinações
  seed/μ e em N=19, sem falhas de convergência.
- `calcular_stock_capital_pim` (`src/eurostat_sdmx.jl`) e o kwarg
  `inventário_perpétuo=true` em `calibrar_modelo_portugal`/
  `calibrar_com_ameco_v2`: stock de capital calculado pelo método do
  inventário perpétuo (`Kₜ=(1-δ)Kₜ₋₁+FBCFₜ`, `δ` estimado por setor a
  partir de CCF/stock no ano de referência), em vez do valor reportado
  diretamente pelo Eurostat. Degrada por setor (não globalmente) quando a
  série de FBCF de um setor não chega ao ano pedido. Verificado com dados
  reais de Portugal: a série PIM acompanha o stock reportado ao longo de
  22 anos, com desvio moderado e crescente (esperado — taxa de
  depreciação única por setor, não diferenciada por tipo de ativo).

## [0.4.0] — 2026-07-28

### Adicionado
- CI headless via GitHub Actions (`.github/workflows/test.yml`), Julia 1.10 e 1.
- `sistema_Ndept_io!` (opcional, `acoplado=true` em `simular_Ndept`/`simular_Ndept_customizado`):
  acopla a matriz técnica A à dinâmica de N departamentos via um termo de
  mobilidade de capital `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ` calculado sobre capital
  valorizado a preços de produção de Sraffa. `sistema_Ndept!` mantém-se como
  a versão "setores independentes" por omissão. Ver `docs/LIMITACOES.md` item 1.
- `calcular_taxas_lucro_precos(sol, p)` em `src/analise.jl`, para reproduzir
  fora da EDO as taxas de lucro ponderadas por preços usadas pelo sistema acoplado.
- `src/ameco_sdmx.jl`: cliente para a API REST SDMX oficial da AMECO
  (`descarregar_ameco_sdmx`, `obter_dados_ameco(..., método=:sdmx)`),
  substituindo o download do ficheiro TXT estático — descontinuado pela
  Comissão Europeia (confirmado 2026-07). Verificado com dados reais de
  Portugal (PIB, emprego, remunerações, FBCF, stock de capital líquido);
  `verificar_sdmx_ameco()` faz uma verificação manual de sanidade. Métodos
  `:auto`/`:download` passam a usar a API SDMX como caminho automático; os
  fluxos `:local`/`:csv` (ficheiro TXT/CSV já descarregado) mantêm-se
  disponíveis. Ver `docs/LIMITACOES.md` item 3.
- `src/eurostat_sdmx.jl`: dados setoriais reais via API SDMX do Eurostat
  (VAB, remunerações, consumo de capital fixo, emprego, FBCF, stock de
  capital líquido — dataflows `NAMA_10_A64`, `NAMA_10_A64_E`,
  `NAMA_10_A64_P5`, `NAMA_10_NFA_ST`), e matriz técnica `A` real a partir do
  IOT simétrico (`NAIO_10_CP1620`). Opt-in em ambos os caminhos de
  calibração:
  - `calibrar_modelo_portugal(..., fonte_dados=:eurostat)` — 19 setores CAE,
    dados reais e matriz `A` real; lança erro se indisponível (sem
    fallback silencioso).
  - `calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` — 3 setores
    macro, dados reais e matriz `A` real (ver entrada seguinte); cai para
    os pesos fixos e A aleatória com aviso se o país não tiver cobertura
    Eurostat ou o pedido falhar.
  - `verificar_eurostat_setorial()` faz uma verificação manual de sanidade.
  - Comportamento por omissão em ambos os caminhos inalterado (sintético /
    pesos fixos), suite de testes continua totalmente offline.
- `MAPA_AMECO_SDMX` (`src/ameco_sdmx.jl`) alargado de 6 para 22 das 25
  variáveis de `CÓDIGOS_AMECO_VARIÁVEIS` (consumo privado/público,
  exportações, importações, emprego assalariado, taxa de desemprego,
  população ativa, remunerações por assalariado, produtividade do
  trabalho, IPC, receitas/despesas do governo, saldo orçamental, balança
  corrente, custos unitários de trabalho, dívida pública), mais 2 séries
  calculadas a partir de séries já mapeadas (deflator do PIB, balança
  comercial de bens) — 24/25 no total. Stock de capital bruto confirmado
  indisponível nesta API (não fica "pendente"). Todas verificadas com
  chamadas reais contra Portugal (défice, desemprego e dívida pública 2022
  batem com valores conhecidos).
- `agregar_matriz_io` (`src/eurostat_sdmx.jl`): agregação de matrizes
  técnicas pela fórmula padrão de Leontief (colunas ponderadas pelo VAB/
  output dos setores finos), reutilizável com matrizes reais ou aleatórias.
  Usada para (a) construir a matriz `A` real do caminho AMECO de 3 setores
  a partir da matriz real de 19 setores já limpa — a via direta (agregar os
  fluxos brutos do IOT) tinha sido tentada e rejeitada numa sessão anterior
  por misturar margens de comércio/transporte com serviços genuínos; e (b)
  as novas agregações `:macro`/`:média` do caminho INE (ver entrada
  seguinte). Testada offline com um exemplo sintético verificado à mão.
- `calibrar_modelo_portugal` ganha agregação real para `agregação=:macro`
  (3 setores, mesmos grupos do caminho AMECO) e `:média` (10 setores, nível
  padrão NACE Rev.2 "A10") via `agregar_setores`
  (`src/calibracao_pt.jl`) — antes, ambos os valores eram aceites mas
  silenciosamente ignorados, correndo sempre `:detalhada`. Funciona com
  dados sintéticos ou reais (Eurostat), sem distinção de código.
- `sistema_Ndept_io!` ganha um segundo mecanismo opcional, independente da
  mobilidade de capital: `realização=true` acresce uma pressão de
  realização agregada (`ρ_real = Σmin(Oᵢ,(A·O)ᵢ)/Σ(A·O)ᵢ`, output bruto vs.
  procura intermédia implícita em A) que amortece o reinvestimento quando a
  estrutura técnica não sustenta os outputs correntes — sem introduzir
  variáveis de estado novas nem exigir um solver de equações
  algébrico-diferenciais (DAE, explicitamente fora de alcance). Robustez
  verificada em 20 combinações seed/μ sem falhas do solver.
- `verificar_equilibrio_Ndept(sol, p)` (`src/analise.jl`): generalização a N
  setores de `verificar_equilibrio_2dept`, verificação a posteriori (desvio
  `Oᵢ−(A·O)ᵢ` por setor e `ρ_real` agregado).

### Corrigido
- `MAPA_AMECO_SDMX`: vários mnemónicos herdados de `CÓDIGOS_AMECO_VARIÁVEIS`
  (nunca antes verificados contra a API) estavam errados — `receitas_governo`
  e `despesas_governo` tinham os códigos trocados, e `consumo_privado`/
  `exportações`/`importações` usavam mnemónicos já retirados da API
  (`UNCT`/`UXTG`/`UMTG` → `UCPH`/`UXGS`/`UMGS`). `_obter_série_sdmx` passa a
  aceitar `transformação` e `unidade` (nem todos os capítulos AMECO usam
  TRANSFORMATION=1/UNIT=0).
- `calcular_precos_producao` agora rejeita corretamente `r̄ ≥ R_max` (antes só
  detetava matriz literalmente singular, permitindo preços negativos silenciosos
  acima de R_max apesar do que a docstring prometia).
- `simular_choque_salarial`: `R_max` reportado passa a usar a matriz técnica e
  os coeficientes de trabalho reais da simulação (`p_base.A`, `l ∝ V`), em vez
  de uma matriz auxiliar `A_ref` e `l = ones(N)`. Ver `docs/LIMITACOES.md` item 2.

## [0.3.0]

### Adicionado
- Integração AMECO para todos os países da base (UE, Área do Euro, EUA, Japão).
- `obter_dados_ameco` com métodos `:auto`, `:download`, `:local`, `:csv`, `:sintético`, `:manual`.
- Download automático da base TXT (`descarregar_ameco_automatico`) e parser de largura fixa (`ler_ficheiro_ameco_txt`).
- Processador de CSV AMECO (`processar_csv_ameco`).
- Calibração a partir de dados AMECO (`calibrar_com_ameco_v2`, `calibrar_com_dados_ameco`).
- Comparação internacional (`comparar_países_ameco`) e séries temporais (`analisar_série_temporal_ameco`).
- Reorganização do código num repositório modular (src/, test/, examples/, docs/).
- Suite de testes (`test/runtests.jl`) e demonstração (`examples/demo.jl`).
- `docs/LIMITACOES.md` documentando limitações conhecidas.

### Corrigido
- `Statistics` importado explicitamente (mean/std/median/var/cor/quantile).
- Parâmetros da EDO passados como `NamedTuple` (type-stable) em vez de `Dict`.
- `matriz_identidade(N)` substitui usos incorretos da constante `I` do LinearAlgebra.
- Validação de calibração usa histogramas robustos (sem dependência dura de boxplot).
- Eliminado o bug `match_obj` não definido no fluxo de atualização AMECO (função de atualização removida/reescrita).
- `seed` opcional e partilhada nas simulações para reprodutibilidade e comparabilidade base-vs-choque.

### Conhecido (ver docs/LIMITACOES.md)
- A matriz técnica A não realimenta a dinâmica de N departamentos.
- `R_max` no choque salarial é ilustrativo (matriz auxiliar).
- URLs e formato do parser AMECO são heurísticos.
- Calibração AMECO limitada à agregação macro (3 setores) com pesos fixos.
- Dados por omissão são sintéticos.

## [0.2.0]
- Calibração INE (Portugal) com 19 setores CAE (sintético).
- Fronteira distributiva w-r e validação de taxas de lucro calibradas.

## [0.1.0]
- Modelo de 2 e N departamentos, acumulação via EDOs.
- Valores-trabalho, preços de produção de Sraffa, problema da transformação.
