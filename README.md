# Banco de Dados: ERP e BI em MySQL

Banco de dados, rotinas e relatórios para gestão de compras, vendas, ressuprimento e BI de uma farmácia (unidade piloto: Matriz), preparado para replicação nas filiais.

> **Dados simulados.** O projeto nasceu sem fonte de dados real. Os arquivos `04` e `05` geram catálogo, vendas, compras e estoque **fictícios** só para validar o pipeline. Margens, coberturas, m², metas e limiares são **hipóteses de partida**. O veredito de rollout só tem valor de negócio com dados reais.

## Requisitos
- MySQL **8.0.16 ou superior** (usa CTEs recursivas, funções de janela e CHECK constraints).
- Um cliente SQL: MySQL Workbench, DBeaver Community ou o `mysql` de linha de comando.
- Permissão de administrador (root) para criar banco, usuários e eventos.

## Instalação (passo a passo)
1. Extraia a pasta `farmacia-erp` e abra um terminal dentro dela.
2. Entre no MySQL com UTF-8 (necessário por causa dos acentos):
   ```
   mysql -u root -p --default-character-set=utf8mb4
   ```
3. Execute o instalador:
   ```
   SOURCE 00_instalar_tudo.sql;
   ```
   Se preferir Workbench ou DBeaver, abra e execute **como script** cada arquivo na ordem numérica abaixo.
4. O arquivo `05` leva de dezenas de segundos a poucos minutos. Quando terminar, valide:
   ```sql
   USE farmacia;
   SELECT COUNT(*) FROM vendas;  SELECT COUNT(*) FROM estoque_lotes;
   CALL sp_veredito_rollout(1);
   ```
5. (Opcional) Edite as senhas e rode `08_usuarios_e_backup.sql`.
6. Para manter os eventos agendados após reiniciar o servidor, adicione `event_scheduler=ON` na seção `[mysqld]` do `my.ini` (Windows) ou `my.cnf` (Linux/macOS).

> Estes scripts não foram executados em um MySQL real durante a elaboração. Na primeira execução, se algum arquivo acusar erro, copie a mensagem e o número da linha para correção.

## Ordem e conteúdo dos arquivos
| Arquivo | Conteúdo | Manter em produção? |
|---|---|---|
| `00_instalar_tudo.sql` | Chama os demais na ordem | Sim |
| `01_schema.sql` | 25 tabelas, chaves e índices | Sim |
| `02_views.sql` | Métricas de estoque, metas, liquidação, vitrine Click and Collect | Sim |
| `03_configuracao.sql` | Filial, segmentos, categorias, parâmetros, limiares | Sim, ajustando valores |
| `04_simulacao_catalogo.sql` | 8 fornecedores e 39 produtos fictícios | Não (substituir) |
| `05_simulacao_operacao.sql` | 180 dias de vendas, compras, lotes, Kardex, metas, snapshots | Não (substituir) |
| `06_rotinas_e_automacao.sql` | Procedures, trigger, eventos, afinidades iniciais | Sim |
| `07_relatorios_executivos.sql` | 14 consultas de rotina (diárias, semanais, mensais) | Sim |
| `08_usuarios_e_backup.sql` | Usuários `farmacia_app` e `farmacia_bi`, agendador | Sim |
| `99_limpar_simulacao.sql` | Apaga dados simulados e mantém a estrutura | Rodar uma vez |
| `DICIONARIO_DE_DADOS.md` | Descrição das tabelas, views e rotinas | Documentação |

## As 6 camadas do pipeline
| Camada | Onde está |
|---|---|
| 1. Modelagem e métricas | `01`, `02` (`v_metricas_estoque`, `v_giro_snapshot`) |
| 2. Divulgação de informações | `07` (alertas de ruptura, vencimento, capital imobilizado) |
| 3. Campanhas e cross-selling | `afinidades`, `sp_criar_cross_selling`, `v_combos_click_collect`, `v_resultado_crosssell` |
| 4. Renovação e otimização | `sp_gerar_liquidacao`, `v_sugestao_pedido`, `07` (fornecedores) |
| 5. Analytics e ROI | `v_meta_vs_real`, `07` (margem por categoria, curva ABC, rentabilidade por m²) |
| 6. Rollout | `sp_veredito_rollout`, `parametros_rollout`, `sp_provisionar_filial` |

## Rotina de uso
- **Diária:** consultas 1 a 6 do arquivo `07` (ruptura, pedido, vencimentos, estoque, capital, compras em trânsito).
- **Semanal:** consultas 7 a 9, e a revisão de `SELECT * FROM v_sugestoes_liquidacao;`.
- **Mensal:** consultas 10 a 13 e `CALL sp_veredito_rollout(1);`.

**Ciclo de liquidação** (sugestões semanais são automáticas; a aprovação é manual):
```sql
CALL sp_gerar_liquidacao(1);
SELECT * FROM v_sugestoes_liquidacao;
CALL sp_ativar_liquidacao(<id_campanha>);
CALL sp_baixar_vencidos(1);
SELECT * FROM v_resultado_liquidacao;
```

**Ciclo de cross-selling:**
```sql
CALL sp_atualizar_afinidades(1);
CALL sp_criar_cross_selling(1, 10.00, 14);
CALL sp_ativar_cross_selling(<id_campanha>);
SELECT * FROM v_combos_click_collect;
SELECT * FROM v_resultado_crosssell;
```

## Regras de negócio embutidas (confirmar com o farmacêutico responsável)
- Medicamento de prescrição, tarjado ou controlado **nunca** recebe desconto promocional: a sugestão é devolver ao fornecedor.
- No cross-selling só MIPs são âncora; o desconto vai no complemento do segmento Bem-Estar, Conveniência e Impulso.
- Combos não são criados se a âncora ou o complemento estiver abaixo do estoque de segurança.
- Piso de margem: liquidação a custo + 5%; complemento do combo a custo + 15%.
- Lotes controlados (Portaria 344) **não** são baixados automaticamente.
- `livro_controlados` é uma estrutura simplificada e **não substitui o SNGPC**.
- `preco_max_consumidor` (CMED) está simulado; substitua pela tabela oficial.

## Migração para dados reais
1. Faça backup (`mysqldump`).
2. Rode `99_limpar_simulacao.sql`.
3. Ajuste `03_configuracao.sql` (CNPJ real, margens-alvo, coberturas, m², limiares) e cadastre fornecedores, produtos e `produto_filial` reais.
4. Carregue vendas, compras e lotes reais (ex.: `LOAD DATA` a partir de CSV exportado do PDV).
5. Grave o **lote vendido** em `itens_venda.id_lote` (FEFO) para medir a liquidação por lote.
6. Aguarde pelo menos 6 meses de dados e rode `CALL sp_veredito_rollout(1);`.

## Rollout para as filiais
```sql
CALL sp_provisionar_filial('Farmácia Filial 01', '20000000000001', 'Bairro', 'Cidade');
```
Depois: ajuste lead time e m² reais, cadastre as metas da filial, acompanhe 90 dias de operação e rode `CALL sp_veredito_rollout(<id_filial>);`. Os eventos agendados (`ev_*`) hoje apontam para a filial 1; replique-os por filial.

## Limitações conhecidas
- O consumo diário é por produto, não por lote.
- O PDV e o e-commerce precisam ler `liquidacao_lotes` (ativas) e `v_combos_click_collect` para que os descontos cheguem ao caixa.
- Cross-selling descoberto nos dados simulados tende a lift próximo de 1 (sorteio independente).
- O banco hoje roda em um único laptop: mantenha backup fora dele.

## Como consultar o projeto
- **MySQL Workbench / DBeaver:** host `localhost`, porta `3306`, banco `farmacia`, usuário `farmacia_bi` (somente leitura).
- **Excel / Power BI:** Obter Dados > MySQL, apontando para as views `v_*`.
- **Metabase** (roda local) para painéis no navegador.
