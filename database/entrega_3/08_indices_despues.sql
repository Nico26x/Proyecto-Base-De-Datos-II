-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - INDICES: MEDICION DESPUES + CASO DONDE NO AYUDA
-- EJECUTAR COMO: TURISMO_USER, despues de 07_indices.sql.
-- Repite exactamente las consultas y la medicion de 06_indices_antes.sql.
-- Los resultados reales y la comparacion estan en
-- SUSTENTACION_indices_seguridad.md.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 200

-- -----------------------------------------------------------------------------
-- Q1 - DISPONIBILIDAD DE HABITACION (texto identico al de SP_CREAR_RESERVA)
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q1_DESPUES' FOR
SELECT COUNT(*)
  FROM reserva_habitacion rh
  JOIN reserva r
    ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = :p_id_habitacion
   AND r.estado <> 'CANCELADA'
   AND TRUNC(rh.fecha_checkin)  < :v_fecha_out
   AND TRUNC(rh.fecha_checkout) > :v_fecha_in;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q1_DESPUES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- Q2 - CIERRE DE CAJA DIARIO
-- TRUNC es necesario: SP_CREAR_RESERVA_PAGO guarda el pago con SYSDATE (hora).
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q2_DESPUES' FOR
SELECT metodo, COUNT(*) AS transacciones, SUM(monto) AS total
  FROM pago
 WHERE TRUNC(fecha_transaccion) = :p_dia
 GROUP BY metodo
 ORDER BY metodo;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q2_DESPUES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- Q3 - HISTORIAL DE UN CLIENTE
-- -----------------------------------------------------------------------------
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_DESPUES' FOR
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

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_DESPUES', 'TYPICAL'));

-- -----------------------------------------------------------------------------
-- MEDICION DE TIEMPO: cada consulta se ejecuta muchas veces con valores reales
-- (una sola ejecucion tarda < 1 ms y no se puede comparar).
--   Q1: una vez por cada habitacion (ventana fija de 3 noches).
--   Q2: una vez por cada dia con pagos.
--   Q3: una vez por cada uno de los primeros 300 clientes.
-- Bloque identico al de 06_indices_antes.sql.
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
    DBMS_OUTPUT.PUT_LINE('=== MEDICION DESPUES ===');

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

-- =============================================================================
-- CASO DONDE EL INDICE NO AYUDA: RESERVA(ESTADO)
-- Consulta: listado de reservas pendientes.
-- ESTADO solo tiene 4 valores repartidos casi por igual (~25 % de las filas cada
-- uno). Para devolver 1 de cada 4 filas es mas barato leer la tabla completa
-- (118 bloques en lectura multibloque) que hacer ~6 300 saltos indice -> tabla.
-- El indice se crea solo para la demostracion y se elimina al final, porque
-- solo agregaria costo a cada INSERT/UPDATE de RESERVA.
-- =============================================================================
BEGIN
    EXECUTE IMMEDIATE 'CREATE INDEX idx_reserva_estado ON reserva (estado)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -955 THEN RAISE; END IF;  -- ORA-00955: ya existe
END;
/

BEGIN
    DBMS_STATS.GATHER_INDEX_STATS(ownname => USER, indname => 'IDX_RESERVA_ESTADO');
END;
/

SELECT index_name, distinct_keys, clustering_factor, leaf_blocks
  FROM user_indexes
 WHERE index_name = 'IDX_RESERVA_ESTADO';

SELECT estado, COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
  FROM reserva
 GROUP BY estado
 ORDER BY estado;

-- a) El optimizador, con el indice disponible, decide NO usarlo.
EXPLAIN PLAN SET STATEMENT_ID = 'NOAYUDA_LIBRE' FOR
SELECT id_reserva, id_cliente, fecha_creacion
  FROM reserva
 WHERE estado = 'PENDIENTE';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'NOAYUDA_LIBRE', 'TYPICAL'));

-- b) Forzando el indice con un hint el costo estimado sube.
EXPLAIN PLAN SET STATEMENT_ID = 'NOAYUDA_FORZADO' FOR
SELECT /*+ INDEX(reserva idx_reserva_estado) */ id_reserva, id_cliente, fecha_creacion
  FROM reserva
 WHERE estado = 'PENDIENTE';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'NOAYUDA_FORZADO', 'TYPICAL'));

-- c) Medicion real: 200 ejecuciones de cada variante.
DECLARE
    v_inicio NUMBER;
    v_filas  NUMBER;
BEGIN
    v_inicio := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. 200 LOOP
        v_filas := 0;
        FOR f IN (SELECT /*+ FULL(reserva) */ id_reserva, id_cliente, fecha_creacion
                    FROM reserva WHERE estado = 'PENDIENTE') LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Sin indice (FULL SCAN):   filas=' || v_filas ||
                         '  total_ms=' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10);

    v_inicio := DBMS_UTILITY.GET_TIME;
    FOR i IN 1 .. 200 LOOP
        v_filas := 0;
        FOR f IN (SELECT /*+ INDEX(reserva idx_reserva_estado) */ id_reserva, id_cliente, fecha_creacion
                    FROM reserva WHERE estado = 'PENDIENTE') LOOP
            v_filas := v_filas + 1;
        END LOOP;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Con indice (forzado):     filas=' || v_filas ||
                         '  total_ms=' || (DBMS_UTILITY.GET_TIME - v_inicio) * 10);
END;
/

-- El indice no aporta: se elimina para no penalizar las escrituras.
DROP INDEX idx_reserva_estado;
