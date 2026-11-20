-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - SEGURIDAD: ROLES Y USUARIOS DE DEMOSTRACION
-- EJECUTAR COMO: SYSTEM (o SYS AS SYSDBA) conectado a XEPDB1.
-- Idempotente: borra y recrea solo los roles/usuarios de este script.
-- Los privilegios sobre objetos los otorga el dueno (TURISMO_USER) en
-- 10_vistas_seguridad.sql; aqui solo se crean los roles y se asignan.
--
--   ROL                    USUARIO DEMO            QUIEN ES
--   ROL_RECEPCION          USR_RECEPCION           atiende clientes en mostrador
--   ROL_ADMIN_ALOJAMIENTO  USR_ADMIN_ALOJAMIENTO   mantiene habitaciones/tarifas
--   ROL_GERENTE            USR_GERENTE             consulta todo y liquida meses
--   ROL_AUDITOR            USR_AUDITOR             revisa pagos y cambios de tarifa
--
-- Contrasenas de demostracion (solo para el entorno academico).
-- =============================================================================

SET SERVEROUTPUT ON

DECLARE
    PROCEDURE ejecutar_ignorando(p_sql VARCHAR2, p_codigo_ignorado NUMBER) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != p_codigo_ignorado THEN RAISE; END IF;
    END;
BEGIN
    FOR u IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                 'USR_RECEPCION', 'USR_ADMIN_ALOJAMIENTO', 'USR_GERENTE', 'USR_AUDITOR'))) LOOP
        ejecutar_ignorando('DROP USER ' || u.nombre || ' CASCADE', -1918);  -- no existe
    END LOOP;

    FOR r IN (SELECT column_value AS nombre FROM TABLE(sys.odcivarchar2list(
                 'ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR'))) LOOP
        ejecutar_ignorando('DROP ROLE ' || r.nombre, -1919);                -- no existe
    END LOOP;
END;
/

CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

-- Unico privilegio de sistema: poder conectarse. Ningun rol puede crear objetos.
GRANT CREATE SESSION TO rol_recepcion, rol_admin_alojamiento, rol_gerente, rol_auditor;

CREATE USER usr_recepcion         IDENTIFIED BY "Recepcion2026";
CREATE USER usr_admin_alojamiento IDENTIFIED BY "AdminAloj2026";
CREATE USER usr_gerente           IDENTIFIED BY "Gerente2026";
CREATE USER usr_auditor           IDENTIFIED BY "Auditor2026";

GRANT rol_recepcion         TO usr_recepcion;
GRANT rol_admin_alojamiento TO usr_admin_alojamiento;
GRANT rol_gerente           TO usr_gerente;
GRANT rol_auditor           TO usr_auditor;

COLUMN grantee      FORMAT A24
COLUMN granted_role FORMAT A24

SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE grantee LIKE 'USR\_%' ESCAPE '\'
 ORDER BY grantee;
