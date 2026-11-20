-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - CREACION DE INDICES
-- EJECUTAR COMO: TURISMO_USER, despues de 06_indices_antes.sql.
-- Idempotente: si un indice ya existe no se vuelve a crear.
-- No modifica tablas, datos, PKG_TURISMO ni triggers.
-- =============================================================================

SET SERVEROUTPUT ON

DECLARE
    TYPE t_ddl IS TABLE OF VARCHAR2(400) INDEX BY VARCHAR2(30);
    v_ddl     t_ddl;
    v_nombre  VARCHAR2(30);
    v_existe  PLS_INTEGER;
BEGIN
    -- Q1 - COMPUESTO. id_habitacion es la columna de acceso (igualdad) y las
    -- fechas van dentro del indice para descartar estadias sin ir a la tabla.
    -- Lo usan SP_CREAR_RESERVA, SP_CREAR_RESERVA_BLOQUEADA y el trigger de
    -- solapamiento en cada reserva: sus resultados no cambian, solo el camino.
    v_ddl('IDX_RESHAB_HAB_FECHAS') :=
        'CREATE INDEX idx_reshab_hab_fechas
             ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout)';

    -- Q2 - BASADO EN FUNCION. La consulta filtra por TRUNC(fecha_transaccion);
    -- un indice normal sobre fecha_transaccion no se puede usar con esa funcion.
    v_ddl('IDX_PAGO_DIA') :=
        'CREATE INDEX idx_pago_dia ON pago (TRUNC(fecha_transaccion))';

    -- Q3 - Llaves foraneas que no tenian indice. Ademas de acelerar el join,
    -- evitan el bloqueo de toda la tabla hija al borrar un padre (ON DELETE CASCADE).
    v_ddl('IDX_RESERVA_CLIENTE') :=
        'CREATE INDEX idx_reserva_cliente ON reserva (id_cliente)';
    v_ddl('IDX_RESHAB_RESERVA') :=
        'CREATE INDEX idx_reshab_reserva ON reserva_habitacion (id_reserva)';
    v_ddl('IDX_PAGO_RESERVA') :=
        'CREATE INDEX idx_pago_reserva ON pago (id_reserva)';

    v_nombre := v_ddl.FIRST;
    WHILE v_nombre IS NOT NULL LOOP
        SELECT COUNT(*) INTO v_existe FROM user_indexes WHERE index_name = v_nombre;
        IF v_existe = 0 THEN
            EXECUTE IMMEDIATE v_ddl(v_nombre);
            DBMS_OUTPUT.PUT_LINE('Creado: ' || v_nombre);
        ELSE
            DBMS_OUTPUT.PUT_LINE('Ya existia: ' || v_nombre);
        END IF;
        v_nombre := v_ddl.NEXT(v_nombre);
    END LOOP;
END;
/

-- Estadisticas para que el optimizador conozca los indices nuevos.
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

COLUMN index_name        FORMAT A24
COLUMN table_name        FORMAT A20
COLUMN columnas          FORMAT A50
COLUMN column_expression FORMAT A40

SELECT i.index_name, i.table_name, i.index_type,
       LISTAGG(c.column_name, ', ') WITHIN GROUP (ORDER BY c.column_position) AS columnas,
       i.status
  FROM user_indexes i
  JOIN user_ind_columns c ON c.index_name = i.index_name
 WHERE i.index_name LIKE 'IDX\_%' ESCAPE '\'
 GROUP BY i.index_name, i.table_name, i.index_type, i.status
 ORDER BY i.table_name, i.index_name;

-- La columna SYS_NC... del indice basado en funcion corresponde a esta expresion:
SELECT index_name, column_expression FROM user_ind_expressions;
