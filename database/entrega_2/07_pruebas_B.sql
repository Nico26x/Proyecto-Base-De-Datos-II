
   -- =============================================================================
   -- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
   -- PRUEBAS: trigger de solapamiento, sp_crear_reserva y liquidacion mensual (B)
   -- =============================================================================
   SET SERVEROUTPUT ON;

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

    SELECT MIN(id_cliente)   INTO v_cliente FROM cliente;
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