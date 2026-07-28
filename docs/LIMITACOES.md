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

O que **ainda não** está feito: a condição de realização/consistência de
reprodução (a procura de capital constante do setor i ser satisfeita pelo
output real dos fornecedores) não é imposta na dinâmica — só o efeito de
mobilidade de capital sobre taxas de lucro díspares. À semelhança do modelo de
2 departamentos (cujo `verificar_equilibrio_2dept` também só verifica a
posteriori, sem realimentar `sistema_2dept!`), não existe ainda um mecanismo de
compensação de oferta/procura setorial dentro da EDO. Validado por teste
(`test/runtests.jl`, "Simulação N-dept acoplada") que a dispersão das taxas de
lucro entre setores diminui ao longo do tempo sob mobilidade de capital.

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

**Trabalho pendente (parcialmente resolvido):** `MAPA_AMECO_SDMX` mapeia
agora 20 das 25 variáveis de `CÓDIGOS_AMECO_VARIÁVEIS`, verificadas com
chamadas reais em 2026-07: além das 6 originais (PIB corrente/constante,
emprego total, remunerações, FBCF, stock de capital líquido), acrescentaram-se
consumo privado/público, exportações, importações, emprego assalariado, taxa
de desemprego, população ativa, remunerações por assalariado, produtividade
do trabalho, IPC, receitas/despesas do governo, saldo orçamental e balança
corrente. Os valores obtidos para Portugal batem com figuras reais conhecidas
(défice 2022 ≈ -0.3% do PIB, desemprego 2022 ≈ 6.2%).

**Nota importante:** vários mnemónicos que estavam em `CÓDIGOS_AMECO_VARIÁVEIS`
(nunca antes verificados) revelaram-se **incorretos** contra a API real —
por exemplo `UUTG` estava atribuído a `receitas_governo` mas é na realidade
`despesas_governo` (as duas trocadas), e `consumo_privado`/`exportações`/
`importações` usavam mnemónicos (`UNCT`/`UXTG`/`UMTG`) que já não existem na
API atual (os corretos são `UCPH`/`UXGS`/`UMGS`). `MAPA_AMECO_SDMX` usa os
códigos corrigidos; `CÓDIGOS_AMECO_VARIÁVEIS` (`estruturas.jl`, usado só pelo
parser TXT legado) não foi alterado — continua a ser heurístico, como sempre
se avisou.

Ainda por confirmar: custos unitários de trabalho (indexados — a API exige um
ano de referência específico que não se identificou), deflator do PIB (não
encontrado como item próprio no capítulo do PIB), dívida pública, balança
comercial e stock de capital bruto. Ficam simplesmente ausentes do resultado
(preenchidos a 0.0/NaN por `construir_dados_ameco`, sem erro) até serem
confirmados. Corra `verificar_sdmx_ameco()` manualmente (não faz parte dos
testes automáticos, para não depender de rede em CI) antes de confiar nos
dados numa análise real.

O antigo caminho TXT/CSV (`ler_ficheiro_ameco_txt`, `processar_csv_ameco`,
métodos `:local`/`:csv`) mantém-se disponível para quem já tenha um ficheiro
descarregado manualmente, mas deixou de ser o caminho automático.

Se todas as vias falharem, `obter_dados_ameco(..., método=:auto)` recorre
silenciosamente a **dados sintéticos** (com aviso). Verifique sempre o campo
`fonte` do resultado.

## 4. Calibração AMECO é macro (3 setores), com pesos fixos por omissão (parcialmente corrigido)

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
países da UE/EEE; fora dessa cobertura, ou se o pedido falhar, cai
silenciosamente (com aviso) para os pesos fixos — nunca lança erro.

**Ainda não corrigido:** a matriz técnica `A` desta via **mantém-se sempre
aleatória** (`criar_matriz_tecnica`), mesmo com `dados_setoriais=:eurostat`.
Tentou-se construir `A` a partir do IOT simétrico real do Eurostat
(`NAIO_10_CP1620`) agregado aos 3 setores macro (mesma técnica usada com
sucesso no caminho INE de 19 setores — ver item 4-bis abaixo), mas a
agregação a apenas 3 grupos mistura de forma enganadora as margens de
comércio/transporte (ver item 4-bis) com os restantes 11 setores de
serviços: mesmo depois de tratar as margens negativas célula a célula (não
apenas na matriz final), a linha do Terciário como fornecedor ficou
implausivelmente pequena (ordens de grandeza abaixo do Secundário), sinal de
que a maior parte do que a tabela regista sob comércio/transporte é margem,
não fornecimento direto. Não se encontrou uma forma fiável de separar as
duas coisas só com este dataflow — ficou documentado como trabalho pendente,
não usado por não haver confiança suficiente na fidelidade do resultado.

## 4-bis. Matriz técnica A real (Eurostat IOT) — implementada só para 19 setores

`construir_matriz_io_eurostat` (`src/eurostat_sdmx.jl`) constrói `A` a
partir do IOT simétrico do Eurostat (`NAIO_10_CP1620`), usado por
`calibrar_modelo_portugal(..., fonte_dados=:eurostat)` (19 setores CAE —
ver item 5). Verificado com dados reais de Portugal: matriz não-negativa,
ρ(A)≈0.12-0.15 consoante o ano, estável em 2018/2020/2022. A tabela regista
margens de comércio/transporte por vezes como fluxos negativos (convenção
normal de contabilidade nacional, confirmada: 100% das ~300 células
negativas de PT/2022 estão confinadas às secções de comércio/transporte
como fornecedoras) — tratadas célula a célula (não na matriz agregada) antes
de somar, para não apagar fluxos genuínos de outros setores. Ver item 4 para
a razão por que isto não se generalizou à agregação de 3 setores macro.

## 5. `agregação` na calibração INE não está totalmente ligada

`calibrar_modelo_portugal` aceita o argumento `agregação` mas só corre em
`:detalhada` (19 setores). Os modos `:média` e `:macro` do INE não estão
implementados nesta versão.

## 6. Todos os dados por omissão são SINTÉTICOS (dados reais agora opcionais)

Tanto o caminho INE como o AMECO usam, **por omissão**, dados **gerados** com
padrões plausíveis. Servem para demonstração, testes e desenvolvimento
metodológico — **não para análise empírica publicável** nesse modo.

**Dados reais disponíveis (opt-in):**
- INE: `calibrar_modelo_portugal(fonte_dados=:eurostat)` — 19 setores CAE,
  dados reais Eurostat, incluindo matriz técnica `A` real (ver item 4-bis).
- AMECO: `calibrar_com_ameco_v2(..., dados_setoriais=:eurostat)` — 3 setores
  macro, dados reais Eurostat (exceto `A`, ver item 4).

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

A suite de testes (`test/runtests.jl`, 33 testes) corre localmente e em CI
(GitHub Actions, Julia 1.10 e 1, em cada push a `main`) — ver
`.github/workflows/test.yml`. Cobre os caminhos sintéticos/opt-in
por omissão; os caminhos de dados reais (`fonte_dados=:eurostat`,
`dados_setoriais=:eurostat`, `método=:sdmx`) exigem rede e não correm em CI —
verifique-os manualmente com `verificar_sdmx_ameco()` e
`verificar_eurostat_setorial()` antes de os usar numa análise real.
