-- ============================================================
-- 07_relatorios_executivos.sql | Consultas de rotina da Matriz (somente leitura)
-- Margem = margem de contribuição bruta (receita - custo da mercadoria), sem taxas e impostos.
-- Rode uma consulta por vez (selecione o bloco e execute).
-- ============================================================
USE farmacia;
SET @matriz := 1;

-- ===== DIÁRIO =====
-- 1) Alerta de ruptura (ordenado por urgência)
SELECT id_filial, id_produto, nome, categoria, qtd_estoque, estoque_seguranca, ponto_pedido, cobertura_dias,
       CASE WHEN qtd_estoque = 0                  THEN 'RUPTURA'
            WHEN qtd_estoque <= estoque_seguranca THEN 'CRITICO'
            ELSE 'REPOR' END AS alerta
FROM v_metricas_estoque
WHERE id_filial = @matriz AND consumo_dia > 0 AND qtd_estoque <= ponto_pedido
ORDER BY FIELD(alerta,'RUPTURA','CRITICO','REPOR'), cobertura_dias;

-- 2) Sugestão de pedido
SELECT * FROM v_sugestao_pedido WHERE id_filial = @matriz AND qtd_sugerida > 0 ORDER BY id_fornecedor_padrao, nome;

-- 3) Vencimento próximo (FEFO, janela de 90 dias)
SELECT l.id_filial, p.id_produto, p.nome, c.nome AS categoria, l.lote, l.validade,
       DATEDIFF(l.validade, CURDATE()) AS dias_para_vencer, l.qtd_atual,
       ROUND(l.qtd_atual * l.custo_unitario, 2) AS valor_em_risco,
       CASE WHEN l.validade < CURDATE() THEN 'VENCIDO'
            WHEN l.validade <= DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'CRITICO_30D'
            WHEN l.validade <= DATE_ADD(CURDATE(), INTERVAL 60 DAY) THEN 'ATENCAO_60D'
            ELSE 'MONITORAR_90D' END AS faixa
FROM estoque_lotes l
JOIN produtos p   ON p.id_produto = l.id_produto
JOIN categorias c ON c.id_categoria = p.id_categoria
WHERE l.id_filial = @matriz AND l.qtd_atual > 0 AND l.validade IS NOT NULL
  AND l.validade <= DATE_ADD(CURDATE(), INTERVAL 90 DAY)
ORDER BY l.validade;

-- 4) Saúde do estoque
SELECT COUNT(*) AS skus_com_giro, SUM(qtd_estoque = 0) AS rupturas,
       SUM(qtd_estoque > 0 AND qtd_estoque <= estoque_seguranca) AS criticos,
       ROUND(100 * SUM(qtd_estoque = 0) / COUNT(*), 1) AS taxa_ruptura_pct,
       ROUND(AVG(cobertura_dias), 1) AS cobertura_media_dias
FROM v_metricas_estoque WHERE id_filial = @matriz AND consumo_dia > 0;

-- 5) Capital imobilizado e valor em risco de vencimento
SELECT ROUND(SUM(qtd_atual * custo_unitario), 2) AS capital_em_estoque,
       ROUND(SUM(CASE WHEN validade < CURDATE() THEN qtd_atual * custo_unitario END), 2) AS valor_vencido,
       ROUND(SUM(CASE WHEN validade BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 60 DAY)
                      THEN qtd_atual * custo_unitario END), 2) AS valor_vence_em_60d
FROM estoque_lotes WHERE id_filial = @matriz;

-- 6) Pedidos de compra em trânsito
SELECT f.razao_social, c.data_pedido, c.data_prevista, SUM(ic.qtd_pedida) AS unidades_pedidas,
       ROUND(SUM(ic.qtd_pedida * ic.custo_unitario), 2) AS valor
FROM compras c
JOIN fornecedores f  ON f.id_fornecedor = c.id_fornecedor
JOIN itens_compra ic ON ic.id_compra = c.id_compra
WHERE c.id_filial = @matriz AND c.status = 'ENVIADO'
GROUP BY f.razao_social, c.id_compra, c.data_pedido, c.data_prevista
ORDER BY c.data_prevista;

-- ===== SEMANAL =====
-- 7) Painel de vendas por canal (30 dias)
WITH vend AS (
  SELECT v.id_venda, v.canal,
         SUM(iv.qtd * iv.preco_unitario - iv.desconto) AS receita,
         SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario) AS margem
  FROM vendas v JOIN itens_venda iv ON iv.id_venda = v.id_venda
  WHERE v.id_filial = @matriz AND v.status = 'CONCLUIDA'
    AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
  GROUP BY v.id_venda, v.canal
)
SELECT IF(GROUPING(canal), 'TOTAL', canal) AS canal, COUNT(*) AS tickets,
       ROUND(SUM(receita), 2) AS receita, ROUND(AVG(receita), 2) AS ticket_medio,
       ROUND(100 * SUM(margem) / SUM(receita), 1) AS margem_pct
FROM vend GROUP BY canal WITH ROLLUP;

-- 8) Margem real vs. margem-alvo por categoria (30 dias)
SELECT s.nome AS segmento, c.nome AS categoria,
       ROUND(SUM(iv.qtd * iv.preco_unitario - iv.desconto), 2) AS receita,
       ROUND(100 * SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario)
                 / SUM(iv.qtd * iv.preco_unitario - iv.desconto), 1) AS margem_real_pct,
       c.margem_alvo_pct,
       ROUND(100 * SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario)
                 / SUM(iv.qtd * iv.preco_unitario - iv.desconto) - c.margem_alvo_pct, 1) AS gap_pp
FROM vendas v
JOIN itens_venda iv ON iv.id_venda = v.id_venda
JOIN produtos p     ON p.id_produto = iv.id_produto
JOIN categorias c   ON c.id_categoria = p.id_categoria
JOIN segmentos s    ON s.id_segmento = c.id_segmento
WHERE v.id_filial = @matriz AND v.status = 'CONCLUIDA'
  AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY s.nome, c.id_categoria, c.nome, c.margem_alvo_pct
ORDER BY gap_pp;

-- 9) Funil do Click and Collect (30 dias)
SELECT status, COUNT(*) AS reservas, SUM(qtd) AS unidades
FROM reservas_click_collect
WHERE reservado_em >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY status;

-- ===== MENSAL =====
-- 10) Curva ABC por margem de contribuição (90 dias)
WITH m AS (
  SELECT p.id_produto, p.nome,
         SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario) AS margem
  FROM vendas v
  JOIN itens_venda iv ON iv.id_venda = v.id_venda
  JOIN produtos p     ON p.id_produto = iv.id_produto
  WHERE v.id_filial = @matriz AND v.status = 'CONCLUIDA'
    AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
  GROUP BY p.id_produto, p.nome
),
acum AS (
  SELECT m.*, SUM(margem) OVER (ORDER BY margem DESC) / SUM(margem) OVER () AS pct_acum FROM m
)
SELECT id_produto, nome, ROUND(margem, 2) AS margem, ROUND(100 * pct_acum, 1) AS pct_acumulado,
       CASE WHEN pct_acum <= 0.80 THEN 'A' WHEN pct_acum <= 0.95 THEN 'B' ELSE 'C' END AS classe
FROM acum ORDER BY margem DESC;

-- 11) Meta x realizado: segmentos abaixo da meta
SELECT competencia, segmento, SUM(meta_receita) AS meta, SUM(receita_real) AS realizado,
       ROUND(100 * SUM(receita_real) / SUM(meta_receita), 1) AS atingimento_pct
FROM v_meta_vs_real WHERE id_filial = @matriz
GROUP BY competencia, segmento HAVING atingimento_pct < 100
ORDER BY competencia DESC, atingimento_pct;

-- 12) Rentabilidade por m² (margem de contribuição, 90 dias)
SELECT c.nome AS categoria, a.metros_quadrados,
       ROUND(SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario), 2) AS margem_90d,
       ROUND(SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario) / 3 / a.metros_quadrados, 2) AS margem_mes_por_m2,
       RANK() OVER (ORDER BY SUM(iv.qtd * iv.preco_unitario - iv.desconto - iv.qtd * iv.custo_unitario) / a.metros_quadrados DESC) AS ranking
FROM vendas v
JOIN itens_venda iv ON iv.id_venda = v.id_venda
JOIN produtos p     ON p.id_produto = iv.id_produto
JOIN categorias c   ON c.id_categoria = p.id_categoria
JOIN area_categoria_filial a ON a.id_filial = v.id_filial AND a.id_categoria = c.id_categoria
WHERE v.id_filial = @matriz AND v.status = 'CONCLUIDA'
  AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
GROUP BY c.id_categoria, c.nome, a.metros_quadrados
ORDER BY ranking;

-- 13) Desempenho de fornecedores para negociação (180 dias)
SELECT f.razao_social, f.tipo, COUNT(DISTINCT c.id_compra) AS pedidos,
       ROUND(SUM(ic.qtd_recebida * ic.custo_unitario), 2) AS valor_comprado,
       ROUND(100 * SUM(ic.qtd_recebida) / NULLIF(SUM(ic.qtd_pedida), 0), 1) AS fill_rate_pct,
       ROUND(AVG(DATEDIFF(c.data_recebimento, c.data_pedido)), 1) AS prazo_medio_real_dias,
       ROUND(AVG(DATEDIFF(c.data_recebimento, c.data_prevista)), 1) AS atraso_medio_dias
FROM compras c
JOIN fornecedores f  ON f.id_fornecedor = c.id_fornecedor
JOIN itens_compra ic ON ic.id_compra = c.id_compra
WHERE c.id_filial = @matriz AND c.status = 'RECEBIDO'
  AND c.data_pedido >= DATE_SUB(CURDATE(), INTERVAL 180 DAY)
GROUP BY f.id_fornecedor, f.razao_social, f.tipo
ORDER BY valor_comprado DESC;

-- 14) Prontidão para rollout
CALL sp_veredito_rollout(1);
