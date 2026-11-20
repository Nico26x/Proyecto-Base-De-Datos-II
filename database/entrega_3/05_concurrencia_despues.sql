-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - CONCURRENCIA DESPUES DEL BLOQUEO
-- GUIA MANUAL: NO EJECUTAR ESTE ARCHIVO COMPLETO.
-- PRERREQUISITO: ejecutar 01_reserva_con_bloqueo.sql y verificarlo VALID.
-- Abra dos worksheets con conexiones NO COMPARTIDAS como TURISMO_USER. Ejecute
-- cada seccion mediante Run Script (F5); ACCEPT, VARIABLE y PRINT requieren ese
-- modo. Los SID impresos deben ser diferentes. Ambas sesiones deben estar
-- limpias porque COMMIT o ROLLBACK afectan toda su transaccion.
--
-- SP_CREAR_RESERVA_BLOQUEADA toma un lock sobre HABITACION antes de validar e
-- insertar. La sesion B no llega al INSERT ni al trigger hasta que A termina.
-- =============================================================================

SET SERVEROUTPUT ON

-- -----------------------------------------------------------------------------
-- PASO 0 - ELEGIR UN CANDIDATO LIBRE
-- -----------------------------------------------------------------------------

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

-- CAPTURA 1: candidato libre que se copiara en A y B.

-- =============================================================================
-- VARIANTE PRINCIPAL: A CONFIRMA Y B RECIBE ORA-20201
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SESION A - EJECUTAR PRIMERO EN EL WORKSHEET A
-- -----------------------------------------------------------------------------

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

    sp_crear_reserva_bloqueada(
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
        ' RESERVA=' || :v_id_reserva_a || ' - LOCK ACTIVO'
    );
END;
/

PRINT v_id_reserva_a

-- NO HACER COMMIT TODAVIA.
-- CAPTURA 2: A termino y conserva el lock sobre HABITACION.

-- -----------------------------------------------------------------------------
-- SESION B - INICIAR AHORA EN EL WORKSHEET B
-- -----------------------------------------------------------------------------

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

    BEGIN
        sp_crear_reserva_bloqueada(
            p_id_cliente    => &p_id_cliente,
            p_id_habitacion => &p_id_habitacion,
            p_fecha_in      => TO_DATE('&p_fecha_in', 'YYYY-MM-DD'),
            p_fecha_out     => TO_DATE('&p_fecha_out', 'YYYY-MM-DD'),
            p_num_huespedes => 1,
            p_id_reserva    => :v_id_reserva_b
        );
        RAISE_APPLICATION_ERROR(-20975, 'B acepto un periodo ya confirmado por A.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20201 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                'SESION B DESPUES=' ||
                TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM') ||
                ' CODIGO ESPERADO=' || SQLCODE
            );
    END;
END;
/

-- B quedara ejecutando en SELECT FOR UPDATE. No cancele la sentencia.
-- CAPTURA 3: B aparece ejecutando/esperando mientras A mantiene el lock.

-- -----------------------------------------------------------------------------
-- SESION A - CUANDO B ESTE ESPERANDO
-- -----------------------------------------------------------------------------

COMMIT;

-- CAPTURA 4: A confirma. B se desbloquea y muestra ORA-20201 porque ahora ve
-- la reserva confirmada de A.

-- -----------------------------------------------------------------------------
-- SESION B - DESPUES DE RECIBIR ORA-20201
-- -----------------------------------------------------------------------------

ROLLBACK;

-- -----------------------------------------------------------------------------
-- LIMPIEZA DE LA VARIANTE COMMIT - EJECUTAR SOLO EN SESION A
-- -----------------------------------------------------------------------------
-- :v_id_reserva_a conserva el ID impreso. Si se cerro el worksheet, sustituya
-- el bind por ese ID exacto. Nunca use un filtro diferente.

DECLARE
    v_id       reserva.id_reserva%TYPE := :v_id_reserva_a;
    v_borradas NUMBER;
    v_reserva  NUMBER;
    v_detalles NUMBER;
    v_total_detalles NUMBER;
    v_pagos    NUMBER;
    v_servicios NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO v_reserva
      FROM reserva r
      JOIN reserva_habitacion rh
        ON rh.id_reserva = r.id_reserva
     WHERE r.id_reserva = v_id
       AND rh.id_habitacion = &p_id_habitacion
       AND TRUNC(rh.fecha_checkin) = TO_DATE('&p_fecha_in', 'YYYY-MM-DD')
       AND TRUNC(rh.fecha_checkout) = TO_DATE('&p_fecha_out', 'YYYY-MM-DD');

    SELECT COUNT(*) INTO v_pagos FROM pago WHERE id_reserva = v_id;
    SELECT COUNT(*) INTO v_servicios FROM reserva_servicio WHERE id_reserva = v_id;
    SELECT COUNT(*) INTO v_total_detalles
      FROM reserva_habitacion
     WHERE id_reserva = v_id;

    IF v_reserva != 1 OR v_total_detalles != 1
       OR v_pagos != 0 OR v_servicios != 0 THEN
        RAISE_APPLICATION_ERROR(
            -20976,
            'El ID no corresponde exclusivamente a la reserva de demostracion.'
        );
    END IF;

    DELETE FROM reserva
     WHERE id_reserva = v_id;

    v_borradas := SQL%ROWCOUNT;

    SELECT COUNT(*)
      INTO v_detalles
      FROM reserva_habitacion
     WHERE id_reserva = v_id;

    SELECT COUNT(*) INTO v_pagos FROM pago WHERE id_reserva = v_id;
    SELECT COUNT(*) INTO v_servicios FROM reserva_servicio WHERE id_reserva = v_id;

    IF v_borradas != 1 OR v_detalles != 0 OR v_pagos != 0 OR v_servicios != 0 THEN
        RAISE_APPLICATION_ERROR(-20976, 'La limpieza de la reserva de A fallo.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'LIMPIEZA OK: reserva=' || v_id ||
        ' y todas sus relaciones fueron eliminadas por cascada.'
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- El COMMIT dentro del bloque pertenece exclusivamente a la limpieza manual y
-- solo ocurre despues de validar el ID y todas las relaciones afectadas.

-- CAPTURA 5: salida LIMPIEZA OK y commit de limpieza.

-- =============================================================================
-- VARIANTE ADICIONAL SEGURA: A REVIERTE Y B PUEDE CONTINUAR
-- =============================================================================
-- Vuelva a ejecutar PASO 0, capture un candidato libre y ejecute nuevamente los
-- ACCEPT de cada worksheet con exactamente los mismos valores.
--
-- SESION A:
--   1. Ejecute el bloque de A anterior con SP_CREAR_RESERVA_BLOQUEADA.
--   2. No confirme.
--
-- SESION B:
--   1. Ejecute el siguiente bloque; quedara esperando.
--
-- SESION A:
--   1. Seleccione y ejecute: ROLLBACK; B se desbloqueara.
--
-- SESION B:
--   1. La llamada terminara correctamente porque A no confirmo conflicto.
--   2. Ejecute ROLLBACK para eliminar su reserva temporal.

-- SESION B - BLOQUE PARA LA VARIANTE ROLLBACK:
VARIABLE v_id_reserva_b_segura NUMBER

BEGIN
    DBMS_OUTPUT.PUT_LINE(
        'B SEGURA SID=' || SYS_CONTEXT('USERENV', 'SID') ||
        ' ANTES=' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM')
    );

    sp_crear_reserva_bloqueada(
        p_id_cliente    => &p_id_cliente,
        p_id_habitacion => &p_id_habitacion,
        p_fecha_in      => TO_DATE('&p_fecha_in', 'YYYY-MM-DD'),
        p_fecha_out     => TO_DATE('&p_fecha_out', 'YYYY-MM-DD'),
        p_num_huespedes => 1,
        p_id_reserva    => :v_id_reserva_b_segura
    );

    DBMS_OUTPUT.PUT_LINE(
        'B SEGURA DESPUES=' ||
        TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM') ||
        ' RESERVA=' || :v_id_reserva_b_segura
    );
END;
/

PRINT v_id_reserva_b_segura

-- SESION B, despues de comprobar el exito:
ROLLBACK;

-- CAPTURA 6: B continuo tras el ROLLBACK de A y luego elimino su propia fila.
