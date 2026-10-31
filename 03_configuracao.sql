-- ============================================================
-- 03_configuracao.sql | Dados de CONFIGURAÇÃO (mantenha ao migrar para dados reais)
-- Valores de margem, cobertura, m² e limiares são HIPÓTESES de partida: ajuste à sua loja.
-- ============================================================
USE farmacia;

INSERT INTO filiais (nome, cnpj, tipo) VALUES
  ('Farmácia Matriz', '00000000000000', 'MATRIZ');   -- troque pelo CNPJ real

INSERT INTO segmentos (nome, zona_loja, localizacao, papel) VALUES
  ('Medicamentos',                       'Zona de Destino',     'Fundo da loja',                  'DESTINO'),
  ('Higiene Pessoal e Cuidados Diários', 'Zona de Rotina',      'Meio da loja',                   'ROTINA'),
  ('Bem-Estar, Conveniência e Impulso',  'Zona de Margem Alta', 'Entrada, corredores e checkout', 'MARGEM_ALTA'),
  ('Categorias Especializadas',          'Sazonal e Nicho',     'Ajustado ao bairro',             'NICHO');

INSERT INTO categorias (id_segmento, nome, exige_receita, controle_validade, atras_do_balcao, margem_alvo_pct) VALUES
  (1, 'Prescritos (Tarjados)',               1, 1, 1, 22.00),   -- id 1
  (1, 'Genéricos e Similares',               1, 1, 1, 45.00),   -- id 2
  (1, 'MIPs (Isentos de Prescrição)',        0, 1, 0, 32.00),   -- id 3
  (2, 'Cuidados Capilares',                  0, 1, 0, 38.00),   -- id 4
  (2, 'Higiene Oral',                        0, 1, 0, 40.00),   -- id 5
  (2, 'Cuidados Corporais',                  0, 1, 0, 38.00),   -- id 6
  (2, 'Barbear e Depilação',                 0, 0, 0, 40.00),   -- id 7
  (3, 'Dermocosméticos',                     0, 1, 0, 48.00),   -- id 8
  (3, 'Conveniência / Check-out',            0, 1, 0, 55.00),   -- id 9
  (3, 'Suplementos e Vitaminas',             0, 1, 0, 42.00),   -- id 10
  (4, 'Infantil e Baby',                     0, 1, 0, 25.00),   -- id 11
  (4, 'Melhor Idade / Cuidados Especiais',   0, 1, 0, 30.00),   -- id 12
  (4, 'Primeiros Socorros',                  0, 1, 0, 45.00);   -- id 13

INSERT INTO parametros_categoria (id_categoria, cobertura_alvo_dias, dias_seguranca) VALUES
  (1,20,4),(2,20,3),(3,15,3),(4,25,3),(5,30,3),(6,30,3),(7,40,3),
  (8,45,5),(9,10,2),(10,40,5),(11,20,4),(12,30,5),(13,45,4);

INSERT INTO area_categoria_filial (id_filial, id_categoria, metros_quadrados) VALUES
  (1,1,18),(1,2,14),(1,3,16),(1,4,10),(1,5,6),(1,6,12),(1,7,5),
  (1,8,9),(1,9,7),(1,10,8),(1,11,12),(1,12,6),(1,13,5);

-- Liquidação por faixa de dias até o vencimento (piso: custo + margem_minima_pct)
INSERT INTO regras_liquidacao (dias_min, dias_max, desconto_pct) VALUES
  (46, 60, 15.00), (31, 45, 25.00), (16, 30, 40.00), (0, 15, 50.00);

-- Critérios de prontidão para o rollout (usados por sp_veredito_rollout)
INSERT INTO parametros_rollout (kpi, regra, limite, descricao) VALUES
  ('Histórico de vendas (meses)',                      '>=',  6, 'Meses de dados reais na unidade'),
  ('Cadastro completo (% produtos ativos)',            '>=', 98, 'Custo, preço e fornecedor preenchidos'),
  ('Lotes com validade (% categorias com controle)',   '>=', 99, 'Rastreabilidade de validade'),
  ('Taxa de ruptura (% SKUs com giro)',                '<=',  3, 'SKUs com giro e estoque zero'),
  ('Atingimento de meta (3 últimos meses fechados, %)','>=', 95, 'Receita real / meta'),
  ('Fill rate dos fornecedores (%)',                   '>=', 90, 'Recebido / pedido');
