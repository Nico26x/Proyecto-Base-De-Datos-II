-- =============================================================================
-- TURISMOUQ - ENTREGA 3
-- Reserva serializada por habitacion mediante SELECT FOR UPDATE.
-- La transaccion pertenece al llamador: este procedimiento no confirma ni
-- revierte y el bloqueo se conserva hasta COMMIT o ROLLBACK.
-- PRERREQUISITO: PKG_TURISMO de Entrega 2 debe estar VALID.
-- Ejecute este DDL en una sesion sin trabajo pendiente: Oracle hace commit
-- implicito antes y despues de CREATE OR REPLACE.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_crear_reserva_bloqueada(
    p_id_cliente     IN  cliente.id_cliente%TYPE,
    p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
    p_fecha_in       IN  DATE,
    p_fecha_out      IN  DATE,
    p_num_huespedes  IN  NUMBER,
    p_id_reserva     OUT reserva.id_reserva%TYPE
)
IS
    v_id_habitacion habitacion.id_habitacion%TYPE;
BEGIN
    BEGIN
        SELECT id_habitacion
          INTO v_id_habitacion
          FROM habitacion
         WHERE id_habitacion = p_id_habitacion
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20311,
                'La habitacion ' || NVL(TO_CHAR(p_id_habitacion), 'NULL') ||
                ' no existe y no puede bloquearse.'
            );
    END;

    pkg_turismo.sp_crear_reserva(
        p_id_cliente    => p_id_cliente,
        p_id_habitacion => p_id_habitacion,
        p_fecha_in      => p_fecha_in,
        p_fecha_out     => p_fecha_out,
        p_num_huespedes => p_num_huespedes,
        p_id_reserva    => p_id_reserva
    );
END sp_crear_reserva_bloqueada;
/

SHOW ERRORS PROCEDURE sp_crear_reserva_bloqueada

SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'SP_CREAR_RESERVA_BLOQUEADA';

SELECT name, type, line, position, text
  FROM user_errors
 WHERE name = 'SP_CREAR_RESERVA_BLOQUEADA'
 ORDER BY sequence;
