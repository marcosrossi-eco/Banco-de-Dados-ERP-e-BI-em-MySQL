-- ============================================================
-- 00_instalar_tudo.sql | Instala o projeto completo na ordem correta
-- Use dentro da pasta dos scripts, no cliente de linha de comando:
--   cd farmacia-erp
--   mysql -u root -p --default-character-set=utf8mb4
--   mysql> SOURCE 00_instalar_tudo.sql;
-- (No Workbench/DBeaver, abra e execute cada arquivo na ordem numérica.)
-- ============================================================
SOURCE 01_schema.sql;
SOURCE 02_views.sql;
SOURCE 03_configuracao.sql;
SOURCE 04_simulacao_catalogo.sql;
SOURCE 05_simulacao_operacao.sql;
SOURCE 06_rotinas_e_automacao.sql;
-- Opcional (edite as senhas antes): SOURCE 08_usuarios_e_backup.sql;
