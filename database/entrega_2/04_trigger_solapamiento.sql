-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
-- TRIGGER: trg_solapamiento_reserva_hab
-- DESCRIPCION: Impide que una habitacion tenga dos estadias que se crucen.
-- REGLA: intervalo [check-in, check-out). Una estadia que sale el dia X y otra
--        que entra el dia X NO se cruzan. Las reservas CANCELADA no ocupan.
-- NOTA: Un trigger de fila simple no puede consultar su propia tabla (ORA-04091,
--       tabla mutante). Por eso se usa un COMPOUND TRIGGER: se guardan las filas
--       en AFTER EACH ROW y se valida en AFTER STATEMENT, donde la tabla ya no
--       esta mutando.
-- =============================================================================

CREATE OR REPLACE TRIGGER trg_solapamiento_reserva_hab
FOR INSERT OR UPDATE OF id_habitacion, fecha_checkin, fecha_checkout, id_reserva
ON reserva_habitacion
COMPOUND TRIGGER

    TYPE t_estadia IS RECORD (
        id_reserva_habitacion reserva_habitacion.id_reserva_habitacion%TYPE,
        id_reserva            reserva_habitacion.id_reserva%TYPE,
        id_habitacion         reserva_habitacion.id_habitacion%TYPE,
        fecha_checkin         reserva_habitacion.fecha_checkin%TYPE,
        fecha_checkout        reserva_habitacion.fecha_checkout%TYPE
    );

    TYPE t_estadias IS TABLE OF t_estadia INDEX BY PLS_INTEGER;

    g_estadias  t_estadias;
    g_indice    PLS_INTEGER;

    BEFORE STATEMENT IS
    BEGIN
        g_indice := 0;
        g_estadias.DELETE;
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        g_indice := g_indice + 1;
        g_estadias(g_indice).id_reserva_habitacion := :NEW.id_reserva_habitacion;
        g_estadias(g_indice).id_reserva            := :NEW.id_reserva;
        g_estadias(g_indice).id_habitacion         := :NEW.id_habitacion;
        g_estadias(g_indice).fecha_checkin         := :NEW.fecha_checkin;
        g_estadias(g_indice).fecha_checkout        := :NEW.fecha_checkout;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_conflictos PLS_INTEGER;
    BEGIN
        FOR i IN 1 .. g_indice LOOP
            SELECT COUNT(*)
              INTO v_conflictos
              FROM reserva_habitacion rh
              JOIN reserva r
                ON r.id_reserva = rh.id_reserva
             WHERE rh.id_habitacion = g_estadias(i).id_habitacion
               AND rh.id_reserva_habitacion <> g_estadias(i).id_reserva_habitacion
               AND r.estado <> 'CANCELADA'
               AND TRUNC(rh.fecha_checkin)  < TRUNC(g_estadias(i).fecha_checkout)
               AND TRUNC(rh.fecha_checkout) > TRUNC(g_estadias(i).fecha_checkin)
               -- Si la propia reserva esta cancelada, no ocupa la habitacion.
               AND EXISTS (
                   SELECT 1
                     FROM reserva rp
                    WHERE rp.id_reserva = g_estadias(i).id_reserva
                      AND rp.estado <> 'CANCELADA'
               );

            IF v_conflictos > 0 THEN
                RAISE_APPLICATION_ERROR(
                    -20205,
                    'La habitacion ' || g_estadias(i).id_habitacion ||
                    ' ya tiene una reserva que se cruza con el periodo ' ||
                    TO_CHAR(g_estadias(i).fecha_checkin, 'YYYY-MM-DD') || ' a ' ||
                    TO_CHAR(g_estadias(i).fecha_checkout, 'YYYY-MM-DD') || '.'
                );
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_solapamiento_reserva_hab;
/

SHOW ERRORS TRIGGER trg_solapamiento_reserva_hab;


