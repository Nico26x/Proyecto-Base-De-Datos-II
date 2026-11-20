-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - INDICES: MEDICION ANTES
-- EJECUTAR COMO: TURISMO_USER (Run Script / F5 o SQL*Plus).
-- PROPOSITO: capturar plan y tiempo de las 3 consultas lentas SIN los indices
-- de la Entrega 3. Solo lee datos: no cambia estructura ni filas de negocio.
--
-- Las 3 consultas elegidas (todas hacian TABLE ACCESS FULL para pocas filas):
--   Q1 Disponibilidad de una habitacion: misma consulta de PKG_TURISMO.
--      SP_CREAR_RESERVA y TRG_SOLAPAMIENTO_RESERVA_HAB. Corre en CADA reserva.
--   Q2 Cierre de caja diario: pagos de un dia agrupados por metodo.
--   Q3 Historial de un cliente: reservas, estadias y pagos por identificacion.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 200

-- -----------------------------------------------------------------------------
-- PASO 0 - Volver al estado "antes" (solo borra los indices creados en 07).
-- Las PK/UK de Entrega 1 y 2 no se tocan.
-- -----------------------------------------------------------------------------
BEGIN
    FOR i IN (
        SELECT index_name
          FROM user_indexes
         WHERE index_name IN ('IDX_RESHAB_HAB_FECHAS', 'IDX_PAGO_DIA',
                              'IDX_RESERVA_CLIENTE', 'IDX_RESHAB_RESERVA',
                              'IDX_PAGO_RESERVA', 'IDX_RESERVA_ESTADO')
    ) LOOP
        EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
        DBMS_OUTPUT.PUT_LINE('Indice eliminado para medir antes: ' || i.index_name);
    END LOOP;
END;
/

-- Estadisticas actualizadas: sin ellas el optimizador adivina y la comparacion
-- antes/despues no es justa.
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

SELECT table_name, num_rows, blocks
  FROM user_tables
 WHERE table_name IN ('CLIENTE', 'RESERVA', 'RESERVA_HABITACION', 'PAGO')
 ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- Q1 - DISPONIBILIDAD DE HABITACION (texto identico al de SP_CREAR_RESERVA)
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q1_ANTES' FOR
SELECT COUNT(*)
  FROM reserva_habitacion rh
  JOIN reserva r
    ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = :p_id_habitacion
   AND r.estado <> 'CANCELADA'
   AND TRUNC(rh.fecha_checkin)  < :v_fecha_out
   AND TRUNC(rh.fecha_checkout) > :v_fecha_in;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q1_ANTES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- Q2 - CIERRE DE CAJA DIARIO
-- TRUNC es necesario: SP_CREAR_RESERVA_PAGO guarda el pago con SYSDATE (hora).
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q2_ANTES' FOR
SELECT metodo, COUNT(*) AS transacciones, SUM(monto) AS total
  FROM pago
 WHERE TRUNC(fecha_transaccion) = :p_dia
 GROUP BY metodo
 ORDER BY metodo;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q2_ANTES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- Q3 - HISTORIAL DE UN CLIENTE
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_ANTES' FOR
SELECT c.nombre_completo, r.id_reserva, r.estado,
       rh.fecha_checkin, rh.fecha_checkout, rh.subtotal_calculado,
       NVL(SUM(p.monto), 0) AS pagado
  FROM cliente c
  JOIN reserva r             ON r.id_cliente  = c.id_cliente
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  LEFT JOIN pago p           ON p.id_reserva  = r.id_reserva
 WHERE c.identificacion = :p_identificacion
 GROUP BY c.nombre_completo, r.id_reserva, r.estado,
          rh.fecha_checkin, rh.fecha_checkout, rh.subtotal_calculado
 ORDER BY rh.fecha_checkin DESC;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_ANTES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- MEDICION DE TIEMPO: cada consulta se ejecuta muchas veces con valores reales
-- (una sola ejecucion tarda < 1 ms y no se puede comparar).
--   Q1: una vez por cada habitacion (ventana fija de 3 noches).
--   Q2: una vez por cada dia con pagos.
--   Q3: una vez por cada uno de los primeros 300 clientes.
-- 08_indices_despues.sql repite exactamente este bloque.
-- -----------------------------------------------------------------------------
DECLARE
    v_inicio  NUMBER;
    v_n       PLS_INTEGER;
    v_cuenta  NUMBER;
    v_filas   NUMBER := 0;

    PROCEDURE imprimir(p_nombre VARCHAR2, p_inicio NUMBER, p_n PLS_INTEGER, p_filas NUMBER) IS
        v_ms NUMBER := (DBMS_UTILITY.GET_TIME - p_inicio) * 10;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 28) || ' ejecuciones=' || p_n ||
                             '  filas=' || p_filas ||
                             '  total_ms=' || v_ms ||
                             '  ms_por_ejecucion=' || ROUND(v_ms / p_n, 3));
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== MEDICION ANTES ===');

    v_inicio := DBMS_UTILITY.GET_TIME; v_n := 0;
    FOR h IN (SELECT id_habitacion FROM habitacion) LOOP
        SELECT COUNT(*) INTO v_cuenta
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = h.id_habitacion
           AND r.estado <> 'CANCELADA'
           AND TRUNC(rh.fecha_checkin)  < DATE '2025-07-13'
           AND TRUNC(rh.fecha_checkout) > DATE '2025-07-10';
        v_n := v_n + 1; v_filas := v_filas + v_cuenta;
    END LOOP;
    imprimir('Q1 disponibilidad', v_inicio, v_n, v_filas);

    v_inicio := DBMS_UTILITY.GET_TIME; v_n := 0; v_filas := 0;
    FOR d IN (SELECT DISTINCT TRUNC(fecha_transaccion) AS dia FROM pago) LOOP
        FOR f IN (SELECT metodo, COUNT(*) AS transacciones, SUM(monto) AS total
                    FROM pago
                   WHERE TRUNC(fecha_transaccion) = d.dia
                   GROUP BY metodo) LOOP
            v_filas := v_filas + 1;
        END LOOP;
        v_n := v_n + 1;
    END LOOP;
    imprimir('Q2 cierre de caja', v_inicio, v_n, v_filas);

    v_inicio := DBMS_UTILITY.GET_TIME; v_n := 0; v_filas := 0;
    FOR c IN (SELECT identificacion
                FROM (SELECT identificacion FROM cliente ORDER BY id_cliente)
               WHERE ROWNUM <= 300) LOOP
        FOR f IN (SELECT c2.nombre_completo, r.id_reserva, NVL(SUM(p.monto), 0) AS pagado
                    FROM cliente c2
                    JOIN reserva r             ON r.id_cliente  = c2.id_cliente
                    JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
                    LEFT JOIN pago p           ON p.id_reserva  = r.id_reserva
                   WHERE c2.identificacion = c.identificacion
                   GROUP BY c2.nombre_completo, r.id_reserva, r.estado,
                            rh.fecha_checkin, rh.fecha_checkout, rh.subtotal_calculado) LOOP
            v_filas := v_filas + 1;
        END LOOP;
        v_n := v_n + 1;
    END LOOP;
    imprimir('Q3 historial cliente', v_inicio, v_n, v_filas);
END;
/
