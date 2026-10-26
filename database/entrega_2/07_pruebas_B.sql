-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
-- PRUEBAS: trigger de solapamiento, pkg_turismo.sp_crear_reserva y
--          pkg_turismo.sp_liquidar_mes (Integrante B)
-- REQUISITOS: scripts 04 (trigger) y 06 (tabla y paquete) ya ejecutados.
-- Cada bloque revierte sus datos con ROLLBACK TO SAVEPOINT.
-- =============================================================================

SET SERVEROUTPUT ON;

-- ============================================================
-- PRUEBAS trigger de solapamiento
-- ============================================================
DECLARE
    v_cliente  cliente.id_cliente%TYPE;
    v_hab      habitacion.id_habitacion%TYPE;
    v_res_a    reserva.id_reserva%TYPE;
    v_res_b    reserva.id_reserva%TYPE;
    v_res_c    reserva.id_reserva%TYPE;
    v_res_d    reserva.id_reserva%TYPE;
    v_codigo   NUMBER;
BEGIN
    SAVEPOINT prueba_solapamiento;

    SELECT MIN(id_cliente)    INTO v_cliente FROM cliente;
    SELECT MIN(id_habitacion) INTO v_hab     FROM habitacion;

    -- Reserva A: 10 al 15 de enero de 2030 (debe entrar).
    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_a;
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
    VALUES (v_res_a, v_hab, DATE '2030-01-10', DATE '2030-01-15', 0);
    DBMS_OUTPUT.PUT_LINE('PRUEBA 1 OK: reserva base aceptada.');

    -- Reserva B: 12 al 14 (cruza con A): debe rechazarse con -20205.
    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_b;
    BEGIN
        INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
        VALUES (v_res_b, v_hab, DATE '2030-01-12', DATE '2030-01-14', 0);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 2 fallo: no se rechazo el cruce.');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
            IF v_codigo != -20205 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 2 OK: cruce rechazado (ORA-20205).');
    END;

    -- Reserva C: entra el 15, justo cuando A sale (contigua): debe permitirse.
    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CONFIRMADA')
    RETURNING id_reserva INTO v_res_c;
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
    VALUES (v_res_c, v_hab, DATE '2030-01-15', DATE '2030-01-18', 0);
    DBMS_OUTPUT.PUT_LINE('PRUEBA 3 OK: reserva contigua permitida.');

    -- Reserva D: CANCELADA, mismo periodo que A: debe permitirse.
    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CANCELADA')
    RETURNING id_reserva INTO v_res_d;
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
    VALUES (v_res_d, v_hab, DATE '2030-01-10', DATE '2030-01-15', 0);
    DBMS_OUTPUT.PUT_LINE('PRUEBA 4 OK: reserva cancelada no bloquea.');

    ROLLBACK TO prueba_solapamiento;
    DBMS_OUTPUT.PUT_LINE('Datos de prueba revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_solapamiento;
        RAISE;
END;
/

-- ============================================================
-- PRUEBAS pkg_turismo.sp_crear_reserva
-- ============================================================
DECLARE
    v_cliente   cliente.id_cliente%TYPE;
    v_hab       habitacion.id_habitacion%TYPE;
    v_capacidad habitacion.capacidad%TYPE;
    v_res       reserva.id_reserva%TYPE;
    v_res2      reserva.id_reserva%TYPE;
    v_esperado  NUMBER;
    v_guardado  NUMBER;
    v_cantidad  NUMBER;
BEGIN
    SAVEPOINT prueba_sp_reserva;

    SELECT MIN(id_cliente) INTO v_cliente FROM cliente;
    SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
    SELECT capacidad INTO v_capacidad FROM habitacion WHERE id_habitacion = v_hab;

    -- PRUEBA 1: reserva valida, el subtotal coincide con la funcion de A.
    pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-11-10', DATE '2026-11-13', 1, v_res);
    v_esperado := fn_valor_estadia(v_hab, DATE '2026-11-10', DATE '2026-11-13');

    SELECT subtotal_calculado INTO v_guardado
      FROM reserva_habitacion WHERE id_reserva = v_res;

    IF v_guardado != v_esperado THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 1 fallo: subtotal ' || v_guardado ||
                                ' distinto de ' || v_esperado);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 1 OK: reserva ' || v_res || ' creada, subtotal ' || v_guardado);

    -- PRUEBA 2: misma habitacion, fechas que se cruzan -> -20201.
    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-11-12', DATE '2026-11-14', 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 2 fallo: no se rechazo el cruce.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20201 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 2 OK: ORA-20201 habitacion no disponible.');
    END;

    -- PRUEBA 3: reserva contigua (entra el dia que sale la anterior) -> permitida.
    pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-11-13', DATE '2026-11-15', 1, v_res2);
    DBMS_OUTPUT.PUT_LINE('PRUEBA 3 OK: reserva contigua ' || v_res2 || ' permitida.');

    -- PRUEBA 4A: checkout igual al checkin -> -20202.
    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-12-01', DATE '2026-12-01', 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 4A fallo: no se rechazo checkout = checkin.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20202 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 4A OK: ORA-20202 checkout igual al checkin.');
    END;

    -- PRUEBA 4B: checkout anterior al checkin -> -20202.
    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-12-05', DATE '2026-12-01', 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 4B fallo: no se rechazo checkout < checkin.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20202 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 4B OK: ORA-20202 checkout anterior al checkin.');
    END;

    -- PRUEBA 5: capacidad excedida -> -20203.
    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-12-10', DATE '2026-12-12',
                                     v_capacidad + 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 5 fallo: no se rechazo la capacidad.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20203 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 5 OK: ORA-20203 capacidad excedida.');
    END;

    -- PRUEBA 6A: cliente inexistente -> -20204.
    BEGIN
        pkg_turismo.sp_crear_reserva(-1, v_hab, DATE '2026-12-10', DATE '2026-12-12', 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 6A fallo: no se rechazo el cliente.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20204 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 6A OK: ORA-20204 cliente inexistente.');
    END;

    -- PRUEBA 6B: habitacion inexistente -> -20204.
    BEGIN
        pkg_turismo.sp_crear_reserva(v_cliente, -1, DATE '2026-12-10', DATE '2026-12-12', 1, v_res2);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 6B fallo: no se rechazo la habitacion.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20204 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 6B OK: ORA-20204 habitacion inexistente.');
    END;

    -- Todo se revierte; las pruebas no dejan datos.
    ROLLBACK TO prueba_sp_reserva;

    SELECT COUNT(*) INTO v_cantidad
      FROM reserva_habitacion
     WHERE id_habitacion = v_hab
       AND fecha_checkin >= DATE '2026-11-01';

    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'Quedaron datos de prueba sin revertir.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('Datos de prueba revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_sp_reserva;
        RAISE;
END;
/

-- ============================================================
-- PRUEBAS pkg_turismo.sp_liquidar_mes
-- ============================================================
DECLARE
    v_cliente       cliente.id_cliente%TYPE;
    v_hab           habitacion.id_habitacion%TYPE;
    v_aloj          alojamiento.id_alojamiento%TYPE;
    v_res           reserva.id_reserva%TYPE;
    v_res_canc      reserva.id_reserva%TYPE;
    v_servicio      servicio.id_servicio%TYPE;
    v_precio        servicio.precio_unitario%TYPE;
    v_hab_esperado  NUMBER;
    v_serv_esperado NUMBER;
    v_procesados    NUMBER;
    v_filas         NUMBER;
    v_noches        NUMBER;
    v_ing_hab       NUMBER;
    v_ing_serv      NUMBER;
    v_total         NUMBER;
    v_periodo       DATE := DATE '2026-11-01';
BEGIN
    SAVEPOINT prueba_liquidacion;

    SELECT MIN(id_cliente) INTO v_cliente FROM cliente;
    SELECT MIN(id_habitacion) INTO v_hab FROM habitacion;
    SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = v_hab;

    -- Reserva valida de 3 noches en noviembre 2026.
    pkg_turismo.sp_crear_reserva(v_cliente, v_hab, DATE '2026-11-10', DATE '2026-11-13', 1, v_res);
    v_hab_esperado := fn_valor_estadia(v_hab, DATE '2026-11-10', DATE '2026-11-13');

    -- Un servicio del mismo alojamiento consumido en noviembre.
    SELECT id_servicio, precio_unitario
      INTO v_servicio, v_precio
      FROM servicio
     WHERE id_servicio = (SELECT MIN(id_servicio) FROM servicio WHERE id_alojamiento = v_aloj);

    INSERT INTO reserva_servicio (id_reserva, id_servicio, cantidad, fecha_consumo, subtotal)
    VALUES (v_res, v_servicio, 2, DATE '2026-11-11', 2 * v_precio);
    v_serv_esperado := 2 * v_precio;

    -- Reserva CANCELADA en el mismo mes: NO debe contarse.
    INSERT INTO reserva (id_cliente, estado) VALUES (v_cliente, 'CANCELADA')
    RETURNING id_reserva INTO v_res_canc;
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, subtotal_calculado)
    VALUES (v_res_canc, v_hab, DATE '2026-11-20', DATE '2026-11-23', 999999);

    -- PRUEBA 1: liquidar noviembre 2026; solo ese alojamiento tiene movimiento.
    pkg_turismo.sp_liquidar_mes(2026, 11, v_procesados);

    IF v_procesados != 1 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 1 fallo: alojamientos procesados = ' || v_procesados);
    END IF;

    SELECT noches, ingreso_habitaciones, ingreso_servicios, total
      INTO v_noches, v_ing_hab, v_ing_serv, v_total
      FROM liquidacion_mensual
     WHERE id_alojamiento = v_aloj AND periodo = v_periodo;

    IF v_noches != 3
       OR v_ing_hab != v_hab_esperado
       OR v_ing_serv != v_serv_esperado
       OR v_total != v_hab_esperado + v_serv_esperado THEN
        RAISE_APPLICATION_ERROR(-20990,
            'PRUEBA 1 fallo: noches=' || v_noches || ', hab=' || v_ing_hab ||
            ', serv=' || v_ing_serv || ', total=' || v_total);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 1 OK: noches=' || v_noches || ', hab=' || v_ing_hab ||
                         ', serv=' || v_ing_serv || ', total=' || v_total);
    DBMS_OUTPUT.PUT_LINE('PRUEBA 2 OK: la reserva CANCELADA no se conto.');

    -- PRUEBA 3: re-liquidar el mismo mes no duplica filas.
    pkg_turismo.sp_liquidar_mes(2026, 11, v_procesados);
    SELECT COUNT(*) INTO v_filas FROM liquidacion_mensual WHERE periodo = v_periodo;
    IF v_filas != 1 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 3 fallo: filas = ' || v_filas);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 3 OK: re-liquidar reemplaza, no duplica.');

    -- PRUEBA 4: mes invalido -> -20206.
    BEGIN
        pkg_turismo.sp_liquidar_mes(2026, 13, v_procesados);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 4 fallo: no se rechazo el mes 13.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20206 THEN RAISE; END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 4 OK: ORA-20206 periodo invalido.');
    END;

    -- PRUEBA 5: un mes sin movimiento procesa 0 alojamientos.
    pkg_turismo.sp_liquidar_mes(2027, 6, v_procesados);
    IF v_procesados != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 5 fallo: procesados = ' || v_procesados);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 5 OK: mes sin movimiento procesa 0.');

    ROLLBACK TO prueba_liquidacion;

    SELECT COUNT(*) INTO v_filas FROM liquidacion_mensual WHERE periodo = v_periodo;
    IF v_filas != 0 THEN
        RAISE_APPLICATION_ERROR(-20990, 'Quedaron liquidaciones de prueba sin revertir.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('Datos de prueba revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_liquidacion;
        RAISE;
END;
/

-- ============================================================
-- PRUEBA de la funcion a traves del paquete: ambas columnas deben coincidir
-- ============================================================
SELECT pkg_turismo.valor_estadia(1, DATE '2026-06-10', DATE '2026-06-11') AS por_paquete,
       fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-11')          AS directa
FROM dual;