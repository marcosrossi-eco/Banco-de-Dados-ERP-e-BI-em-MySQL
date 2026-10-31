# Dicionário de dados | banco `farmacia`

## Hierarquia e cadastros
| Tabela | Finalidade | Colunas-chave |
|---|---|---|
| `filiais` | Unidades da rede (Matriz e filiais) | `id_filial`, `cnpj`, `tipo`, `bairro` |
| `segmentos` | As 4 zonas de loja | `id_segmento`, `zona_loja`, `papel` |
| `categorias` | Categorias por segmento | `id_categoria`, `id_segmento`, `exige_receita`, `controle_validade`, `margem_alvo_pct` |
| `fornecedores` | Laboratórios e distribuidores | `id_fornecedor`, `tipo`, `prazo_entrega_dias` |
| `produtos` | Cadastro-mestre (comum às filiais) | `ean`, `tipo_medicamento`, `tarja`, `controlado_344`, `custo_medio`, `preco_venda`, `preco_max_consumidor`, `margem_pct` (calculada) |
| `produto_filial` | Parâmetros do produto por filial | `estoque_minimo`, `dias_seguranca`, `lead_time_dias` |
| `parametros_categoria` | Cobertura-alvo e dias de segurança por categoria | `cobertura_alvo_dias`, `dias_seguranca` |
| `area_categoria_filial` | m² por categoria e filial | `metros_quadrados` |

## Estoque
| Tabela | Finalidade | Colunas-chave |
|---|---|---|
| `estoque_lotes` | Saldo físico por lote (PDV e e-commerce compartilham) | `lote`, `validade`, `qtd_atual`, `custo_unitario` |
| `movimentacoes_estoque` | Kardex: entradas, saídas, perdas, ajustes | `tipo`, `qtd` (positivo entra, negativo sai) |
| `estoque_snapshot_diario` | Posição diária, base do giro com estoque médio | `data_ref`, `qtd`, `valor_estoque` |
| `livro_controlados` | Registro simplificado de controlados (não substitui o SNGPC) | `tipo_mov`, `numero_receita`, `crm_prescritor` |

## Compras e vendas
| Tabela | Finalidade | Colunas-chave |
|---|---|---|
| `compras` / `itens_compra` | Pedidos a fornecedores e itens | `status`, `data_prevista`, `data_recebimento`, `qtd_pedida`, `qtd_recebida` |
| `vendas` / `itens_venda` | Tickets e linhas | `canal` (PDV, ECOMMERCE, CLICK_COLLECT), `status`, `desconto` (valor total da linha), `id_lote` |
| `reservas_click_collect` | Reserva de estoque do e-commerce | `status`, `expira_em` |

## Metas e campanhas
| Tabela | Finalidade | Colunas-chave |
|---|---|---|
| `metas_comerciais` | Meta mensal por categoria | `competencia` (dia 01), `meta_receita`, `meta_margem_pct` |
| `campanhas` / `campanha_itens` | Campanhas e produtos (âncora ou complemento) | `tipo`, `canal`, `status` |
| `afinidades` | Pares âncora (MIP) e complemento (segmento 3) | `origem`, `lift`, `ativa` |
| `campanha_combos` | Combos "Leve junto na retirada" | `preco_combo_compl`, `desconto_pct` |
| `regras_liquidacao` | Desconto por faixa de dias até o vencimento | `dias_min`, `dias_max`, `desconto_pct`, `margem_minima_pct` |
| `liquidacao_lotes` | Sugestões e ações sobre lotes | `acao` (LIQUIDAR, DEVOLVER_FORNECEDOR, BAIXAR_VENCIDO), `status` |
| `parametros_rollout` | Limiares de prontidão para expansão | `kpi`, `regra`, `limite` |

## Views
| View | Responde |
|---|---|
| `v_consumo_90d` | Consumo médio diário por produto (90 dias) |
| `v_estoque_atual` | Estoque vendável e vencido por produto |
| `v_metricas_estoque` | Giro, cobertura, estoque de segurança, ponto de pedido |
| `v_giro_snapshot` | Giro anual com estoque médio real |
| `v_sugestao_pedido` | Quanto repor, descontando o que está em trânsito |
| `v_meta_vs_real` | Atingimento de meta e margem por categoria e mês |
| `v_sugestoes_liquidacao` | Fila de decisão do gestor |
| `v_resultado_liquidacao` | Unidades vendidas no período da liquidação |
| `v_combos_click_collect` | Vitrine do combo com disponibilidade real |
| `v_resultado_crosssell` | Attach rate da campanha vs. janela anterior |

## Procedures, trigger e eventos
| Objeto | Função |
|---|---|
| `sp_gerar_liquidacao(filial)` | Gera sugestões de liquidação, devolução e baixa |
| `sp_ativar_liquidacao(campanha)` | Aprovação humana da liquidação |
| `sp_baixar_vencidos(filial)` | Baixa de lotes vencidos (exceto controlados) |
| `sp_encerrar_liquidacoes(filial)` | Encerra campanhas vencidas |
| `sp_atualizar_afinidades(filial)` | Descobre pares nos tickets (5+ vendas juntas, lift 1,2 ou mais) |
| `sp_criar_cross_selling(filial, desconto, dias)` | Cria a campanha de combos (nasce PLANEJADA) |
| `sp_ativar_cross_selling(campanha)` | Aprovação humana do cross-selling |
| `sp_provisionar_filial(nome, cnpj, bairro, cidade)` | Cria filial herdando parâmetros da Matriz |
| `sp_veredito_rollout(filial)` | KPIs de prontidão e veredito APTO ou NÃO APTO |
| `tr_afinidades_valida` | Impede âncora que não seja MIP e complemento fora do segmento 3 |
| `ev_snapshot_diario` | Snapshot diário de estoque (01:00) |
| `ev_liquidacao_semanal` | Gera sugestões de liquidação toda semana (02:00) |
| `ev_liquidacao_encerra` | Encerra liquidações vencidas diariamente (03:00) |
