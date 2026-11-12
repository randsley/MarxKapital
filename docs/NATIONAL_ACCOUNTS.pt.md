# Das contas nacionais a C, V e S

*[🇬🇧 Read this in English](NATIONAL_ACCOUNTS.md)*

Como a calibração com dados reais (`calibrate_portugal_model(data_source = :eurostat)`,
`src/calibration_pt.jl`; a camada de dados em `src/eurostat_sdmx.jl`) transforma
as contas nacionais do Eurostat (SEC 2010) nos departamentos do modelo. Todas
as séries são por secção da NACE Rev. 2 (A–S), em milhões de euros a preços
correntes, salvo indicação em contrário. Os notebooks 9–12 usam as mesmas
séries, a partir do extrato estático `data/eurostat_eu_sectors.csv`.

## 1. Rubricas das contas → grandezas do modelo

| Modelo | Significado | Rubrica SEC 2010 | Fluxo de dados e chave do Eurostat | Notas |
|---|---|---|---|---|
| `V` | capital variável (salários) | D1, remunerações dos empregados | `NAMA_10_A64`, `A.CP_MEUR..D1.PT` | Opcionalmente mais o rendimento do trabalho dos independentes (§3) |
| `S` | mais-valia | B1G − D1 − P51C | VAB: `NAMA_10_A64`, `…B1G…`; CCF: `…P51C…` | Excedente de exploração líquido e rendimento misto líquido, mais os outros impostos líquidos sobre a produção (D29 − D39), que estão no VAB a preços de base |
| `e = S/V` | taxa de exploração | | | Com o piso `e_floor` (§4); `e_raw` guarda o rácio antes do piso |
| `C` | capital constante (stock) | N11N, ativos fixos líquidos | `NAMA_10_NFA_ST`, `A.CRC_MEUR..N11N.PT` (custo corrente de substituição) | Ou série própria por inventário permanente (`perpetual_inventory = true`, `docs/LIMITATIONS.pt.md` item 7). Não inclui existências |
| `k = C/V` | composição orgânica | | | |
| `δ` | taxa de depreciação | P51C / N11N | | |
| `σ_c` | parte da mais-valia reinvestida em `C` | P51G / S | FBCF: `NAMA_10_A64_P5`, `A.CP_MEUR..N11G.P51G.PT` | Limitada a [0,1; 0,7]; supõe-se `σ_v` = 0,15 |
| `l` | trabalho direto por unidade de produto | EMP_DC / B1G | `NAMA_10_A64_E`, `A.THS_PER..EMP_DC.PT` | Normalizado para máximo 1 |
| `A` | coeficientes técnicos | consumo intermédio de produção interna | `NAIO_10_CP1700`, `stk_flow = DOM` (produto × ramo) | Só anos de referência (PT: 2010, 2013, 2015, 2017, 2020); raio espectral mantido < 1 |
| procura final | | P3_S13, P3_S14 + P3_S15, P5, P6 | o mesmo quadro | `params.final_demand` |
| coeficientes de importação | | consumo intermédio importado / P1 | o mesmo quadro, linha `IMP` | `params.import_coefficients` |
| fluxos reais (notebook 12) | | B1G e P51G em volumes encadeados | `NAMA_10_A64`, `NAMA_10_A64_P5`, unidade `CLV15_MEUR` | Só rácios dentro de um setor, porque os volumes encadeados não são aditivos |

## 2. Secções NACE → tratamento no modelo

O modelo trata cada departamento que mantém como um produtor capitalista de mais-valia. Não separa o trabalho produtivo do improdutivo *dentro* dos setores que mantém. Essa distinção conta para o nível da taxa de lucro (ver abaixo).

| Secção | | `sectors = :market` | `e` bruto, PT 2022: excluídos | imputados (pessoas) | imputados (horas) |
|---|---|---|---|---|---|
| A | Agricultura, silvicultura, pesca | mantida | 1,39 | −0,20 | 0,07 |
| B | Indústrias extrativas | mantida | 0,65 | 0,47 | 0,49 |
| C | Indústrias transformadoras | mantida | 0,53 | 0,45 | 0,45 |
| D | Eletricidade, gás, vapor | mantida | −0,53 | −0,53 | −0,53 |
| E | Água, saneamento, resíduos | mantida | 0,34 | 0,33 | 0,33 |
| F | Construção | mantida | 0,33 | 0,14 | 0,12 |
| G | Comércio por grosso e a retalho | mantida | 0,53 | 0,33 | 0,34 |
| H | Transportes e armazenagem | mantida | 0,23 | 0,14 | 0,13 |
| I | Alojamento e restauração | mantida | 0,86 | 0,54 | 0,51 |
| J | Informação e comunicação | mantida | 0,22 | 0,14 | 0,14 |
| K | Atividades financeiras e de seguros | mantida | 1,51 | 1,37 | 1,39 |
| **L** | **Atividades imobiliárias** | **deixada de fora** | 8,52 | 5,04 | |
| M | Atividades de consultoria, científicas e técnicas | mantida | 0,34 | 0,05 | 0,05 |
| N | Atividades administrativas e de apoio | mantida | 0,33 | −0,04 | 0,04 |
| **O** | **Administração pública** | **deixada de fora** | −0,03 | −0,03 | |
| **P** | **Educação** | **deixada de fora** | −0,01 | −0,07 | |
| **Q** | **Saúde e apoio social** | **deixada de fora** | 0,09 | 0,02 | |
| R | Atividades artísticas e recreativas | mantida | 0,12 | −0,18 | −0,15 |
| S | Outras atividades de serviços | mantida | 0,62 | −0,12 | −0,04 |

**Porque ficam de fora L, O, P e Q** (`NON_MARKET_SECTIONS`, os mesmos 15 setores mercantis dos notebooks 9–12):

- **O, P e Q são sobretudo não mercantis.** As contas valorizam a produção não mercantil pelo seu custo, pelo que o seu excedente de exploração é, por convenção, apenas a depreciação do capital público. O seu `e` é ≈ 0 por construção, não por medição. As contas oficiais tratam a atividade pública como produção "com lucro nulo" (Shaikh 2016, cap. 4, p. 129, n. 11).
- **L é dominada pelas rendas imputadas.** A renda que os proprietários-ocupantes se considera pagarem a si próprios conta como produção, e as habitações como capital. Shaikh (2016, cap. 7) retira estes lucros e este capital "fictícios" pela mesma razão (Shaikh e Tonak 1994, pp. 253–254). Em Portugal o stock de capital de L é cerca de 15 vezes o seu VAB.

O que acontece às ligações com as secções deixadas de fora:
- O que os setores mercantis compram a L, O, P e Q (rendas, por exemplo) vem de fora da economia modelada, como as importações. É somado aos coeficientes de importação (`outside_input_coefficients`), para que a produção bruta continue a ser reconstruída corretamente a partir do valor acrescentado (`_gross_output`, `src/core.jl`).
- O que L, O, P e Q compram aos setores mercantis passa a procura exógena e é somado à procura final pública (`outside_purchases_from_iot`). Em Portugal, no quadro de 2020, são 10,4 mil milhões de euros.

**Trabalho produtivo e improdutivo.** A tradição clássica e marxista conta o comércio por grosso e a retalho, os serviços financeiros, os serviços jurídicos, a publicidade, as forças armadas e a função pública como atividades não produtivas. Os seus custos são pagos pela mais-valia produzida noutros setores, não se somam a ela (Shaikh 2016, cap. 4, pp. 129–130; Shaikh e Tonak 1994; Mohun 2005). Com essa contabilidade, a taxa de lucro medida pelo excedente de exploração convencional é uma fração estável da clássica (Shaikh 2016, p. 130). `sectors = :market` só faz parte do caminho: deixa de fora as secções não mercantis, mas mantém G e K como departamentos que produzem mais-valia. É uma limitação do modelo, não uma tese sobre eles.

## 3. Os trabalhadores independentes

O excedente bruto de exploração inclui o rendimento misto dos independentes, que é em parte um salário. `self_employed` decide como é tratado:

- `:excluded` (por omissão): `V` = D1 tal como publicado. Todo o rendimento dos independentes conta como mais-valia, o que sobrestima `e` onde o trabalho independente é comum (A: 1,39).
- `:imputed`: cada independente ganha a remuneração média dos empregados da sua secção, `V × EMP_DC / SAL_DC` em pessoas. É o método de Shaikh e Tonak (1994, pp. 110–113), usado na parte salarial ajustada do AMECO (Shaikh 2016, cap. 7, n. 31).
- `:imputed_hours`: o mesmo por hora trabalhada (`THS_HW`, `fetch_eurostat_sector_hours`). Um agricultor que trabalha parte do ano conta menos. Sobe a agricultura de −0,20 para 0,07, mas quase não mexe em M, N, R e S, onde imputar um salário à taxa do empregado médio deixa pouca ou nenhuma mais-valia.

## 4. O piso de `e`

`Department` exige `e > 0`, pelo que a calibração usa `e = max(e_floor, e_raw)` (`e_floor = 0,1` por omissão; `docs/LIMITATIONS.pt.md` item 8). O piso cobre três coisas diferentes, que as opções separam:

| Portugal, 2022 | Setores no piso | `r` agregado, com o piso (bruto) |
|---|---|---|
| 19 secções, excluídos (por omissão) | 4 de 19: D, O, P, Q | 6,12% (5,80%) |
| 19 secções, imputados | 9 de 19: A, D, M, N, O, P, Q, R, S | 4,65% (3,70%) |
| `sectors = :market`, excluídos | 1 de 15: D | 11,27% (11,18%) |
| `:market`, `e_years = 5`, excluídos | 1 de 15: R | 11,09% (11,03%) |
| `:market`, `e_years = 5`, imputados | 5 de 15: A, M, N, R, S | 7,79% (6,59%) |
| `:market`, `e_years = 5`, `:imputed_hours` | 5 de 15: A, M, N, R, S | 7,66% (6,98%) |

- **As secções não mercantis** explicam O, P e Q. `sectors = :market` retira-as, e com elas L, cujo enorme stock de capital é o que mantém a taxa de lucro agregada perto de 6%.
- **Anos excecionais:** o −0,53 da eletricidade em 2022 é a crise energética (5,4–6,8 em 2015–2019). `e_years` calcula `e` a partir de somas sobre vários anos; cinco anos (2018–2022) dão D 3,70. Uma janela de três anos (2020–2022) é dominada pela pandemia, que põe os transportes (H) e as artes (R) abaixo do piso, pelo que a janela deve ser longa o bastante para cobrir um ciclo inteiro.
- **A imputação:** com os independentes contados a um salário, A, M, N, R e S ficam com `e` em zero ou abaixo. A margem líquida estreita está nas contas, não no método. O piso fixa então o seu `e` em 0,1, o que é uma escolha de modelação; `e_raw` guarda o valor medido.

## Referências

- Mohun, S. (2005). On measuring the wealth of nations: the US economy, 1964–2001. *Cambridge Journal of Economics*, 29(5), 799–815.
- Shaikh, A. (2016). *Capitalism: Competition, Conflict, Crises*. Oxford University Press.
- Shaikh, A. e Tonak, E. A. (1994). *Measuring the Wealth of Nations: The Political Economy of National Accounts*. Cambridge University Press.
