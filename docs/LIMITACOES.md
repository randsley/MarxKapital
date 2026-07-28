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

**Trabalho pendente:** `MAPA_AMECO_SDMX` só mapeia, para já, as 6 variáveis
que `calibrar_com_dados_ameco` efetivamente lê (PIB corrente/constante,
emprego total, remunerações, FBCF, stock de capital líquido) — as restantes
~17 variáveis de `CÓDIGOS_AMECO_VARIÁVEIS` (consumo, comércio externo,
finanças públicas, preços) ainda não têm capítulo/item SDMX confirmado;
ficam simplesmente ausentes do resultado (preenchidas a 0.0/NaN por
`construir_dados_ameco`, sem erro) até serem verificadas e acrescentadas ao
mapa. Corra `verificar_sdmx_ameco()` manualmente (não faz parte dos testes
automáticos, para não depender de rede em CI) antes de confiar nos dados numa
análise real.

O antigo caminho TXT/CSV (`ler_ficheiro_ameco_txt`, `processar_csv_ameco`,
métodos `:local`/`:csv`) mantém-se disponível para quem já tenha um ficheiro
descarregado manualmente, mas deixou de ser o caminho automático.

Se todas as vias falharem, `obter_dados_ameco(..., método=:auto)` recorre
silenciosamente a **dados sintéticos** (com aviso). Verifique sempre o campo
`fonte` do resultado.

## 4. Calibração AMECO é macro (3 setores) com pesos fixos

`calibrar_com_dados_ameco` só implementa a agregação `:macro`
(Primário/Secundário/Terciário). A repartição do PIB, do emprego e do stock
de capital por setor usa **pesos fixos por país** codificados em
`_dist_setorial_vab`, `_dist_setorial_emprego` e `[0.10, 0.35, 0.55]`. São
aproximações; países sem perfil específico caem no perfil médio da UE.

## 5. `agregação` na calibração INE não está totalmente ligada

`calibrar_modelo_portugal` aceita o argumento `agregação` mas só corre em
`:detalhada` (19 setores). Os modos `:média` e `:macro` do INE não estão
implementados nesta versão.

## 6. Todos os dados por omissão são SINTÉTICOS

Tanto o caminho INE como o AMECO usam, por omissão, dados **gerados** com
padrões plausíveis. Servem para demonstração, testes e desenvolvimento
metodológico — **não para análise empírica publicável**. Para resultados
reais é necessário ligar dados oficiais (ficheiro AMECO TXT/CSV real, ou
Quadros de Recursos e Empregos do INE).

## 7. Stock de capital e depreciação são aproximados

O capital constante é aproximado pelo stock de capital, e a depreciação é
fixada em ~10% do stock em vários pontos. Uma calibração séria exigiria
séries de stock de capital líquido por setor (método do inventário perpétuo)
e taxas de depreciação diferenciadas.

---

Nada disto foi verificado por execução no ambiente onde o pacote foi montado
(sem Julia instalado). Recomenda-se correr `julia install_deps.jl` seguido de
`julia --project=. test/runtests.jl` antes do primeiro uso sério.
