# Limitações conhecidas e trabalho pendente

*[🇬🇧 Read this in English](LIMITACOES.en.md)*

Este ficheiro documenta, sem rodeios, o que ainda não está correto ou
completo. Nenhum destes pontos impede a execução, mas todos afetam a
interpretação dos resultados.

## 1. A matriz técnica A não realimenta a dinâmica de N departamentos

Em `sistema_Ndept!` (ficheiro `src/nucleo.jl`), a acumulação de cada
departamento depende apenas da sua própria mais-valia:

    dCᵢ/dt = σ_c,ᵢ · Sᵢ − δᵢ · Cᵢ
    dVᵢ/dt = σ_v,ᵢ · Sᵢ

A matriz `A` é calculada e transportada em `p.A`, mas **não entra nas
equações**. Ou seja: a estrutura input-output existe para o cálculo de
valores-trabalho e preços de produção (que a usam corretamente), mas a
simulação temporal trata os setores como independentes. Isto contradiz a
lógica da reprodução ampliada, onde o consumo de capital constante de um
setor é o output de outro.

**Consequência:** os ciclos e a (não-)convergência das taxas de lucro na
simulação N-dept refletem apenas heterogeneidade de parâmetros iniciais, não
interdependência setorial real.

**Correção pendente:** acoplar a acumulação via A, por exemplo exigindo que a
procura de capital constante do setor i (ΔCᵢ) seja satisfeita pelo output dos
setores fornecedores (colunas/linhas de A), e introduzir um mecanismo de
mobilidade de capital que desloque investimento para setores com r > r̄.

**Corrigido:** `sistema_Ndept_io!` (`src/nucleo.jl`), selecionável
com `acoplado=true` em `simular_Ndept`/`simular_Ndept_customizado`, acopla A à
dinâmica através de um termo de mobilidade de capital `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ`
calculado sobre capital valorizado a preços de produção de Sraffa (que dependem
de A), em vez do `e/(k+1)` nu. `sistema_Ndept!` mantém-se como versão por
omissão ("setores independentes"), inalterada, por compatibilidade.
`r̄` é a média de `r` ponderada por `C` (não a razão agregada `ΣS/Σ(C+V)`,
usada até uma correção posterior) — a única escolha para a qual
`Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exatamente, garantindo que o termo de mobilidade
realoca capital constante agregado entre setores em vez de o criar ou
destruir. Verificado por teste (`test/runtests.jl`, "Mobilidade de
capital — conservação exata").

**Corrigido (segundo mecanismo, opcional):** `sistema_Ndept_io!`
aceita agora `realização=true` (transportado via `p.realização`, kwarg de
`simular_Ndept`/`simular_Ndept_customizado`), que acresce uma pressão de
realização escalando o reinvestimento planeado por
`ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1), travando a acumulação quando
a estrutura técnica não consegue sustentar os níveis de output correntes.
`xᵢ` é o output bruto **genuíno**, não o fluxo tipo valor-acrescentado
`Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (capital constante *transferido*, não o stock `Cᵢ`) usado
numa correção anterior: `Wᵢ` omite o consumo intermédio circulante que a
matriz `A` efetivamente precifica. Reconstrói-se `xᵢ` a partir da própria
identidade custo-output do modelo — ver mais abaixo, "Corrigido (output
bruto genuíno...)". Verificado por teste
(`test/runtests.jl`, "Simulação N-dept com pressão de realização") e por
robustez em 20 combinações seed/μ sem falhas do solver.

**Corrigido (terceiro mecanismo, exato por setor, opcional):**
`sistema_Ndept_io!` aceita agora `racionamento=true` (tem precedência sobre
`realização`), que resolve **racionamento de quantidades por setor** — não
apenas uma pressão agregada. A expansão de output *desejada* de cada setor
`j`, `Δxⱼ=σ_c,ⱼ·Sⱼ·xⱼ/Cⱼ` (investimento planeado convertido para escala de
output via o rácio capital-output corrente, não a despesa `σ_c,ⱼSⱼ`
diretamente — uma correção posterior, ver abaixo), exige inputs dos
fornecedores na proporção `A[:,j]` (tecnologia
Leontief, sem substituição entre inputs), pelo que o reinvestimento
realizado fica limitado pelo input mais escasso — e o racionamento sofrido
por um setor reduz a sua procura efetiva de TODOS os seus inputs, afetando
por sua vez o racionamento dos seus fornecedores. Resolve-se por iteração de
ponto fixo (`_resolver_racionamento`, `src/nucleo.jl`):

```
κⱼ = min_{i: A[i,j]>0} ρᵢ          (limitado pelo input mais escasso)
Dᵢ = Σⱼ A[i,j]·κⱼ·Δxⱼ               (procura efetiva, já consistente com o racionamento)
ρᵢ = min(1, xᵢ / Dᵢ)               (regra do lado curto)
```

Mecanismo de racionamento de quantidades à Bénassy/Barro-Grossman
(disequilibrium macro), não uma restrição algébrica gerida por um solver
DAE: resolve-se por iteração de ponto fixo dentro do próprio cálculo do
lado direito da EDO (com sub-relaxação, necessária — a versão sem
relaxação oscila indefinidamente em vez de convergir, confirmado num
exemplo de 2 setores), tal como os preços de Sraffa já são resolvidos
por um sistema linear direto na mesma função. Sem convergência em 200
iterações, cai-se para `κ=1` (sem racionamento) com aviso — a mesma
degradação graciosa usada no resto do código. **Não foi necessária** a
dependência `NonlinearSolve.jl` nem transformar o sistema numa DAE
formal (mass-matrix/`DAEProblem`) — o ponto fixo já dá uma resposta
exata (dentro da tolerância numérica) ao problema de racionamento tal
como formulado, sem precisar de expor `(ρ,κ)` como estado gerido pelo
solver. Verificado com um exemplo de solução fechada (`test/runtests.jl`,
"Racionamento de mercado (ponto fixo)": `ρ₁=√0.8`, verificado à mão) e por
robustez em 20 combinações seed/μ (N=8) e em N=19, sem falhas de
convergência nem do solver da EDO.

`verificar_equilibrio_Ndept(sol, p)` (`src/analise.jl`) generaliza
`verificar_equilibrio_2dept` a N setores: devolve o *resíduo de uso
intermédio* `xᵢ−(A·x)ᵢ` por setor e `ρ_real` (a versão agregada) num dado
instante, a posteriori — não é uma medida de desequilíbrio ou de
mercado (um resíduo positivo é o caso normal em contabilidade
input-output: output disponível para consumo, exportações, etc., que
este diagnóstico não modela), e não usa o racionamento por setor (esse
já está embutido em `κ` dentro de `sistema_Ndept_io!` quando
`racionamento=true`).

**Corrigido (output bruto genuíno, não um fluxo tipo valor-acrescentado):**
`Oᵢ`/`xᵢ` acima já não é `Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (que omite consumo intermédio
circulante — materiais, energia, serviços comprados — e não é gross
output no sentido input-output usado para construir `A`). Reconstrói-se
`xᵢ` a partir da própria identidade custo-output do modelo: como `A[i,j]`
é definida como input `i` por unidade de output bruto do comprador `j`,
o consumo circulante de `j` é `zⱼ=(Σᵢ A[i,j])·xⱼ`, donde
`xⱼ = Wⱼ/(1-Σᵢ A[i,j])` — sem introduzir novo estado, recalculado a cada
avaliação do lado direito da EDO tal como os preços de Sraffa. Válido só
quando `A` representa o requisito de input circulante *completo* de cada
setor (verdadeiro por construção para as matrizes sintéticas fechadas
usadas nestas simulações; não para a matriz real de uso doméstico do
Eurostat, que omite importações por definição — nunca usada nesta
reconstrução). A condição de admissibilidade `Σᵢ A[i,j]<1` (necessária
para o denominador ser positivo) não é garantida por `ρ(A)<1`
(que limita o raio espectral, não qualquer soma de coluna individual);
verificada e corrigida uma única vez quando a simulação é montada
(`_garantir_admissibilidade_output`, `src/nucleo.jl`), reescalando `A`
uniformemente se necessário, com aviso — não um clamp silencioso
reaplicado a cada avaliação. Verificado por teste
(`test/runtests.jl`, "Output bruto reconstruído..." e "Admissibilidade
da reconstrução de output bruto").

**Corrigido (procura de investimento em escala de output, não despesa):**
o `Δxⱼ` na fórmula do racionamento acima substitui uma versão anterior
que aplicava `A[i,j]` diretamente à despesa de investimento planeada
`σ_c,ⱼSⱼ`, como se uma unidade de despesa exigisse a mesma composição de
inputs que uma unidade de output físico — um problema dimensional
identificado em revisão externa. `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` converte a despesa
para uma expansão de output via o rácio capital-output corrente do
setor, antes de `A` ser aplicada. Continua por resolver: todo o `xᵢ`
reconstruído é tratado como disponível para a procura de investimento
`Dᵢ`, sem descontar a reposição de inputs intermédios (já contada em
`zᵢ`) nem outra procura final — não há fonte de dados no pipeline atual
com a alocação de consumo por setor de origem, pelo que `Dᵢ≤xᵢ` deve
ler-se como um limite superior à oferta investível, não um balanço de
reprodução totalmente líquido.

## 2. R_max no choque salarial usa uma matriz auxiliar (corrigido)

Em `simular_choque_salarial` (`src/choques.jl`), o `R_max` reportado era
calculado com uma matriz `A_ref` gerada só para dar uma referência de
viabilidade e com `l = ones(N)` — não a matriz da simulação nem os
coeficientes de trabalho reais dos departamentos.

**Corrigido:** `R_max` passou a usar `p_base.A` (a matriz técnica
efetivamente devolvida por `simular_Ndept_customizado` para o cenário base)
e `l = [d.v for d in depts]` (coeficientes de trabalho proporcionais a V,
mesma convenção usada em `sistema_Ndept_io!`). O valor de viabilidade
reportado corresponde agora ao cenário simulado, não a uma referência
auxiliar.

Mitigação já aplicada (mantida): a mesma `seed` é passada aos dois cenários
(base e choque), pelo que as matrizes técnicas das duas simulações são
idênticas e a comparação base-vs-choque é reprodutível.

## 3. Download AMECO (corrigido: API SDMX oficial substitui o ficheiro TXT)

**Contexto histórico:** esta secção descrevia as URLs heurísticas do antigo
ficheiro TXT estático (`URLS_AMECO_TENTAR`, `src/ameco_download.jl`) e o
parser de largura fixa (`ler_ficheiro_ameco_txt`). Confirmado em 2026-07 que
essa distribuição foi **descontinuada pela Comissão Europeia** — todas as
URLs devolvem 404 ou redirecionam para a página HTML do portal, nunca dados.

**Corrigido:** a AMECO passou a expor uma **API REST SDMX oficial**
(`src/ameco_sdmx.jl`, `webgate.ec.europa.eu/ecfin/redisstat`, a mesma
plataforma da nova ferramenta de dados do Eurostat). `obter_dados_ameco`
(métodos `:auto`/`:sdmx`/`:download`) usa-a como caminho automático por
omissão. Verificado com chamadas reais (2026-07): PIB, emprego, remunerações,
FBCF e stock de capital líquido de Portugal, devolvidos corretamente desde
1960. Os mnemónicos em `CÓDIGOS_AMECO_VARIÁVEIS` (UVGD, OVGD, etc.)
confirmaram-se válidos como código `ITEM` nesta API, sem necessidade de
remapear. Os códigos de país precisaram de um mapeamento próprio
(`CÓDIGOS_PAÍSES_AMECO_SDMX`), maioritariamente ISO3 mas com irregularidades
reais (GRC não EL, GBR não UK, ROM não ROU).

**Resolvido (quase por completo):** `MAPA_AMECO_SDMX` mapeia agora 22 das 25
variáveis de `CÓDIGOS_AMECO_VARIÁVEIS`, mais 2 séries calculadas a partir de
séries já mapeadas (deflator do PIB, balança comercial) — 24/25 no total,
todas verificadas com chamadas reais em 2026-07. Além das 6 originais (PIB
corrente/constante, emprego total, remunerações, FBCF, stock de capital
líquido) e das 14 seguintes (consumo privado/público, exportações,
importações, emprego assalariado, taxa de desemprego, população ativa,
remunerações por assalariado, produtividade do trabalho, IPC,
receitas/despesas do governo, saldo orçamental e balança corrente),
acrescentaram-se: custos unitários de trabalho (capítulo 07-07, item `PLCD`,
`TRANSFORMATION=3`), dívida pública (capítulo 18-02, item `UDGGL` — confirma-se
o mnemónico antigo, nunca verificado, estava certo desta vez), deflator do
PIB (calculado, `PIB_corrente/PIB_constante×100`, não pedido à API) e
balança comercial (calculada, exportações menos importações de **bens**
apenas — capítulo 11-01, itens `DXGT`/`DMGT`, `UNIT=99`; distinta de
`exportações`/`importações`, que cobrem bens e serviços). Os valores obtidos
para Portugal batem com figuras reais conhecidas (défice 2022 ≈ -0.3% do
PIB, desemprego 2022 ≈ 6.2%, dívida pública 2022 ≈ 111% do PIB).

**Confirmado indisponível (não "pendente"):** stock de capital bruto. Só o
capítulo de stock líquido (`AMECO_CHAPTER08-01`) existe nesta API, sem
equivalente bruto publicado — verificado por wildcard completo dos itens do
capítulo, não apenas por não ter sido encontrado à primeira tentativa.

**Nota importante:** vários mnemónicos que estavam em `CÓDIGOS_AMECO_VARIÁVEIS`
(nunca antes verificados) revelaram-se **incorretos** contra a API real —
por exemplo `UUTG` estava atribuído a `receitas_governo` mas é na realidade
`despesas_governo` (as duas trocadas), e `consumo_privado`/`exportações`/
`importações` usavam mnemónicos (`UNCT`/`UXTG`/`UMTG`) que já não existem na
API atual (os corretos são `UCPH`/`UXGS`/`UMGS`). `MAPA_AMECO_SDMX` usa os
códigos corrigidos; `CÓDIGOS_AMECO_VARIÁVEIS` (`estruturas.jl`, usado só pelo
parser TXT legado) não foi alterado — continua a ser heurístico, como sempre
se avisou.

Só o stock de capital bruto (confirmado indisponível, ver acima) fica
ausente do resultado (preenchido a 0.0 por `construir_dados_ameco`, sem
erro). Corra `verificar_sdmx_ameco()` manualmente (não faz parte dos testes
automáticos, para não depender de rede em CI) antes de confiar nos dados
numa análise real.

O antigo caminho TXT/CSV (`ler_ficheiro_ameco_txt`, `processar_csv_ameco`,
métodos `:local`/`:csv`) mantém-se disponível para quem já tenha um ficheiro
descarregado manualmente, mas deixou de ser o caminho automático.

Se todas as vias falharem, `obter_dados_ameco(..., método=:auto)` recorre
silenciosamente a **dados sintéticos** (com aviso). Verifique sempre o campo
`fonte` do resultado.

## 4. Calibração AMECO é macro (3 setores), com pesos fixos por omissão (corrigido)

`calibrar_com_dados_ameco` só implementa a agregação `:macro`
(Primário/Secundário/Terciário). Por omissão (`dados_setoriais=:fixo`), a
repartição do PIB, do emprego e do stock de capital por setor usa **pesos
fixos por país** codificados em `_dist_setorial_vab`,
`_dist_setorial_emprego` e `_dist_setorial_stock`. São aproximações; países
sem perfil específico caem no perfil médio da UE. Como VAB, remunerações e
CCF se repartem pelos mesmos pesos, `e` sai igual nos três setores; só `k`
difere.

**Corrigido (pesos fixos):** este caminho deduzia como depreciação 10% do
stock de capital de cada setor, em vez do CCF real da AMECO (o mesmo erro do
item 9), e repartia o stock por `[0.10, 0.35, 0.55]`, que dava ao Primário
12–17 vezes o seu VAB em capital. Com os dois, o rendimento líquido saía
negativo no Primário (e, com dados sintéticos, também no Secundário): `e`
ficava no piso 0.1 e `r` negativo, incoerente com `r = e/(k+1)`. Agora usa-se
a série de CCF da AMECO (`UKCT`), repartida como o VAB (as quotas setoriais
reais do CCF seguem de perto as do VAB), e quotas de stock do Eurostat para
Portugal, `[0.02, 0.16, 0.82]` (`NAMA_10_NFA_ST`, 2019/2022: 0.016 / 0.16 /
0.82; o Terciário inclui a habitação). `r` calcula-se com `e/(k+1)` a partir
do `e` com piso, e os setores que saturam no piso são reportados, como no
caminho INE (item 8). Em `comparar_países_ameco`, as colunas `PIB` e
`Quota_Salarial` mediam afinal o capital adiantado `Σ(C+V)` e `ΣV/Σ(C+V)`;
medem agora o VAB e `ΣV/ΣVAB`.

**Corrigido (opcional):** `dados_setoriais=:eurostat` usa VAB, remunerações,
consumo de capital fixo, emprego, FBCF e stock de capital **reais** do
Eurostat (`src/eurostat_sdmx.jl`, dataflows `NAMA_10_A64`, `NAMA_10_A64_E`,
`NAMA_10_A64_P5`, `NAMA_10_NFA_ST`), agregados às 3 secções macro. Só cobre
países da UE/EEE; fora dessa cobertura, ou se o pedido (dados ou matriz A)
falhar, cai silenciosamente (com aviso) para os pesos fixos e A aleatória —
nunca lança erro.

**Matriz A real — corrigida, com boa reconciliação, não uma ressalva
conhecida:** constrói-se primeiro a matriz real aos 19 setores finos (ver
item 4-bis) e agrega-se essa matriz de **coeficientes** (não fluxos
brutos) aos 3 grupos pela fórmula padrão de agregação de
Leontief (`agregar_matriz_io`, `src/eurostat_sdmx.jl`):
`A₃[gi,gj] = Σ A₁₉[i,j]·VAB[j] / Σ VAB[j]` (soma ponderada por VAB dentro do
grupo `j`). A ressalva sobre a linha do Terciário que constava aqui numa
versão anterior descrevia um sintoma da tabela errada usada nessa altura
(ver item 4-bis) — resolvida, não contornada, com a correção do dataflow.

## 4-bis. Matriz técnica A real — dataflow errado, encontrado e corrigido

**Histórico do bug (2026-07/08):** uma auditoria pedida em revisão externa
(quantificar o efeito de um passo de "clipping" de margens, reconciliar
totais publicados, documentar a correspondência CPA↔NACE, resolver a
questão doméstico-vs-total-uso) revelou algo mais fundamental do que
qualquer uma dessas perguntas: `construir_matriz_io_eurostat`
(`src/eurostat_sdmx.jl`) usava `NAIO_10_CP1620`, que **não é** a tabela
IOT simétrica — o título real no Eurostat é "Table of trade and
transport margins", uma tabela satélite pequena, usada para decompor a
tabela de usos a preços de comprador nas suas componentes (fluxos a
preços base + margens + impostos-subsídios), não a tabela simétrica em
si. Construir `A` a partir dela subavaliava os fluxos intersetoriais em
mais de uma ordem de grandeza (consumo intermédio total implícito
≈8.8 mil M€ para Portugal 2020, contra um verdadeiro ≈177.8 mil M€
calculado como output publicado menos VAB publicado, somado por todas
as secções NACE) — e todas as células negativas anteriormente atribuídas
a uma convenção de realocação de margens eram simplesmente a mecânica
dessa tabela satélite, não uma característica da estrutura input-output
real. Isto explica diretamente o raio espectral implausivelmente baixo
(ρ(A)≈0.11-0.15) e o `R_max` implausivelmente alto (≈600-700%) reportados
em versões anteriores deste ficheiro e do artigo em `paper/`.

**Corrigido:** `construir_matriz_io_eurostat` usa agora `NAIO_10_CP1700`
("Symmetric input-output table at basic prices, product by product"), a
tabela real, com `stk_flow=DOM` (fluxos só de uso doméstico — a tabela
publica também `IMP` e `TOTAL`, confirmado por consulta real; `A` deve
representar interdependência produtiva *doméstica*, e um input importado
não é fornecido por nenhum setor doméstico). Verificado com dados reais
de Portugal: zero células negativas, reconciliação exata contra a linha
`P1` (output bruto) publicada pela própria tabela para as 19 secções,
ρ(A)≈0.52-0.60 (consoante `stk_flow`), `R_max`≈68-91% — ambos
economicamente plausíveis. `NAIO_10_CP1700` é uma tabela de referência
(não anual — Portugal: 2010/2013/2015/2017/2020), diferente do resto do
pipeline; um pedido para um ano sem tabela publicada cai automaticamente
para o ano de referência mais próximo (`_ano_iot_mais_próximo`), com
aviso — pelo que a matriz `A` de um pedido para 2022, por exemplo, tem
na prática vintage 2020 (ver `paper/main.tex`, Secção 4.2, para como o
artigo separa explicitamente os resultados de 2020 e 2022 em vez de os
misturar).

Usada por `calibrar_modelo_portugal(..., fonte_dados=:eurostat)` (19
setores CAE — ver item 5) e, agregada via `agregar_matriz_io`, por
`calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` (3 setores macro
— ver item 4). Verificação completa (frequência de rescala de admissibilidade,
reconciliação, questão doméstico/importado) em `paper/matrix_audit.jl`,
corrido manualmente contra a API ao vivo.

## 5. `agregação` na calibração INE não está totalmente ligada (corrigido)

`calibrar_modelo_portugal` aceitava o argumento `agregação` mas só corria em
`:detalhada` (19 setores); os modos `:média` e `:macro` eram ignorados
silenciosamente.

**Corrigido:** `:macro` agrega aos mesmos 3 setores usados no caminho AMECO
(`GRUPOS_MACRO_NACE`); `:média` agrega a 10 setores, o nível padrão NACE
Rev.2 "A10" (`GRUPOS_MEDIO_NACE`, `src/eurostat_sdmx.jl`) — uma agregação
reconhecida, não inventada. `agregar_setores` (`src/calibracao_pt.jl`) soma
as variáveis de fluxo por grupo e agrega `A` pela mesma fórmula de Leontief
do item 4 — funciona tanto com `fonte_dados=:sintético` (A aleatória) como
`:eurostat` (A real), sem distinção de código entre os dois casos.
Verificado: as 6 combinações (`:detalhada`/`:macro`/`:média` ×
`:sintético`/`:eurostat`) produzem matrizes não-negativas com ρ(A)<1.

## 6. Todos os dados por omissão são SINTÉTICOS (dados reais agora opcionais)

Tanto o caminho INE como o AMECO usam, **por omissão**, dados **gerados** com
padrões plausíveis. Servem para demonstração, testes e desenvolvimento
metodológico — **não para análise empírica publicável** nesse modo.

**Dados reais disponíveis (opt-in):**
- INE: `calibrar_modelo_portugal(fonte_dados=:eurostat, agregação=:detalhada|:macro|:média)`
  — 19, 3 ou 10 setores, dados e matriz técnica `A` reais (ver item 4-bis e item 5).
- AMECO: `calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` — 3 setores
  macro, dados e matriz `A` reais (ver item 4).

Continua a ser necessário pedir explicitamente estes modos — o comportamento
por omissão em ambos os caminhos mantém-se sintético/pesos fixos, por
compatibilidade com o comportamento histórico e para manter a suite de
testes totalmente offline (ver `verificar_eurostat_setorial()` para uma
verificação manual, fora dos testes automáticos).

## 7. Stock de capital e depreciação são aproximados (corrigido, com ressalva)

O capital constante é aproximado pelo stock de capital, e a depreciação é
fixada em ~10% do stock em vários pontos (fora dos caminhos de dados reais,
onde já se usa CCF/stock real). Por omissão, o caminho `:eurostat` usa o
stock líquido reportado diretamente pelo Eurostat para o ano pedido.

**Corrigido (opcional):** `inventário_perpétuo=true`
(`calibrar_modelo_portugal`/`calibrar_com_ameco_v2`, com
`fonte_dados`/`dados_setoriais=:eurostat`) substitui essa leitura direta por
uma série própria calculada pelo método do inventário perpétuo (PIM —
`calcular_stock_capital_pim`, `src/eurostat_sdmx.jl`):
`Kₜ = (1-δ)·Kₜ₋₁ + FBCFₜ`, com `δ` estimado (`CCF/stock` no ano de
referência, não um valor fixo) e semeada a partir do ano mais antigo com
stock e FBCF reportados. Verificado com dados reais de Portugal: a série PIM
acompanha o stock reportado ao longo de 22 anos (2000-2022), com desvio
crescente mas moderado até ao ano mais recente (setor C: ~10% em 2022) —
esperado, já que o PIM aqui usa uma taxa de depreciação única por setor, não
diferenciada por tipo de ativo (estruturas, máquinas, TIC, etc. têm vidas
úteis muito diferentes na prática — dados de FBCF por tipo de ativo já estão
disponíveis no Eurostat, `NAMA_10_A64_P5` tem uma dimensão `asset10`, mas
construir um PIM multi-ativo exigiria também perfis de depreciação por tipo
de ativo, que a Eurostat não publica diretamente — ficou por fazer).

Degrada por setor, não globalmente: se a FBCF histórica de um setor não
chegar ao ano pedido, ou `δ` estimado não for válido, esse setor
individualmente cai para o valor reportado pelo Eurostat, sem afetar os
restantes.

---

A suite de testes (`test/runtests.jl`, 168 testes) corre localmente e em CI
(GitHub Actions, Julia 1.10 e 1, em cada push a `main`) — ver
`.github/workflows/test.yml`. Cobre os caminhos sintéticos/opt-in
por omissão; os caminhos de dados reais (`fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`, `método=:sdmx`) exigem rede e não correm em CI —
verifique-os manualmente com `verificar_sdmx_ameco()`,
`verificar_eurostat_setorial()` e `paper/matrix_audit.jl` antes de os usar
numa análise real.

## 8. Piso imposto em `e` (rate of exploitation) na calibração setorial

`estimar_parametros_setoriais` (`src/calibracao_pt.jl`) impõe `e =
max(0.1, taxa_mais_valia)`: setores cujo rendimento empresarial (após
CCF) é próximo de zero ou negativo relativamente às remunerações
produziriam `e` nulo ou negativo, que o modelo não aceita
(`Departamento` exige `e>0`). Este é um valor imposto, não uma
observação puramente empírica — a função agora reporta explicitamente
quantos setores saturam no piso (ex.: 4/19 para Portugal 2022), em vez
de o fazer silenciosamente. Não existe ainda uma tabela em anexo com os
quatro valores brutos (não-piso) lado a lado com os valores impostos, o
que fortaleceria a transparência — ver `paper/main.tex`, Secção 5.1, para
a mesma ressalva no contexto do artigo.

## 9. Formato da série de exploração/depreciação AMECO (corrigido)

`analisar_série_temporal_com_dados` (`src/ameco.jl`) usava, numa versão
anterior, uma dedução fixa de 10% do stock de capital (a preços
constantes) como "depreciação" ao calcular o excedente, em vez de
consumo de capital fixo (CCF) real — isto quebrava a invariância
algébrica que `e=(Y-V-CCF)/V` deveria ter sob um deflator comum aplicado
a `Y`, `V` e CCF em conjunto, já que o termo de 10% não escalava com o
deflator. **Corrigido:** usa-se agora a série real de CCF da AMECO
(item `UKCT`, capítulo 03-05), deflacionada de forma consistente com `V`
e `Y` em cada convenção de valorização (`valorização=:corrente`,
`:consistente` ou `:consistente_fbcf`, este último usando o deflator do
investimento em vez do deflator do PIB, para testar sensibilidade à
escolha do deflator). Verificado diretamente: `e` é agora idêntico entre
convenções para todos os anos, para Portugal e Espanha — não apenas
afirmado algebricamente.

## 10. Diferenciação automática, TSSI e bifurcações — alcance

- **Convergência do racionamento: local provada, global não.** A
  jacobiana exata (`jacobiana_racionamento`) é triangular com os setores
  ordenados por ρ*, com espetro em `[−1, 0]` (`paper/main.tex`,
  Proposição 1): a iteração amortecida converge localmente para todo
  `α ∈ (0, 1)`. Continuam em aberto a unicidade do ponto fixo e a
  convergência global a partir de qualquer ρ inicial. A Proposição
  assume o caso genérico (sem empates no mínimo que define κⱼ, nenhum
  `xᵢ/Dᵢ = 1` exato); nos empates a diferenciação automática devolve a
  derivada do ramo escolhido por `minimum`.
- **Relaxação por omissão (corrigido: 0.5 → 2/3).** Com valores próprios
  0 e −1 presentes (todos os casos do sweep), o `α` que minimiza o raio
  espectral é 2/3 (raio 1/3). Passou a ser o valor por omissão
  (`RELAXAÇÃO_PADRÃO`): ≈30% menos iterações, e a convergência longe do
  ponto fixo foi verificada empiricamente (6870 execuções por `α`, de 0.4
  a 0.95, sem falhas — `paper/main.tex`, Tabela 2), já que a Proposição 1
  só garante convergência local.
- **Hessianas através do racionamento não são suportadas.** A derivada do
  ponto fixo pelo teorema da função implícita é só de primeira ordem;
  `hessiana_sistema` funciona sem `racionamento=true`.
- **A TSSI é só uma camada de valorização.** O termo de mobilidade de
  capital continua a usar taxas de lucro simultaneístas (Sraffa); não há
  uma variante da dinâmica conduzida pela TSSI. O desfasamento τ é um só
  e fixo (não uma distribuição de tempos de rotação por setor), e a
  depreciação `d = δC/x` é valorizada a preços-base, não a preços
  históricos de aquisição.
- **Bifurcações da EDO de acumulação: só no modelo cruzado (corrigido em
  parte).** `sistema_Ndept!` e `sistema_Ndept_io!` crescem sem limite e
  não têm equilíbrios em níveis; os estados estacionários são raios de
  crescimento equilibrado, pontos fixos do sistema normalizado
  (`src/crescimento.jl`). Mas sem preços de mercado a taxa de lucro de um
  setor não depende da sua dimensão relativa: não há crescimento
  equilibrado interior (o capital concentra-se num setor), mesmo com
  `μ_v`, `realização` ou `racionamento`. Só a dinâmica cruzada opcional
  (`preços_mercado=true`, `src/cruzado.jl`) tem raios interiores, e é aí
  que `bifurcacao_acumulação` deteta Hopf e continua os ciclos-limite.
  Nos mapas (racionamento, TSSI), a classificação fold/flip/Neimark–Sacker
  é feita sobre os multiplicadores em `continuar_ponto_fixo`, porque a
  deteção do BifurcationKit assume EDOs; no racionamento, a perda de
  estabilidade em `s_c` é uma colisão de fronteira (mapa seccionalmente
  suave), localizada só à resolução do passo de continuação.
- **Sem bifurcação no mapa de preços TSSI nos casos testados** (50
  economias aleatórias, escala da mais-valia em [0.05, 10]). É uma
  verificação empírica, não uma prova de estabilidade para todo o `A`.

## 11. Dinâmica cruzada (preços de mercado) e ciclos de acumulação — alcance

- **Hipóteses do modelo cruzado.** Os preços de mercado respondem ao
  excesso de procura relativo com velocidade única `β`; os bens de capital
  são comprados na composição das colunas de A e todo o consumo num cabaz
  fixo `cesto` (por omissão, as quotas do output líquido inicial — não há
  dados de procura final por setor de origem no pipeline). Os preços são
  normalizados para que o lucro total iguale a mais-valia total. Não se
  combina com `realização` nem com `racionamento`.
- **`μ_v` (mobilidade do capital variável) está desligado por omissão.**
  Os ciclos de acumulação aparecem a partir de `μ_v ≈ 0.5–1.3` (Hopf
  supercrítico em todas as 30 economias aleatórias testadas, com
  `β = 0.1`); o valor empírico de `μ_v` não está calibrado.
- **Os ciclos aproximam-se da fronteira do simplex.** Longe do Hopf, as
  quotas setoriais descem a 10⁻³–10⁻⁴: as oscilações quase eliminam
  setores, o que é pouco plausível economicamente e indica que falta um
  mecanismo de travagem (p.ex. entrada de capital novo ou limites à
  saída).
- **Deteção de bifurcações.** Dois Hopf no mesmo passo de continuação
  escapam à deteção (`dsmax = 0.01` por omissão; `bifurcacao_acumulação`
  avisa quando a contagem de valores próprios instáveis discorda). As
  bifurcações dos ciclos (fold, duplicação de período, Neimark–Sacker)
  dependem do passo e só se consideram confirmadas quando a simulação
  direta (`ciclo_simulado`) concorda. A troca de ramo automática do
  BifurcationKit no Hopf falha (jacobiana singular); o ramo é semeado
  pelo preditor da forma normal.
- **Caos: evidência numérica, não prova.** No regime irregular, o maior
  expoente de Lyapunov (`expoentes_lyapunov`) é positivo e robusto à
  condição inicial, à tolerância de integração e à duração (e dois
  expoentes são positivos a `μ_v` alto: hipercaos), mas são estimativas
  de tempo finito, não uma demonstração assistida por computador. A
  coexistência de um ciclo estável e do toro foi verificada por
  varrimento do parâmetro nos dois sentidos (`histerese_simulada`), não
  pelas bacias de atração completas.
- **Custo.** A continuação de ciclos por colocação é lenta para N = 6
  (≈100 s), e cada estimativa de expoentes de Lyapunov leva ≈100 s; os
  testes usam horizontes curtos.
