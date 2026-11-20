-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - CONCURRENCIA ANTES DEL BLOQUEO
-- GUIA MANUAL: NO EJECUTAR ESTE ARCHIVO COMPLETO.
-- Abra dos worksheets con conexiones NO COMPARTIDAS, ambos como TURISMO_USER,
-- y ejecute solo la seccion indicada en cada uno mediante Run Script (F5).
-- Los SID impresos deben ser diferentes. Use sesiones limpias, sin otro trabajo
-- pendiente, porque ROLLBACK afecta toda la transaccion de cada sesion.
--
-- El trigger de solapamiento no puede ver cambios no confirmados de otra
-- sesion. Por ello ambas sesiones pueden validar e insertar el mismo periodo.
-- Ninguna seccion hace COMMIT; al final se revierte todo en ambas sesiones.
-- =============================================================================

SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- PASO 0 - EJECUTAR UNA SOLA VEZ PARA ELEGIR EL CANDIDATO
-- -----------------------------------------------------------------------------
-- Devuelve una noche libre con temporada prioritaria y tarifa unicas. Copie
-- exactamente los cuatro valores obtenidos en las dos sesiones.

WITH limites AS (
    SELECT MIN(TRUNC(fecha_inicio)) AS fecha_min,
           MAX(TRUNC(fecha_fin)) AS fecha_max
      FROM temporada
),
fechas AS (
    SELECT fecha_min + LEVEL - 1 AS fecha_in
      FROM limites
    CONNECT BY LEVEL <= fecha_max - fecha_min
),
candidatas AS (
    SELECT h.id_habitacion, h.capacidad, f.fecha_in,
           f.fecha_in + 1 AS fecha_out, t.id_temporada,
           CASE
               WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2
               ELSE 1
           END AS prioridad
      FROM habitacion h
      CROSS JOIN fechas f
      JOIN temporada t
        ON f.fecha_in BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
     WHERE h.capacidad >= 1
),
priorizadas AS (
    SELECT c.*,
           MIN(prioridad) OVER (
               PARTITION BY id_habitacion, fecha_in
           ) AS prioridad_minima
      FROM candidatas c
),
validos AS (
    SELECT p.id_habitacion, p.capacidad, p.fecha_in, p.fecha_out
      FROM priorizadas p
      JOIN tarifa ta
        ON ta.id_habitacion = p.id_habitacion
       AND ta.id_temporada = p.id_temporada
     WHERE p.prioridad = p.prioridad_minima
     GROUP BY p.id_habitacion, p.capacidad, p.fecha_in, p.fecha_out
    HAVING COUNT(DISTINCT p.id_temporada) = 1
       AND COUNT(ta.id_tarifa) = 1
)
SELECT (SELECT MIN(id_cliente) FROM cliente) AS id_cliente,
       v.id_habitacion,
       TO_CHAR(v.fecha_in, 'YYYY-MM-DD') AS fecha_in,
       TO_CHAR(v.fecha_out, 'YYYY-MM-DD') AS fecha_out,
       v.capacidad
  FROM (
      SELECT x.*
        FROM validos x
       WHERE NOT EXISTS (
                 SELECT 1
                   FROM reserva_habitacion rh
                   JOIN reserva r
                     ON r.id_reserva = rh.id_reserva
                  WHERE rh.id_habitacion = x.id_habitacion
                    AND r.estado <> 'CANCELADA'
                    AND TRUNC(rh.fecha_checkin) < x.fecha_out
                    AND TRUNC(rh.fecha_checkout) > x.fecha_in
             )
       ORDER BY x.fecha_in, x.id_habitacion
  ) v
 WHERE ROWNUM = 1;

-- CAPTURA 1: candidato seleccionado antes de iniciar ambas transacciones.

-- =============================================================================
-- SESION A - EJECUTAR SOLO EN EL PRIMER WORKSHEET
-- =============================================================================

ACCEPT p_id_cliente NUMBER PROMPT 'ID cliente de la consulta previa: '
ACCEPT p_id_habitacion NUMBER PROMPT 'ID habitacion de la consulta previa: '
ACCEPT p_fecha_in CHAR PROMPT 'Fecha inicial YYYY-MM-DD: '
ACCEPT p_fecha_out CHAR PROMPT 'Fecha final YYYY-MM-DD: '

VARIABLE v_id_reserva_a NUMBER

BEGIN
    DBMS_OUTPUT.PUT_LINE(
        'SESION A SID=' || SYS_CONTEXT('USERENV', 'SID') ||
        ' ANTES=' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM')
    );

    pkg_turismo.sp_crear_reserva(
        p_id_cliente    => &p_id_cliente,
        p_id_habitacion => &p_id_habitacion,
        p_fecha_in      => TO_DATE('&p_fecha_in', 'YYYY-MM-DD'),
        p_fecha_out     => TO_DATE('&p_fecha_out', 'YYYY-MM-DD'),
        p_num_huespedes => 1,
        p_id_reserva    => :v_id_reserva_a
    );

    DBMS_OUTPUT.PUT_LINE(
        'SESION A DESPUES=' ||
        TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM') ||
        ' RESERVA=' || :v_id_reserva_a
    );
END;
/

PRINT v_id_reserva_a

-- NO EJECUTAR COMMIT.
-- CAPTURA 2: A termino, muestra su ID y mantiene la transaccion abierta.

-- =============================================================================
-- SESION B - EJECUTAR SOLO EN EL SEGUNDO WORKSHEET
-- =============================================================================

ACCEPT p_id_cliente NUMBER PROMPT 'MISMO ID cliente usado en A: '
ACCEPT p_id_habitacion NUMBER PROMPT 'MISMO ID habitacion usado en A: '
ACCEPT p_fecha_in CHAR PROMPT 'MISMA fecha inicial YYYY-MM-DD: '
ACCEPT p_fecha_out CHAR PROMPT 'MISMA fecha final YYYY-MM-DD: '

VARIABLE v_id_reserva_b NUMBER

BEGIN
    DBMS_OUTPUT.PUT_LINE(
        'SESION B SID=' || SYS_CONTEXT('USERENV', 'SID') ||
        ' ANTES=' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM')
    );

    pkg_turismo.sp_crear_reserva(
        p_id_cliente    => &p_id_cliente,
        p_id_habitacion => &p_id_habitacion,
        p_fecha_in      => TO_DATE('&p_fecha_in', 'YYYY-MM-DD'),
        p_fecha_out     => TO_DATE('&p_fecha_out', 'YYYY-MM-DD'),
        p_num_huespedes => 1,
        p_id_reserva    => :v_id_reserva_b
    );

    DBMS_OUTPUT.PUT_LINE(
        'SESION B DESPUES=' ||
        TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM') ||
        ' RESERVA=' || :v_id_reserva_b
    );
END;
/

PRINT v_id_reserva_b

-- NO EJECUTAR COMMIT.
-- CAPTURA 3: B tambien termino, sin esperar un COMMIT de A. Los IDs son
-- distintos y ambas sesiones aceptaron el mismo intervalo.

-- -----------------------------------------------------------------------------
-- LIMPIEZA - EJECUTAR PRIMERO EN B Y DESPUES EN A
-- -----------------------------------------------------------------------------

-- SESION B:
ROLLBACK;

-- SESION A:
-- Seleccione y ejecute en el worksheet A la siguiente sentencia:
--     ROLLBACK;

-- CAPTURA 4: ambos rollbacks terminaron; no queda ninguna fila de la prueba.
