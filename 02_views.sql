-- ============================================================
-- 02_views.sql | Métricas, relatórios e vitrines (views não usam variáveis @)
-- ============================================================
USE farmacia;

CREATE OR REPLACE VIEW v_consumo_90d AS
SELECT v.id_filial, iv.id_produto,
       SUM(iv.qtd)                AS qtd_90d,
       ROUND(SUM(iv.qtd) / 90, 3) AS consumo_dia
FROM vendas v
JOIN itens_venda iv ON iv.id_venda = v.id_venda
WHERE v.status = 'CONCLUIDA'
  AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY v.id_filial, iv.id_produto;

CREATE OR REPLACE VIEW v_estoque_atual AS
SELECT id_filial, id_produto,
       SUM(CASE WHEN validade IS NULL OR validade >= CURDATE() THEN qtd_atual ELSE 0 END) AS qtd_vendavel,
       SUM(CASE WHEN validade < CURDATE() THEN qtd_atual ELSE 0 END)                       AS qtd_vencida
FROM estoque_lotes
GROUP BY id_filial, id_produto;

-- Giro, cobertura, estoque de segurança e ponto de pedido
CREATE OR REPLACE VIEW v_metricas_estoque AS
WITH base AS (
  SELECT pf.id_filial, p.id_produto, p.nome, c.id_categoria, c.nome AS categoria,
         p.id_fornecedor_padrao, pf.lead_time_dias, pf.dias_seguranca,
         COALESCE(e.qtd_vendavel, 0) AS qtd_estoque,
         COALESCE(k.qtd_90d, 0)      AS qtd_90d,
         COALESCE(k.consumo_dia, 0)  AS consumo_dia
  FROM produto_filial pf
  JOIN produtos p   ON p.id_produto = pf.id_produto AND p.ativo = 1
  JOIN categorias c ON c.id_categoria = p.id_categoria
  LEFT JOIN v_estoque_atual e ON e.id_filial = pf.id_filial AND e.id_produto = pf.id_produto
  LEFT JOIN v_consumo_90d  k ON k.id_filial = pf.id_filial AND k.id_produto = pf.id_produto
)
SELECT b.*,
       CEIL(b.consumo_dia * b.dias_seguranca)                      AS estoque_seguranca,
       CEIL(b.consumo_dia * (b.lead_time_dias + b.dias_seguranca)) AS ponto_pedido,
       CASE WHEN b.consumo_dia > 0 THEN ROUND(b.qtd_estoque / b.consumo_dia, 1) END AS cobertura_dias,
       CASE WHEN b.qtd_estoque > 0 THEN ROUND((b.qtd_90d / b.qtd_estoque) * (365 / 90), 2) END AS giro_anual
FROM base b;

-- Giro com estoque médio real (snapshots diários)
CREATE OR REPLACE VIEW v_giro_snapshot AS
SELECT s.id_filial, s.id_produto,
       ROUND(AVG(s.qtd), 1) AS estoque_medio_90d,
       k.qtd_90d,
       ROUND(k.qtd_90d * (365 / 90) / NULLIF(AVG(s.qtd), 0), 2) AS giro_anual
FROM estoque_snapshot_diario s
JOIN v_consumo_90d k ON k.id_filial = s.id_filial AND k.id_produto = s.id_produto
WHERE s.data_ref >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY s.id_filial, s.id_produto, k.qtd_90d;

-- Sugestão de pedido com cobertura-alvo por categoria
CREATE OR REPLACE VIEW v_sugestao_pedido AS
WITH transito AS (
  SELECT c.id_filial, ic.id_produto, SUM(ic.qtd_pedida - ic.qtd_recebida) AS qtd_transito
  FROM compras c JOIN itens_compra ic ON ic.id_compra = c.id_compra
  WHERE c.status IN ('ABERTO','ENVIADO')
  GROUP BY c.id_filial, ic.id_produto
)
SELECT m.id_filial, m.id_produto, m.nome, m.categoria, m.id_fornecedor_padrao,
       m.qtd_estoque, COALESCE(t.qtd_transito, 0) AS qtd_transito, m.ponto_pedido,
       GREATEST(CEIL(m.consumo_dia * (m.lead_time_dias + pc.cobertura_alvo_dias))
                - m.qtd_estoque - COALESCE(t.qtd_transito, 0), 0) AS qtd_sugerida
FROM v_metricas_estoque m
JOIN parametros_categoria pc ON pc.id_categoria = m.id_categoria
LEFT JOIN transito t ON t.id_filial = m.id_filial AND t.id_produto = m.id_produto
WHERE m.consumo_dia > 0
  AND m.qtd_estoque + COALESCE(t.qtd_transito, 0) <= m.ponto_pedido;

-- Metas x realizado por categoria/mês
CREATE OR REPLACE VIEW v_meta_vs_real AS
WITH realizado AS (
  SELECT v.id_filial, p.id_categoria,
         DATE_SUB(DATE(v.data_hora), INTERVAL DAYOFMONTH(v.data_hora) - 1 DAY) AS competencia,
         SUM(iv.qtd * iv.preco_unitario - iv.desconto)                              AS receita,
         SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario) AS margem_contrib
  FROM vendas v
  JOIN itens_venda iv ON iv.id_venda = v.id_venda
  JOIN produtos p     ON p.id_produto = iv.id_produto
  WHERE v.status = 'CONCLUIDA'
  GROUP BY v.id_filial, p.id_categoria, competencia
)
SELECT m.id_filial, m.competencia, s.id_segmento, s.nome AS segmento,
       c.id_categoria, c.nome AS categoria,
       m.meta_receita, COALESCE(r.receita, 0) AS receita_real,
       ROUND(100 * COALESCE(r.receita, 0) / NULLIF(m.meta_receita, 0), 1) AS atingimento_receita_pct,
       m.meta_margem_pct,
       ROUND(100 * r.margem_contrib / NULLIF(r.receita, 0), 1)            AS margem_real_pct
FROM metas_comerciais m
JOIN categorias c ON c.id_categoria = m.id_categoria
JOIN segmentos s  ON s.id_segmento = c.id_segmento
LEFT JOIN realizado r ON r.id_filial = m.id_filial
                     AND r.id_categoria = m.id_categoria
                     AND r.competencia = m.competencia;

-- Fila de decisão da liquidação
CREATE OR REPLACE VIEW v_sugestoes_liquidacao AS
SELECT q.id_liq, q.id_campanha, p.id_produto AS ID_Produto, p.nome AS Nome, c.nome AS Categoria,
       l.lote, l.validade, q.dias_para_vencer, l.qtd_atual AS Qtd_Estoque, q.qtd_em_risco,
       q.preco_original AS Preço_Venda, q.preco_liquidacao, q.desconto_efetivo_pct,
       ROUND(100 * (q.preco_liquidacao - l.custo_unitario) / NULLIF(q.preco_liquidacao, 0), 1) AS Margem_pct_liquidacao,
       ROUND(q.qtd_em_risco * l.custo_unitario, 2) AS custo_em_risco,
       q.acao
FROM liquidacao_lotes q
JOIN estoque_lotes l ON l.id_lote = q.id_lote
JOIN produtos p      ON p.id_produto = q.id_produto
JOIN categorias c    ON c.id_categoria = p.id_categoria
WHERE q.status = 'SUGERIDA'
ORDER BY FIELD(q.acao, 'BAIXAR_VENCIDO', 'DEVOLVER_FORNECEDOR', 'LIQUIDAR'), q.dias_para_vencer;

CREATE OR REPLACE VIEW v_resultado_liquidacao AS
SELECT q.id_liq, c.nome AS campanha, p.nome AS produto, q.qtd_em_risco, q.desconto_efetivo_pct,
       COALESCE((SELECT SUM(iv.qtd)
                 FROM itens_venda iv JOIN vendas v ON v.id_venda = iv.id_venda
                 WHERE iv.id_produto = q.id_produto AND v.id_filial = c.id_filial
                   AND v.status = 'CONCLUIDA'
                   AND DATE(v.data_hora) BETWEEN c.data_inicio AND LEAST(c.data_fim, CURDATE())), 0) AS unid_vendidas_periodo,
       q.status
FROM liquidacao_lotes q
JOIN campanhas c ON c.id_campanha = q.id_campanha
JOIN produtos p  ON p.id_produto = q.id_produto
WHERE q.acao = 'LIQUIDAR' AND q.status IN ('ATIVA','CONCLUIDA');

-- Vitrine do Click and Collect: preço do combo e disponibilidade real (estoque menos reservas)
CREATE OR REPLACE VIEW v_combos_click_collect AS
WITH res AS (
  SELECT id_produto, SUM(qtd) AS q FROM reservas_click_collect
  WHERE status = 'RESERVADA' AND expira_em > NOW() GROUP BY id_produto
)
SELECT c.id_campanha, cb.id_combo, pa.nome AS Nome_Ancora,
       pc.id_produto AS ID_Produto, pc.nome AS Nome, cat.nome AS Categoria,
       'CLICK_COLLECT' AS Canal,
       GREATEST(LEAST(COALESCE(ea.qtd_vendavel, 0) - COALESCE(ra.q, 0),
                      COALESCE(ec.qtd_vendavel, 0) - COALESCE(rc.q, 0)), 0) AS Qtd_Estoque,
       cb.preco_normal_compl,
       cb.preco_combo_compl AS Preço_Venda,
       ROUND(100 * (cb.preco_combo_compl - pc.custo_medio) / cb.preco_combo_compl, 1) AS Margem_pct,
       c.data_fim
FROM campanha_combos cb
JOIN campanhas c    ON c.id_campanha = cb.id_campanha AND c.status = 'ATIVA'
                   AND CURDATE() BETWEEN c.data_inicio AND c.data_fim
JOIN produtos pa    ON pa.id_produto = cb.id_ancora
JOIN produtos pc    ON pc.id_produto = cb.id_complemento
JOIN categorias cat ON cat.id_categoria = pc.id_categoria
LEFT JOIN v_estoque_atual ea ON ea.id_filial = c.id_filial AND ea.id_produto = cb.id_ancora
LEFT JOIN v_estoque_atual ec ON ec.id_filial = c.id_filial AND ec.id_produto = cb.id_complemento
LEFT JOIN res ra ON ra.id_produto = cb.id_ancora
LEFT JOIN res rc ON rc.id_produto = cb.id_complemento;

-- Attach rate do cross-selling: campanha vs. janela anterior de mesmo tamanho
CREATE OR REPLACE VIEW v_resultado_crosssell AS
WITH janela AS (
  SELECT cb.id_combo, c.id_filial, c.canal, cb.id_ancora, cb.id_complemento, c.data_inicio,
         LEAST(c.data_fim, CURDATE()) AS data_fim_efetiva,
         DATE_SUB(c.data_inicio, INTERVAL DATEDIFF(c.data_fim, c.data_inicio) + 1 DAY) AS base_inicio
  FROM campanha_combos cb JOIN campanhas c ON c.id_campanha = cb.id_campanha
  WHERE c.status IN ('ATIVA', 'ENCERRADA')
),
linhas AS (
  SELECT j.id_combo, v.id_venda,
         IF(DATE(v.data_hora) >= j.data_inicio, 'CAMPANHA', 'BASE') AS periodo,
         MAX(iv.id_produto = j.id_ancora)      AS tem_ancora,
         MAX(iv.id_produto = j.id_complemento) AS tem_comp
  FROM janela j
  JOIN vendas v ON v.id_filial = j.id_filial AND v.status = 'CONCLUIDA'
               AND (j.canal = 'TODOS' OR v.canal = j.canal)
               AND DATE(v.data_hora) BETWEEN j.base_inicio AND j.data_fim_efetiva
  JOIN itens_venda iv ON iv.id_venda = v.id_venda
                     AND iv.id_produto IN (j.id_ancora, j.id_complemento)
  GROUP BY j.id_combo, v.id_venda, periodo
)
SELECT l.id_combo,
       SUM(l.periodo = 'BASE' AND l.tem_ancora = 1) AS tickets_ancora_base,
       ROUND(100 * SUM(l.periodo = 'BASE' AND l.tem_ancora = 1 AND l.tem_comp = 1)
                 / NULLIF(SUM(l.periodo = 'BASE' AND l.tem_ancora = 1), 0), 1) AS attach_base_pct,
       SUM(l.periodo = 'CAMPANHA' AND l.tem_ancora = 1) AS tickets_ancora_campanha,
       ROUND(100 * SUM(l.periodo = 'CAMPANHA' AND l.tem_ancora = 1 AND l.tem_comp = 1)
                 / NULLIF(SUM(l.periodo = 'CAMPANHA' AND l.tem_ancora = 1), 0), 1) AS attach_campanha_pct
FROM linhas l
GROUP BY l.id_combo;
