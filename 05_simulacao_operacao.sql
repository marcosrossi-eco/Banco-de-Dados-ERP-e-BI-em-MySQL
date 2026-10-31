-- ============================================================
-- 05_simulacao_operacao.sql | 180 dias de operação SIMULADA da Matriz
-- Usa RAND(): cada execução gera números diferentes. Pode levar de dezenas de segundos a poucos minutos.
-- O "LIMIT 100000000" nas tabelas derivadas força a materialização, para que cada RAND()
-- seja sorteado uma única vez por linha.
-- Cenário de teste intencional: ids múltiplos de 13 = ruptura; resto 3 na divisão por 7 = estoque crítico;
-- ids múltiplos de 5 = lote vencendo em 10 a 80 dias; ids múltiplos de 11 = lote já vencido.
-- ============================================================
USE farmacia;
SET @matriz := 1;
SET SESSION cte_max_recursion_depth = 10000;

DROP TABLE IF EXISTS seed_num;
CREATE TABLE seed_num (n INT NOT NULL PRIMARY KEY);
INSERT INTO seed_num
WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 200)
SELECT n FROM r;

-- Calendário com sazonalidade semanal e crescimento suave (mais antigo = menor)
DROP TABLE IF EXISTS seed_dias;
CREATE TABLE seed_dias (dia DATE NOT NULL PRIMARY KEY, fator DECIMAL(4,3) NOT NULL);
INSERT INTO seed_dias (dia, fator)
SELECT DATE_SUB(CURDATE(), INTERVAL n DAY),
       ROUND((CASE DAYOFWEEK(DATE_SUB(CURDATE(), INTERVAL n DAY))
                WHEN 1 THEN 0.35 WHEN 7 THEN 0.60 ELSE 0.55 END)
             * (0.85 + 0.15 * (180 - n) / 180), 3)
FROM seed_num WHERE n <= 180;

-- Pesos de popularidade (sorteio ponderado de produtos)
DROP TABLE IF EXISTS seed_peso;
CREATE TABLE seed_peso (
  id_produto INT UNSIGNED PRIMARY KEY, pop DECIMAL(5,2), ini DECIMAL(10,4), fim DECIMAL(10,4)
);
INSERT INTO seed_peso (id_produto, pop, ini, fim)
SELECT p.id_produto, s.pop,
       SUM(s.pop) OVER (ORDER BY s.id) - s.pop,
       SUM(s.pop) OVER (ORDER BY s.id)
FROM seed_produtos s
JOIN produtos p ON p.ean = CONCAT('7890000', LPAD(s.id,6,'0'));
SELECT SUM(pop) INTO @peso_total FROM seed_peso;

-- VENDAS (~70 tickets/dia; 78% PDV, 12% e-commerce, 10% Click and Collect; 2% canceladas)
INSERT INTO vendas (id_filial, data_hora, canal, status)
SELECT @matriz,
       TIMESTAMP(t.dia, SEC_TO_TIME(8*3600 + FLOOR(t.rh * 12 * 3600))),
       CASE WHEN t.rc < 0.78 THEN 'PDV' WHEN t.rc < 0.90 THEN 'ECOMMERCE' ELSE 'CLICK_COLLECT' END,
       IF(t.rs < 0.02, 'CANCELADA', 'CONCLUIDA')
FROM (SELECT d.dia, d.fator, RAND() rk, RAND() rh, RAND() rc, RAND() rs
      FROM seed_dias d JOIN seed_num n ON n.n <= 130
      LIMIT 100000000) t
WHERE t.rk < t.fator;

-- ITENS DE VENDA (1 a 4 linhas por ticket, produto sorteado pelo peso)
INSERT INTO itens_venda (id_venda, id_produto, qtd, preco_unitario, custo_unitario, desconto)
SELECT t.id_venda, p.id_produto, t.qtd, p.preco_venda, p.custo_medio,
       IF(t.rd < 0.08, ROUND(t.qtd * p.preco_venda * 0.10, 2), 0)
FROM (SELECT v.id_venda, k.n AS k, RAND() * @peso_total AS u,
             1 + (RAND() < 0.25) + (RAND() < 0.08) AS qtd, RAND() AS rd, RAND() AS keep
      FROM vendas v JOIN seed_num k ON k.n <= 4
      LIMIT 100000000) t
JOIN seed_peso w ON t.u >= w.ini AND t.u < w.fim
JOIN produtos p ON p.id_produto = w.id_produto
WHERE t.k = 1 OR t.keep < CASE t.k WHEN 2 THEN 0.55 WHEN 3 THEN 0.25 ELSE 0.10 END;

-- RESERVAS DO CLICK AND COLLECT (reserva no pedido, validade 48h)
INSERT INTO reservas_click_collect (id_venda, id_produto, qtd, status, reservado_em, expira_em)
SELECT v.id_venda, iv.id_produto, iv.qtd,
       IF(DATE(v.data_hora) = DATE_SUB(CURDATE(), INTERVAL 1 DAY), 'RESERVADA', 'RETIRADA'),
       v.data_hora, DATE_ADD(v.data_hora, INTERVAL 48 HOUR)
FROM vendas v JOIN itens_venda iv ON iv.id_venda = v.id_venda
WHERE v.canal = 'CLICK_COLLECT' AND v.status = 'CONCLUIDA';

-- COMPRAS: 1 pedido por fornecedor por semana (27 semanas); pedidos ainda não entregues ficam ENVIADO
INSERT INTO compras (id_filial, id_fornecedor, data_pedido, data_prevista, data_recebimento, status)
SELECT @matriz, t.id_fornecedor, t.dped, DATE_ADD(t.dped, INTERVAL t.prazo DAY),
       IF(t.rec_calc <= CURDATE(), t.rec_calc, NULL),
       IF(t.rec_calc <= CURDATE(), 'RECEBIDO', 'ENVIADO')
FROM (SELECT f.id_fornecedor, f.prazo_entrega_dias AS prazo,
             DATE_SUB(CURDATE(), INTERVAL (s.n - 1) * 7 DAY) AS dped,
             DATE_ADD(DATE_SUB(CURDATE(), INTERVAL (s.n - 1) * 7 DAY),
                      INTERVAL f.prazo_entrega_dias + IF(RAND() < 0.7, 0, 1 + FLOOR(RAND() * 3)) DAY) AS rec_calc
      FROM seed_num s CROSS JOIN fornecedores f
      WHERE s.n <= 27
      LIMIT 100000000) t;

-- ITENS DE COMPRA (pedido = consumo semanal real x 0,95 a 1,15; fill rate 88% a 100%)
INSERT INTO itens_compra (id_compra, id_produto, qtd_pedida, qtd_recebida, custo_unitario)
SELECT t.id_compra, t.id_produto, t.qp,
       IF(t.status = 'RECEBIDO', ROUND(t.qp * (0.88 + t.rf * 0.12)), 0),
       ROUND(t.custo * (0.97 + t.rc * 0.06), 2)
FROM (SELECT c.id_compra, c.status, p.id_produto, p.custo_medio AS custo,
             GREATEST(1, CEIL(COALESCE(k.consumo_dia, 0.2) * 7 * (0.95 + RAND() * 0.20))) AS qp,
             RAND() AS rf, RAND() AS rc
      FROM compras c
      JOIN produtos p ON p.id_fornecedor_padrao = c.id_fornecedor
      LEFT JOIN v_consumo_90d k ON k.id_filial = c.id_filial AND k.id_produto = p.id_produto
      WHERE c.id_filial = @matriz
      LIMIT 100000000) t;

-- LOTES EM ESTOQUE (2 por produto)
INSERT INTO estoque_lotes (id_filial, id_produto, lote, validade, qtd_atual, custo_unitario, data_entrada)
SELECT @matriz, t.id_produto, CONCAT(x.tag, '-', LPAD(t.id_produto, 4, '0')),
       CASE WHEN t.controle_validade = 0 THEN NULL
            WHEN x.tag = 'L1' AND MOD(t.id_produto, 5) = 0 THEN DATE_ADD(CURDATE(), INTERVAL 10 + FLOOR(t.r1 * 70) DAY)
            WHEN x.tag = 'L1' THEN DATE_ADD(CURDATE(), INTERVAL 200 + FLOOR(t.r1 * 300) DAY)
            ELSE DATE_ADD(CURDATE(), INTERVAL 400 + FLOOR(t.r2 * 300) DAY) END,
       ROUND(t.alvo * x.share), t.custo_medio,
       DATE_SUB(CURDATE(), INTERVAL IF(x.tag = 'L1', 40, 10) DAY)
FROM (SELECT p.id_produto, p.custo_medio, c.controle_validade,
             CASE WHEN MOD(p.id_produto, 13) = 0 THEN 0
                  ELSE CEIL(COALESCE(k.consumo_dia, 0.2) * pc.cobertura_alvo_dias *
                       (CASE WHEN MOD(p.id_produto, 7) = 3 THEN 0.15 ELSE 0.4 + RAND() * 1.4 END)) END AS alvo,
             RAND() r1, RAND() r2
      FROM produtos p
      JOIN categorias c ON c.id_categoria = p.id_categoria
      JOIN parametros_categoria pc ON pc.id_categoria = p.id_categoria
      LEFT JOIN v_consumo_90d k ON k.id_filial = @matriz AND k.id_produto = p.id_produto
      LIMIT 100000000) t
JOIN (SELECT 'L1' AS tag, 0.4 AS share UNION ALL SELECT 'L2', 0.6) x
WHERE ROUND(t.alvo * x.share) > 0;

-- Lotes já vencidos, para testar o alerta VENCIDO
INSERT INTO estoque_lotes (id_filial, id_produto, lote, validade, qtd_atual, custo_unitario, data_entrada)
SELECT @matriz, p.id_produto, CONCAT('VENC-', LPAD(p.id_produto, 4, '0')),
       DATE_SUB(CURDATE(), INTERVAL 12 DAY), 4, p.custo_medio, DATE_SUB(CURDATE(), INTERVAL 400 DAY)
FROM produtos p JOIN categorias c ON c.id_categoria = p.id_categoria
WHERE c.controle_validade = 1 AND MOD(p.id_produto, 11) = 0;

UPDATE produto_filial pf
JOIN v_consumo_90d k ON k.id_filial = pf.id_filial AND k.id_produto = pf.id_produto
SET pf.estoque_minimo = CEIL(k.consumo_dia * pf.dias_seguranca)
WHERE pf.id_filial = @matriz;

-- KARDEX: entradas, saídas, perdas e reconciliação inicial
INSERT INTO movimentacoes_estoque (id_filial, id_produto, tipo, qtd, data_hora, obs)
SELECT c.id_filial, ic.id_produto, 'ENTRADA_COMPRA', ic.qtd_recebida, TIMESTAMP(c.data_recebimento, '09:00:00'), 'Recebimento de compra'
FROM compras c JOIN itens_compra ic ON ic.id_compra = c.id_compra
WHERE c.status = 'RECEBIDO' AND ic.qtd_recebida > 0;

INSERT INTO movimentacoes_estoque (id_filial, id_produto, tipo, qtd, data_hora, obs)
SELECT v.id_filial, iv.id_produto, 'SAIDA_VENDA', -iv.qtd, v.data_hora, v.canal
FROM vendas v JOIN itens_venda iv ON iv.id_venda = v.id_venda
WHERE v.status = 'CONCLUIDA';

INSERT INTO movimentacoes_estoque (id_filial, id_produto, tipo, qtd, data_hora, obs)
SELECT @matriz, t.id_produto,
       CASE WHEN t.r < 0.5 THEN 'QUEBRA' WHEN t.r < 0.85 THEN 'PERDA' ELSE 'VENCIMENTO' END,
       -(1 + FLOOR(t.r2 * 3)), TIMESTAMP(t.dia, '18:00:00'), 'Perda operacional simulada'
FROM (SELECT p.id_produto, d.dia, RAND() r, RAND() r2, RAND() rk
      FROM produtos p CROSS JOIN seed_dias d LIMIT 100000000) t
WHERE t.rk < 0.004;

INSERT INTO movimentacoes_estoque (id_filial, id_produto, tipo, qtd, data_hora, obs)
SELECT @matriz, p.id_produto, 'AJUSTE',
       COALESCE(e.q, 0) - COALESCE(m.q, 0),
       TIMESTAMP(DATE_SUB(CURDATE(), INTERVAL 180 DAY), '00:00:00'),
       'Saldo inicial / reconciliação da simulação'
FROM produtos p
LEFT JOIN (SELECT id_produto, SUM(qtd_atual) q FROM estoque_lotes
           WHERE id_filial = @matriz GROUP BY id_produto) e ON e.id_produto = p.id_produto
LEFT JOIN (SELECT id_produto, SUM(qtd) q FROM movimentacoes_estoque
           WHERE id_filial = @matriz GROUP BY id_produto) m ON m.id_produto = p.id_produto
WHERE COALESCE(e.q, 0) <> COALESCE(m.q, 0);

-- LIVRO DE CONTROLADOS (simulado)
INSERT INTO livro_controlados (id_filial, id_produto, tipo_mov, qtd, data_hora, numero_receita, crm_prescritor, farmaceutico_resp)
SELECT v.id_filial, iv.id_produto, 'SAIDA', iv.qtd, v.data_hora,
       CONCAT('RX', LPAD(iv.id_item, 8, '0')),
       CONCAT('CRM-SP-', 10000 + MOD(iv.id_item * 7919, 80000)),
       'Farmacêutico Responsável (simulado)'
FROM itens_venda iv
JOIN vendas v ON v.id_venda = iv.id_venda AND v.status = 'CONCLUIDA'
JOIN produtos p ON p.id_produto = iv.id_produto AND p.controlado_344 = 1;

INSERT INTO livro_controlados (id_filial, id_produto, tipo_mov, qtd, data_hora, farmaceutico_resp)
SELECT c.id_filial, ic.id_produto, 'ENTRADA', ic.qtd_recebida, TIMESTAMP(c.data_recebimento, '09:00:00'),
       'Farmacêutico Responsável (simulado)'
FROM compras c
JOIN itens_compra ic ON ic.id_compra = c.id_compra AND ic.qtd_recebida > 0
JOIN produtos p ON p.id_produto = ic.id_produto AND p.controlado_344 = 1
WHERE c.status = 'RECEBIDO';

-- METAS: meses fechados, baseadas no ritmo recente x 0,92 a 1,12
INSERT INTO metas_comerciais (id_filial, id_categoria, competencia, meta_receita, meta_margem_pct)
SELECT @matriz, r.id_categoria, m.competencia, ROUND(r.ref_mes * (0.92 + RAND() * 0.20), 2), c.margem_alvo_pct
FROM (SELECT DISTINCT DATE_SUB(dia, INTERVAL DAYOFMONTH(dia) - 1 DAY) AS competencia FROM seed_dias) m
CROSS JOIN (SELECT p.id_categoria, SUM(iv.qtd * iv.preco_unitario - iv.desconto) / 90 * 30 AS ref_mes
            FROM vendas v
            JOIN itens_venda iv ON iv.id_venda = v.id_venda
            JOIN produtos p ON p.id_produto = iv.id_produto
            WHERE v.status = 'CONCLUIDA' AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
            GROUP BY p.id_categoria) r
JOIN categorias c ON c.id_categoria = r.id_categoria
WHERE m.competencia > DATE_SUB(DATE_SUB(CURDATE(), INTERVAL 180 DAY),
                               INTERVAL DAYOFMONTH(DATE_SUB(CURDATE(), INTERVAL 180 DAY)) - 1 DAY)
  AND m.competencia < DATE_SUB(CURDATE(), INTERVAL DAYOFMONTH(CURDATE()) - 1 DAY);

-- SNAPSHOTS: histórico diário de estoque reconstruído a partir do Kardex
INSERT INTO estoque_snapshot_diario (data_ref, id_filial, id_produto, qtd, valor_estoque)
SELECT x.dia, @matriz, x.id_produto, x.saldo, ROUND(x.saldo * p.custo_medio, 2)
FROM (SELECT d.dia, p2.id_produto,
             GREATEST(SUM(COALESCE(m.q, 0)) OVER (PARTITION BY p2.id_produto ORDER BY d.dia), 0) AS saldo
      FROM seed_dias d
      CROSS JOIN produtos p2
      LEFT JOIN (SELECT id_produto, DATE(data_hora) AS dia, SUM(qtd) AS q
                 FROM movimentacoes_estoque WHERE id_filial = @matriz
                 GROUP BY id_produto, DATE(data_hora)) m
             ON m.id_produto = p2.id_produto AND m.dia = d.dia) x
JOIN produtos p ON p.id_produto = x.id_produto;
