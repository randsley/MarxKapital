# MarxKapital: Portuguese → English name glossary

In v1.0.0 the whole codebase moved from Portuguese to English names: functions, types, struct fields, constants, keyword arguments, symbol values, returned fields, source files and data strings. It is a clean break, with no aliases: code written against v0.8.x must be updated using the tables below.

## Conventions

- **Spelling** is US English, matching the README: labor, analyze, modeling.
- **Verb prefixes** are translated literally: calcular_ → compute_, simular_ → simulate_, obter_ → fetch_ (network), verificar_ → check_, criar_ → create_, exemplo_ → example_, plotar_ → plot_.
  - Noun-style names (`profit_rates(...)`) are more idiomatic Julia. They would clash with locals of the same name (`profit_rates = profit_rates(...)`), so the verb prefixes stay.
- **National-accounts acronyms** use the English uppercase forms: VAB → GVA, FBCF → GFCF, CCF → CFC, EBE → GOS, PIB → GDP, IPC → CPI.
  - INE, AMECO, NACE, SDMX, IOT, PIM and TSSI stay as they are.
- **Math notation is unchanged**: `C, V, S, e, k, r, A, l, λ, σ_c, σ_v, γ, δ, μ, μ_v, β, ω, θ, κ, ρ, τ, R_max, N`. So are dimension tags: `2dept`, `Ndept`, `_io`.
- **Marxian terms**:
  - Departamento → Department
  - mais-valia → surplus value
  - taxa de mais-valia → surplus-value rate
  - composição orgânica → organic composition
  - valores-trabalho → labor values
  - preços de produção → production prices
  - problema da transformação → transformation problem
  - crescimento equilibrado → balanced growth
  - dinâmica cruzada → cross-dual
  - racionamento → rationing
  - realização → realization
  - numerário → numeraire
- **Data strings are translated too**:
  - AMECO country names (`"Alemanha"` → `"Germany"`; `fetch_ameco_data("Germany")`).
  - Sector names (the official English NACE Rev.2 titles).
  - The keys of `AMECO_VARIABLE_CODES`.
- **No shadowing**: a target that is already a Base or library name in a scope that calls it gets another name. For example `nomes` → `name_list`, because `names(df)` is called nearby; `valor` → `amount`, because of `ForwardDiff.value`. Kwargs such as `values`, `step` and `order` are checked one scope at a time during the rename.
- **Kept as is** are external names (Plots, BifurcationKit, DifferentialEquations and SDMX field names such as `OBS_VALUE`, `nace_r2`, `stk_flow`), names that are already English, and short math or loop locals.

## Decisions

1. `códigos_cae` → `nace_codes`: the codes are NACE section letters (CAE Rev.3 = NACE Rev.2 at that level).
2. Verb prefixes stay (see above), rather than noun names for the pure computations.
3. `src/visualizacao.jl` → `plotting.jl`; `src/exemplos.jl` → `examples.jl`.
4. `calibrar_com_ameco_v2` → `calibrate_with_ameco_v2`, keeping its `v2`.
5. Docs are English-primary: `CHANGELOG.md` + `CHANGELOG.pt.md`, `docs/LIMITATIONS.md` + `.pt.md` (formerly `LIMITACOES`), `docs/PROJECT_STATUS.md` + `.pt.md` (formerly `ESTADO_DO_PROJETO`). Past CHANGELOG entries keep their Portuguese identifiers, because they describe old versions.
6. The version is **v1.0.0** (clean break).


## Files (17)

| Portuguese | English | Note |
|---|---|---|
| `src/estruturas.jl` | `src/types.jl` |  |
| `src/nucleo.jl` | `src/core.jl` |  |
| `src/analise.jl` | `src/analysis.jl` |  |
| `src/distributiva.jl` | `src/distribution.jl` |  |
| `src/choques.jl` | `src/shocks.jl` |  |
| `src/diferenciacao.jl` | `src/differentiation.jl` |  |
| `src/cruzado.jl` | `src/cross_dual.jl` |  |
| `src/crescimento.jl` | `src/growth.jl` |  |
| `src/bifurcacao.jl` | `src/bifurcation.jl` |  |
| `src/calibracao_pt.jl` | `src/calibration_pt.jl` |  |
| `src/visualizacao.jl` | `src/plotting.jl` |  |
| `src/exemplos.jl` | `src/examples.jl` |  |
| `paper/gerar_resultados.jl` | `paper/generate_results.jl` |  |
| `paper/jacobiana_bifurcacao.jl` | `paper/jacobian_bifurcation.jl` |  |
| `paper/acumulacao_bifurcacao.jl` | `paper/accumulation_bifurcation.jl` |  |
| `paper/figures/acumulacao_stats.tex` | `paper/figures/accumulation_stats.tex` |  |
| `notebooks/limpar_saidas.jl` | `notebooks/strip_outputs.jl` |  |

## Types (4)

| Portuguese | English | Note |
|---|---|---|
| `Departamento` | `Department` | Marx's "Department I/II" |
| `ParâmetrosCalibrados` | `CalibratedParameters` |  |
| `DadosINE` | `INEData` |  |
| `DadosAMECO` | `AMECOData` |  |

## Struct fields (43)

| Portuguese | English | Note |
|---|---|---|
| `nome` | `name` |  |
| `nomes_setores` | `sector_names` |  |
| `códigos_cae` | `nace_codes` | CAE Rev.3 = NACE Rev.2 at section level |
| `VAB` | `GVA` | valor acrescentado bruto = gross value added |
| `fonte` | `source` |  |
| `ano_base` | `base_year` |  |
| `data_calibração` | `calibration_date` |  |
| `qualidade_ajuste` | `fit_quality` |  |
| `ano` | `year` |  |
| `qre` | `supply_use` | quadro de recursos e empregos = supply and use table |
| `contas_setor` | `sector_accounts` |  |
| `emprego` | `employment` |  |
| `fbcf` | `gfcf` |  |
| `metadados` | `metadata` | field/local; DataFrames.metadata: check |
| `país` | `country` |  |
| `código_país` | `country_code` |  |
| `anos` | `years` |  |
| `PIB` | `GDP` |  |
| `PIB_real` | `real_GDP` |  |
| `consumo_privado` | `private_consumption` |  |
| `consumo_público` | `public_consumption` |  |
| `FBCF` | `GFCF` | formação bruta de capital fixo = gross fixed capital formation |
| `exportações` | `exports` |  |
| `importações` | `imports` |  |
| `emprego_assalariado` | `employees` |  |
| `desemprego` | `unemployment` |  |
| `população_ativa` | `labor_force` |  |
| `remunerações` | `compensation` | compensation of employees |
| `produtividade` | `productivity` |  |
| `custos_unitários_trabalho` | `unit_labor_costs` |  |
| `deflator_PIB` | `GDP_deflator` |  |
| `deflator_FBCF` | `GFCF_deflator` |  |
| `IPC` | `CPI` |  |
| `CCF` | `CFC` | consumo de capital fixo = consumption of fixed capital |
| `receitas_governo` | `government_revenue` |  |
| `despesas_governo` | `government_expenditure` |  |
| `saldo_orçamental` | `budget_balance` |  |
| `dívida_pública` | `public_debt` |  |
| `balança_corrente` | `current_account` |  |
| `balança_comercial` | `trade_balance` |  |
| `stock_capital_total` | `total_capital_stock` |  |
| `data_download` | `download_date` |  |
| `notas` | `notes` |  |

## Constants (18)

| Portuguese | English | Note |
|---|---|---|
| `ANOS_IOT_CONHECIDOS` | `KNOWN_IOT_YEARS` |  |
| `CÓDIGOS_AMECO_VARIÁVEIS` | `AMECO_VARIABLE_CODES` | keys translated too (GDP_current, ...) |
| `CÓDIGOS_GRUPOS_MEDIO` | `MEDIUM_GROUP_CODES` |  |
| `CÓDIGOS_PAÍSES_AMECO` | `AMECO_COUNTRY_CODES` | keys become English country names |
| `CÓDIGOS_PAÍSES_AMECO_SDMX` | `AMECO_SDMX_COUNTRY_CODES` |  |
| `GRUPOS_MACRO_NACE` | `NACE_MACRO_GROUPS` |  |
| `GRUPOS_MEDIO_NACE` | `NACE_MEDIUM_GROUPS` |  |
| `MAPA_AMECO_SDMX` | `AMECO_SDMX_MAP` |  |
| `NOMES_GRUPOS_MEDIO` | `MEDIUM_GROUP_NAMES` | values translated |
| `RELAXAÇÃO_PADRÃO` | `DEFAULT_RELAXATION` |  |
| `SECÇÕES_NACE` | `NACE_SECTIONS` |  |
| `SETORES_CAE_PT` | `PT_SECTORS` | sector names become the official English NACE titles; paper's NACE_EN dict becomes redundant |
| `URLS_AMECO_TENTAR` | `AMECO_URLS_TO_TRY` |  |
| `URL_AMECO_PORTAL` | `AMECO_PORTAL_URL` |  |
| `URL_BASE_EUROSTAT_SDMX` | `EUROSTAT_SDMX_BASE_URL` |  |
| `URL_BASE_SDMX_AMECO` | `AMECO_SDMX_BASE_URL` |  |
| `TODAS` | `RUN_ALL` | test/notebooks.jl |
| `RUÍDO` | `NOISE` |  |

## Public functions (99)

| Portuguese | English | Note |
|---|---|---|
| `agregar_matriz_io` | `aggregate_io_matrix` |  |
| `agregar_setores` | `aggregate_sectors` |  |
| `ajuda_modelo` | `model_help` |  |
| `analisar_convergencia` | `analyze_convergence` |  |
| `analisar_série_temporal_ameco` | `analyze_ameco_time_series` |  |
| `analisar_série_temporal_com_dados` | `analyze_time_series_with_data` |  |
| `bifurcacao_acumulação` | `accumulation_bifurcation` |  |
| `bifurcacao_racionamento` | `rationing_bifurcation` |  |
| `bifurcacao_tssi` | `tssi_bifurcation` |  |
| `calcular_composicoes_organicas` | `compute_organic_compositions` |  |
| `calcular_precos_producao` | `compute_production_prices` |  |
| `calcular_stock_capital_pim` | `compute_pim_capital_stock` |  |
| `calcular_taxa_lucro_maxima` | `compute_max_profit_rate` |  |
| `calcular_taxa_media_lucro` | `compute_average_profit_rate` |  |
| `calcular_taxas_lucro` | `compute_profit_rates` |  |
| `calcular_taxas_lucro_precos` | `compute_price_profit_rates` |  |
| `calcular_valores_trabalho` | `compute_labor_values` |  |
| `calibrar_com_ameco_v2` | `calibrate_with_ameco_v2` |  |
| `calibrar_com_dados_ameco` | `calibrate_with_ameco_data` |  |
| `calibrar_modelo_portugal` | `calibrate_portugal_model` |  |
| `ciclo_simulado` | `simulated_cycle` |  |
| `com_parâmetro` | `with_parameter` |  |
| `comparar_choques_salariais` | `compare_wage_shocks` |  |
| `comparar_países_ameco` | `compare_ameco_countries` |  |
| `comparar_tssi_simultaneo` | `compare_tssi_simultaneous` |  |
| `construir_dados_ameco` | `build_ameco_data` |  |
| `construir_matriz_io_eurostat` | `build_eurostat_io_matrix` |  |
| `continuar_ponto_fixo` | `continue_fixed_point` |  |
| `crescimento_equilibrado` | `balanced_growth` |  |
| `criar_departamentos` | `create_departments` |  |
| `criar_departamentos_de_params` | `departments_from_params` |  |
| `criar_matriz_tecnica` | `create_technical_matrix` |  |
| `curva_hopf` | `hopf_curve` |  |
| `curva_salario_lucro` | `wage_profit_curve` |  |
| `curvatura_fronteira` | `frontier_curvature` |  |
| `descarregar_ameco_automatico` | `download_ameco_auto` |  |
| `descarregar_ameco_sdmx` | `download_ameco_sdmx` |  |
| `estabilidade_tssi` | `tssi_stability` |  |
| `estado_cruzado` | `cross_dual_state` |  |
| `estimar_parametros_setoriais` | `estimate_sector_parameters` |  |
| `exemplo_2dept` | `example_2dept` |  |
| `exemplo_Ndept` | `example_Ndept` |  |
| `exemplo_ameco_portugal` | `example_ameco_portugal` |  |
| `exemplo_comparação_grandes_economias` | `example_large_economies` |  |
| `exemplo_comparação_sul_europa` | `example_southern_europe` |  |
| `exemplo_portugal` | `example_portugal` |  |
| `exemplo_transformacao` | `example_transformation` |  |
| `exemplo_workflow_completo_ameco` | `example_full_ameco_workflow` |  |
| `expoentes_lyapunov` | `lyapunov_exponents` |  |
| `gerar_dados_sintéticos_ameco` | `generate_synthetic_ameco_data` |  |
| `gerar_dados_sintéticos_portugal` | `generate_synthetic_portugal_data` |  |
| `hessiana_mk` | `model_hessian` | thin wrapper over ForwardDiff.hessian |
| `hessiana_sistema` | `system_hessian` |  |
| `histerese_simulada` | `simulated_hysteresis` |  |
| `indicadores_crescimento` | `growth_indicators` |  |
| `jacobiana_parametro` | `parameter_jacobian` |  |
| `jacobiana_racionamento` | `rationing_jacobian` |  |
| `jacobiana_sistema` | `system_jacobian` |  |
| `ler_ficheiro_ameco_txt` | `read_ameco_txt_file` |  |
| `listar_países_ameco` | `list_ameco_countries` |  |
| `mapa_tssi` | `tssi_map` |  |
| `modelo_dois_departamentos` | `two_department_model` |  |
| `obter_dados_ameco` | `fetch_ameco_data` |  |
| `obter_dados_portugal_eurostat` | `fetch_portugal_eurostat_data` |  |
| `obter_emprego_setorial_eurostat` | `fetch_eurostat_sector_employment` |  |
| `obter_fbcf_setorial_eurostat` | `fetch_eurostat_sector_gfcf` |  |
| `obter_stock_capital_setorial_eurostat` | `fetch_eurostat_sector_capital_stock` |  |
| `obter_série_ccf_setorial_eurostat` | `fetch_eurostat_sector_cfc_series` |  |
| `obter_série_fbcf_setorial_eurostat` | `fetch_eurostat_sector_gfcf_series` |  |
| `obter_série_stock_capital_setorial_eurostat` | `fetch_eurostat_sector_capital_stock_series` |  |
| `obter_vab_remuneracoes_ccf_eurostat` | `fetch_eurostat_gva_compensation_cfc` |  |
| `plotar_2dept` | `plot_2dept` |  |
| `plotar_Ndept` | `plot_Ndept` |  |
| `plotar_bifurcacao` | `plot_bifurcation` |  |
| `problema_transformacao` | `transformation_problem` |  |
| `processar_csv_ameco` | `parse_ameco_csv` |  |
| `processar_qre` | `process_supply_use` |  |
| `raio_espectral` | `spectral_radius` |  |
| `raio_espectral_amortecido` | `damped_spectral_radius` |  |
| `relaxação_ótima` | `optimal_relaxation` |  |
| `simular_2dept` | `simulate_2dept` |  |
| `simular_Ndept` | `simulate_Ndept` |  |
| `simular_Ndept_customizado` | `simulate_Ndept_custom` |  |
| `simular_choque_salarial` | `simulate_wage_shock` |  |
| `simular_normalizado` | `simulate_normalized` |  |
| `sistema_2dept!` | `system_2dept!` |  |
| `sistema_Ndept!` | `system_Ndept!` |  |
| `sistema_Ndept_io!` | `system_Ndept_io!` |  |
| `sistema_cruzado!` | `cross_dual_system!` |  |
| `sistema_normalizado` | `normalized_system` |  |
| `testar_modelo` | `test_model` |  |
| `validar_taxas_lucro_calibradas` | `validate_calibrated_profit_rates` |  |
| `valorizar_tssi` | `tssi_valuation` |  |
| `varrimento_salarial` | `wage_sweep` |  |
| `verificar_equilibrio_2dept` | `check_equilibrium_2dept` |  |
| `verificar_equilibrio_Ndept` | `check_equilibrium_Ndept` |  |
| `verificar_eurostat_setorial` | `check_eurostat_sectoral` |  |
| `verificar_sdmx_ameco` | `check_ameco_sdmx` |  |
| `dados_tssi` | `tssi_data` |  |

## Internal functions and helpers (44)

| Portuguese | English | Note |
|---|---|---|
| `_ano_iot_mais_próximo` | `_nearest_iot_year` |  |
| `_cruzado` | `_is_cross_dual` |  |
| `_dist_setorial_emprego` | `_sector_employment_shares` |  |
| `_dist_setorial_stock` | `_sector_stock_shares` |  |
| `_dist_setorial_vab` | `_sector_gva_shares` |  |
| `_do_livre` | `_from_free` |  |
| `_para_livre` | `_to_free` |  |
| `_garantir_admissibilidade_output` | `_ensure_output_admissibility` |  |
| `_mapa_racionamento` | `_rationing_map` |  |
| `_medidas_órbita` | `_orbit_measures` |  |
| `_obter_secções_eurostat` | `_fetch_eurostat_sections` |  |
| `_obter_série_sdmx` | `_fetch_sdmx_series` |  |
| `_problema_acumulação` | `_accumulation_problem` |  |
| `_projetar` | `_project` |  |
| `_racionamento_dual` | `_rationing_dual` |  |
| `_razão_preço_valor` | `_price_value_ratio` |  |
| `_registar_download` | `_log_download` |  |
| `_resolver_código_país` | `_resolve_country_code` |  |
| `_resolver_racionamento` | `_solve_rationing` |  |
| `_rhs_normalizado!` | `_rhs_normalized!` |  |
| `_secção_do_código_a64` | `_section_of_a64_code` |  |
| `_sistema_de` | `_system_of` |  |
| `_somar_por_grupo` | `_sum_by_group` |  |
| `_stock_capital_pim_por_secção` | `_pim_capital_stock_by_section` |  |
| `_taxas_lucro_io` | `_io_profit_rates` |  |
| `_tipo_bifurcação_mapa` | `_map_bifurcation_type` |  |
| `_tipo_parâmetros` | `_parameter_type` |  |
| `_valores_setoriais_eurostat` | `_eurostat_sector_values` |  |
| `_κ_racionamento` | `_κ_rationing` |  |
| `grupo_de` | `group_of` |  |
| `secção_para_grupo` | `section_to_group` |  |
| `código_para_nome` | `code_to_name` |  |
| `nomes_por_código` | `names_by_code` |  |
| `sistema!` | `system!` |  |
| `variacional!` | `variational!` |  |
| `perna` | `leg` | one side of a two-sided continuation |
| `registar!` | `record!` | paper: writes a \newcommand macro |
| `correr_ipynb` | `run_ipynb` |  |
| `correr_pluto` | `run_pluto` |  |
| `renderizar` | `render` |  |
| `salvar` | `save_figure` |  |
| `jacobiana_df` | `jacobian_fd` | test helper: finite-difference Jacobian |
| `medir` | `measure` |  |
| `correr` | `run_case` | avoids shadowing a library name |

## Keyword arguments (63)

| Portuguese | English | Note |
|---|---|---|
| `acoplado` | `coupled` |  |
| `realização` | `realization` |  |
| `racionamento` | `rationing` |  |
| `preços_mercado` | `market_prices` |  |
| `cesto` | `basket` | consumption basket |
| `fonte_dados` | `data_source` |  |
| `dados_setoriais` | `sector_data` |  |
| `fonte_setorial` | `sector_source` |  |
| `método` | `method` |  |
| `inventário_perpétuo` | `perpetual_inventory` |  |
| `T_aquecimento` | `T_warmup` |  |
| `T_transiente` | `T_transient` |  |
| `variante` | `variant` |  |
| `valores` | `values` | shadows Base.values in that scope: check at rename |
| `max_passos` | `max_steps` |  |
| `relaxação` | `relaxation` |  |
| `devolver_diagnóstico` | `return_diagnostics` |  |
| `ano_iot` | `iot_year` |  |
| `ano_inicial` | `start_year` |  |
| `agregação` | `aggregation` |  |
| `agregação_setorial` | `sector_aggregation` |  |
| `força_redownload` | `force_redownload` |  |
| `intervalo` | `interval` |  |
| `intervalo_relaxação` | `relaxation_interval` |  |
| `intervalo_órbitas` | `orbit_interval` |  |
| `intervalo_μv` | `μv_interval` |  |
| `n_pontos` | `n_points` |  |
| `n_pontos_tssi` | `n_tssi_points` |  |
| `n_inícios` | `n_starts` |  |
| `parâmetro` | `parameter` |  |
| `numerário` | `numeraire` |  |
| `tamanho_bloco` | `block_size` |  |
| `n_blocos` | `n_blocks` |  |
| `escala` | `scale` | shadows Plots.scale: check |
| `escala_mais_valia` | `surplus_value_scale` |  |
| `passo` | `step` | shadows Base.step: check at rename |
| `passo_h` | `step_h` |  |
| `alvo` | `target` |  |
| `ordem` | `order` | shadows Base.order: check |
| `diretório` | `directory` |  |
| `ficheiro` | `file` |  |
| `pasta` | `folder` |  |
| `caminho` | `path` |  |
| `unidade` | `unit` |  |
| `tipo` | `kind` |  |
| `mecanismo` | `mechanism` |  |
| `mecanismos` | `mechanisms` |  |
| `intensidade_capital` | `capital_intensity` |  |
| `limite_fora` | `outer_limit` |  |
| `tol_estabilidade` | `stability_tol` |  |
| `trials_por_combinação` | `trials_per_combination` |  |
| `estrutura` | `structure` |  |
| `forma` | `shape` |  |
| `formas` | `shapes` |  |
| `plotar` | `show_plot` | `plot` would shadow Plots.plot inside the function |
| `p_inicial` | `p_initial` |  |
| `n_econ` | `n_economies` |  |
| `códigos` | `codes` |  |
| `países` | `countries` |  |
| `setores` | `sectors` |  |
| `todo` | `mode` | check: kwarg with values :local/:manual |
| `choque` | `shock` |  |
| `choques` | `shocks` |  |

## Symbol values (20)

| Portuguese | English | Note |
|---|---|---|
| `:sintético` | `:synthetic` |  |
| `:fixo` | `:fixed` |  |
| `:aleatoria` | `:random` |  |
| `:blocos` | `:blocks` |  |
| `:convexa` | `:convex` |  |
| `:côncava` | `:concave` |  |
| `:detalhada` | `:detailed` |  |
| `:simultâneo` | `:simultaneous` |  |
| `:consistente` | `:consistent` |  |
| `:consistente_fbcf` | `:consistent_gfcf` |  |
| `:corrente` | `:current` |  |
| `:mobilidade` | `:mobility` |  |
| `:média` | `:medium` |  |
| `:uniforme` | `:uniform` |  |
| `:proporcional` | `:proportional` |  |
| `:escala_e` | `:e_scale` |  |
| `:periódico` | `:periodic` |  |
| `:equilíbrio` | `:equilibrium` |  |
| `:ciclo` | `:cycle` |  |
| `:fim` | `:stop` |  |

## Returned fields, NamedTuple keys and DataFrame columns (250)

| Portuguese | English | Note |
|---|---|---|
| `convergiu` | `converged` |  |
| `iterações` | `iterations` |  |
| `estável` | `stable` |  |
| `resíduo` | `residual` |  |
| `resíduos` | `residuals` |  |
| `valores_próprios` | `eigenvalues` |  |
| `quota_C` | `share_C` |  |
| `quota_V` | `share_V` |  |
| `quota_mín` | `min_share` |  |
| `quota` | `share` |  |
| `quota_salarial` | `wage_share` |  |
| `r_agregada` | `r_aggregate` |  |
| `dispersão_r` | `r_dispersion` |  |
| `dispersão` | `dispersion` |  |
| `dispersão_final` | `final_dispersion` |  |
| `excesso` | `excess` |  |
| `parte_real_máx` | `max_real_part` |  |
| `oscilatório` | `oscillatory` |  |
| `frequência` | `frequency` |  |
| `período` | `period` |  |
| `períodos` | `periods` |  |
| `fração_racionada` | `rationed_fraction` |  |
| `racionado` | `rationed` |  |
| `raio` | `radius` |  |
| `raios` | `radii` |  |
| `antítona` | `antitone` |  |
| `α_ótimo` | `α_optimal` |  |
| `transversalidade` | `transversality` |  |
| `supercrítico` | `supercritical` |  |
| `tem_hopf` | `has_hopf` |  |
| `viável` | `feasible` |  |
| `viável_média` | `feasible_mean` |  |
| `setores_problemáticos` | `problem_sectors` |  |
| `pontuação` | `score` |  |
| `pontuação_final` | `final_score` |  |
| `impacto_final` | `final_impact` |  |
| `impacto_inicial` | `initial_impact` |  |
| `impacto_r_final` | `final_r_impact` |  |
| `impacto_r_inicial` | `initial_r_impact` |  |
| `r_choque_final` | `r_shock_final` |  |
| `r_choque_inicial` | `r_shock_initial` |  |
| `r_choque_traj` | `r_shock_traj` |  |
| `K_choque_final` | `K_shock_final` |  |
| `K_choque_inicial` | `K_shock_initial` |  |
| `K_choque_traj` | `K_shock_traj` |  |
| `sol_choque` | `sol_shock` |  |
| `depts_choque` | `depts_shock` |  |
| `p_choque` | `p_shock` |  |
| `coexistência` | `coexistence` |  |
| `órbitas` | `orbits` |  |
| `ramo` | `branch` |  |
| `ramos` | `branches` |  |
| `sem_ramo` | `no_branch` |  |
| `multiplicadores` | `multipliers` |  |
| `preços` | `prices` |  |
| `preços_simultâneos` | `simultaneous_prices` |  |
| `p_simultâneo` | `p_simultaneous` |  |
| `r_simultâneo` | `r_simultaneous` |  |
| `valorização` | `valuation` |  |
| `erro_invariantes` | `invariance_error` |  |
| `erro_lucro` | `profit_error` |  |
| `erro_walras` | `walras_error` |  |
| `posição_fronteira` | `frontier_position` |  |
| `posição_r` | `r_position` |  |
| `curvatura` | `curvature` |  |
| `convergência_local` | `local_convergence` |  |
| `taxa_convergência` | `convergence_rate` |  |
| `taxa_lucro` | `profit_rate` |  |
| `taxas_lucro` | `profit_rates` |  |
| `taxa_mais_valia` | `surplus_value_rate` |  |
| `mais_valia` | `surplus_value` |  |
| `composição_orgânica` | `organic_composition` |  |
| `composição` | `composition` |  |
| `capital_total` | `total_capital` |  |
| `capital_transferido` | `transferred_capital` |  |
| `transferido` | `transferred` |  |
| `preço_total` | `total_price` |  |
| `valor_total` | `total_value` |  |
| `valor_produto` | `product_value` |  |
| `valores_trabalho` | `labor_values` |  |
| `r_media` | `r_mean` |  |
| `r_média` | `r_mean` |  |
| `r_mediana` | `r_median` |  |
| `r_medio_idx` | `r_mean_idx` |  |
| `k_média` | `k_mean` |  |
| `margem` | `margin` |  |
| `margem_média` | `mean_margin` |  |
| `elasticidade` | `elasticity` |  |
| `elasticidade_média` | `mean_elasticity` |  |
| `retorno` | `return_` | `return` is a keyword |
| `retornos` | `returns` |  |
| `retorno_médio` | `mean_return` |  |
| `estado_final` | `final_state` |  |
| `gap_final` | `final_gap` |  |
| `equilibrio` | `equilibrium` |  |
| `desequilibrio` | `disequilibrium` |  |
| `deseq` | `diseq` |  |
| `lado_esquerdo` | `lhs` |  |
| `lado_direito` | `rhs` |  |
| `lado_esq` | `lhs` |  |
| `lado_dir` | `rhs` |  |
| `lado` | `side` |  |
| `termo_mobilidade` | `mobility_term` |  |
| `dX_com_mobilidade` | `dX_with_mobility` |  |
| `dX_sem_mobilidade` | `dX_without_mobility` |  |
| `mobilidade_C` | `mobility_C` |  |
| `procura` | `demand` |  |
| `procura_intermédia` | `intermediate_demand` |  |
| `soma_procura` | `demand_sum` |  |
| `D_planeado` | `D_planned` |  |
| `consumo` | `consumption` |  |
| `investimento` | `investment` |  |
| `output_bruto` | `gross_output` |  |
| `output_bruto_via_vab` | `gross_output_via_gva` |  |
| `r_efetivo` | `r_effective` |  |
| `r_barra` | `r_bar` |  |
| `e_bruto` | `e_raw` |  |
| `e_implícita` | `e_implied` |  |
| `n_saturados` | `n_saturated` |  |
| `saldo` | `balance` |  |
| `receitas` | `revenue` |  |
| `despesas` | `expenditure` |  |
| `dívida` | `debt` |  |
| `dívida_base` | `debt_base` |  |
| `desemp_base` | `unemp_base` |  |
| `emprego_base` | `employment_base` |  |
| `emprego_tot` | `employment_total` |  |
| `emprego_total` | `employment_total` |  |
| `emprego_s` | `employment_s` |  |
| `emprego_v` | `employment_v` |  |
| `PIB_base` | `GDP_base` |  |
| `PIB_total` | `GDP_total` |  |
| `PIB_corrente` | `GDP_current` |  |
| `PIB_constante` | `GDP_constant` |  |
| `CCF_total` | `CFC_total` |  |
| `FBCF_setorial` | `GFCF_sectoral` |  |
| `FBCF_total` | `GFCF_total` |  |
| `S_setorial` | `S_sectoral` |  |
| `VAB_grupo` | `GVA_group` |  |
| `EBE` | `GOS` | excedente bruto de exploração = gross operating surplus |
| `rendimento` | `income` |  |
| `rendimento_empresarial` | `business_income` |  |
| `salário_médio` | `mean_wage` |  |
| `stock_capital` | `capital_stock` |  |
| `stock_reportado` | `stock_reported` |  |
| `stock_série` | `stock_series` |  |
| `stock_tot` | `stock_total` |  |
| `pct_depreciação` | `pct_depreciation` |  |
| `pct_investimento` | `pct_investment` |  |
| `pct_remunerações` | `pct_compensation` |  |
| `remun` | `comp` |  |
| `remun_s` | `comp_s` |  |
| `remun_tot` | `comp_total` |  |
| `taxa` | `rate` |  |
| `taxa_desemprego` | `unemployment_rate` |  |
| `remunerações_por_assalariado` | `compensation_per_employee` |  |
| `produtividade_trabalho` | `labor_productivity` |  |
| `custos_unit_trabalho` | `unit_labor_costs` |  |
| `custos_unit` | `unit_costs` |  |
| `custo` | `cost` |  |
| `stock_capital_líquido` | `net_capital_stock` |  |
| `stock_capital_bruto` | `gross_capital_stock` |  |
| `Comp_Orgânica` | `Organic_Composition` | DataFrame column |
| `Taxa_Exploração` | `Exploitation_Rate` | DataFrame column |
| `Taxa_Lucro` | `Profit_Rate` | DataFrame column |
| `Quota_Salarial` | `Wage_Share` | DataFrame column |
| `País` | `Country` | DataFrame column |
| `PAÍS` | `COUNTRY` |  |
| `setor` | `sector` |  |
| `setoriais_reais` | `real_sectoral` |  |
| `código_cae` | `nace_code` |  |
| `nome_país` | `country_name` |  |
| `nome_var` | `var_name` |  |
| `nomes` | `name_list` | avoids shadowing a library name |
| `nomes_grupos` | `group_names` |  |
| `códigos_grupos` | `group_codes` |  |
| `data_calibração` | `calibration_date` |  |
| `n_execuções` | `n_runs` |  |
| `n_convergiu` | `n_converged` |  |
| `n_instáveis` | `n_unstable` |  |
| `n_racionado` | `n_rationed` |  |
| `n_rac` | `n_rat` |  |
| `n_rac_maior` | `n_rat_larger` |  |
| `n_reescalada` | `n_rescaled` |  |
| `n_vab` | `n_gva` |  |
| `n_pontos` | `n_points` |  |
| `foi_reescalada` | `was_rescaled` |  |
| `reescalada` | `rescaled` |  |
| `reescalada2` | `rescaled2` |  |
| `reescaladas` | `rescaled_runs` |  |
| `não_reescaladas` | `unrescaled_runs` |  |
| `frac_não` | `frac_unresc` |  |
| `it_não` | `it_unresc` |  |
| `fração` | `fraction` |  |
| `frações` | `fractions` |  |
| `iterações_05` | `iterations_05` |  |
| `iterações_convergidas` | `converged_iterations` |  |
| `convergiu_05` | `converged_05` |  |
| `observadas` | `observed` |  |
| `observadas_05` | `observed_05` |  |
| `previstas_05` | `predicted_05` |  |
| `previstas_padrão` | `predicted_default` |  |
| `raio_05` | `radius_05` |  |
| `raio_padrão` | `radius_default` |  |
| `raio_ótimo` | `radius_optimal` |  |
| `raios_max_θ` | `radii_max_θ` |  |
| `detetados` | `detected` |  |
| `plausível` | `plausible` |  |
| `válidos` | `valid` |  |
| `negativos` | `negatives` |  |
| `escassos` | `scarce` |  |
| `difere` | `differs` |  |
| `caos` | `chaos` |  |
| `caóticos` | `chaotic` |  |
| `hiper` | `hyper` | hyperchaos |
| `cruzamentos` | `crossings` |  |
| `saltos` | `jumps` |  |
| `ciclo` | `cycle` | shadows Base.cycle: check |
| `curva` | `curve` |  |
| `densidade` | `density` |  |
| `densidades` | `densities` |  |
| `desvio` | `deviation` |  |
| `desvios` | `deviations` |  |
| `desvios_A` | `deviations_A` |  |
| `desvios_T` | `deviations_T` |  |
| `desvios_médios` | `mean_deviations` |  |
| `erro` | `error_` | `error` is Base |
| `erros` | `errors` |  |
| `falhas` | `failures` |  |
| `tem_menos_um` | `has_minus_one` |  |
| `tem_zero` | `has_zero` |  |
| `para_fora` | `outward` |  |
| `para_hopf` | `to_hopf` |  |
| `subir` | `up` |  |
| `descer` | `down` |  |
| `k_volta` | `k_back` |  |
| `medidas` | `measures` |  |
| `media` | `avg` | avoids shadowing a library name |
| `média` | `avg` | avoids shadowing a library name |
| `média_v` | `mean_v` |  |
| `resultado` | `result` |  |
| `resultados` | `results` |  |
| `res_medio` | `res_mean` |  |
| `resíduo_pct` | `residual_pct` |  |
| `validação` | `validation` |  |
| `qualidade` | `quality` |  |
| `soma` | `total_sum` |  |
| `K_base_inicial` | `K_base_initial` |  |
| `r_base_inicial` | `r_base_initial` |  |
| `máx` | `peak` | avoids shadowing a library name |

## AMECO country names (36)

| Portuguese | English | Code |
|---|---|---|
| `"Áustria"` | `"Austria"` | `AT` |
| `"Bélgica"` | `"Belgium"` | `BE` |
| `"Bulgária"` | `"Bulgaria"` | `BG` |
| `"Croácia"` | `"Croatia"` | `HR` |
| `"Chipre"` | `"Cyprus"` | `CY` |
| `"República Checa"` | `"Czechia"` | `CZ` |
| `"Dinamarca"` | `"Denmark"` | `DK` |
| `"Estónia"` | `"Estonia"` | `EE` |
| `"Finlândia"` | `"Finland"` | `FI` |
| `"França"` | `"France"` | `FR` |
| `"Alemanha"` | `"Germany"` | `DE` |
| `"Grécia"` | `"Greece"` | `EL` |
| `"Hungria"` | `"Hungary"` | `HU` |
| `"Irlanda"` | `"Ireland"` | `IE` |
| `"Itália"` | `"Italy"` | `IT` |
| `"Letónia"` | `"Latvia"` | `LV` |
| `"Lituânia"` | `"Lithuania"` | `LT` |
| `"Luxemburgo"` | `"Luxembourg"` | `LU` |
| `"Países Baixos"` | `"Netherlands"` | `NL` |
| `"Polónia"` | `"Poland"` | `PL` |
| `"Roménia"` | `"Romania"` | `RO` |
| `"Eslováquia"` | `"Slovakia"` | `SK` |
| `"Eslovénia"` | `"Slovenia"` | `SI` |
| `"Espanha"` | `"Spain"` | `ES` |
| `"Suécia"` | `"Sweden"` | `SE` |
| `"Área do Euro"` | `"Euro Area"` | `EA` |
| `"Área do Euro (19)"` | `"Euro Area (19)"` | `EA19` |
| `"Reino Unido"` | `"United Kingdom"` | `UK` |
| `"Noruega"` | `"Norway"` | `NO` |
| `"Suíça"` | `"Switzerland"` | `CH` |
| `"Islândia"` | `"Iceland"` | `IS` |
| `"Turquia"` | `"Turkey"` | `TR` |
| `"União Europeia (27)"` | `"European Union (27)"` | `EU27` |
| `"União Europeia (28)"` | `"European Union (28)"` | `EU28` |
| `"Estados Unidos"` | `"United States"` | `US` |
| `"Japão"` | `"Japan"` | `JP` |

## AMECO variable keys (`AMECO_VARIABLE_CODES`) (25)

| Portuguese | English | Mnemonic |
|---|---|---|
| `"PIB_corrente"` | `"GDP_current"` | `UVGD` |
| `"PIB_constante"` | `"GDP_constant"` | `OVGD` |
| `"consumo_privado"` | `"private_consumption"` | `UCPH` |
| `"consumo_público"` | `"public_consumption"` | `UCTG` |
| `"FBCF"` | `"GFCF"` | `UIGT` |
| `"exportações"` | `"exports"` | `UXGS` |
| `"importações"` | `"imports"` | `UMGS` |
| `"emprego_total"` | `"employment_total"` | `NETD` |
| `"emprego_assalariado"` | `"employees"` | `NWTD` |
| `"taxa_desemprego"` | `"unemployment_rate"` | `ZUTN` |
| `"população_ativa"` | `"labor_force"` | `NLTN` |
| `"remunerações"` | `"compensation"` | `UWCD` |
| `"remunerações_por_assalariado"` | `"compensation_per_employee"` | `HWCDW` |
| `"produtividade_trabalho"` | `"labor_productivity"` | `ZVGDE` |
| `"custos_unit_trabalho"` | `"unit_labor_costs"` | `PLCD` |
| `"deflator_PIB"` | `"GDP_deflator"` | `PVGD` |
| `"IPC"` | `"CPI"` | `ZCPIH` |
| `"receitas_governo"` | `"government_revenue"` | `URTG` |
| `"despesas_governo"` | `"government_expenditure"` | `UUTG` |
| `"saldo_orçamental"` | `"budget_balance"` | `UBLG` |
| `"dívida_pública"` | `"public_debt"` | `UDGGL` |
| `"balança_corrente"` | `"current_account"` | `UBCA` |
| `"balança_comercial"` | `"trade_balance"` | `UBTB` |
| `"stock_capital_líquido"` | `"net_capital_stock"` | `OKND` |
| `"stock_capital_bruto"` | `"gross_capital_stock"` | `OKCD` |

## Local variables (177)

Local variables were renamed mechanically and are not listed.
