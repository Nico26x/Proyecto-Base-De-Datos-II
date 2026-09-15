-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ
-- ARCHIVO: 01_tablespaces.sql
-- DESCRIPCIÓN: Creación del tablespace dedicado para el histórico de reservas.
-- =============================================================================

-- 1. Creación del Tablespace TS_HISTORICO_RESERVAS
CREATE TABLESPACE ts_historico_reservas
DATAFILE 'ts_historico_reservas01.dbf' 
SIZE 100M 
AUTOEXTEND ON 
NEXT 10M 
MAXSIZE UNLIMITED;

-- 2. Otorgar permisos de cuota al usuario sobre el nuevo tablespace
ALTER USER turismo_user QUOTA UNLIMITED ON ts_historico_reservas;