# Registo de alterações

Formato baseado em Keep a Changelog. Versionamento semântico.

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
