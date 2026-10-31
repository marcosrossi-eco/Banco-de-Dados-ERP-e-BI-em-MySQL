-- ============================================================
-- 99_limpar_simulacao.sql | Remove TODOS os dados simulados e mantém estrutura e configuração
-- Rode antes de carregar dados reais. IRREVERSÍVEL: faça backup antes.
-- ============================================================
USE farmacia;
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE livro_controlados;   TRUNCATE reservas_click_collect; TRUNCATE movimentacoes_estoque;
TRUNCATE estoque_snapshot_diario; TRUNCATE liquidacao_lotes;    TRUNCATE campanha_combos;
TRUNCATE afinidades;          TRUNCATE campanha_itens;          TRUNCATE campanhas;
TRUNCATE itens_venda;         TRUNCATE vendas;                  TRUNCATE itens_compra;
TRUNCATE compras;             TRUNCATE estoque_lotes;           TRUNCATE metas_comerciais;
DELETE FROM produto_filial;
DELETE FROM produtos;
DELETE FROM fornecedores;
SET FOREIGN_KEY_CHECKS = 1;
DROP TABLE IF EXISTS seed_num, seed_dias, seed_peso, seed_produtos;
-- Mantidos: filiais, segmentos, categorias, parametros_categoria, area_categoria_filial,
--           regras_liquidacao, parametros_rollout (ajuste-os à sua realidade).
-- Depois: cadastre fornecedores, produtos reais e produto_filial; ajuste m² e metas.
