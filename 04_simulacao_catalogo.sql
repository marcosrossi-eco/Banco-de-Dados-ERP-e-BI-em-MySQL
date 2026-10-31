-- ============================================================
-- 04_simulacao_catalogo.sql | Fornecedores e catálogo SIMULADOS (39 produtos)
-- Dados fictícios para validar o pipeline. Remova com 99_limpar_simulacao.sql.
-- ============================================================
USE farmacia;
SET @matriz := 1;

INSERT INTO fornecedores (razao_social, cnpj, tipo, prazo_entrega_dias, condicao_pagamento) VALUES
 ('Laboratório Referência Nacional','10000000000001','LABORATORIO',5,'28 dias'),
 ('Laboratório Genéricos Brasil',   '10000000000002','LABORATORIO',4,'30 dias'),
 ('Distribuidora Saúde Sul',        '10000000000003','DISTRIBUIDOR',2,'21 dias'),
 ('Distribuidora Central Farma',    '10000000000004','DISTRIBUIDOR',2,'28 dias'),
 ('Indústria Higiene e Cuidados',   '10000000000005','LABORATORIO',3,'30 dias'),
 ('Distribuidora Conveniência Plus','10000000000006','DISTRIBUIDOR',1,'14 dias'),
 ('Nutri Suplementos Ltda',         '10000000000007','DISTRIBUIDOR',3,'28 dias'),
 ('Baby Care Distribuidora',        '10000000000008','DISTRIBUIDOR',3,'28 dias');

DROP TABLE IF EXISTS seed_produtos;
CREATE TABLE seed_produtos (
  id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  nome VARCHAR(150), cat VARCHAR(80), tipo VARCHAR(20), tarja VARCHAR(10),
  ctrl TINYINT, rec TINYINT, forn INT, custo DECIMAL(10,2), preco DECIMAL(10,2), pop DECIMAL(5,2)
);
INSERT INTO seed_produtos (nome,cat,tipo,tarja,ctrl,rec,forn,custo,preco,pop) VALUES
 ('Amoxicilina 500mg 21 cápsulas','Prescritos (Tarjados)','REFERENCIA','VERMELHA',0,1,1,18.50,39.90,6),
 ('Losartana Potássica 50mg 30 comp','Prescritos (Tarjados)','REFERENCIA','VERMELHA',0,1,1,12.00,27.90,9),
 ('Clonazepam 2mg 30 comp','Prescritos (Tarjados)','REFERENCIA','PRETA',1,1,1,9.00,21.90,5),
 ('Dipirona Sódica 500mg 10 comp (Genérico)','Genéricos e Similares','GENERICO','SEM_TARJA',0,0,2,2.10,6.90,12),
 ('Atenolol 25mg 30 comp (Genérico)','Genéricos e Similares','GENERICO','VERMELHA',0,1,2,3.80,12.90,8),
 ('Metformina 850mg 30 comp (Similar)','Genéricos e Similares','SIMILAR','VERMELHA',0,1,2,4.20,14.90,8),
 ('Paracetamol 750mg 20 comp','MIPs (Isentos de Prescrição)','MIP','SEM_TARJA',0,0,3,3.80,12.90,14),
 ('Ibuprofeno 400mg 10 cápsulas','MIPs (Isentos de Prescrição)','MIP','SEM_TARJA',0,0,3,5.50,16.90,10),
 ('Loratadina 10mg 12 comp','MIPs (Isentos de Prescrição)','MIP','SEM_TARJA',0,0,3,4.00,13.50,7),
 ('Shampoo Anticaspa 400ml','Cuidados Capilares','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,9.80,21.90,8),
 ('Condicionador Hidratação 325ml','Cuidados Capilares','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,7.20,17.90,6),
 ('Tintura Castanho Escuro 5.0','Cuidados Capilares','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,8.50,22.90,3),
 ('Creme Dental 90g','Higiene Oral','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,2.40,6.50,15),
 ('Escova Dental Macia','Higiene Oral','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,3.10,9.90,9),
 ('Enxaguante Bucal 500ml','Higiene Oral','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,8.60,19.90,6),
 ('Sabonete em Barra 85g','Cuidados Corporais','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,1.20,3.50,16),
 ('Desodorante Aerossol 150ml','Cuidados Corporais','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,7.90,16.90,11),
 ('Protetor Solar FPS 50 120ml','Cuidados Corporais','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,24.00,54.90,5),
 ('Aparelho de Barbear 2 Lâminas','Barbear e Depilação','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,3.00,8.90,5),
 ('Espuma de Barbear 200ml','Barbear e Depilação','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,6.50,15.90,4),
 ('Cera Depilatória Roll-on','Barbear e Depilação','NAO_MEDICAMENTO','SEM_TARJA',0,0,5,11.00,26.90,2),
 ('Hidratante Facial FPS 30 50g','Dermocosméticos','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,38.00,89.90,3),
 ('Sérum Vitamina C 30ml','Dermocosméticos','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,55.00,129.90,2),
 ('Água Micelar 200ml','Dermocosméticos','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,22.00,52.90,3),
 ('Bala de Menta 30g','Conveniência / Check-out','NAO_MEDICAMENTO','SEM_TARJA',0,0,6,0.90,2.99,20),
 ('Água Mineral 500ml','Conveniência / Check-out','NAO_MEDICAMENTO','SEM_TARJA',0,0,6,0.80,3.00,18),
 ('Pilha AA c/ 4','Conveniência / Check-out','NAO_MEDICAMENTO','SEM_TARJA',0,0,6,9.50,22.90,6),
 ('Whey Protein 900g','Suplementos e Vitaminas','NAO_MEDICAMENTO','SEM_TARJA',0,0,7,78.00,159.90,2),
 ('Creatina 300g','Suplementos e Vitaminas','NAO_MEDICAMENTO','SEM_TARJA',0,0,7,45.00,99.90,2),
 ('Ômega 3 60 cápsulas','Suplementos e Vitaminas','NAO_MEDICAMENTO','SEM_TARJA',0,0,7,21.00,49.90,4),
 ('Fralda Descartável M c/ 30','Infantil e Baby','NAO_MEDICAMENTO','SEM_TARJA',0,0,8,28.00,54.90,7),
 ('Lenço Umedecido 50un','Infantil e Baby','NAO_MEDICAMENTO','SEM_TARJA',0,0,8,4.50,11.90,8),
 ('Fórmula Infantil 800g','Infantil e Baby','NAO_MEDICAMENTO','SEM_TARJA',0,0,8,48.00,89.90,3),
 ('Fralda Geriátrica G c/ 8','Melhor Idade / Cuidados Especiais','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,22.00,44.90,3),
 ('Medidor de Glicemia + 10 tiras','Melhor Idade / Cuidados Especiais','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,38.00,79.90,1.5),
 ('Curativo Hidrocolóide','Melhor Idade / Cuidados Especiais','NAO_MEDICAMENTO','SEM_TARJA',0,0,4,14.00,32.90,1),
 ('Algodão 50g','Primeiros Socorros','NAO_MEDICAMENTO','SEM_TARJA',0,0,3,2.50,6.90,5),
 ('Gaze Estéril c/ 10','Primeiros Socorros','NAO_MEDICAMENTO','SEM_TARJA',0,0,3,2.00,5.90,4),
 ('Álcool 70% 1L','Primeiros Socorros','NAO_MEDICAMENTO','SEM_TARJA',0,0,3,5.50,12.90,7);

INSERT INTO produtos (ean, nome, id_categoria, tipo_medicamento, tarja, controlado_344,
                      exige_receita, id_fornecedor_padrao, custo_medio, preco_venda)
SELECT CONCAT('7890000', LPAD(s.id,6,'0')), s.nome, c.id_categoria, s.tipo, s.tarja,
       s.ctrl, s.rec, s.forn, s.custo, s.preco
FROM seed_produtos s JOIN categorias c ON c.nome = s.cat;

-- Preço máximo ao consumidor SIMULADO (substituir pela tabela CMED oficial)
UPDATE produtos SET preco_max_consumidor = ROUND(preco_venda * 1.10, 2)
WHERE tipo_medicamento <> 'NAO_MEDICAMENTO';

INSERT INTO produto_filial (id_filial, id_produto, estoque_minimo, dias_seguranca, lead_time_dias)
SELECT @matriz, p.id_produto, 0, pc.dias_seguranca, f.prazo_entrega_dias
FROM produtos p
JOIN parametros_categoria pc ON pc.id_categoria = p.id_categoria
JOIN fornecedores f ON f.id_fornecedor = p.id_fornecedor_padrao;
