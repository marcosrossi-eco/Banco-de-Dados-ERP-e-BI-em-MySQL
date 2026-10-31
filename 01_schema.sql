-- ============================================================
-- 01_schema.sql | Estrutura completa do banco (MySQL 8.0.16+)
-- Execute em um servidor onde o banco "farmacia" ainda não existe.
-- ============================================================
CREATE DATABASE IF NOT EXISTS farmacia
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE farmacia;

-- ---------- Hierarquia da loja ----------
CREATE TABLE filiais (
  id_filial  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome       VARCHAR(100) NOT NULL,
  cnpj       CHAR(14)     NOT NULL,
  tipo       ENUM('MATRIZ','FILIAL') NOT NULL DEFAULT 'FILIAL',
  bairro     VARCHAR(80)  NULL,
  cidade     VARCHAR(80)  NULL,
  ativo      TINYINT(1)   NOT NULL DEFAULT 1,
  criado_em  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_filial),
  UNIQUE KEY uk_filiais_cnpj (cnpj)
) ENGINE=InnoDB;

CREATE TABLE segmentos (
  id_segmento TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome        VARCHAR(80) NOT NULL,
  zona_loja   VARCHAR(80) NOT NULL,
  localizacao VARCHAR(80) NOT NULL,
  papel       ENUM('DESTINO','ROTINA','MARGEM_ALTA','NICHO') NOT NULL,
  PRIMARY KEY (id_segmento),
  UNIQUE KEY uk_segmentos_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE categorias (
  id_categoria      SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_segmento       TINYINT UNSIGNED NOT NULL,
  nome              VARCHAR(80) NOT NULL,
  exige_receita     TINYINT(1) NOT NULL DEFAULT 0,
  controle_validade TINYINT(1) NOT NULL DEFAULT 1,
  atras_do_balcao   TINYINT(1) NOT NULL DEFAULT 0,
  margem_alvo_pct   DECIMAL(5,2) NULL,
  PRIMARY KEY (id_categoria),
  UNIQUE KEY uk_categorias (id_segmento, nome),
  KEY ix_categorias_segmento (id_segmento),
  CONSTRAINT fk_categorias_segmento FOREIGN KEY (id_segmento) REFERENCES segmentos (id_segmento)
) ENGINE=InnoDB;

-- ---------- Cadastros ----------
CREATE TABLE fornecedores (
  id_fornecedor      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  razao_social       VARCHAR(150) NOT NULL,
  cnpj               CHAR(14) NOT NULL,
  tipo               ENUM('LABORATORIO','DISTRIBUIDOR') NOT NULL,
  prazo_entrega_dias TINYINT UNSIGNED NOT NULL DEFAULT 2,
  condicao_pagamento VARCHAR(60) NULL,
  ativo              TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id_fornecedor),
  UNIQUE KEY uk_fornecedores_cnpj (cnpj)
) ENGINE=InnoDB;

CREATE TABLE produtos (
  id_produto           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ean                  VARCHAR(14)  NOT NULL,
  nome                 VARCHAR(150) NOT NULL,
  id_categoria         SMALLINT UNSIGNED NOT NULL,
  principio_ativo      VARCHAR(150) NULL,
  tipo_medicamento     ENUM('NAO_MEDICAMENTO','REFERENCIA','GENERICO','SIMILAR','MIP') NOT NULL DEFAULT 'NAO_MEDICAMENTO',
  tarja                ENUM('SEM_TARJA','VERMELHA','PRETA') NOT NULL DEFAULT 'SEM_TARJA',
  controlado_344       TINYINT(1) NOT NULL DEFAULT 0,
  exige_receita        TINYINT(1) NOT NULL DEFAULT 0,
  id_fornecedor_padrao INT UNSIGNED NULL,
  custo_medio          DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  preco_venda          DECIMAL(10,2) NOT NULL,
  preco_max_consumidor DECIMAL(10,2) NULL,   -- CMED (simulado enquanto não houver tabela oficial)
  margem_pct           DECIMAL(6,2) GENERATED ALWAYS AS
     (IF(preco_venda > 0, ROUND((preco_venda - custo_medio) / preco_venda * 100, 2), 0)) STORED,
  ativo                TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id_produto),
  UNIQUE KEY uk_produtos_ean (ean),
  KEY ix_produtos_categoria (id_categoria),
  KEY ix_produtos_fornecedor (id_fornecedor_padrao),
  KEY ix_produtos_ativo_nome (ativo, nome),
  CONSTRAINT fk_produtos_categoria  FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria),
  CONSTRAINT fk_produtos_fornecedor FOREIGN KEY (id_fornecedor_padrao) REFERENCES fornecedores (id_fornecedor),
  CONSTRAINT ck_produtos_preco CHECK (preco_venda >= 0 AND custo_medio >= 0)
) ENGINE=InnoDB;

CREATE TABLE produto_filial (
  id_filial      INT UNSIGNED NOT NULL,
  id_produto     INT UNSIGNED NOT NULL,
  estoque_minimo INT UNSIGNED NOT NULL DEFAULT 0,
  dias_seguranca TINYINT UNSIGNED NOT NULL DEFAULT 3,
  lead_time_dias TINYINT UNSIGNED NOT NULL DEFAULT 2,
  PRIMARY KEY (id_filial, id_produto),
  KEY ix_pf_produto (id_produto),
  CONSTRAINT fk_pf_filial  FOREIGN KEY (id_filial)  REFERENCES filiais (id_filial),
  CONSTRAINT fk_pf_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE area_categoria_filial (
  id_filial        INT UNSIGNED NOT NULL,
  id_categoria     SMALLINT UNSIGNED NOT NULL,
  metros_quadrados DECIMAL(7,2) NOT NULL,
  PRIMARY KEY (id_filial, id_categoria),
  CONSTRAINT fk_acf_filial    FOREIGN KEY (id_filial)    REFERENCES filiais (id_filial),
  CONSTRAINT fk_acf_categoria FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria),
  CONSTRAINT ck_acf_area CHECK (metros_quadrados > 0)
) ENGINE=InnoDB;

CREATE TABLE parametros_categoria (
  id_categoria        SMALLINT UNSIGNED NOT NULL,
  cobertura_alvo_dias TINYINT UNSIGNED NOT NULL,
  dias_seguranca      TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (id_categoria),
  CONSTRAINT fk_pc_categoria FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria)
) ENGINE=InnoDB;

-- ---------- Estoque ----------
CREATE TABLE estoque_lotes (
  id_lote        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial      INT UNSIGNED NOT NULL,
  id_produto     INT UNSIGNED NOT NULL,
  lote           VARCHAR(30) NOT NULL,
  validade       DATE NULL,
  qtd_atual      INT NOT NULL DEFAULT 0,
  custo_unitario DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  data_entrada   DATE NULL,
  PRIMARY KEY (id_lote),
  UNIQUE KEY uk_lote (id_filial, id_produto, lote),
  KEY ix_lote_validade (id_filial, validade),
  KEY ix_lote_produto (id_produto),
  CONSTRAINT fk_lote_filial  FOREIGN KEY (id_filial)  REFERENCES filiais (id_filial),
  CONSTRAINT fk_lote_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto),
  CONSTRAINT ck_lote_qtd CHECK (qtd_atual >= 0)
) ENGINE=InnoDB;

CREATE TABLE movimentacoes_estoque (
  id_mov     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial  INT UNSIGNED NOT NULL,
  id_produto INT UNSIGNED NOT NULL,
  id_lote    BIGINT UNSIGNED NULL,
  tipo       ENUM('ENTRADA_COMPRA','SAIDA_VENDA','PERDA','QUEBRA','VENCIMENTO',
                  'DEVOLUCAO_CLIENTE','DEVOLUCAO_FORNECEDOR',
                  'TRANSFERENCIA_SAIDA','TRANSFERENCIA_ENTRADA','AJUSTE') NOT NULL,
  qtd        INT NOT NULL,
  data_hora  DATETIME NOT NULL,
  obs        VARCHAR(120) NULL,
  PRIMARY KEY (id_mov),
  KEY ix_mov_fil_prod_data (id_filial, id_produto, data_hora),
  KEY ix_mov_tipo (tipo, data_hora),
  CONSTRAINT fk_mov_filial  FOREIGN KEY (id_filial)  REFERENCES filiais (id_filial),
  CONSTRAINT fk_mov_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE estoque_snapshot_diario (
  data_ref      DATE NOT NULL,
  id_filial     INT UNSIGNED NOT NULL,
  id_produto    INT UNSIGNED NOT NULL,
  qtd           INT NOT NULL,
  valor_estoque DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (data_ref, id_filial, id_produto),
  KEY ix_snap_produto (id_produto),
  CONSTRAINT fk_snap_filial  FOREIGN KEY (id_filial)  REFERENCES filiais (id_filial),
  CONSTRAINT fk_snap_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

-- Livro simplificado de controlados. NÃO substitui o SNGPC; validar com o farmacêutico responsável.
CREATE TABLE livro_controlados (
  id_registro       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial         INT UNSIGNED NOT NULL,
  id_produto        INT UNSIGNED NOT NULL,
  tipo_mov          ENUM('ENTRADA','SAIDA') NOT NULL,
  qtd               INT UNSIGNED NOT NULL,
  data_hora         DATETIME NOT NULL,
  numero_receita    VARCHAR(20) NULL,
  crm_prescritor    VARCHAR(20) NULL,
  farmaceutico_resp VARCHAR(80) NULL,
  PRIMARY KEY (id_registro),
  KEY ix_lc_prod_data (id_produto, data_hora),
  CONSTRAINT fk_lc_filial  FOREIGN KEY (id_filial)  REFERENCES filiais (id_filial),
  CONSTRAINT fk_lc_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

-- ---------- Compras ----------
CREATE TABLE compras (
  id_compra        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial        INT UNSIGNED NOT NULL,
  id_fornecedor    INT UNSIGNED NOT NULL,
  data_pedido      DATE NOT NULL,
  data_prevista    DATE NULL,
  data_recebimento DATE NULL,
  status           ENUM('ABERTO','ENVIADO','RECEBIDO','CANCELADO') NOT NULL DEFAULT 'ABERTO',
  PRIMARY KEY (id_compra),
  KEY ix_compras_filial_data (id_filial, data_pedido),
  KEY ix_compras_fornecedor (id_fornecedor),
  CONSTRAINT fk_compras_filial     FOREIGN KEY (id_filial)     REFERENCES filiais (id_filial),
  CONSTRAINT fk_compras_fornecedor FOREIGN KEY (id_fornecedor) REFERENCES fornecedores (id_fornecedor)
) ENGINE=InnoDB;

CREATE TABLE itens_compra (
  id_item        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_compra      BIGINT UNSIGNED NOT NULL,
  id_produto     INT UNSIGNED NOT NULL,
  qtd_pedida     INT UNSIGNED NOT NULL,
  qtd_recebida   INT UNSIGNED NOT NULL DEFAULT 0,
  custo_unitario DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (id_item),
  KEY ix_ic_compra (id_compra),
  KEY ix_ic_produto (id_produto),
  CONSTRAINT fk_ic_compra  FOREIGN KEY (id_compra)  REFERENCES compras (id_compra),
  CONSTRAINT fk_ic_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

-- ---------- Vendas (canal como atributo) ----------
CREATE TABLE vendas (
  id_venda  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial INT UNSIGNED NOT NULL,
  data_hora DATETIME NOT NULL,
  canal     ENUM('PDV','ECOMMERCE','CLICK_COLLECT') NOT NULL,
  status    ENUM('CONCLUIDA','CANCELADA') NOT NULL DEFAULT 'CONCLUIDA',
  PRIMARY KEY (id_venda),
  KEY ix_vendas_filial_data (id_filial, data_hora),
  KEY ix_vendas_canal (canal, data_hora),
  CONSTRAINT fk_vendas_filial FOREIGN KEY (id_filial) REFERENCES filiais (id_filial)
) ENGINE=InnoDB;

CREATE TABLE itens_venda (
  id_item        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_venda       BIGINT UNSIGNED NOT NULL,
  id_produto     INT UNSIGNED NOT NULL,
  id_lote        BIGINT UNSIGNED NULL,
  qtd            INT UNSIGNED NOT NULL,
  preco_unitario DECIMAL(10,2) NOT NULL,
  custo_unitario DECIMAL(10,2) NOT NULL,
  desconto       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (id_item),
  KEY ix_iv_venda (id_venda),
  KEY ix_iv_produto (id_produto),
  CONSTRAINT fk_iv_venda   FOREIGN KEY (id_venda)   REFERENCES vendas (id_venda),
  CONSTRAINT fk_iv_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto),
  CONSTRAINT fk_iv_lote    FOREIGN KEY (id_lote)    REFERENCES estoque_lotes (id_lote)
) ENGINE=InnoDB;

CREATE TABLE reservas_click_collect (
  id_reserva   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_venda     BIGINT UNSIGNED NOT NULL,
  id_produto   INT UNSIGNED NOT NULL,
  qtd          INT UNSIGNED NOT NULL,
  status       ENUM('RESERVADA','RETIRADA','EXPIRADA','CANCELADA') NOT NULL DEFAULT 'RESERVADA',
  reservado_em DATETIME NOT NULL,
  expira_em    DATETIME NOT NULL,
  PRIMARY KEY (id_reserva),
  KEY ix_res_status_exp (status, expira_em),
  KEY ix_res_venda (id_venda),
  CONSTRAINT fk_res_venda   FOREIGN KEY (id_venda)   REFERENCES vendas (id_venda),
  CONSTRAINT fk_res_produto FOREIGN KEY (id_produto) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

-- ---------- Metas e campanhas ----------
CREATE TABLE metas_comerciais (
  id_filial       INT UNSIGNED NOT NULL,
  id_categoria    SMALLINT UNSIGNED NOT NULL,
  competencia     DATE NOT NULL,          -- sempre dia 01 do mês
  meta_receita    DECIMAL(12,2) NOT NULL,
  meta_margem_pct DECIMAL(5,2) NULL,
  PRIMARY KEY (id_filial, id_categoria, competencia),
  CONSTRAINT fk_meta_filial    FOREIGN KEY (id_filial)    REFERENCES filiais (id_filial),
  CONSTRAINT fk_meta_categoria FOREIGN KEY (id_categoria) REFERENCES categorias (id_categoria)
) ENGINE=InnoDB;

CREATE TABLE campanhas (
  id_campanha  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial    INT UNSIGNED NOT NULL,
  nome         VARCHAR(120) NOT NULL,
  tipo         ENUM('CROSS_SELLING','CLICK_COLLECT','LIQUIDACAO_VENCIMENTO','OUTRA') NOT NULL,
  canal        ENUM('PDV','ECOMMERCE','CLICK_COLLECT','TODOS') NOT NULL DEFAULT 'TODOS',
  data_inicio  DATE NOT NULL,
  data_fim     DATE NOT NULL,
  desconto_pct DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  status       ENUM('PLANEJADA','ATIVA','ENCERRADA') NOT NULL DEFAULT 'PLANEJADA',
  PRIMARY KEY (id_campanha),
  KEY ix_camp_filial_periodo (id_filial, data_inicio, data_fim),
  CONSTRAINT fk_camp_filial FOREIGN KEY (id_filial) REFERENCES filiais (id_filial),
  CONSTRAINT ck_camp_datas CHECK (data_fim >= data_inicio)
) ENGINE=InnoDB;

CREATE TABLE campanha_itens (
  id_campanha INT UNSIGNED NOT NULL,
  id_produto  INT UNSIGNED NOT NULL,
  papel       ENUM('ANCORA','COMPLEMENTO') NOT NULL DEFAULT 'COMPLEMENTO',
  PRIMARY KEY (id_campanha, id_produto),
  KEY ix_ci_produto (id_produto),
  CONSTRAINT fk_ci_campanha FOREIGN KEY (id_campanha) REFERENCES campanhas (id_campanha),
  CONSTRAINT fk_ci_produto  FOREIGN KEY (id_produto)  REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE afinidades (
  id_ancora      INT UNSIGNED NOT NULL,
  id_complemento INT UNSIGNED NOT NULL,
  origem         ENUM('MANUAL','DADOS') NOT NULL,
  lift           DECIMAL(6,2) NULL,
  n_juntos       INT UNSIGNED NULL,
  ativa          TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id_ancora, id_complemento),
  KEY ix_af_comp (id_complemento),
  CONSTRAINT fk_af_ancora FOREIGN KEY (id_ancora)      REFERENCES produtos (id_produto),
  CONSTRAINT fk_af_comp   FOREIGN KEY (id_complemento) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE campanha_combos (
  id_combo           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_campanha        INT UNSIGNED NOT NULL,
  id_ancora          INT UNSIGNED NOT NULL,
  id_complemento     INT UNSIGNED NOT NULL,
  preco_normal_compl DECIMAL(10,2) NOT NULL,
  desconto_pct       DECIMAL(5,2) NOT NULL,
  preco_combo_compl  DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (id_combo),
  UNIQUE KEY uk_combo (id_campanha, id_ancora, id_complemento),
  CONSTRAINT fk_cb_camp FOREIGN KEY (id_campanha)    REFERENCES campanhas (id_campanha),
  CONSTRAINT fk_cb_anc  FOREIGN KEY (id_ancora)      REFERENCES produtos (id_produto),
  CONSTRAINT fk_cb_comp FOREIGN KEY (id_complemento) REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE regras_liquidacao (
  id_regra          TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dias_min          SMALLINT UNSIGNED NOT NULL,
  dias_max          SMALLINT UNSIGNED NOT NULL,
  desconto_pct      DECIMAL(5,2) NOT NULL,
  margem_minima_pct DECIMAL(5,2) NOT NULL DEFAULT 5.00,
  PRIMARY KEY (id_regra)
) ENGINE=InnoDB;

CREATE TABLE liquidacao_lotes (
  id_liq               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_filial            INT UNSIGNED NOT NULL,
  id_campanha          INT UNSIGNED NULL,
  id_lote              BIGINT UNSIGNED NOT NULL,
  id_produto           INT UNSIGNED NOT NULL,
  qtd_em_risco         INT NOT NULL,
  dias_para_vencer     SMALLINT NOT NULL,
  preco_original       DECIMAL(10,2) NULL,
  desconto_pct         DECIMAL(5,2) NULL,
  preco_liquidacao     DECIMAL(10,2) NULL,
  desconto_efetivo_pct DECIMAL(5,2) GENERATED ALWAYS AS
     (ROUND((1 - preco_liquidacao / preco_original) * 100, 2)) STORED,
  acao                 ENUM('LIQUIDAR','DEVOLVER_FORNECEDOR','BAIXAR_VENCIDO') NOT NULL,
  status               ENUM('SUGERIDA','ATIVA','CONCLUIDA','CANCELADA') NOT NULL DEFAULT 'SUGERIDA',
  criada_em            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id_liq),
  KEY ix_liq_status (id_filial, status),
  KEY ix_liq_lote (id_lote),
  CONSTRAINT fk_liq_filial   FOREIGN KEY (id_filial)   REFERENCES filiais (id_filial),
  CONSTRAINT fk_liq_campanha FOREIGN KEY (id_campanha) REFERENCES campanhas (id_campanha),
  CONSTRAINT fk_liq_lote     FOREIGN KEY (id_lote)     REFERENCES estoque_lotes (id_lote),
  CONSTRAINT fk_liq_produto  FOREIGN KEY (id_produto)  REFERENCES produtos (id_produto)
) ENGINE=InnoDB;

CREATE TABLE parametros_rollout (
  kpi       VARCHAR(80) NOT NULL,
  regra     ENUM('>=','<=') NOT NULL,
  limite    DECIMAL(8,2) NOT NULL,
  descricao VARCHAR(150) NULL,
  PRIMARY KEY (kpi)
) ENGINE=InnoDB;
