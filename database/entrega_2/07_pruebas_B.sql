-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
-- PRUEBAS INTEGRADAS: trigger de solapamiento y pkg_turismo
-- Cada bloque revierte sus datos con ROLLBACK TO SAVEPOINT.
-- =============================================================================

SET SERVEROUTPUT ON;

-- ============================================================
-- PRUEBAS TRIGGER DE SOLAPAMIENTO
-- ============================================================
DECLARE
    v_cliente cliente.id_cliente%TYPE;
    v_hab     habitacion.id_habitacion%TYPE;
    v_inicio  DATE;
    v_res_a   reserva.id_reserva%TYPE;
    v_res_b   reserva.id_reserva%TYPE;
    v_res_c   reserva.id_reserva%TYPE;
    v_res_d   reserva.id_reserva%TYPE;
    v_codigo  NUMBER;
    v_restantes NUMBER;
BEGIN
    SAVEPOINT prueba_solapamiento;

    SELECT MIN(id_cliente) INTO v_cliente FROM cliente;

    SELECT id_habitacion, fecha_inicio
      INTO v_hab, v_inicio
      FROM (
          SELECT h.id_habitacion,
                 ADD_MONTHS(TRUNC(SYSDATE), 24) + d.n AS fecha_inicio
            FROM habitacion h
            CROSS JOIN (
                SELECT LEVEL - 1 AS n FROM dual CONNECT BY LEVEL <= 366
            ) d
           WHERE NOT EXISTS (
                     SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = h.id_habitacion
                        AND r.estado <> 'CANCELADA'
                        AND TRUNC(rh.fecha_checkin) < ADD_MONTHS(TRUNC(SYSDATE), 24) + d.n + 8
                        AND TRUNC(rh.fecha_checkout) > ADD_MONTHS(TRUNC(SYSDATE), 24) + d.n
                 )
           ORDER BY d.n, h.id_habitacion
      )
     WHERE ROWNUM = 1;

    IF v_cliente IS NULL OR v_hab IS NULL OR v_inicio IS NULL THEN
        RAISE_APPLICATION_ERROR(-20990, 'No se encontro contexto para probar solapamiento.');
    END IF;

    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_a;
    INSERT INTO reserva_habitacion (
        id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado
    ) VALUES (v_res_a, v_hab, v_inicio, v_inicio + 5, 0);
    DBMS_OUTPUT.PUT_LINE('TRIGGER 1 OK: reserva base aceptada en ' || TO_CHAR(v_inicio, 'YYYY-MM-DD') || '.');

    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_b;
    BEGIN
        INSERT INTO reserva_habitacion (
            id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado
        ) VALUES (v_res_b, v_hab, v_inicio + 2, v_inicio + 4, 0);
        RAISE_APPLICATION_ERROR(-20990, 'TRIGGER 2 fallo: no se rechazo el cruce.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -20205 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('TRIGGER 2 OK: cruce rechazado con ORA-20205.');
    END;

    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_c;
    INSERT INTO reserva_habitacion (
        id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado
    ) VALUES (v_res_c, v_hab, v_inicio + 5, v_inicio + 8, 0);
    DBMS_OUTPUT.PUT_LINE('TRIGGER 3 OK: reserva contigua aceptada.');

    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CANCELADA')
    RETURNING id_reserva INTO v_res_d;
    INSERT INTO reserva_habitacion (
        id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado
    ) VALUES (v_res_d, v_hab, v_inicio, v_inicio + 5, 0);
    DBMS_OUTPUT.PUT_LINE('TRIGGER 4 OK: reserva CANCELADA no bloquea.');

    ROLLBACK TO prueba_solapamiento;

    SELECT COUNT(*)
      INTO v_restantes
      FROM reserva
     WHERE id_reserva IN (v_res_a, v_res_b, v_res_c, v_res_d);

    IF v_restantes != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'TRIGGER fallo: quedaron reservas creadas por la prueba.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('TRIGGER ROLLBACK OK: IDs temporales eliminados.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_solapamiento;
        RAISE;
END;
/

-- ============================================================
-- PRUEBAS PKG_TURISMO.SP_CREAR_RESERVA
-- ============================================================
DECLARE
    v_cliente     cliente.id_cliente%TYPE;
    v_hab         habitacion.id_habitacion%TYPE;
    v_capacidad   habitacion.capacidad%TYPE;
    v_fecha_in    DATE;
    v_fecha_out   DATE;
    v_res         reserva.id_reserva%TYPE;
    v_res2        reserva.id_reserva%TYPE;
    v_esperado    NUMBER;
    v_guardado    NUMBER;
    v_hab_guardada habitacion.id_habitacion%TYPE;
    v_in_guardada  DATE;
    v_out_guardada DATE;
    v_cantidad    NUMBER;
    v_codigo      NUMBER;
    v_cliente_inexistente cliente.id_cliente%TYPE;
    v_hab_inexistente habitacion.id_habitacion%TYPE;
BEGIN
    SAVEPOINT prueba_sp_reserva;

    SELECT MIN(id_cliente), MIN(id_cliente) - 1
      INTO v_cliente, v_cliente_inexistente
      FROM cliente;

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
        SELECT h.id_habitacion, h.capacidad, f.fecha_in, f.fecha_in + 3 AS fecha_out
          FROM habitacion h
          CROSS JOIN fechas f
         WHERE h.capacidad >= 1
    ),
    noches AS (
        SELECT i.id_habitacion, i.capacidad, i.fecha_in, i.fecha_out,
               i.fecha_in + d.n AS fecha_noche
          FROM intervalos i
          CROSS JOIN (SELECT LEVEL - 1 AS n FROM dual CONNECT BY LEVEL <= 3) d
    ),
    candidatas AS (
        SELECT n.*, t.id_temporada,
               CASE WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2 ELSE 1 END AS prioridad
          FROM noches n
          JOIN temporada t
            ON n.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
    ),
    priorizadas AS (
        SELECT c.*, MIN(prioridad) OVER (
                   PARTITION BY id_habitacion, fecha_in, fecha_noche
               ) AS prioridad_minima
          FROM candidatas c
    ),
    resumen_noche AS (
        SELECT p.id_habitacion, p.capacidad, p.fecha_in, p.fecha_out, p.fecha_noche,
               COUNT(DISTINCT p.id_temporada) AS temporadas,
               COUNT(ta.id_tarifa) AS tarifas
          FROM priorizadas p
          LEFT JOIN tarifa ta
            ON ta.id_habitacion = p.id_habitacion
           AND ta.id_temporada = p.id_temporada
         WHERE p.prioridad = p.prioridad_minima
         GROUP BY p.id_habitacion, p.capacidad, p.fecha_in, p.fecha_out, p.fecha_noche
    ),
    validos AS (
        SELECT id_habitacion, capacidad, fecha_in, fecha_out
          FROM resumen_noche
         GROUP BY id_habitacion, capacidad, fecha_in, fecha_out
        HAVING COUNT(*) = 3
           AND SUM(CASE WHEN temporadas = 1 AND tarifas = 1 THEN 0 ELSE 1 END) = 0
    )
    SELECT id_habitacion, capacidad, fecha_in, fecha_out
      INTO v_hab, v_capacidad, v_fecha_in, v_fecha_out
      FROM (
          SELECT v.*
            FROM validos v
           WHERE NOT EXISTS (
                     SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = v.id_habitacion
                        AND r.estado <> 'CANCELADA'
                        AND TRUNC(rh.fecha_checkin) < v.fecha_out
                        AND TRUNC(rh.fecha_checkout) > v.fecha_in
                 )
           ORDER BY v.fecha_in, v.id_habitacion
      )
     WHERE ROWNUM = 1;

    SELECT MIN(id_habitacion) - 1
      INTO v_hab_inexistente
      FROM habitacion;

    pkg_turismo.sp_crear_reserva(
        v_cliente, v_hab, v_fecha_in, v_fecha_out, 1, v_res
    );

    SELECT rh.subtotal_calculado, rh.id_habitacion,
           TRUNC(rh.fecha_checkin), TRUNC(rh.fecha_checkout)
      INTO v_guardado, v_hab_guardada, v_in_guardada, v_out_guardada
      FROM reserva_habitacion rh
     WHERE rh.id_reserva = v_res;

    v_esperado := fn_valor_estadia(v_hab, v_fecha_in, v_fecha_out);

    IF v_guardado IS NULL OR v_esperado IS NULL
       OR v_guardado != v_esperado
       OR v_hab_guardada != v_hab
       OR v_in_guardada != v_fecha_in
       OR v_out_guardada != v_fecha_out THEN
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA fallo: datos o subtotal incorrectos.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(
        'SP RESERVA 1 OK: reserva=' || v_res || ', habitacion=' || v_hab
        || ', subtotal=' || TO_CHAR(v_guardado, 'FM9999999990D00')
    );

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente, v_hab, v_fecha_in + 1, v_fecha_out + 1, 1, v_res2
        );
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA 2 fallo: no se rechazo el cruce.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20201 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('SP RESERVA 2 OK: ORA-20201 por cruce.');
    END;

    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, v_hab, v_fecha_in, v_fecha_in, 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA 3 fallo: fechas iguales aceptadas.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20202 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('SP RESERVA 3 OK: ORA-20202 por fechas invalidas.');
    END;

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente, v_hab, v_fecha_in, v_fecha_out, v_capacidad + 1, v_res2
        );
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA 4 fallo: capacidad excedida aceptada.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20203 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('SP RESERVA 4 OK: ORA-20203 por capacidad.');
    END;

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente_inexistente, v_hab, v_fecha_in, v_fecha_out, 1, v_res2
        );
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA 5 fallo: cliente inexistente aceptado.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20204 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('SP RESERVA 5 OK: ORA-20204 por cliente inexistente.');
    END;

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente, v_hab_inexistente, v_fecha_in, v_fecha_out, 1, v_res2
        );
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA 6 fallo: habitacion inexistente aceptada.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20204 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('SP RESERVA 6 OK: ORA-20204 por habitacion inexistente.');
    END;

    ROLLBACK TO prueba_sp_reserva;

    SELECT COUNT(*) INTO v_cantidad FROM reserva WHERE id_reserva = v_res;
    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'SP RESERVA fallo: el ID temporal sobrevivio al rollback.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('SP RESERVA ROLLBACK OK: reserva temporal eliminada.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_sp_reserva;
        RAISE;
END;
/

-- ============================================================
-- PROPAGACION DE ERRORES DE FN_VALOR_ESTADIA
-- ============================================================
DECLARE
    v_cliente cliente.id_cliente%TYPE;
    v_hab     habitacion.id_habitacion%TYPE;
    v_fecha_sin_temporada DATE;
    v_fecha_tarifa DATE;
    v_id_tarifa tarifa.id_tarifa%TYPE;
    v_reserva reserva.id_reserva%TYPE;
    v_codigo NUMBER;
    v_conteo_inicial NUMBER;
    v_conteo_final NUMBER;
BEGIN
    SAVEPOINT prueba_propagacion;

    SELECT MIN(id_cliente) INTO v_cliente FROM cliente;
    SELECT MIN(id_habitacion) INTO v_hab FROM habitacion WHERE capacidad >= 1;
    SELECT MAX(TRUNC(fecha_fin)) + 2 INTO v_fecha_sin_temporada FROM temporada;
    SELECT COUNT(*) INTO v_conteo_inicial FROM reserva;

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente, v_hab, v_fecha_sin_temporada, v_fecha_sin_temporada + 1, 1, v_reserva
        );
        RAISE_APPLICATION_ERROR(-20990, 'PROPAGACION -20106 fallo: reserva creada.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -20106 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PROPAGACION 1 OK: sp_crear_reserva conservo ORA-20106.');
    END;

    WITH limites AS (
        SELECT MIN(TRUNC(fecha_inicio)) AS fecha_min,
               MAX(TRUNC(fecha_fin)) AS fecha_max
          FROM temporada
    ),
    fechas AS (
        SELECT fecha_min + LEVEL - 1 AS fecha_noche
          FROM limites
        CONNECT BY LEVEL <= fecha_max - fecha_min + 1
    ),
    candidatas AS (
        SELECT f.fecha_noche, t.id_temporada,
               CASE WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2 ELSE 1 END AS prioridad
          FROM fechas f
          JOIN temporada t
            ON f.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
    ),
    priorizadas AS (
        SELECT c.*, MIN(prioridad) OVER (PARTITION BY fecha_noche) AS prioridad_minima
          FROM candidatas c
    )
    SELECT fecha_noche, id_tarifa
      INTO v_fecha_tarifa, v_id_tarifa
      FROM (
          SELECT p.fecha_noche, MIN(ta.id_tarifa) AS id_tarifa
            FROM priorizadas p
            JOIN tarifa ta
              ON ta.id_habitacion = v_hab
             AND ta.id_temporada = p.id_temporada
           WHERE p.prioridad = p.prioridad_minima
             AND NOT EXISTS (
                     SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = v_hab
                        AND r.estado <> 'CANCELADA'
                        AND TRUNC(rh.fecha_checkin) < p.fecha_noche + 1
                        AND TRUNC(rh.fecha_checkout) > p.fecha_noche
                 )
           GROUP BY p.fecha_noche
          HAVING COUNT(DISTINCT p.id_temporada) = 1
             AND COUNT(ta.id_tarifa) = 1
           ORDER BY p.fecha_noche
      )
     WHERE ROWNUM = 1;

    DELETE FROM tarifa WHERE id_tarifa = v_id_tarifa;

    BEGIN
        pkg_turismo.sp_crear_reserva(
            v_cliente, v_hab, v_fecha_tarifa, v_fecha_tarifa + 1, 1, v_reserva
        );
        RAISE_APPLICATION_ERROR(-20990, 'PROPAGACION -20108 fallo: reserva creada.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -20108 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PROPAGACION 2 OK: sp_crear_reserva conservo ORA-20108.');
    END;

    ROLLBACK TO prueba_propagacion;

    SELECT COUNT(*) INTO v_conteo_final FROM reserva;
    IF v_conteo_final != v_conteo_inicial THEN
        RAISE_APPLICATION_ERROR(-20990, 'PROPAGACION fallo: quedaron reservas temporales.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('PROPAGACION ROLLBACK OK: tarifa y auditoria restauradas.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_propagacion;
        RAISE;
END;
/

-- ============================================================
-- PRUEBAS PKG_TURISMO.SP_LIQUIDAR_MES
-- ============================================================
DECLARE
    v_cliente cliente.id_cliente%TYPE;
    v_hab habitacion.id_habitacion%TYPE;
    v_aloj alojamiento.id_alojamiento%TYPE;
    v_fecha_in DATE;
    v_fecha_out DATE;
    v_periodo DATE;
    v_res reserva.id_reserva%TYPE;
    v_res_canc reserva.id_reserva%TYPE;
    v_servicio servicio.id_servicio%TYPE;
    v_precio servicio.precio_unitario%TYPE;
    v_hab_prueba NUMBER;
    v_serv_prueba NUMBER;
    v_noches_base NUMBER;
    v_hab_base NUMBER;
    v_serv_base NUMBER;
    v_noches NUMBER;
    v_ing_hab NUMBER;
    v_ing_serv NUMBER;
    v_total NUMBER;
    v_procesados NUMBER;
    v_filas NUMBER;
    v_filas_iniciales NUMBER;
    v_noches_inicial NUMBER;
    v_hab_inicial NUMBER;
    v_serv_inicial NUMBER;
    v_total_inicial NUMBER;
    v_periodo_vacio DATE;
BEGIN
    SAVEPOINT prueba_liquidacion;

    SELECT MIN(id_cliente) INTO v_cliente FROM cliente;

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
        SELECT h.id_habitacion, h.id_alojamiento, f.fecha_in, f.fecha_in + 3 AS fecha_out
          FROM habitacion h
          CROSS JOIN fechas f
         WHERE h.capacidad >= 1
           AND EXISTS (SELECT 1 FROM servicio s WHERE s.id_alojamiento = h.id_alojamiento)
           AND TRUNC(f.fecha_in, 'MM') = TRUNC(f.fecha_in + 2, 'MM')
    ),
    noches AS (
        SELECT i.*, i.fecha_in + d.n AS fecha_noche
          FROM intervalos i
          CROSS JOIN (SELECT LEVEL - 1 AS n FROM dual CONNECT BY LEVEL <= 3) d
    ),
    candidatas AS (
        SELECT n.*, t.id_temporada,
               CASE WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2 ELSE 1 END AS prioridad
          FROM noches n
          JOIN temporada t
            ON n.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
    ),
    priorizadas AS (
        SELECT c.*, MIN(prioridad) OVER (
                   PARTITION BY id_habitacion, fecha_in, fecha_noche
               ) AS prioridad_minima
          FROM candidatas c
    ),
    resumen AS (
        SELECT p.id_habitacion, p.id_alojamiento, p.fecha_in, p.fecha_out, p.fecha_noche,
               COUNT(DISTINCT p.id_temporada) AS temporadas,
               COUNT(ta.id_tarifa) AS tarifas
          FROM priorizadas p
          LEFT JOIN tarifa ta
            ON ta.id_habitacion = p.id_habitacion
           AND ta.id_temporada = p.id_temporada
         WHERE p.prioridad = p.prioridad_minima
         GROUP BY p.id_habitacion, p.id_alojamiento, p.fecha_in, p.fecha_out, p.fecha_noche
    ),
    validos AS (
        SELECT id_habitacion, id_alojamiento, fecha_in, fecha_out
          FROM resumen
         GROUP BY id_habitacion, id_alojamiento, fecha_in, fecha_out
        HAVING COUNT(*) = 3
           AND SUM(CASE WHEN temporadas = 1 AND tarifas = 1 THEN 0 ELSE 1 END) = 0
    )
    SELECT id_habitacion, id_alojamiento, fecha_in, fecha_out
      INTO v_hab, v_aloj, v_fecha_in, v_fecha_out
      FROM (
          SELECT v.*
            FROM validos v
           WHERE NOT EXISTS (
                     SELECT 1
                       FROM reserva_habitacion rh
                       JOIN reserva r ON r.id_reserva = rh.id_reserva
                      WHERE rh.id_habitacion = v.id_habitacion
                        AND r.estado <> 'CANCELADA'
                        AND TRUNC(rh.fecha_checkin) < v.fecha_out
                        AND TRUNC(rh.fecha_checkout) > v.fecha_in
                 )
           ORDER BY v.fecha_in, v.id_habitacion
      )
     WHERE ROWNUM = 1;

    v_periodo := TRUNC(v_fecha_in, 'MM');

    SELECT COUNT(*), NVL(MAX(noches), 0), NVL(MAX(ingreso_habitaciones), 0),
           NVL(MAX(ingreso_servicios), 0), NVL(MAX(total), 0)
      INTO v_filas_iniciales, v_noches_inicial, v_hab_inicial, v_serv_inicial, v_total_inicial
      FROM liquidacion_mensual
     WHERE id_alojamiento = v_aloj
       AND periodo = v_periodo;

    SELECT NVL(SUM(TRUNC(rh.fecha_checkout) - TRUNC(rh.fecha_checkin)), 0),
           NVL(SUM(rh.subtotal_calculado), 0)
      INTO v_noches_base, v_hab_base
      FROM reserva_habitacion rh
      JOIN reserva r ON r.id_reserva = rh.id_reserva
      JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
     WHERE h.id_alojamiento = v_aloj
       AND r.estado <> 'CANCELADA'
       AND rh.fecha_checkin >= v_periodo
       AND rh.fecha_checkin < ADD_MONTHS(v_periodo, 1);

    SELECT NVL(SUM(rs.subtotal), 0)
      INTO v_serv_base
      FROM reserva_servicio rs
      JOIN reserva r ON r.id_reserva = rs.id_reserva
      JOIN servicio s ON s.id_servicio = rs.id_servicio
     WHERE s.id_alojamiento = v_aloj
       AND r.estado <> 'CANCELADA'
       AND rs.fecha_consumo >= v_periodo
       AND rs.fecha_consumo < ADD_MONTHS(v_periodo, 1);

    pkg_turismo.sp_crear_reserva(
        v_cliente, v_hab, v_fecha_in, v_fecha_out, 1, v_res
    );
    v_hab_prueba := fn_valor_estadia(v_hab, v_fecha_in, v_fecha_out);

    SELECT id_servicio, precio_unitario
      INTO v_servicio, v_precio
      FROM servicio
     WHERE id_servicio = (
               SELECT MIN(id_servicio) FROM servicio WHERE id_alojamiento = v_aloj
           );

    v_serv_prueba := 2 * v_precio;
    INSERT INTO reserva_servicio (
        id_reserva, id_servicio, cantidad, fecha_consumo, subtotal
    ) VALUES (v_res, v_servicio, 2, v_fecha_in + 1, v_serv_prueba);

    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CANCELADA')
    RETURNING id_reserva INTO v_res_canc;
    INSERT INTO reserva_habitacion (
        id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado
    ) VALUES (v_res_canc, v_hab, v_fecha_in, v_fecha_out, 999999);

    pkg_turismo.sp_liquidar_mes(
        EXTRACT(YEAR FROM v_periodo), EXTRACT(MONTH FROM v_periodo), v_procesados
    );

    SELECT noches, ingreso_habitaciones, ingreso_servicios, total
      INTO v_noches, v_ing_hab, v_ing_serv, v_total
      FROM liquidacion_mensual
     WHERE id_alojamiento = v_aloj
       AND periodo = v_periodo;

    IF v_noches != v_noches_base + 3
       OR v_ing_hab != v_hab_base + v_hab_prueba
       OR v_ing_serv != v_serv_base + v_serv_prueba
       OR v_total != v_hab_base + v_hab_prueba + v_serv_base + v_serv_prueba THEN
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION 1 fallo: valores incorrectos.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(
        'LIQUIDACION 1 OK: alojamiento=' || v_aloj || ', periodo='
        || TO_CHAR(v_periodo, 'YYYY-MM') || ', procesados=' || v_procesados
    );
    DBMS_OUTPUT.PUT_LINE('LIQUIDACION 2 OK: reserva CANCELADA excluida.');

    pkg_turismo.sp_liquidar_mes(
        EXTRACT(YEAR FROM v_periodo), EXTRACT(MONTH FROM v_periodo), v_procesados
    );
    SELECT COUNT(*) INTO v_filas
      FROM liquidacion_mensual
     WHERE id_alojamiento = v_aloj
       AND periodo = v_periodo;
    IF v_filas != 1 THEN
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION 3 fallo: re-liquidacion duplicada.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('LIQUIDACION 3 OK: re-liquidar no duplica la fila del alojamiento.');

    BEGIN
        pkg_turismo.sp_liquidar_mes(2026, 13, v_procesados);
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION 4 fallo: mes 13 aceptado.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20206 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('LIQUIDACION 4 OK: ORA-20206 por periodo invalido.');
    END;

    SELECT periodo
      INTO v_periodo_vacio
      FROM (
          SELECT ADD_MONTHS(DATE '2090-01-01', LEVEL - 1) AS periodo
            FROM dual
          CONNECT BY LEVEL <= 120
      ) m
     WHERE NOT EXISTS (
               SELECT 1
                 FROM reserva_habitacion rh
                 JOIN reserva r ON r.id_reserva = rh.id_reserva
                WHERE r.estado <> 'CANCELADA'
                  AND rh.fecha_checkin >= m.periodo
                  AND rh.fecha_checkin < ADD_MONTHS(m.periodo, 1)
           )
       AND NOT EXISTS (
               SELECT 1
                 FROM reserva_servicio rs
                 JOIN reserva r ON r.id_reserva = rs.id_reserva
                WHERE r.estado <> 'CANCELADA'
                  AND rs.fecha_consumo >= m.periodo
                  AND rs.fecha_consumo < ADD_MONTHS(m.periodo, 1)
           )
       AND ROWNUM = 1;

    pkg_turismo.sp_liquidar_mes(
        EXTRACT(YEAR FROM v_periodo_vacio), EXTRACT(MONTH FROM v_periodo_vacio), v_procesados
    );
    IF v_procesados != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION 5 fallo: periodo vacio proceso alojamientos.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('LIQUIDACION 5 OK: periodo vacio seleccionado dinamicamente.');

    ROLLBACK TO prueba_liquidacion;

    SELECT COUNT(*), NVL(MAX(noches), 0), NVL(MAX(ingreso_habitaciones), 0),
           NVL(MAX(ingreso_servicios), 0), NVL(MAX(total), 0)
      INTO v_filas, v_noches, v_ing_hab, v_ing_serv, v_total
      FROM liquidacion_mensual
     WHERE id_alojamiento = v_aloj
       AND periodo = v_periodo;

    IF v_filas != v_filas_iniciales
       OR v_noches != v_noches_inicial
       OR v_ing_hab != v_hab_inicial
       OR v_ing_serv != v_serv_inicial
       OR v_total != v_total_inicial THEN
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION fallo: estado inicial no restaurado.');
    END IF;

    SELECT COUNT(*) INTO v_filas FROM reserva WHERE id_reserva IN (v_res, v_res_canc);
    IF v_filas != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'LIQUIDACION fallo: quedaron reservas temporales.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('LIQUIDACION ROLLBACK OK: estado inicial restaurado.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_liquidacion;
        RAISE;
END;
/

-- ============================================================
-- PRUEBA AUTOMATICA DEL WRAPPER
-- ============================================================
DECLARE
    v_hab habitacion.id_habitacion%TYPE;
    v_fecha DATE;
    v_directo NUMBER;
    v_paquete NUMBER;
    v_diferencia NUMBER;
BEGIN
    WITH limites AS (
        SELECT MIN(TRUNC(fecha_inicio)) AS fecha_min,
               MAX(TRUNC(fecha_fin)) AS fecha_max
          FROM temporada
    ),
    fechas AS (
        SELECT fecha_min + LEVEL - 1 AS fecha_noche
          FROM limites
        CONNECT BY LEVEL <= fecha_max - fecha_min + 1
    ),
    candidatas AS (
        SELECT f.fecha_noche, t.id_temporada,
               CASE WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2 ELSE 1 END AS prioridad
          FROM fechas f
          JOIN temporada t
            ON f.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
    ),
    priorizadas AS (
        SELECT c.*, MIN(prioridad) OVER (PARTITION BY fecha_noche) AS prioridad_minima
          FROM candidatas c
    )
    SELECT id_habitacion, fecha_noche
      INTO v_hab, v_fecha
      FROM (
          SELECT ta.id_habitacion, p.fecha_noche
            FROM priorizadas p
            JOIN tarifa ta ON ta.id_temporada = p.id_temporada
           WHERE p.prioridad = p.prioridad_minima
           GROUP BY ta.id_habitacion, p.fecha_noche
          HAVING COUNT(DISTINCT p.id_temporada) = 1
             AND COUNT(ta.id_tarifa) = 1
           ORDER BY p.fecha_noche, ta.id_habitacion
      )
     WHERE ROWNUM = 1;

    v_directo := fn_valor_estadia(v_hab, v_fecha, v_fecha + 1);
    v_paquete := pkg_turismo.valor_estadia(v_hab, v_fecha, v_fecha + 1);
    v_diferencia := v_paquete - v_directo;

    IF v_directo IS NULL OR v_paquete IS NULL
       OR v_diferencia IS NULL OR v_diferencia != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'WRAPPER fallo: resultado diferente de la funcion directa.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(
        'WRAPPER OK: directo=' || TO_CHAR(v_directo, 'FM9999999990D00')
        || ', paquete=' || TO_CHAR(v_paquete, 'FM9999999990D00')
        || ', diferencia=' || v_diferencia
    );
END;
/
