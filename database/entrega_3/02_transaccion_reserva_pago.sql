-- =============================================================================
-- TURISMOUQ - ENTREGA 3
-- Creacion atomica de reserva y pago.
-- El SAVEPOINT protege solamente esta unidad de trabajo y conserva cualquier
-- operacion previa del llamador. No se hace COMMIT dentro del procedimiento.
-- PRERREQUISITO: ejecutar primero 01_reserva_con_bloqueo.sql.
-- Ejecute este DDL en una sesion sin trabajo pendiente: Oracle hace commit
-- implicito antes y despues de CREATE OR REPLACE.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_crear_reserva_pago(
    p_id_cliente     IN  cliente.id_cliente%TYPE,
    p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
    p_fecha_in       IN  DATE,
    p_fecha_out      IN  DATE,
    p_num_huespedes  IN  NUMBER,
    p_metodo_pago    IN  pago.metodo%TYPE,
    p_monto_pago     IN  pago.monto%TYPE DEFAULT NULL,
    p_id_reserva     OUT reserva.id_reserva%TYPE,
    p_id_pago        OUT pago.id_pago%TYPE
)
IS
    v_subtotal   reserva_habitacion.subtotal_calculado%TYPE;
    v_monto_real pago.monto%TYPE;
BEGIN
    p_id_reserva := NULL;
    p_id_pago    := NULL;

    IF p_metodo_pago IS NULL OR TRIM(p_metodo_pago) IS NULL THEN
        RAISE_APPLICATION_ERROR(-20301, 'El metodo de pago es obligatorio.');
    END IF;

    IF p_monto_pago IS NOT NULL AND p_monto_pago <= 0 THEN
        RAISE_APPLICATION_ERROR(-20302, 'El monto del pago debe ser mayor que cero.');
    END IF;

    SAVEPOINT e3_inicio_reserva_pago;

    BEGIN
        sp_crear_reserva_bloqueada(
            p_id_cliente    => p_id_cliente,
            p_id_habitacion => p_id_habitacion,
            p_fecha_in      => p_fecha_in,
            p_fecha_out     => p_fecha_out,
            p_num_huespedes => p_num_huespedes,
            p_id_reserva    => p_id_reserva
        );

        SELECT subtotal_calculado
          INTO v_subtotal
          FROM reserva_habitacion
         WHERE id_reserva = p_id_reserva;

        v_monto_real := NVL(p_monto_pago, v_subtotal);

        INSERT INTO pago (id_reserva, monto, metodo)
        VALUES (p_id_reserva, v_monto_real, p_metodo_pago)
        RETURNING id_pago INTO p_id_pago;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO e3_inicio_reserva_pago;
            p_id_reserva := NULL;
            p_id_pago    := NULL;
            RAISE;
    END;
END sp_crear_reserva_pago;
/

SHOW ERRORS PROCEDURE sp_crear_reserva_pago

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN (
           'SP_CREAR_RESERVA_BLOQUEADA',
           'SP_CREAR_RESERVA_PAGO'
       )
 ORDER BY object_name;

SELECT name, type, line, position, text
  FROM user_errors
 WHERE name IN (
           'SP_CREAR_RESERVA_BLOQUEADA',
           'SP_CREAR_RESERVA_PAGO'
       )
 ORDER BY name, sequence;
