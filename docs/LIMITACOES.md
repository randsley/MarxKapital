# Limitações conhecidas e trabalho pendente

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

**Parcialmente corrigido:** `sistema_Ndept_io!` (`src/nucleo.jl`), selecionável
com `acoplado=true` em `simular_Ndept`/`simular_Ndept_customizado`, acopla A à
dinâmica através de um termo de mobilidade de capital `μ·(rᵢ − r̄)·Cᵢ`, com `rᵢ`
calculado sobre capital valorizado a preços de produção de Sraffa (que dependem
de A), em vez do `e/(k+1)` nu. `sistema_Ndept!` mantém-se como versão por
omissão ("setores independentes"), inalterada, por compatibilidade.

**Parcialmente corrigido (segundo mecanismo, opcional):** `sistema_Ndept_io!`
aceita agora `realização=true` (transportado via `p.realização`, kwarg de
`simular_Ndept`/`simular_Ndept_customizado`), que acresce uma pressão de
realização: define-se o output bruto por setor `Oᵢ=Cᵢ+Vᵢ+Sᵢ` e a procura
intermédia implícita em A, `(A·O)ᵢ`; a razão de realização agregada
`ρ_real = Σ min(Oᵢ,(A·O)ᵢ) / Σ(A·O)ᵢ` (≤ 1) escala o reinvestimento planeado
(`σ_c,ᵢ·Sᵢ`), travando a acumulação quando a estrutura técnica não consegue
sustentar os níveis de output correntes. Verificado por teste
(`test/runtests.jl`, "Simulação N-dept com pressão de realização") e por
robustez em 20 combinações seed/μ sem falhas do solver.

**Explicitamente fora de alcance (não confundir com o acima):** um
tratamento exato — níveis de output resolvidos como restrições algébricas a
cada instante (haveria de facto realização setor a setor, não só uma pressão
agregada) — exigiria transformar o sistema numa equação
algébrico-diferencial (DAE), com dependências novas
(`DifferentialEquations.jl` tem suporte a DAE, ou `NonlinearSolve.jl`). Não
implementado; a pressão de realização acima é uma aproximação suave que se
mantém uma EDO comum.

`verificar_equilibrio_Ndept(sol, p)` (`src/analise.jl`) generaliza
`verificar_equilibrio_2dept` a N setores: devolve o desvio `Oᵢ−(A·O)ᵢ` por
setor e `ρ_real` num dado instante, a posteriori (não realimenta a
dinâmica por si só — é o `sistema_Ndept_io!` com `realização=true` que usa a
mesma lógica dentro da EDO). À semelhança do modelo de 2 departamentos (cujo
`verificar_equilibrio_2dept` também só verifica a posteriori, sem realimentar
`sistema_2dept!`), a consistência de reprodução setor a setor continua a não
ser imposta de forma exata — só a pressão agregada.

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

## 4. Calibração AMECO é macro (3 setores), com pesos fixos por omissão (corrigido, com ressalva)

`calibrar_com_dados_ameco` só implementa a agregação `:macro`
(Primário/Secundário/Terciário). Por omissão (`dados_setoriais=:fixo`), a
repartição do PIB, do emprego e do stock de capital por setor usa **pesos
fixos por país** codificados em `_dist_setorial_vab`,
`_dist_setorial_emprego` e `[0.10, 0.35, 0.55]`. São aproximações; países
sem perfil específico caem no perfil médio da UE.

**Corrigido (opcional):** `dados_setoriais=:eurostat` usa VAB, remunerações,
consumo de capital fixo, emprego, FBCF e stock de capital **reais** do
Eurostat (`src/eurostat_sdmx.jl`, dataflows `NAMA_10_A64`, `NAMA_10_A64_E`,
`NAMA_10_A64_P5`, `NAMA_10_NFA_ST`), agregados às 3 secções macro. Só cobre
países da UE/EEE; fora dessa cobertura, ou se o pedido (dados ou matriz A)
falhar, cai silenciosamente (com aviso) para os pesos fixos e A aleatória —
nunca lança erro.

**Matriz A real — corrigido, com ressalva conhecida:** a via direta
(agregar os fluxos brutos do IOT do Eurostat a apenas 3 grupos) foi tentada
e rejeitada numa sessão anterior — a agregação a 3 grupos mistura de forma
enganadora as margens de comércio/transporte (ver item 4-bis) com os
restantes 11 setores de serviços, deixando a linha do Terciário
implausivelmente pequena mesmo depois de tratar as margens negativas célula
a célula. A correção que resultou: em vez de agregar os fluxos brutos,
constrói-se primeiro a matriz real aos 19 setores finos (já limpa e
não-negativa — item 4-bis) e agrega-se essa matriz de **coeficientes**
(não fluxos brutos) aos 3 grupos pela fórmula padrão de agregação de
Leontief (`agregar_matriz_io`, `src/eurostat_sdmx.jl`):
`A₃[gi,gj] = Σ A₁₉[i,j]·VAB[j] / Σ VAB[j]` (soma ponderada por VAB dentro do
grupo `j`). Verificado com dados reais de Portugal 2022: matriz não-negativa,
ρ(A)≈0.11. **Ressalva honesta:** isto evita reintroduzir o problema das
margens (já não há valores negativos), mas não o resolve na origem — a
linha do Terciário na matriz agregada continua a refletir o mesmo
subdimensionamento herdado da matriz de 19 setores (ver item 4-bis), só que
já não se manifesta como números inválidos. Uma melhoria real e mais
trabalhosa exigiria combinar tabelas de oferta e utilização (que mantêm as
margens como linha própria) em vez do IOT simétrico — não tentado.

## 4-bis. Matriz técnica A real (Eurostat IOT) — 19 setores (INE) e 3 setores macro (AMECO, agregada)

`construir_matriz_io_eurostat` (`src/eurostat_sdmx.jl`) constrói `A` a
partir do IOT simétrico do Eurostat (`NAIO_10_CP1620`), usado por
`calibrar_modelo_portugal(..., fonte_dados=:eurostat)` (19 setores CAE —
ver item 5) e, agregada via `agregar_matriz_io`, por
`calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` (3 setores macro —
ver item 4). Verificado com dados reais de Portugal: matriz não-negativa,
ρ(A)≈0.12-0.15 consoante o ano, estável em 2018/2020/2022. A tabela regista
margens de comércio/transporte por vezes como fluxos negativos (convenção
normal de contabilidade nacional, confirmada: 100% das ~300 células
negativas de PT/2022 estão confinadas às secções de comércio/transporte
como fornecedoras) — tratadas célula a célula (não na matriz agregada) antes
de somar, para não apagar fluxos genuínos de outros setores. Ver item 4 para
como a agregação a 3 setores macro reutiliza esta matriz (já limpa) em vez
de agregar os fluxos brutos do IOT diretamente.

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
  macro, dados e matriz `A` reais (ver item 4 para a ressalva sobre a linha
  do Terciário na matriz agregada).

Continua a ser necessário pedir explicitamente estes modos — o comportamento
por omissão em ambos os caminhos mantém-se sintético/pesos fixos, por
compatibilidade com o comportamento histórico e para manter a suite de
testes totalmente offline (ver `verificar_eurostat_setorial()` para uma
verificação manual, fora dos testes automáticos).

## 7. Stock de capital e depreciação são aproximados

O capital constante é aproximado pelo stock de capital, e a depreciação é
fixada em ~10% do stock em vários pontos. Uma calibração séria exigiria
séries de stock de capital líquido por setor (método do inventário perpétuo)
e taxas de depreciação diferenciadas.

---

A suite de testes (`test/runtests.jl`, 39 testes) corre localmente e em CI
(GitHub Actions, Julia 1.10 e 1, em cada push a `main`) — ver
`.github/workflows/test.yml`. Cobre os caminhos sintéticos/opt-in
por omissão; os caminhos de dados reais (`fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`, `método=:sdmx`) exigem rede e não correm em CI —
verifique-os manualmente com `verificar_sdmx_ameco()` e
`verificar_eurostat_setorial()` antes de os usar numa análise real.
