-- =============================================================================
-- TURISMOUQ - ENTREGA 3
-- Pruebas automaticas de reserva + pago y rollback parcial.
-- Todas las filas creadas son temporales. Este script nunca hace COMMIT y
-- comprueba que los conteos finales coincidan con los iniciales.
-- =============================================================================

SET SERVEROUTPUT ON

DECLARE
    v_cliente       cliente.id_cliente%TYPE;
    v_habitacion    habitacion.id_habitacion%TYPE;
    v_capacidad     habitacion.capacidad%TYPE;
    v_fecha_in      DATE;
    v_fecha_out     DATE;
    v_id_reserva    reserva.id_reserva%TYPE;
    v_id_pago       pago.id_pago%TYPE;
    v_id_marcadora  reserva.id_reserva%TYPE;
    v_subtotal      reserva_habitacion.subtotal_calculado%TYPE;
    v_monto         pago.monto%TYPE;
    v_codigo        NUMBER;
    v_cantidad      NUMBER;
    v_reservas_0    NUMBER;
    v_habitaciones_0 NUMBER;
    v_pagos_0       NUMBER;
    v_reservas_a    NUMBER;
    v_habitaciones_a NUMBER;
    v_pagos_a       NUMBER;
    v_reservas_b    NUMBER;
    v_habitaciones_b NUMBER;
    v_pagos_b       NUMBER;
BEGIN
    SAVEPOINT prueba_e3_todas;

    SELECT COUNT(*) INTO v_reservas_0 FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_0 FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_0 FROM pago;

    SELECT MIN(id_cliente)
      INTO v_cliente
      FROM cliente;

    IF v_cliente IS NULL THEN
        RAISE_APPLICATION_ERROR(-20970, 'No existe un cliente para las pruebas.');
    END IF;

    -- Busca tres noches libres, con una temporada prioritaria unica y una tarifa.
    WITH limites AS (
        SELECT MIN(TRUNC(fecha_inicio)) AS fecha_min,
               MAX(TRUNC(fecha_fin)) AS fecha_max
          FROM temporada
    ),
    fechas AS (
        SELECT fecha_min + LEVEL - 1 AS fecha_in
          FROM limites
        CONNECT BY LEVEL <= fecha_max - fecha_min - 1
    ),
    intervalos AS (
        SELECT h.id_habitacion, h.capacidad,
               f.fecha_in, f.fecha_in + 3 AS fecha_out
          FROM habitacion h
          CROSS JOIN fechas f
         WHERE h.capacidad >= 1
    ),
    noches AS (
        SELECT i.id_habitacion, i.capacidad, i.fecha_in, i.fecha_out,
               i.fecha_in + d.n AS fecha_noche
          FROM intervalos i
          CROSS JOIN (
              SELECT LEVEL - 1 AS n FROM dual CONNECT BY LEVEL <= 3
          ) d
    ),
    candidatas AS (
        SELECT n.*, t.id_temporada,
               CASE
                   WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2
                   ELSE 1
               END AS prioridad
          FROM noches n
          JOIN temporada t
            ON n.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
    ),
    priorizadas AS (
        SELECT c.*,
               MIN(prioridad) OVER (
                   PARTITION BY id_habitacion, fecha_in, fecha_noche
               ) AS prioridad_minima
          FROM candidatas c
    ),
    resumen_noche AS (
        SELECT p.id_habitacion, p.capacidad, p.fecha_in, p.fecha_out,
               p.fecha_noche,
               COUNT(DISTINCT p.id_temporada) AS temporadas,
               COUNT(ta.id_tarifa) AS tarifas
          FROM priorizadas p
          LEFT JOIN tarifa ta
            ON ta.id_habitacion = p.id_habitacion
           AND ta.id_temporada = p.id_temporada
         WHERE p.prioridad = p.prioridad_minima
         GROUP BY p.id_habitacion, p.capacidad, p.fecha_in,
                  p.fecha_out, p.fecha_noche
    ),
    validos AS (
        SELECT id_habitacion, capacidad, fecha_in, fecha_out
          FROM resumen_noche
         GROUP BY id_habitacion, capacidad, fecha_in, fecha_out
        HAVING COUNT(*) = 3
           AND SUM(
                   CASE
                       WHEN temporadas = 1 AND tarifas = 1 THEN 0
                       ELSE 1
                   END
               ) = 0
    )
    SELECT id_habitacion, capacidad, fecha_in, fecha_out
      INTO v_habitacion, v_capacidad, v_fecha_in, v_fecha_out
      FROM (
          SELECT v.*
            FROM validos v
           WHERE NOT EXISTS (
                     SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r
                         ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = v.id_habitacion
                        AND r.estado <> 'CANCELADA'
                        AND TRUNC(rh.fecha_checkin) < v.fecha_out
                        AND TRUNC(rh.fecha_checkout) > v.fecha_in
                 )
           ORDER BY v.fecha_in, v.id_habitacion
      )
     WHERE ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE(
        'CANDIDATO: cliente=' || v_cliente ||
        ', habitacion=' || v_habitacion ||
        ', fechas=' || TO_CHAR(v_fecha_in, 'YYYY-MM-DD') || ' a ' ||
        TO_CHAR(v_fecha_out, 'YYYY-MM-DD')
    );

    -- -------------------------------------------------------------------------
    -- PRUEBA 1: reserva y pago completo exitosos.
    -- -------------------------------------------------------------------------
    SAVEPOINT prueba_e3_exito;
    v_id_reserva := NULL;
    v_id_pago := NULL;

    sp_crear_reserva_pago(
        p_id_cliente    => v_cliente,
        p_id_habitacion => v_habitacion,
        p_fecha_in      => v_fecha_in,
        p_fecha_out     => v_fecha_out,
        p_num_huespedes => 1,
        p_metodo_pago   => 'PRUEBA E3',
        p_monto_pago    => NULL,
        p_id_reserva    => v_id_reserva,
        p_id_pago       => v_id_pago
    );

    IF v_id_reserva IS NULL OR v_id_pago IS NULL THEN
        RAISE_APPLICATION_ERROR(-20970, 'PRUEBA 1: no se retornaron ambos IDs.');
    END IF;

    SELECT COUNT(*), MAX(rh.subtotal_calculado), MAX(p.monto)
      INTO v_cantidad, v_subtotal, v_monto
      FROM reserva r
      JOIN reserva_habitacion rh
        ON rh.id_reserva = r.id_reserva
      JOIN pago p
        ON p.id_reserva = r.id_reserva
     WHERE r.id_reserva = v_id_reserva
       AND p.id_pago = v_id_pago
       AND rh.id_habitacion = v_habitacion;

    IF v_cantidad != 1 OR v_subtotal IS NULL OR v_monto != v_subtotal THEN
        RAISE_APPLICATION_ERROR(-20970, 'PRUEBA 1: filas o monto incorrectos.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PRUEBA 1 OK: reserva=' || v_id_reserva ||
        ', pago=' || v_id_pago ||
        ', subtotal=' || TO_CHAR(v_subtotal, 'FM9999999990D00') ||
        ', monto=' || TO_CHAR(v_monto, 'FM9999999990D00')
    );

    ROLLBACK TO prueba_e3_exito;

    SELECT COUNT(*) INTO v_cantidad
      FROM reserva
     WHERE id_reserva = v_id_reserva;
    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20970, 'PRUEBA 1: la reserva sobrevivio al rollback.');
    END IF;

    -- -------------------------------------------------------------------------
    -- PRUEBA 2: ORA-12899 durante INSERT PAGO. El metodo supera VARCHAR2(50).
    -- -------------------------------------------------------------------------
    SAVEPOINT prueba_e3_error_pago;
    SELECT COUNT(*) INTO v_reservas_a FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_a FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_a FROM pago;
    v_id_reserva := NULL;
    v_id_pago := NULL;

    BEGIN
        sp_crear_reserva_pago(
            p_id_cliente    => v_cliente,
            p_id_habitacion => v_habitacion,
            p_fecha_in      => v_fecha_in,
            p_fecha_out     => v_fecha_out,
            p_num_huespedes => 1,
            p_metodo_pago   => RPAD('X', 51, 'X'),
            p_monto_pago    => NULL,
            p_id_reserva    => v_id_reserva,
            p_id_pago       => v_id_pago
        );
        RAISE_APPLICATION_ERROR(-20971, 'PRUEBA 2: el pago invalido fue aceptado.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -12899 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE(
                'PRUEBA 2: codigo esperado=' || v_codigo ||
                '; el error ocurrio al insertar PAGO despues de crear la reserva.'
            );
    END;

    SELECT COUNT(*) INTO v_reservas_b FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_b FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_b FROM pago;

    IF v_id_reserva IS NOT NULL OR v_id_pago IS NOT NULL
       OR v_reservas_b != v_reservas_a
       OR v_habitaciones_b != v_habitaciones_a
       OR v_pagos_b != v_pagos_a THEN
        RAISE_APPLICATION_ERROR(-20971, 'PRUEBA 2: el rollback atomico dejo residuos.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PRUEBA 2 OK: RESERVA, RESERVA_HABITACION y PAGO regresaron a sus conteos previos.'
    );
    ROLLBACK TO prueba_e3_error_pago;

    -- -------------------------------------------------------------------------
    -- PRUEBA 3: error original de Entrega 2 antes de crear la reserva.
    -- -------------------------------------------------------------------------
    SAVEPOINT prueba_e3_error_reserva;
    SELECT COUNT(*) INTO v_reservas_a FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_a FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_a FROM pago;
    v_id_reserva := NULL;
    v_id_pago := NULL;

    BEGIN
        sp_crear_reserva_pago(
            p_id_cliente    => v_cliente,
            p_id_habitacion => v_habitacion,
            p_fecha_in      => v_fecha_in,
            p_fecha_out     => v_fecha_in,
            p_num_huespedes => 1,
            p_metodo_pago   => 'PRUEBA E3',
            p_monto_pago    => NULL,
            p_id_reserva    => v_id_reserva,
            p_id_pago       => v_id_pago
        );
        RAISE_APPLICATION_ERROR(-20972, 'PRUEBA 3: las fechas invalidas fueron aceptadas.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -20202 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 3: codigo original esperado=' || v_codigo);
    END;

    SELECT COUNT(*) INTO v_reservas_b FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_b FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_b FROM pago;

    IF v_id_reserva IS NOT NULL OR v_id_pago IS NOT NULL
       OR v_reservas_b != v_reservas_a
       OR v_habitaciones_b != v_habitaciones_a
       OR v_pagos_b != v_pagos_a THEN
        RAISE_APPLICATION_ERROR(-20972, 'PRUEBA 3: el error de reserva dejo residuos.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('PRUEBA 3 OK: ORA-20202 se propago y no se creo PAGO.');
    ROLLBACK TO prueba_e3_error_reserva;

    -- -------------------------------------------------------------------------
    -- PRUEBA 4: rollback parcial respecto a la transaccion del llamador.
    -- -------------------------------------------------------------------------
    SAVEPOINT prueba_e3_raiz;

    INSERT INTO reserva (id_cliente, estado)
    VALUES (v_cliente, 'PRUEBA_E3_MARCADOR')
    RETURNING id_reserva INTO v_id_marcadora;

    SELECT COUNT(*) INTO v_cantidad
      FROM reserva
     WHERE id_reserva = v_id_marcadora
       AND estado = 'PRUEBA_E3_MARCADOR';
    IF v_cantidad != 1 THEN
        RAISE_APPLICATION_ERROR(-20973, 'PRUEBA 4: no se creo la marcadora temporal.');
    END IF;

    SELECT COUNT(*) INTO v_reservas_a FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_a FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_a FROM pago;
    v_id_reserva := NULL;
    v_id_pago := NULL;

    BEGIN
        sp_crear_reserva_pago(
            p_id_cliente    => v_cliente,
            p_id_habitacion => v_habitacion,
            p_fecha_in      => v_fecha_in,
            p_fecha_out     => v_fecha_out,
            p_num_huespedes => 1,
            p_metodo_pago   => RPAD('Y', 51, 'Y'),
            p_monto_pago    => NULL,
            p_id_reserva    => v_id_reserva,
            p_id_pago       => v_id_pago
        );
        RAISE_APPLICATION_ERROR(-20973, 'PRUEBA 4: el pago invalido fue aceptado.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -12899 THEN
                RAISE;
            END IF;
    END;

    SELECT COUNT(*) INTO v_reservas_b FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_b FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_b FROM pago;
    SELECT COUNT(*) INTO v_cantidad
      FROM reserva
     WHERE id_reserva = v_id_marcadora
       AND estado = 'PRUEBA_E3_MARCADOR';

    IF v_cantidad != 1
       OR v_id_reserva IS NOT NULL OR v_id_pago IS NOT NULL
       OR v_reservas_b != v_reservas_a
       OR v_habitaciones_b != v_habitaciones_a
       OR v_pagos_b != v_pagos_a THEN
        RAISE_APPLICATION_ERROR(-20973, 'PRUEBA 4: rollback parcial incorrecto.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PRUEBA 4: marcadora=' || v_id_marcadora ||
        ' sigue visible; la unidad reserva+pago fallida fue eliminada.'
    );

    ROLLBACK TO prueba_e3_raiz;

    SELECT COUNT(*) INTO v_cantidad
      FROM reserva
     WHERE id_reserva = v_id_marcadora;
    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20973, 'PRUEBA 4: la marcadora sobrevivio al rollback final.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PRUEBA 4 OK: rollback parcial demostrado y marcadora temporal eliminada.'
    );

    ROLLBACK TO prueba_e3_todas;

    SELECT COUNT(*) INTO v_reservas_b FROM reserva;
    SELECT COUNT(*) INTO v_habitaciones_b FROM reserva_habitacion;
    SELECT COUNT(*) INTO v_pagos_b FROM pago;

    IF v_reservas_b != v_reservas_0
       OR v_habitaciones_b != v_habitaciones_0
       OR v_pagos_b != v_pagos_0 THEN
        RAISE_APPLICATION_ERROR(-20974, 'LIMPIEZA: los conteos finales no coinciden.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'LIMPIEZA OK: no quedaron filas temporales. Los identities pueden tener huecos.'
    );
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_e3_todas;
        DBMS_OUTPUT.PUT_LINE('PRUEBAS E3 ERROR: ' || SQLCODE || ' - ' || SQLERRM);
        RAISE;
END;
/

-- El bloque ya regreso a prueba_e3_todas tanto en exito como en error. No se
-- usa un ROLLBACK sin savepoint porque podria revertir trabajo previo ajeno.
