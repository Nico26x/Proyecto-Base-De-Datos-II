-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - SEGURIDAD: PERFIL CON LIMITES DE SESION
-- EJECUTAR COMO: SYSTEM (o SYS AS SYSDBA) en XEPDB1, despues de 09_roles.sql.
-- Idempotente: crea el perfil o, si ya existe, le reaplica los limites.
--
-- Limites elegidos (todos soportados por Oracle XE 21c):
--   SESSIONS_PER_USER     2      un operador no abre mas de 2 sesiones a la vez
--   CONNECT_TIME          480    una sesion dura como maximo un turno (8 h)
--   IDLE_TIME             15     sesion inactiva 15 min se corta (puesto abandonado)
--   FAILED_LOGIN_ATTEMPTS 3      al tercer intento fallido la cuenta se bloquea
--   PASSWORD_LOCK_TIME    1/24   ... durante 1 hora
--   PASSWORD_LIFE_TIME    90     la contrasena vence a los 90 dias
--   PASSWORD_GRACE_TIME   7      7 dias de gracia para cambiarla
-- Los limites de sesion (SESSIONS_PER_USER, CONNECT_TIME, IDLE_TIME) solo se
-- aplican si RESOURCE_LIMIT = TRUE; en 21c ese es el valor por defecto y el
-- script lo verifica al final.
-- =============================================================================

SET SERVEROUTPUT ON

DECLARE
    c_limites CONSTANT VARCHAR2(400) :=
        ' LIMIT SESSIONS_PER_USER 2' ||
        ' CONNECT_TIME 480' ||
        ' IDLE_TIME 15' ||
        ' FAILED_LOGIN_ATTEMPTS 3' ||
        ' PASSWORD_LOCK_TIME 1/24' ||
        ' PASSWORD_LIFE_TIME 90' ||
        ' PASSWORD_GRACE_TIME 7';
BEGIN
    EXECUTE IMMEDIATE 'CREATE PROFILE perfil_turismo_operativo' || c_limites;
    DBMS_OUTPUT.PUT_LINE('Perfil creado.');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -2379 THEN RAISE; END IF;  -- ORA-02379: el perfil ya existe
        EXECUTE IMMEDIATE 'ALTER PROFILE perfil_turismo_operativo' || c_limites;
        DBMS_OUTPUT.PUT_LINE('Perfil ya existia: limites reaplicados.');
END;
/

ALTER USER usr_recepcion         PROFILE perfil_turismo_operativo;
ALTER USER usr_admin_alojamiento PROFILE perfil_turismo_operativo;
ALTER USER usr_gerente           PROFILE perfil_turismo_operativo;
ALTER USER usr_auditor           PROFILE perfil_turismo_operativo;

-- -----------------------------------------------------------------------------
-- VERIFICACION
-- -----------------------------------------------------------------------------
COLUMN resource_name FORMAT A24
COLUMN limit         FORMAT A12
COLUMN username      FORMAT A24
COLUMN profile       FORMAT A26
COLUMN value         FORMAT A10

SELECT resource_name, resource_type, limit
  FROM dba_profiles
 WHERE profile = 'PERFIL_TURISMO_OPERATIVO'
   AND limit != 'DEFAULT'
 ORDER BY resource_type, resource_name;

SELECT username, profile, account_status
  FROM dba_users
 WHERE username LIKE 'USR\_%' ESCAPE '\'
 ORDER BY username;

SELECT name, value FROM v$parameter WHERE name = 'resource_limit';
