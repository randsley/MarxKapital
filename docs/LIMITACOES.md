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

## 2. R_max no choque salarial usa uma matriz auxiliar

Em `simular_choque_salarial` (`src/choques.jl`), o `R_max` reportado é
calculado com uma matriz `A_ref` gerada só para dar uma referência de
viabilidade e com `l = ones(N)`. Não é a matriz da simulação nem os
coeficientes de trabalho reais dos departamentos. Trate o `R_max` do choque
como **ilustrativo**, não como um limite exato do cenário simulado.

Mitigação já aplicada: a mesma `seed` é passada aos dois cenários (base e
choque), pelo que as matrizes técnicas das duas simulações são idênticas e a
comparação base-vs-choque é reprodutível.

## 3. Download AMECO: URLs e formato são heurísticos

- A AMECO **não tem API REST oficial**. As URLs em `URLS_AMECO_TENTAR`
  (`src/ameco_download.jl`) são tentativas e podem estar desatualizadas — a
  Comissão muda a localização a cada atualização (Primavera/Outono).
- O parser `ler_ficheiro_ameco_txt` assume um formato de **largura fixa**
  (país 1-2, variável 4-8, sub 10-19, valores de 15 chars a partir da coluna
  21, começando em 1960). Estes offsets são um palpite razoável mas **têm de
  ser validados** contra o ficheiro real; use os parâmetros `ano_inicial`,
  `largura_campo` e `pos_dados` para ajustar.
- Os mnemónicos em `CÓDIGOS_AMECO_VARIÁVEIS` (UVGD, OVGD, etc.) seguem a
  convenção habitual mas devem ser confirmados na nomenclatura vigente.

Se o download ou o parsing falharem, `obter_dados_ameco(..., método=:auto)`
recorre silenciosamente a **dados sintéticos** (com aviso). Verifique sempre
o campo `fonte` do resultado.

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
