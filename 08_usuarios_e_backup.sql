-- ============================================================
-- 08_usuarios_e_backup.sql | Perfis de acesso e agendador de eventos
-- Execute como root. TROQUE AS SENHAS antes de rodar.
-- ============================================================
SET GLOBAL event_scheduler = ON;   -- para persistir após reiniciar, ver README (my.ini / my.cnf)

CREATE USER IF NOT EXISTS 'farmacia_app'@'localhost' IDENTIFIED BY 'TROCAR_SENHA_APP';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON farmacia.* TO 'farmacia_app'@'localhost';

CREATE USER IF NOT EXISTS 'farmacia_bi'@'localhost' IDENTIFIED BY 'TROCAR_SENHA_BI';
GRANT SELECT ON farmacia.* TO 'farmacia_bi'@'localhost';

-- Backup diário (rode no terminal, não no MySQL) e guarde uma cópia FORA do laptop:
--   mysqldump -u root -p --single-transaction --routines --events farmacia > farmacia_AAAA-MM-DD.sql
