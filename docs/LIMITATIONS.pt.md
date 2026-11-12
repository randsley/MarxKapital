# Limitações conhecidas e trabalho pendente

*[🇬🇧 Read this in English](LIMITATIONS.md)*

Este ficheiro documenta, sem rodeios, o que ainda não está correto ou
completo. Nenhum destes pontos impede a execução, mas todos afetam a
interpretação dos resultados.

## 1. A matriz técnica A não realimenta a dinâmica de N departamentos

Em `system_Ndept!` (ficheiro `src/core.jl`), a acumulação de cada
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

**Corrigido:** `system_Ndept_io!` (`src/core.jl`), selecionável
com `coupled=true` em `simulate_Ndept`/`simulate_Ndept_custom`, acopla A à
dinâmica através de um termo de mobilidade de capital `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ`
calculado sobre capital valorizado a preços de produção de Sraffa (que dependem
de A), em vez do `e/(k+1)` nu. `system_Ndept!` mantém-se como versão por
omissão ("setores independentes"), inalterada, por compatibilidade.
`r̄` é a média de `r` ponderada por `C` (não a razão agregada `ΣS/Σ(C+V)`,
usada até uma correção posterior) — a única escolha para a qual
`Σᵢ μ(rᵢ-r̄)Cᵢ = 0` exatamente, garantindo que o termo de mobilidade
realoca capital constante agregado entre setores em vez de o criar ou
destruir. Verificado por teste (`test/runtests.jl`, "Capital mobility — exact conservation").

**Corrigido (segundo mecanismo, opcional):** `system_Ndept_io!`
aceita agora `realization=true` (transportado via `p.realization`, kwarg de
`simulate_Ndept`/`simulate_Ndept_custom`), que acresce uma pressão de
realização escalando o reinvestimento planeado por
`ρ_real = Σ min(xᵢ,(A·x)ᵢ) / Σ(A·x)ᵢ` (≤ 1), travando a acumulação quando
a estrutura técnica não consegue sustentar os níveis de output correntes.
`xᵢ` é o output bruto **genuíno**, não o fluxo tipo valor-acrescentado
`Wᵢ=δᵢCᵢ+Vᵢ+Sᵢ` (capital constante *transferido*, não o stock `Cᵢ`) usado
numa correção anterior: `Wᵢ` omite o consumo intermédio circulante que a
matriz `A` efetivamente precifica. Reconstrói-se `xᵢ` a partir da própria
identidade custo-output do modelo — ver mais abaixo, "Corrigido (output
bruto genuíno...)". Verificado por teste
(`test/runtests.jl`, "N-dept simulation with realization pressure") e por
robustez em 20 combinações seed/μ sem falhas do solver.

**Corrigido (terceiro mecanismo, exato por setor, opcional):**
`system_Ndept_io!` aceita agora `rationing=true` (tem precedência sobre
`realization`), que resolve **racionamento de quantidades por setor** — não
apenas uma pressão agregada. A expansão de output *desejada* de cada setor
`j`, `Δxⱼ=σ_c,ⱼ·Sⱼ·xⱼ/Cⱼ` (investimento planeado convertido para escala de
output via o rácio capital-output corrente, não a despesa `σ_c,ⱼSⱼ`
diretamente — uma correção posterior, ver abaixo), exige inputs dos
fornecedores na proporção `A[:,j]` (tecnologia
Leontief, sem substituição entre inputs), pelo que o reinvestimento
realizado fica limitado pelo input mais escasso — e o racionamento sofrido
por um setor reduz a sua procura efetiva de TODOS os seus inputs, afetando
por sua vez o racionamento dos seus fornecedores. Resolve-se por iteração de
ponto fixo (`_solve_rationing`, `src/core.jl`):

```
κⱼ = min_{i: A[i,j]>0} ρᵢ          (limitado pelo input mais escasso)
Dᵢ = Σⱼ A[i,j]·κⱼ·Δxⱼ               (demand efetiva, já consistente com o rationing)
ρᵢ = min(1, xᵢ / Dᵢ)               (regra do side curto)
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
"Market rationing (fixed point)": `ρ₁=√0.8`, verificado à mão) e por
robustez em 20 combinações seed/μ (N=8) e em N=19, sem falhas de
convergência nem do solver da EDO.

`check_equilibrium_Ndept(sol, p)` (`src/analysis.jl`) generaliza
`check_equilibrium_2dept` a N setores: devolve o *resíduo de uso
intermédio* `xᵢ−(A·x)ᵢ` por setor e `ρ_real` (a versão agregada) num dado
instante, a posteriori — não é uma medida de desequilíbrio ou de
mercado (um resíduo positivo é o caso normal em contabilidade
input-output: output disponível para consumo, exportações, etc., que
este diagnóstico não modela), e não usa o racionamento por setor (esse
já está embutido em `κ` dentro de `system_Ndept_io!` quando
`rationing=true`).

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
usadas nestas simulações; a matriz real de uso doméstico do Eurostat omite
importações por definição, que os coeficientes de importação opcionais
repõem, ver o fim deste item). A condição de admissibilidade `Σᵢ A[i,j]<1` (necessária
para o denominador ser positivo) não é garantida por `ρ(A)<1`
(que limita o raio espectral, não qualquer soma de coluna individual);
verificada e corrigida uma única vez quando a simulação é montada
(`_ensure_output_admissibility`, `src/core.jl`), reescalando `A`
uniformemente se necessário, com aviso — não um clamp silencioso
reaplicado a cada avaliação. Verificado por teste
(`test/runtests.jl`, "Reconstructed gross output..." e "Admissibility of the gross output reconstruction").

**Corrigido (procura de investimento em escala de output, não despesa):**
o `Δxⱼ` na fórmula do racionamento acima substitui uma versão anterior
que aplicava `A[i,j]` diretamente à despesa de investimento planeada
`σ_c,ⱼSⱼ`, como se uma unidade de despesa exigisse a mesma composição de
inputs que uma unidade de output físico — um problema dimensional
identificado em revisão externa. `Δxⱼ=σ_c,ⱼSⱼ·xⱼ/Cⱼ` converte a despesa
para uma expansão de output via o rácio capital-output corrente do
setor, antes de `A` ser aplicada. Por omissão, todo o `xᵢ` reconstruído
é tratado como disponível para a procura de investimento `Dᵢ`, sem
descontar a reposição de inputs intermédios (já contada em `zᵢ`) nem
outra procura final.

**Corrigido em parte (opcional):** as colunas de utilização final da
mesma IOT (`NAIO_10_CP1700`, uso doméstico) dão a procura final por
produto (`final_demand_from_iot`, `fetch_eurostat_final_demand`), agora
guardada em `params.final_demand` nos caminhos Eurostat. Com
`final_demand_share = exogenous_demand_share(params.final_demand)` em
`simulate_Ndept_custom` (e `A = params.A`), o racionamento compara `Dᵢ`
com `(1 − φᵢ)·xᵢ`, onde `φᵢ` é a parcela do output que vai para consumo
final e exportações. Para Portugal 2022 (artigo, Secção 5.7, Tabela 4),
isto não altera a parcela de setores racionados e reduz a acumulação em
cerca de um quinto com 10 e 19 setores. Continua em aberto: a reposição
intermédia não é descontada, pelo que `Dᵢ≤(1−φᵢ)xᵢ` continua a ser um
limite superior à oferta investível, não um balanço de reprodução
totalmente líquido.

**Corrigido (inputs importados, opcional):** a matriz do Eurostat só cobre
inputs domésticos, pelo que o `xᵢ` reconstruído a partir dela deixava de
fora os inputs intermédios importados. A própria linha `IMP` da IOT dá-os
por ramo comprador, e `fetch_eurostat_import_coefficients` converte-os em
coeficientes `mⱼ = IMPⱼ/P1ⱼ`, guardados em `params.import_coefficients` nos
caminhos Eurostat (agregados com os mesmos pesos de VAB que as colunas de
A). Com `import_coefficients` em `simulate_Ndept_custom` (e `A = params.A`),
o output bruto é `xⱼ = Wⱼ/(1 − Σᵢ A[i,j] − mⱼ)` (`_gross_output`), e a
verificação de admissibilidade passa a cobrir `Σᵢ A[i,j] + mⱼ`. Para
Portugal (IOT de 2020), a indústria transformadora importa inputs no valor
de 35% do seu output, e o `x` reconstruído é 2,3 vezes o que a matriz
doméstica sozinha implica; nas outras secções, 1,01 a 1,38 vezes. Com
racionamento (artigo, Tabela 4), a parte de setores racionados não muda,
mas a acumulação em 30 anos sobe 8% com 10 setores (×200,6 → ×215,9) e 31%
com 19 (×72,4 → ×94,7). É opcional, pelo que os números do artigo não
mudam. Não está disponível no modelo cross-dual (`market_prices`), cujos
lucros precisariam também de um preço das importações, nem na camada TSSI.

## 2. R_max no choque salarial usa uma matriz auxiliar (corrigido)

Em `simulate_wage_shock` (`src/shocks.jl`), o `R_max` reportado era
calculado com uma matriz `A_ref` gerada só para dar uma referência de
viabilidade e com `l = ones(N)` — não a matriz da simulação nem os
coeficientes de trabalho reais dos departamentos.

**Corrigido:** `R_max` passou a usar `p_base.A` (a matriz técnica
efetivamente devolvida por `simulate_Ndept_custom` para o cenário base)
e `l = [d.v for d in depts]` (coeficientes de trabalho proporcionais a V,
mesma convenção usada em `system_Ndept_io!`). O valor de viabilidade
reportado corresponde agora ao cenário simulado, não a uma referência
auxiliar.

Mitigação já aplicada (mantida): a mesma `seed` é passada aos dois cenários
(base e choque), pelo que as matrizes técnicas das duas simulações são
idênticas e a comparação base-vs-choque é reprodutível.

## 3. Download AMECO (corrigido: API SDMX oficial substitui o ficheiro TXT)

**Contexto histórico:** esta secção descrevia as URLs heurísticas do antigo
ficheiro TXT estático (`AMECO_URLS_TO_TRY`, `src/ameco_download.jl`) e o
parser de largura fixa (`read_ameco_txt_file`). Confirmado em 2026-07 que
essa distribuição foi **descontinuada pela Comissão Europeia** — todas as
URLs devolvem 404 ou redirecionam para a página HTML do portal, nunca dados.

**Corrigido:** a AMECO passou a expor uma **API REST SDMX oficial**
(`src/ameco_sdmx.jl`, `webgate.ec.europa.eu/ecfin/redisstat`, a mesma
plataforma da nova ferramenta de dados do Eurostat). `fetch_ameco_data`
(métodos `:auto`/`:sdmx`/`:download`) usa-a como caminho automático por
omissão. Verificado com chamadas reais (2026-07): PIB, emprego, remunerações,
FBCF e stock de capital líquido de Portugal, devolvidos corretamente desde
1960. Os mnemónicos em `AMECO_VARIABLE_CODES` (UVGD, OVGD, etc.)
confirmaram-se válidos como código `ITEM` nesta API, sem necessidade de
remapear. Os códigos de país precisaram de um mapeamento próprio
(`AMECO_SDMX_COUNTRY_CODES`), maioritariamente ISO3 mas com irregularidades
reais (GRC não EL, GBR não UK, ROM não ROU).

**Resolvido (quase por completo):** `AMECO_SDMX_MAP` mapeia agora 22 das 25
variáveis de `AMECO_VARIABLE_CODES`, mais 2 séries calculadas a partir de
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
PIB (calculado, `GDP_current/GDP_constant×100`, não pedido à API) e
balança comercial (calculada, exportações menos importações de **bens**
apenas — capítulo 11-01, itens `DXGT`/`DMGT`, `UNIT=99`; distinta de
`exports`/`imports`, que cobrem bens e serviços). Os valores obtidos
para Portugal batem com figuras reais conhecidas (défice 2022 ≈ -0.3% do
PIB, desemprego 2022 ≈ 6.2%, dívida pública 2022 ≈ 111% do PIB).

**Confirmado indisponível (não "pendente"):** stock de capital bruto. Só o
capítulo de stock líquido (`AMECO_CHAPTER08-01`) existe nesta API, sem
equivalente bruto publicado — verificado por wildcard completo dos itens do
capítulo, não apenas por não ter sido encontrado à primeira tentativa.

**Nota importante:** vários mnemónicos que estavam em `AMECO_VARIABLE_CODES`
(nunca antes verificados) revelaram-se **incorretos** contra a API real —
por exemplo `UUTG` estava atribuído a `government_revenue` mas é na realidade
`government_expenditure` (as duas trocadas), e `private_consumption`/`exports`/
`imports` usavam mnemónicos (`UNCT`/`UXTG`/`UMTG`) que já não existem na
API atual (os corretos são `UCPH`/`UXGS`/`UMGS`). `AMECO_SDMX_MAP` usa os
códigos corrigidos; `AMECO_VARIABLE_CODES` (`types.jl`, usado só pelo
parser TXT legado) não foi alterado — continua a ser heurístico, como sempre
se avisou.

Só o stock de capital bruto (confirmado indisponível, ver acima) fica
ausente do resultado (preenchido a 0.0 por `build_ameco_data`, sem
erro). Corra `check_ameco_sdmx()` manualmente (não faz parte dos testes
automáticos, para não depender de rede em CI) antes de confiar nos dados
numa análise real.

O antigo caminho TXT/CSV (`read_ameco_txt_file`, `parse_ameco_csv`,
métodos `:local`/`:csv`) mantém-se disponível para quem já tenha um ficheiro
descarregado manualmente, mas deixou de ser o caminho automático.

Se todas as vias falharem, `fetch_ameco_data(..., method=:auto)` recorre
silenciosamente a **dados sintéticos** (com aviso). Verifique sempre o campo
`source` do resultado.

## 4. Calibração AMECO é macro (3 setores), com pesos fixos por omissão (corrigido)

`calibrate_with_ameco_data` só implementa a agregação `:macro`
(Primário/Secundário/Terciário). Por omissão (`sector_data=:fixed`), a
repartição do PIB, do emprego e do stock de capital por setor usa **pesos
fixos por país** codificados em `_sector_gva_shares`,
`_sector_employment_shares` e `_sector_stock_shares`. São aproximações; países
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
caminho INE (item 8). Em `compare_ameco_countries`, as colunas `GDP` e
`Wage_Share` mediam afinal o capital adiantado `Σ(C+V)` e `ΣV/Σ(C+V)`;
medem agora o VAB e `ΣV/ΣVAB`.

**Corrigido (valorização do capital):** este caminho dividia o stock de
capital líquido do AMECO (`OKND`, a preços constantes de 2020) pelas
remunerações a preços correntes, pelo que `k` descia a cada ano de inflação
depois de 2020: em 2024 ficava 17–25% abaixo do valor certo na Alemanha, em
Portugal e na Polónia. O stock é agora revalorizado ao custo de substituição
corrente com o deflator da FBCF (`PIGT`, 2020 = 100), a base de preços do
stock do Eurostat no caminho `:eurostat`, e o `k` calibrado é igual a
`analyze_time_series_with_data(...; valuation = :consistent_gfcf)`.
**Trabalhadores por conta própria (opcional):** as remunerações dos
empregados deixam de fora os trabalhadores por conta própria, cujo
rendimento passa a contar como mais-valia e sobrestima `e` (em 2024, cerca
de 1,8 vezes na Grécia e em Itália). `self_employed = :imputed` conta cada um
deles com a remuneração média de um empregado, como faz a parte salarial
ajustada do AMECO. É opcional e está disponível em todos os caminhos de
dados reais: em `:fixed` com o rácio agregado do AMECO; em `sector_data =
:eurostat` e em `calibrate_portugal_model(...; data_source = :eurostat)` por
secção NACE, a partir dos empregados (`SAL_DC`) e do emprego (`EMP_DC`) do
Eurostat, imputado nas 19 secções antes de qualquer agregação
(`impute_self_employed`). O trabalho por conta própria é muito desigual: em
Portugal, 2022, o fator é 2,98 na agricultura, 1,84 nos outros serviços e
1,58 nas atividades imobiliárias, mas 1,05 na indústria transformadora. A
imputação baixa o `e` agregado de 0,45 para 0,26 e `r` de 5,8% para 3,7%.
Supõe que os trabalhadores por conta própria ganham o mesmo que os
empregados da sua secção; onde o rendimento misto fica aquém disso
(agricultura: `e` bruto −0,20), `e` fica negativo e mais setores batem no
piso do item 8. Contam-se pessoas, não horas trabalhadas.

**Corrigido (opcional):** `sector_data=:eurostat` usa VAB, remunerações,
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
Leontief (`aggregate_io_matrix`, `src/eurostat_sdmx.jl`):
`A₃[gi,gj] = Σ A₁₉[i,j]·GVA[j] / Σ GVA[j]` (soma ponderada por VAB dentro do
grupo `j`). A ressalva sobre a linha do Terciário que constava aqui numa
versão anterior descrevia um sintoma da tabela errada usada nessa altura
(ver item 4-bis) — resolvida, não contornada, com a correção do dataflow.

## 4-bis. Matriz técnica A real — dataflow errado, encontrado e corrigido

**Histórico do bug (2026-07/08):** uma auditoria pedida em revisão externa
(quantificar o efeito de um passo de "clipping" de margens, reconciliar
totais publicados, documentar a correspondência CPA↔NACE, resolver a
questão doméstico-vs-total-uso) revelou algo mais fundamental do que
qualquer uma dessas perguntas: `build_eurostat_io_matrix`
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

**Corrigido:** `build_eurostat_io_matrix` usa agora `NAIO_10_CP1700`
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
para o ano de referência mais próximo (`_nearest_iot_year`), com
aviso — pelo que a matriz `A` de um pedido para 2022, por exemplo, tem
na prática vintage 2020 (ver `paper/main.tex`, Secção 4.2, para como o
artigo separa explicitamente os resultados de 2020 e 2022 em vez de os
misturar).

Usada por `calibrate_portugal_model(..., data_source=:eurostat)` (19
setores CAE — ver item 5) e, agregada via `aggregate_io_matrix`, por
`calibrate_with_ameco_v2(..., sector_data=:eurostat)` (3 setores macro
— ver item 4). Verificação completa (frequência de rescala de admissibilidade,
reconciliação, questão doméstico/importado) em `paper/matrix_audit.jl`,
corrido manualmente contra a API ao vivo.

## 5. `aggregation` na calibração INE não está totalmente ligada (corrigido)

`calibrate_portugal_model` aceitava o argumento `aggregation` mas só corria em
`:detailed` (19 setores); os modos `:medium` e `:macro` eram ignorados
silenciosamente.

**Corrigido:** `:macro` agrega aos mesmos 3 setores usados no caminho AMECO
(`NACE_MACRO_GROUPS`); `:medium` agrega a 10 setores, o nível padrão NACE
Rev.2 "A10" (`NACE_MEDIUM_GROUPS`, `src/eurostat_sdmx.jl`) — uma agregação
reconhecida, não inventada. `aggregate_sectors` (`src/calibration_pt.jl`) soma
as variáveis de fluxo por grupo e agrega `A` pela mesma fórmula de Leontief
do item 4 — funciona tanto com `data_source=:synthetic` (A aleatória) como
`:eurostat` (A real), sem distinção de código entre os dois casos.
Verificado: as 6 combinações (`:detailed`/`:macro`/`:medium` ×
`:synthetic`/`:eurostat`) produzem matrizes não-negativas com ρ(A)<1.

## 6. Todos os dados por omissão são SINTÉTICOS (dados reais agora opcionais)

Tanto o caminho INE como o AMECO usam, **por omissão**, dados **gerados** com
padrões plausíveis. Servem para demonstração, testes e desenvolvimento
metodológico — **não para análise empírica publicável** nesse modo.

**Dados reais disponíveis (opt-in):**
- INE: `calibrate_portugal_model(data_source=:eurostat, aggregation=:detailed|:macro|:medium)`
  — 19, 3 ou 10 setores, dados e matriz técnica `A` reais (ver item 4-bis e item 5).
- AMECO: `calibrate_with_ameco_v2(..., sector_data=:eurostat)` — 3 setores
  macro, dados e matriz `A` reais (ver item 4).

Continua a ser necessário pedir explicitamente estes modos — o comportamento
por omissão em ambos os caminhos mantém-se sintético/pesos fixos, por
compatibilidade com o comportamento histórico e para manter a suite de
testes totalmente offline (ver `check_eurostat_sectoral()` para uma
verificação manual, fora dos testes automáticos).

## 7. Stock de capital e depreciação são aproximados (corrigido, com ressalva)

O capital constante é aproximado pelo stock de capital. A depreciação vem
dos dados sempre que estes existem: os caminhos de dados reais e o caminho
AMECO de pesos fixos usam o consumo de capital fixo (CCF) reportado, e os
dados INE sintéticos fixam o CCF como uma parcela do VAB. Nenhum caminho
usa ainda 10% fixos do stock. Por omissão, o caminho `:eurostat` usa o
stock líquido reportado diretamente pelo Eurostat para o ano pedido.

**Corrigido (opcional):** `perpetual_inventory=true`
(`calibrate_portugal_model`/`calibrate_with_ameco_v2`, com
`data_source`/`sector_data=:eurostat`) substitui essa leitura direta por
uma série própria calculada pelo método do inventário perpétuo (PIM —
`compute_pim_capital_stock`, `src/eurostat_sdmx.jl`):
`Kₜ = (1-δ)·Kₜ₋₁ + GFCFₜ`, com `δ` estimado (`CFC/stock` no ano de
referência, não um valor fixo) e semeada a partir do ano mais antigo com
stock e FBCF reportados. Verificado com dados reais de Portugal (2026-10):
a série PIM fica abaixo do stock reportado, 15% no agregado em 2010 e 28% em
2022. Por setor, o desvio em 2022 vai de +11% (agricultura, A) a −36%
(atividades imobiliárias, L); a indústria transformadora (C) está em −10%.
Os maiores desvios estão nos setores dominados por edifícios e estruturas
(L, O, G, K, Q), o que é coerente com a principal simplificação: o PIM aqui
usa uma taxa de depreciação única por setor, estimada por CCF/stock, e não
uma por tipo de ativo (estruturas, máquinas, TIC, etc. têm vidas
úteis muito diferentes na prática — dados de FBCF por tipo de ativo já estão
disponíveis no Eurostat, `NAMA_10_A64_P5` tem uma dimensão `asset10`, mas
construir um PIM multi-ativo exigiria também perfis de depreciação por tipo
de ativo, que a Eurostat não publica diretamente — ficou por fazer).

Degrada por setor, não globalmente: se a FBCF histórica de um setor não
chegar ao ano pedido, ou `δ` estimado não for válido, esse setor
individualmente cai para o valor reportado pelo Eurostat, sem afetar os
restantes.

---

A suite de testes (`test/runtests.jl`, 464 testes) corre localmente e em CI
(GitHub Actions, Julia 1.10 e 1, em cada push a `main`) — ver
`.github/workflows/test.yml`. Cobre os caminhos sintéticos/opt-in
por omissão; os caminhos de dados reais (`data_source=:eurostat`,
`sector_data=:eurostat`, `method=:sdmx`) exigem rede e não correm em CI —
verifique-os manualmente com `check_ameco_sdmx()`,
`check_eurostat_sectoral()` e `paper/matrix_audit.jl` antes de os usar
numa análise real.

## 8. Piso imposto em `e` (taxa de exploração) na calibração setorial (documentado)

`estimate_sector_parameters` (`src/calibration_pt.jl`) impõe `e =
max(0.1, surplus_value_rate)`: setores cujo rendimento empresarial (após
CCF) é próximo de zero ou negativo relativamente às remunerações
produziriam `e` nulo ou negativo, que o modelo não aceita
(`Department` exige `e>0`). Este é um valor imposto, não uma
observação puramente empírica — a função agora reporta explicitamente
quantos setores saturam no piso (ex.: 4/19 para Portugal 2022), em vez
de o fazer silenciosamente.

**Documentado:** `CalibratedParameters` traz agora também `e_raw`, o rácio
antes do piso (nos caminhos INE e AMECO), e o artigo mostra os valores
brutos e impostos lado a lado (`paper/main.tex`, Secção 5.1, Tabela 3,
gerada por `paper/generate_results.jl`). Para Portugal 2022, os quatro
setores no piso são a eletricidade (`e` bruto ≈ −0,53), a administração
pública, a educação (ambas ligeiramente negativas) e a saúde (≈ 0,09). O
piso quase não mexe no agregado: `r = ΣS/Σ(C+V)` é 6,12% com ele e 5,80%
com os rácios brutos. O piso mantém-se, porque `Department` exige
`e > 0`. Com os trabalhadores por conta própria imputados (`self_employed =
:imputed`, item 4), o piso aplica-se a 9 dos 19 setores em vez de 4: a
agricultura (A), as atividades de consultoria (M) e administrativas (N), as
artes (R) e os outros serviços (S) juntam-se aos quatro acima, pelo que o
piso pesa mais nesse caminho.

## 9. Formato da série de exploração/depreciação AMECO (corrigido)

`analyze_time_series_with_data` (`src/ameco.jl`) usava, numa versão
anterior, uma dedução fixa de 10% do stock de capital (a preços
constantes) como "depreciação" ao calcular o excedente, em vez de
consumo de capital fixo (CCF) real — isto quebrava a invariância
algébrica que `e=(Y-V-CFC)/V` deveria ter sob um deflator comum aplicado
a `Y`, `V` e CCF em conjunto, já que o termo de 10% não escalava com o
deflator. **Corrigido:** usa-se agora a série real de CCF da AMECO
(item `UKCT`, capítulo 03-05), deflacionada de forma consistente com `V`
e `Y` em cada convenção de valorização (`valuation=:current`,
`:consistent` ou `:consistent_gfcf`, este último usando o deflator do
investimento em vez do deflator do PIB, para testar sensibilidade à
escolha do deflator). Verificado diretamente: `e` é agora idêntico entre
convenções para todos os anos, para Portugal e Espanha — não apenas
afirmado algebricamente.

## 10. Diferenciação automática, TSSI e bifurcações — alcance

- **Convergência do racionamento: local provada, global não.** A
  jacobiana exata (`rationing_jacobian`) é triangular com os setores
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
  (`DEFAULT_RELAXATION`): ≈30% menos iterações, e a convergência longe do
  ponto fixo foi verificada empiricamente (6870 execuções por `α`, de 0.4
  a 0.95, sem falhas — `paper/main.tex`, Tabela 2), já que a Proposição 1
  só garante convergência local.
- **Hessianas através do racionamento (corrigido).** A derivada do ponto
  fixo pelo teorema da função implícita era só de primeira ordem, pelo que
  `system_hessian` falhava com `rationing=true`. `_rationing_fixed_point`
  (`src/core.jl`) aplica agora o teorema da função implícita uma vez por
  nível de `Dual`: o nível interior devolve ρ* com a sua primeira derivada,
  e diferenciar a fórmula de primeira ordem nesse ponto dá a segunda
  derivada exata (de facto, qualquer ordem). Verificado contra diferenças
  finitas do Jacobiano exato (concordância de cerca de 10⁻⁸ em três
  economias aleatórias de 6–8 setores com racionamento ativo) e contra a
  forma fechada do exemplo de 2 setores. É a Hessiana do ramo ativo: o mapa
  é suave por troços, pelo que não está definida em empates em κ nem em
  `ρᵢ = 1`, tal como o Jacobiano.
- **A TSSI é só uma camada de valorização.** O termo de mobilidade de
  capital continua a usar taxas de lucro simultaneístas (Sraffa); não há
  uma variante da dinâmica conduzida pela TSSI. O desfasamento τ é um só
  e fixo (não uma distribuição de tempos de rotação por setor).
- **Depreciação a custo histórico (resolvido, opcional).** Por omissão, a
  depreciação `d = δC/x` é valorizada a preços-base.
  `tssi_valuation(...; depreciation = :historical)` mantém em vez disso um
  valor contabilístico do capital fixo por setor: o investimento bruto é
  comprado ao preço TSSI do passo anterior do bem de capital do setor (o
  preço ponderado pela coluna de `A`), a depreciação retira `δh` do valor
  contabilístico e as alienações saem ao custo médio contabilístico. `d`
  passa a ser o valor contabilístico consumido por unidade de produto. Os
  invariantes continuam a valer à precisão da máquina; numa simulação
  acoplada de 6 setores, o rácio valor contabilístico/`C` fica entre 0,95
  e 1,16 e a taxa de lucro TSSI muda menos de 0,2 pontos.
- **Bifurcações da EDO de acumulação: só no modelo cruzado (corrigido em
  parte).** `system_Ndept!` e `system_Ndept_io!` crescem sem limite e
  não têm equilíbrios em níveis; os estados estacionários são raios de
  crescimento equilibrado, pontos fixos do sistema normalizado
  (`src/growth.jl`). Mas sem preços de mercado a taxa de lucro de um
  setor não depende da sua dimensão relativa: não há crescimento
  equilibrado interior (o capital concentra-se num setor), mesmo com
  `μ_v`, `realization` ou `rationing`. Só a dinâmica cruzada opcional
  (`market_prices=true`, `src/cross_dual.jl`) tem raios interiores, e é aí
  que `accumulation_bifurcation` deteta Hopf e continua os ciclos-limite.
  Nos mapas (racionamento, TSSI), a classificação fold/flip/Neimark–Sacker
  é feita sobre os multiplicadores em `continue_fixed_point`, porque a
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
  fixo `basket`: por omissão, as quotas do output líquido inicial, uma
  hipótese; numa calibração com dados reais,
  `consumption_basket(params.final_demand)` dá as quotas reais do consumo
  das famílias (com `A = params.A`). Para Portugal 2022, o cabaz real sobe
  a taxa de crescimento equilibrado de cerca de 0,14 para 0,19 com 10 e 19
  setores e não altera a estabilidade (artigo, Secção 5.7). Os preços são
  normalizados para que o lucro total iguale a mais-valia total. Não se
  combina com `realization` nem com `rationing`.
- **`μ` é constante; os dados dizem que não é.** O notebook 8 estima o
  coeficiente de mobilidade do capital a partir dos fluxos de capital na
  UE27 (financiamento externo líquido contra o diferencial de taxa de lucro
  desfasado, 1996–2024). Entre países, no período inteiro, `μ̂` ≈ 0,33 sem
  os centros financeiros, perto do valor por omissão de 0,3. De ano para
  ano dentro de cada país é nulo em média: 0,15 antes de 2008 e −0,27
  depois. O `μ` constante do modelo corresponde ao padrão de longo prazo,
  não à resposta numa crise de crédito. Entre os próprios departamentos do
  modelo, os setores, o notebook 9 conclui que `μ` não é identificado
  (Portugal, 15 setores de mercado, 2002–2023). Os setores não têm registo
  do capital transferido, pelo que este é construído como o investimento
  líquido para além de uma parte comum do excedente próprio. Dentro de cada
  setor, com efeitos de setor e de ano, `μ̂` ≈ 0,11 (erro de Driscoll–Kraay
  0,05) contando o rendimento dos trabalhadores por conta própria como
  mais-valia, mas −0,19 a −0,35 imputando-o como salário: o excedente entra
  dos dois lados da equação. Os diferenciais setoriais persistentes não
  atraem capital (`μ̂` = −0,31 entre setores).
  O notebook 10 repete a estimativa nos 15 setores de mercado de 26 países
  da UE, com efeitos país × ano que absorvem o ciclo de crédito de cada
  país (`compute_mobility_panel`, `estimate_mobility`). Aí `μ̂` ≈ −0,14
  (erro agrupado por país 0,05), com quaisquer efeitos fixos, com o
  diferencial instrumentado pelo seu desfasamento (−0,12), e negativo em 21
  de 26 países; o 0,11 de Portugal é a exceção. Não é sobretudo erro de
  medida: o investimento líquido sobe com o diferencial (0,08), mas menos
  do que uma parte comum de reinvestimento do excedente do setor exigiria
  (0,21). O que os dados rejeitam é o `σ_c` comum a todos os departamentos
  do modelo, que obriga toda a resposta do investimento à rentabilidade a
  passar por `μ`. Uma parte reinvestida que difira entre departamentos, ou
  que caia com a taxa de lucro, permitiria estimar `μ` líquido dela. A
  aparente quebra em 2008 (`μ̂` −0,16 antes, −0,06 depois, com efeitos
  comuns) tem a mesma origem: a resposta do investimento líquido ao
  diferencial é estável, e a parte reinvestida líquida de amortizações caiu
  para metade (0,19 para 0,10); a parte bruta, o `σ_c` do modelo, não mudou
  (as amortizações subiram; notebook 11). Portanto, o que os dados rejeitam
  não é um `μ` constante no tempo. O notebook 11 estima a função de
  investimento do modelo com uma parte reinvestida que cai com a
  rentabilidade relativa, `σ_c·(r̄/rᵢ)^η`: `μ̂` é então positivo para
  qualquer `η` (0,05 a 0,13), mas o painel não identifica `η`; o
  investimento segue o excedente próprio a cerca de um décimo da parte
  média, o que calibra `η` ≈ 1 e dá `μ̂` = 0,13 (erro 0,04). No modelo,
  `η` = 1 com esse `μ` deixa os setores pouco rentáveis acumular até a taxa
  de lucro chegar a zero: a função de investimento calibrada precisa de uma
  saída para o capital pouco rentável, e de `η` no sistema cruzado, antes
  de poder ser usada em simulações de longo prazo.
- **O termo de mobilidade usa a taxa de lucro média, e os dados
  concordam.** Shaikh (2016, cap. 7) defende que a concorrência iguala a
  taxa incremental, o rendimento do investimento novo, pelo que as taxas
  médias podem diferir para sempre. O notebook 12 mede-a no painel da UE
  (`compute_incremental_panel`, `estimate_persistence`): os diferenciais
  da taxa incremental são sobretudo transitórios (4–14% da sua variância é
  entre unidades país × setor, contra 74–78% nos diferenciais da taxa
  média), mas não se igualam (uma dispersão permanente de 6–8 pp líquida
  de ruído, metade dos 14–15 pp das taxas médias), e têm muito ruído, com
  um enviesamento mecânico do investimento passado no denominador. O
  capital segue o diferencial da taxa média: na função de investimento com
  `η` = 1, `μ̂` = 0,14 (erro 0,03), enquanto o diferencial incremental
  move o investimento um terço por desvio-padrão e nada acrescenta quando
  entram os dois. Dentro de um departamento do modelo, os rendimentos
  constantes tornam iguais as taxas marginal e média, pelo que o modelo
  não muda; os diferenciais médios persistentes dos dados (gerações de
  capital, o que as contas contam como capital) pertencem à técnica
  calibrada de cada departamento, e as estimativas de `μ` absorvem-nos nos
  efeitos país × setor.
- **Parte reinvestida (opcional).** `simulate_Ndept_custom(...; η, σ_schedule)`
  substitui o `σ_c` fixo de cada departamento por `σ_c,ᵢ·m(t)·(r̄/rᵢ)^η`:
  uma elasticidade `η` da parte reinvestida à rentabilidade relativa (0 =
  parte fixa, por omissão) e um multiplicador `m(t)` constante por troços
  (`σ_schedule`). Os notebooks 10–11 justificam `η`: com uma parte fixa o
  painel da UE dá um `μ̂` negativo. A parte reinvestida bruta não mudou
  depois de 2008, pelo que os dados não pedem um calendário; fica
  disponível para cenários. Só no sistema acoplado sem preços de mercado: no sistema
  cruzado os lucros a preços de mercado podem ser ≤ 0, pelo que `(r̄/rᵢ)^η`
  não está definido (ainda não suportado). Um calendário torna o sistema não
  autónomo, pelo que as ferramentas de crescimento equilibrado e de
  bifurcação o rejeitam.
- **`μ_v` (mobilidade do capital variável) está desligado por omissão.**
  Os ciclos de acumulação aparecem a partir de `μ_v ≈ 0.5–1.3` (Hopf
  supercrítico em todas as 30 economias aleatórias testadas, com
  `β = 0.1`); o valor empírico de `μ_v` não está calibrado.
- **Os ciclos aproximam-se da fronteira do simplex (resolvido em parte:
  fricção de saída opcional).** Longe do Hopf, as quotas setoriais descem
  a 10⁻³–10⁻⁴ (10⁻⁵ em `μ_v = 2.4`): as oscilações quase eliminam
  setores, o que é pouco plausível economicamente. `exit_friction = ε > 0`
  (`simulate_Ndept`, `simulate_Ndept_custom`, ou `p.exit_friction`;
  parâmetro de continuação `:exit_friction` em `with_parameter`) amortece
  cada saída dos termos de mobilidade por `sᵢ/(sᵢ + ε)`, `sᵢ` a quota do
  setor, e escala as entradas por um fator comum para que o termo continue
  a somar exatamente 0 (`_mobility_flow`). Na economia de
  referência do artigo (β = 0.1), `ε = 0.05` eleva a menor quota em
  `μ_v = 2.4` de 9,5·10⁻⁶ para 4,3·10⁻³ (de 5,8·10⁻⁴ para 5,8·10⁻³ em
  `μ_v = 2.0`), desloca para cima o primeiro ponto de Hopf (a estabilidade
  perde-se perto de `μ_v ≈ 1.2` em vez de 1.05) e muda o regime que
  prevalece para um dado `μ_v`, mas os ciclos mantêm-se (artigo, Secção
  5.6). Por omissão
  `ε = 0`, pelo que os restantes resultados do artigo não mudam. A forma
  funcional e `ε` são hipóteses, não estimativas, e a entrada de capital
  novo não é modelada.
- **Deteção de bifurcações.** Dois Hopf no mesmo passo de continuação
  escapam à deteção (`dsmax = 0.01` por omissão; `accumulation_bifurcation`
  avisa quando a contagem de valores próprios instáveis discorda). As
  bifurcações dos ciclos (fold, duplicação de período, Neimark–Sacker)
  dependem do passo e só se consideram confirmadas quando a simulação
  direta (`simulated_cycle`) concorda. A troca de ramo automática do
  BifurcationKit no Hopf falha (jacobiana singular); o ramo é semeado
  pelo preditor da forma normal.
- **Caos: evidência numérica, não prova.** No regime irregular, o maior
  expoente de Lyapunov (`lyapunov_exponents`) é positivo e robusto à
  condição inicial, à tolerância de integração e à duração (e dois
  expoentes são positivos a `μ_v` alto: hipercaos), mas são estimativas
  de tempo finito, não uma demonstração assistida por computador. A
  coexistência de um ciclo estável e do toro foi verificada por
  varrimento do parâmetro nos dois sentidos (`simulated_hysteresis`), não
  pelas bacias de atração completas.
- **Custo.** A continuação de ciclos por colocação é lenta para N = 6
  (≈100 s), e cada estimativa de expoentes de Lyapunov leva ≈100 s; os
  testes usam horizontes curtos.

## 12. Anos de previsão da AMECO (corrigido)

A AMECO publica as previsões da Comissão para o ano da edição e o seguinte
nas mesmas séries que os dados observados, e nada na resposta SDMX as
assinala: `OBS_STATUS` é `A` em todos os anos. Pedir anos até 2027 à edição
da primavera de 2026 devolvia, sem aviso, as previsões de 2026 e 2027, pelo
que uma calibração para 2026, ou uma série temporal que lá chegasse, usava
previsões como se fossem dados.

**Corrigido:** o ano da edição lê-se da coluna `LAST UPDATE` da resposta
SDMX (`_release_year`) e, no caminho SDMX, `fetch_ameco_data` retira os
anos a partir do ano da edição, com aviso (`_drop_forecast_years`). O
último ano observado fica registado em `data.notes["last_actual_year"]`.
Um ano de calibração para lá dele recua para esse ano, com aviso.
`include_forecasts=true` (em `fetch_ameco_data`, `calibrate_with_ameco_v2`
e `analyze_ameco_time_series`) mantém as previsões. Testado offline
(`test/runtests.jl`, "AMECO forecast years").

**Ressalva:** os ficheiros TXT/CSV legados não trazem data de edição, pelo
que nesses caminhos não se retira nenhum ano. A regra assume o calendário
habitual da AMECO (edições de primavera e outono, cada uma com previsões
para o ano corrente e o seguinte). O último ano observado é ele próprio
provisório e pode ser revisto em edições posteriores. Se não for possível
ler o ano da edição de `LAST UPDATE` (coluna em falta ou num formato
desconhecido), não se retira nenhum ano e `fetch_ameco_data` avisa que as
previsões não podem ser identificadas, em vez de as manter em silêncio
(`_apply_forecast_rule`).
