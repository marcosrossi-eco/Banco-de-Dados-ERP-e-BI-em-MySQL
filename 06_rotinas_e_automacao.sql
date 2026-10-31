-- ============================================================
-- 06_rotinas_e_automacao.sql | Procedures, trigger, eventos e afinidades iniciais
-- Contém DELIMITER: no MySQL Workbench/DBeaver rode o arquivo inteiro como script.
-- ============================================================
USE farmacia;

DROP PROCEDURE IF EXISTS sp_gerar_liquidacao;
DROP PROCEDURE IF EXISTS sp_ativar_liquidacao;
DROP PROCEDURE IF EXISTS sp_baixar_vencidos;
DROP PROCEDURE IF EXISTS sp_encerrar_liquidacoes;
DROP PROCEDURE IF EXISTS sp_atualizar_afinidades;
DROP PROCEDURE IF EXISTS sp_criar_cross_selling;
DROP PROCEDURE IF EXISTS sp_ativar_cross_selling;
DROP PROCEDURE IF EXISTS sp_provisionar_filial;
DROP PROCEDURE IF EXISTS sp_veredito_rollout;
DROP TRIGGER   IF EXISTS tr_afinidades_valida;

DELIMITER $$

-- ---------- LIQUIDAÇÃO (camada 4) ----------
-- Gera sugestões. Medicamento de prescrição/controlado nunca recebe desconto: vira DEVOLVER_FORNECEDOR.
CREATE PROCEDURE sp_gerar_liquidacao(IN p_filial INT UNSIGNED)
BEGIN
  DECLARE v_camp INT UNSIGNED;
  DECLARE v_n INT DEFAULT 0;

  UPDATE liquidacao_lotes SET status = 'CANCELADA'
  WHERE id_filial = p_filial AND status = 'SUGERIDA';

  INSERT INTO campanhas (id_filial, nome, tipo, canal, data_inicio, data_fim, desconto_pct, status)
  VALUES (p_filial, CONCAT('Liquidação FEFO ', DATE_FORMAT(CURDATE(), '%d/%m/%Y')),
          'LIQUIDACAO_VENCIMENTO', 'TODOS', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY),
          0.00, 'PLANEJADA');
  SET v_camp = LAST_INSERT_ID();

  INSERT INTO liquidacao_lotes
    (id_filial, id_campanha, id_lote, id_produto, qtd_em_risco, dias_para_vencer,
     preco_original, desconto_pct, preco_liquidacao, acao)
  SELECT p_filial,
         IF(p.exige_receita = 1 OR p.controlado_344 = 1 OR p.tarja <> 'SEM_TARJA', NULL, v_camp),
         l.id_lote, l.id_produto,
         l.qtd_atual - FLOOR(COALESCE(k.consumo_dia, 0) * DATEDIFF(l.validade, CURDATE())),
         DATEDIFF(l.validade, CURDATE()),
         p.preco_venda, r.desconto_pct,
         ROUND(LEAST(p.preco_venda,
                     GREATEST(p.preco_venda * (1 - r.desconto_pct / 100),
                              l.custo_unitario * (1 + r.margem_minima_pct / 100))), 2),
         IF(p.exige_receita = 1 OR p.controlado_344 = 1 OR p.tarja <> 'SEM_TARJA',
            'DEVOLVER_FORNECEDOR', 'LIQUIDAR')
  FROM estoque_lotes l
  JOIN produtos p ON p.id_produto = l.id_produto
  JOIN regras_liquidacao r ON DATEDIFF(l.validade, CURDATE()) BETWEEN r.dias_min AND r.dias_max
  LEFT JOIN v_consumo_90d k ON k.id_filial = l.id_filial AND k.id_produto = l.id_produto
  WHERE l.id_filial = p_filial AND l.qtd_atual > 0
    AND l.validade IS NOT NULL AND l.validade >= CURDATE()
    AND l.qtd_atual > COALESCE(k.consumo_dia, 0) * DATEDIFF(l.validade, CURDATE())
    AND NOT EXISTS (SELECT 1 FROM liquidacao_lotes x
                    WHERE x.id_lote = l.id_lote AND x.status = 'ATIVA');

  INSERT INTO liquidacao_lotes
    (id_filial, id_campanha, id_lote, id_produto, qtd_em_risco, dias_para_vencer,
     preco_original, desconto_pct, preco_liquidacao, acao)
  SELECT p_filial, NULL, l.id_lote, l.id_produto, l.qtd_atual,
         DATEDIFF(l.validade, CURDATE()), NULL, NULL, NULL, 'BAIXAR_VENCIDO'
  FROM estoque_lotes l
  WHERE l.id_filial = p_filial AND l.qtd_atual > 0 AND l.validade < CURDATE();

  INSERT IGNORE INTO campanha_itens (id_campanha, id_produto, papel)
  SELECT DISTINCT id_campanha, id_produto, 'ANCORA'
  FROM liquidacao_lotes
  WHERE id_campanha = v_camp AND acao = 'LIQUIDAR';

  SELECT COUNT(*) INTO v_n FROM campanha_itens WHERE id_campanha = v_camp;
  IF v_n = 0 THEN
    DELETE FROM campanhas WHERE id_campanha = v_camp;
  END IF;
END$$

CREATE PROCEDURE sp_ativar_liquidacao(IN p_campanha INT UNSIGNED)
BEGIN
  UPDATE campanhas SET status = 'ATIVA', data_inicio = CURDATE()
  WHERE id_campanha = p_campanha AND status = 'PLANEJADA';
  UPDATE liquidacao_lotes SET status = 'ATIVA'
  WHERE id_campanha = p_campanha AND acao = 'LIQUIDAR' AND status = 'SUGERIDA';
END$$

-- Controlados ficam de fora da baixa automática: exigem procedimento formal e registro próprio
CREATE PROCEDURE sp_baixar_vencidos(IN p_filial INT UNSIGNED)
BEGIN
  INSERT INTO movimentacoes_estoque (id_filial, id_produto, id_lote, tipo, qtd, data_hora, obs)
  SELECT l.id_filial, l.id_produto, l.id_lote, 'VENCIMENTO', -l.qtd_atual, NOW(), 'Baixa de lote vencido'
  FROM estoque_lotes l JOIN produtos p ON p.id_produto = l.id_produto
  WHERE l.id_filial = p_filial AND l.qtd_atual > 0 AND l.validade < CURDATE() AND p.controlado_344 = 0;

  UPDATE liquidacao_lotes q
  JOIN estoque_lotes l ON l.id_lote = q.id_lote
  JOIN produtos p ON p.id_produto = l.id_produto
  SET q.status = 'CONCLUIDA'
  WHERE q.id_filial = p_filial AND q.acao = 'BAIXAR_VENCIDO' AND q.status = 'SUGERIDA'
    AND l.validade < CURDATE() AND p.controlado_344 = 0;

  UPDATE estoque_lotes l JOIN produtos p ON p.id_produto = l.id_produto
  SET l.qtd_atual = 0
  WHERE l.id_filial = p_filial AND l.qtd_atual > 0 AND l.validade < CURDATE() AND p.controlado_344 = 0;
END$$

CREATE PROCEDURE sp_encerrar_liquidacoes(IN p_filial INT UNSIGNED)
BEGIN
  UPDATE liquidacao_lotes q JOIN campanhas c ON c.id_campanha = q.id_campanha
  SET q.status = 'CONCLUIDA'
  WHERE q.id_filial = p_filial AND q.status = 'ATIVA' AND c.data_fim < CURDATE();

  UPDATE campanhas SET status = 'ENCERRADA'
  WHERE id_filial = p_filial AND tipo = 'LIQUIDACAO_VENCIMENTO'
    AND status = 'ATIVA' AND data_fim < CURDATE();
END$$

-- ---------- CROSS-SELLING (camada 3) ----------
-- Âncora só MIP; complemento só do segmento 3 (Bem-Estar, Conveniência e Impulso)
CREATE TRIGGER tr_afinidades_valida BEFORE INSERT ON afinidades FOR EACH ROW
BEGIN
  IF (SELECT tipo_medicamento FROM produtos WHERE id_produto = NEW.id_ancora) <> 'MIP' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Âncora deve ser MIP';
  END IF;
  IF (SELECT c.id_segmento FROM produtos p JOIN categorias c ON c.id_categoria = p.id_categoria
      WHERE p.id_produto = NEW.id_complemento) <> 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Complemento deve ser do segmento Bem-Estar, Conveniência e Impulso';
  END IF;
END$$

-- Descobre afinidades reais nos tickets (180 dias): 5+ vendas juntas e lift >= 1,2
CREATE PROCEDURE sp_atualizar_afinidades(IN p_filial INT UNSIGNED)
BEGIN
  INSERT INTO afinidades (id_ancora, id_complemento, origem, lift, n_juntos)
  WITH itens AS (
    SELECT DISTINCT iv.id_venda, iv.id_produto
    FROM itens_venda iv JOIN vendas v ON v.id_venda = iv.id_venda
    WHERE v.id_filial = p_filial AND v.status = 'CONCLUIDA'
      AND v.data_hora >= DATE_SUB(CURDATE(), INTERVAL 180 DAY)
  ),
  tot  AS (SELECT COUNT(DISTINCT id_venda) AS n FROM itens),
  solo AS (SELECT id_produto, COUNT(*) AS n FROM itens GROUP BY id_produto),
  pares AS (
    SELECT a.id_produto AS ia, b.id_produto AS ib, COUNT(*) AS nj
    FROM itens a
    JOIN itens b ON b.id_venda = a.id_venda
    JOIN produtos pa ON pa.id_produto = a.id_produto AND pa.tipo_medicamento = 'MIP'
    JOIN produtos pb ON pb.id_produto = b.id_produto
    JOIN categorias cb ON cb.id_categoria = pb.id_categoria AND cb.id_segmento = 3
    GROUP BY a.id_produto, b.id_produto
    HAVING COUNT(*) >= 5
  )
  SELECT p.ia, p.ib, 'DADOS', ROUND((p.nj / sa.n) / (sb.n / t.n), 2), p.nj
  FROM pares p
  JOIN solo sa ON sa.id_produto = p.ia
  JOIN solo sb ON sb.id_produto = p.ib
  CROSS JOIN tot t
  WHERE (p.nj / sa.n) / (sb.n / t.n) >= 1.2
  ON DUPLICATE KEY UPDATE lift = VALUES(lift), n_juntos = VALUES(n_juntos);
END$$

-- Cria "Leve junto na retirada" (nasce PLANEJADA). Combo bloqueado se faltar estoque; piso de margem de 15% no complemento
CREATE PROCEDURE sp_criar_cross_selling(IN p_filial INT UNSIGNED, IN p_desc DECIMAL(5,2), IN p_dias SMALLINT)
BEGIN
  DECLARE v_camp INT UNSIGNED;
  DECLARE v_n INT DEFAULT 0;

  INSERT INTO campanhas (id_filial, nome, tipo, canal, data_inicio, data_fim, desconto_pct, status)
  VALUES (p_filial, CONCAT('Leve junto na retirada ', DATE_FORMAT(CURDATE(), '%d/%m/%Y')),
          'CROSS_SELLING', 'CLICK_COLLECT', CURDATE(), DATE_ADD(CURDATE(), INTERVAL p_dias DAY),
          p_desc, 'PLANEJADA');
  SET v_camp = LAST_INSERT_ID();

  INSERT INTO campanha_combos (id_campanha, id_ancora, id_complemento, preco_normal_compl, desconto_pct, preco_combo_compl)
  SELECT v_camp, af.id_ancora, af.id_complemento, pc.preco_venda, p_desc,
         ROUND(LEAST(pc.preco_venda,
                     GREATEST(pc.preco_venda * (1 - p_desc / 100), pc.custo_medio * 1.15)), 2)
  FROM afinidades af
  JOIN produtos pa ON pa.id_produto = af.id_ancora      AND pa.ativo = 1
  JOIN produtos pc ON pc.id_produto = af.id_complemento AND pc.ativo = 1
  JOIN v_metricas_estoque ma ON ma.id_filial = p_filial AND ma.id_produto = af.id_ancora
  JOIN v_metricas_estoque mc ON mc.id_filial = p_filial AND mc.id_produto = af.id_complemento
  WHERE af.ativa = 1
    AND ma.qtd_estoque > ma.estoque_seguranca
    AND mc.qtd_estoque > mc.estoque_seguranca;

  INSERT IGNORE INTO campanha_itens (id_campanha, id_produto, papel)
  SELECT id_campanha, id_ancora, 'ANCORA' FROM campanha_combos WHERE id_campanha = v_camp;
  INSERT IGNORE INTO campanha_itens (id_campanha, id_produto, papel)
  SELECT id_campanha, id_complemento, 'COMPLEMENTO' FROM campanha_combos WHERE id_campanha = v_camp;

  SELECT COUNT(*) INTO v_n FROM campanha_combos WHERE id_campanha = v_camp;
  IF v_n = 0 THEN
    DELETE FROM campanha_itens WHERE id_campanha = v_camp;
    DELETE FROM campanhas WHERE id_campanha = v_camp;
  END IF;
  SELECT IF(v_n = 0, NULL, v_camp) AS id_campanha_criada, v_n AS combos;
END$$

CREATE PROCEDURE sp_ativar_cross_selling(IN p_campanha INT UNSIGNED)
BEGIN
  UPDATE campanhas SET status = 'ATIVA', data_inicio = CURDATE()
  WHERE id_campanha = p_campanha AND tipo = 'CROSS_SELLING' AND status = 'PLANEJADA';
END$$

-- ---------- ROLLOUT (camada 6) ----------
-- Cria uma filial herdando parâmetros da Matriz (id 1). Os m² copiados são PLACEHOLDER.
CREATE PROCEDURE sp_provisionar_filial(
  IN p_nome VARCHAR(100), IN p_cnpj CHAR(14), IN p_bairro VARCHAR(80), IN p_cidade VARCHAR(80))
BEGIN
  DECLARE v_id INT UNSIGNED;
  INSERT INTO filiais (nome, cnpj, tipo, bairro, cidade) VALUES (p_nome, p_cnpj, 'FILIAL', p_bairro, p_cidade);
  SET v_id = LAST_INSERT_ID();

  INSERT INTO produto_filial (id_filial, id_produto, estoque_minimo, dias_seguranca, lead_time_dias)
  SELECT v_id, id_produto, 0, dias_seguranca, lead_time_dias FROM produto_filial WHERE id_filial = 1;

  INSERT INTO area_categoria_filial (id_filial, id_categoria, metros_quadrados)
  SELECT v_id, id_categoria, metros_quadrados FROM area_categoria_filial WHERE id_filial = 1;

  SELECT v_id AS id_filial_criada;
END$$

-- Veredito de prontidão: os limiares vêm da tabela parametros_rollout
CREATE PROCEDURE sp_veredito_rollout(IN p_filial INT UNSIGNED)
BEGIN
  WITH kpis AS (
    SELECT 'Histórico de vendas (meses)' AS kpi,
           TIMESTAMPDIFF(MONTH, MIN(data_hora), MAX(data_hora)) AS valor_atual
    FROM vendas WHERE id_filial = p_filial
    UNION ALL
    SELECT 'Cadastro completo (% produtos ativos)',
           ROUND(100 * SUM(custo_medio > 0 AND preco_venda > 0 AND id_fornecedor_padrao IS NOT NULL) / COUNT(*), 2)
    FROM produtos WHERE ativo = 1
    UNION ALL
    SELECT 'Lotes com validade (% categorias com controle)',
           ROUND(100 * SUM(l.validade IS NOT NULL) / COUNT(*), 2)
    FROM estoque_lotes l
    JOIN produtos p   ON p.id_produto = l.id_produto
    JOIN categorias c ON c.id_categoria = p.id_categoria
    WHERE l.id_filial = p_filial AND l.qtd_atual > 0 AND c.controle_validade = 1
    UNION ALL
    SELECT 'Taxa de ruptura (% SKUs com giro)',
           ROUND(100 * SUM(qtd_estoque = 0) / COUNT(*), 2)
    FROM v_metricas_estoque WHERE id_filial = p_filial AND consumo_dia > 0
    UNION ALL
    SELECT 'Atingimento de meta (3 últimos meses fechados, %)',
           ROUND(100 * SUM(receita_real) / NULLIF(SUM(meta_receita), 0), 2)
    FROM v_meta_vs_real
    WHERE id_filial = p_filial
      AND competencia >= DATE_SUB(DATE_SUB(CURDATE(), INTERVAL DAYOFMONTH(CURDATE()) - 1 DAY), INTERVAL 3 MONTH)
      AND competencia <  DATE_SUB(CURDATE(), INTERVAL DAYOFMONTH(CURDATE()) - 1 DAY)
    UNION ALL
    SELECT 'Fill rate dos fornecedores (%)',
           ROUND(100 * SUM(ic.qtd_recebida) / NULLIF(SUM(ic.qtd_pedida), 0), 2)
    FROM compras c JOIN itens_compra ic ON ic.id_compra = c.id_compra
    WHERE c.id_filial = p_filial AND c.status = 'RECEBIDO'
  ),
  avaliado AS (
    SELECT k.kpi, k.valor_atual, r.regra, r.limite,
           COALESCE(CASE r.regra WHEN '>=' THEN k.valor_atual >= r.limite
                                 ELSE k.valor_atual <= r.limite END, 0) AS ok
    FROM kpis k
    JOIN parametros_rollout r ON r.kpi = k.kpi COLLATE utf8mb4_0900_ai_ci
  )
  SELECT kpi, valor_atual, regra, limite, IF(ok, 'OK', 'PENDENTE') AS status FROM avaliado
  UNION ALL
  SELECT 'VEREDITO DE ROLLOUT', NULL, NULL, NULL, IF(MIN(ok) = 1, 'APTO', 'NÃO APTO') FROM avaliado;
END$$

DELIMITER ;

-- ---------- Eventos agendados (requer event_scheduler = ON; ver 08_usuarios_e_backup.sql) ----------
-- Snapshot diário de estoque (posição de fechamento do dia anterior)
CREATE EVENT IF NOT EXISTS ev_snapshot_diario
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO
  INSERT INTO estoque_snapshot_diario (data_ref, id_filial, id_produto, qtd, valor_estoque)
  SELECT DATE_SUB(CURDATE(), INTERVAL 1 DAY), pf.id_filial, pf.id_produto,
         COALESCE(SUM(l.qtd_atual), 0),
         COALESCE(ROUND(SUM(l.qtd_atual * l.custo_unitario), 2), 0)
  FROM produto_filial pf
  LEFT JOIN estoque_lotes l ON l.id_filial = pf.id_filial AND l.id_produto = pf.id_produto
  GROUP BY pf.id_filial, pf.id_produto
  ON DUPLICATE KEY UPDATE qtd = VALUES(qtd), valor_estoque = VALUES(valor_estoque);

-- Sugestões de liquidação toda semana (a APROVAÇÃO continua manual)
CREATE EVENT IF NOT EXISTS ev_liquidacao_semanal
ON SCHEDULE EVERY 1 WEEK STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 2 HOUR)
DO CALL sp_gerar_liquidacao(1);

CREATE EVENT IF NOT EXISTS ev_liquidacao_encerra
ON SCHEDULE EVERY 1 DAY STARTS (TIMESTAMP(CURDATE()) + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO CALL sp_encerrar_liquidacoes(1);

-- ---------- Hipóteses iniciais de afinidade (validar com o gestor e, depois, com dados reais) ----------
INSERT INTO afinidades (id_ancora, id_complemento, origem)
SELECT a.id_produto, b.id_produto, 'MANUAL'
FROM (SELECT 'Paracetamol 750mg 20 comp' AS an, 'Ômega 3 60 cápsulas' AS cp
      UNION ALL SELECT 'Ibuprofeno 400mg 10 cápsulas', 'Whey Protein 900g'
      UNION ALL SELECT 'Loratadina 10mg 12 comp', 'Hidratante Facial FPS 30 50g'
      UNION ALL SELECT 'Paracetamol 750mg 20 comp', 'Água Mineral 500ml') m
JOIN produtos a ON a.nome = m.an
JOIN produtos b ON b.nome = m.cp;
