-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - PRUEBAS DE SEGURIDAD
-- EJECUTAR: Run Script (F5) o SQL*Plus, despues de 09, 10 y 11.
-- El script se conecta como cada usuario de demostracion (CONNECT) y prueba
-- lo que DEBE poder hacer y lo que NO. Cada linea imprime:
--   OK    -> el resultado fue el esperado (permitido o denegado)
--   FALLO -> el rol tiene un privilegio de mas o de menos
-- Todo DML de prueba se revierte con ROLLBACK: no deja datos.
-- Ajuste la cadena de conexion si su base no es localhost:1521/XEPDB1.
-- =============================================================================

DEFINE cadena = localhost:1521/XEPDB1
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

-- =============================================================================
-- 1. RECEPCION: solo vistas
-- =============================================================================
CONNECT usr_recepcion/"Recepcion2026"@&cadena
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_pruebas PLS_INTEGER := 0;
    v_fallos  PLS_INTEGER := 0;
    v_limite  VARCHAR2(40);

    PROCEDURE probar(p_sql VARCHAR2, p_permitido BOOLEAN) IS
        v_n NUMBER;
    BEGIN
        v_pruebas := v_pruebas + 1;
        IF UPPER(p_sql) LIKE 'SELECT%' THEN
            EXECUTE IMMEDIATE p_sql INTO v_n;
        ELSE
            EXECUTE IMMEDIATE p_sql;
            v_n := SQL%ROWCOUNT;
        END IF;
        IF p_permitido THEN
            DBMS_OUTPUT.PUT_LINE('OK    PERMITIDO (' || v_n || ')  ' || p_sql);
        ELSE
            v_fallos := v_fallos + 1;
            DBMS_OUTPUT.PUT_LINE('FALLO DEBIA SER DENEGADO     ' || p_sql);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF p_permitido THEN
                v_fallos := v_fallos + 1;
                DBMS_OUTPUT.PUT_LINE('FALLO ' || SQLERRM || '  ' || p_sql);
            ELSE
                DBMS_OUTPUT.PUT_LINE('OK    DENEGADO ' || RPAD(SUBSTR(SQLERRM, 1, 9), 10) || p_sql);
            END IF;
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ' || USER || ' ===');
    -- DDL primero: Oracle hace COMMIT implicito antes de cualquier DDL (aun si
    -- falla), y eso confirmaria el DML de prueba que viene despues.
    probar('CREATE TABLE tabla_intrusa (x NUMBER)', FALSE);
    -- Si puede usar sus vistas
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_clientes', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_habitaciones', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_reservas', TRUE);
    probar('INSERT INTO turismo_user.v_recepcion_clientes (tipo_identificacion, identificacion, nombre_completo, email) ' ||
           'VALUES (''CC'', ''SEG-PRUEBA-01'', ''Cliente Prueba Seguridad'', ''seg.prueba01@turismouq.test'')', TRUE);
    probar('UPDATE turismo_user.v_recepcion_clientes SET nombre_completo = ''Cliente Prueba Editado'' ' ||
           'WHERE identificacion = ''SEG-PRUEBA-01''', TRUE);
    -- Nunca puede tocar las tablas directamente
    probar('SELECT COUNT(*) FROM turismo_user.cliente', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.reserva', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.reserva_habitacion', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.pago', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.tarifa', FALSE);
    -- Ni hacer en las vistas lo que no se le otorgo
    probar('DELETE FROM turismo_user.v_recepcion_clientes WHERE 1 = 0', FALSE);
    probar('UPDATE turismo_user.v_recepcion_reservas SET estado = ''CANCELADA'' WHERE 1 = 0', FALSE);
    ROLLBACK;

    SELECT limit INTO v_limite FROM user_resource_limits WHERE resource_name = 'SESSIONS_PER_USER';
    DBMS_OUTPUT.PUT_LINE('Perfil aplicado: SESSIONS_PER_USER = ' || v_limite);
    DBMS_OUTPUT.PUT_LINE('RESUMEN ' || USER || ': ' || v_pruebas || ' pruebas, ' || v_fallos || ' fallos');
END;
/

-- =============================================================================
-- 2. ADMINISTRADOR DE ALOJAMIENTO: mantiene oferta, no toca dinero ni clientes
-- =============================================================================
CONNECT usr_admin_alojamiento/"AdminAloj2026"@&cadena
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_pruebas PLS_INTEGER := 0;
    v_fallos  PLS_INTEGER := 0;
    v_limite  VARCHAR2(40);

    PROCEDURE probar(p_sql VARCHAR2, p_permitido BOOLEAN) IS
        v_n NUMBER;
    BEGIN
        v_pruebas := v_pruebas + 1;
        IF UPPER(p_sql) LIKE 'SELECT%' THEN
            EXECUTE IMMEDIATE p_sql INTO v_n;
        ELSE
            EXECUTE IMMEDIATE p_sql;
            v_n := SQL%ROWCOUNT;
        END IF;
        IF p_permitido THEN
            DBMS_OUTPUT.PUT_LINE('OK    PERMITIDO (' || v_n || ')  ' || p_sql);
        ELSE
            v_fallos := v_fallos + 1;
            DBMS_OUTPUT.PUT_LINE('FALLO DEBIA SER DENEGADO     ' || p_sql);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF p_permitido THEN
                v_fallos := v_fallos + 1;
                DBMS_OUTPUT.PUT_LINE('FALLO ' || SQLERRM || '  ' || p_sql);
            ELSE
                DBMS_OUTPUT.PUT_LINE('OK    DENEGADO ' || RPAD(SUBSTR(SQLERRM, 1, 9), 10) || p_sql);
            END IF;
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ' || USER || ' ===');
    probar('SELECT COUNT(*) FROM turismo_user.habitacion', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.tarifa', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.reserva_habitacion', TRUE);
    probar('UPDATE turismo_user.tarifa SET valor_noche = valor_noche ' ||
           'WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM turismo_user.tarifa)', TRUE);
    probar('INSERT INTO turismo_user.servicio (id_alojamiento, nombre, precio_unitario) ' ||
           'SELECT MIN(id_alojamiento), ''Servicio prueba seguridad'', 1000 FROM turismo_user.alojamiento', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.pago', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.cliente', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.auditoria_tarifa', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_clientes', FALSE);
    probar('DELETE FROM turismo_user.habitacion WHERE 1 = 0', FALSE);
    probar('UPDATE turismo_user.reserva_habitacion SET subtotal_calculado = 0 WHERE 1 = 0', FALSE);
    probar('DECLARE n NUMBER; BEGIN turismo_user.pkg_turismo.sp_liquidar_mes(2025, 1, n); END;', FALSE);
    ROLLBACK;

    SELECT limit INTO v_limite FROM user_resource_limits WHERE resource_name = 'SESSIONS_PER_USER';
    DBMS_OUTPUT.PUT_LINE('Perfil aplicado: SESSIONS_PER_USER = ' || v_limite);
    DBMS_OUTPUT.PUT_LINE('RESUMEN ' || USER || ': ' || v_pruebas || ' pruebas, ' || v_fallos || ' fallos');
END;
/

-- =============================================================================
-- 3. GERENTE: lee todo el negocio y ejecuta la liquidacion, sin DML directo
-- =============================================================================
CONNECT usr_gerente/"Gerente2026"@&cadena
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_pruebas PLS_INTEGER := 0;
    v_fallos  PLS_INTEGER := 0;
    v_limite  VARCHAR2(40);

    PROCEDURE probar(p_sql VARCHAR2, p_permitido BOOLEAN) IS
        v_n NUMBER;
    BEGIN
        v_pruebas := v_pruebas + 1;
        IF UPPER(p_sql) LIKE 'SELECT%' THEN
            EXECUTE IMMEDIATE p_sql INTO v_n;
        ELSE
            EXECUTE IMMEDIATE p_sql;
            v_n := SQL%ROWCOUNT;
        END IF;
        IF p_permitido THEN
            DBMS_OUTPUT.PUT_LINE('OK    PERMITIDO (' || v_n || ')  ' || p_sql);
        ELSE
            v_fallos := v_fallos + 1;
            DBMS_OUTPUT.PUT_LINE('FALLO DEBIA SER DENEGADO     ' || p_sql);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF p_permitido THEN
                v_fallos := v_fallos + 1;
                DBMS_OUTPUT.PUT_LINE('FALLO ' || SQLERRM || '  ' || p_sql);
            ELSE
                DBMS_OUTPUT.PUT_LINE('OK    DENEGADO ' || RPAD(SUBSTR(SQLERRM, 1, 9), 10) || p_sql);
            END IF;
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ' || USER || ' ===');
    probar('SELECT COUNT(*) FROM turismo_user.reserva', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.pago', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.cliente', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.liquidacion_mensual', TRUE);
    probar('DECLARE n NUMBER; BEGIN turismo_user.pkg_turismo.sp_liquidar_mes(2025, 1, n); END;', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.auditoria_tarifa', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.usuario_sistema', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_reservas', FALSE);
    probar('UPDATE turismo_user.tarifa SET valor_noche = 0 WHERE 1 = 0', FALSE);
    probar('DELETE FROM turismo_user.pago WHERE 1 = 0', FALSE);
    probar('INSERT INTO turismo_user.liquidacion_mensual (id_alojamiento, periodo, noches, ' ||
           'ingreso_habitaciones, ingreso_servicios, total) VALUES (1, SYSDATE, 0, 0, 0, 0)', FALSE);
    ROLLBACK;

    SELECT limit INTO v_limite FROM user_resource_limits WHERE resource_name = 'SESSIONS_PER_USER';
    DBMS_OUTPUT.PUT_LINE('Perfil aplicado: SESSIONS_PER_USER = ' || v_limite);
    DBMS_OUTPUT.PUT_LINE('RESUMEN ' || USER || ': ' || v_pruebas || ' pruebas, ' || v_fallos || ' fallos');
END;
/

-- =============================================================================
-- 4. AUDITOR: solo lectura de dinero y auditoria
-- =============================================================================
CONNECT usr_auditor/"Auditor2026"@&cadena
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    v_pruebas PLS_INTEGER := 0;
    v_fallos  PLS_INTEGER := 0;
    v_limite  VARCHAR2(40);

    PROCEDURE probar(p_sql VARCHAR2, p_permitido BOOLEAN) IS
        v_n NUMBER;
    BEGIN
        v_pruebas := v_pruebas + 1;
        IF UPPER(p_sql) LIKE 'SELECT%' THEN
            EXECUTE IMMEDIATE p_sql INTO v_n;
        ELSE
            EXECUTE IMMEDIATE p_sql;
            v_n := SQL%ROWCOUNT;
        END IF;
        IF p_permitido THEN
            DBMS_OUTPUT.PUT_LINE('OK    PERMITIDO (' || v_n || ')  ' || p_sql);
        ELSE
            v_fallos := v_fallos + 1;
            DBMS_OUTPUT.PUT_LINE('FALLO DEBIA SER DENEGADO     ' || p_sql);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF p_permitido THEN
                v_fallos := v_fallos + 1;
                DBMS_OUTPUT.PUT_LINE('FALLO ' || SQLERRM || '  ' || p_sql);
            ELSE
                DBMS_OUTPUT.PUT_LINE('OK    DENEGADO ' || RPAD(SUBSTR(SQLERRM, 1, 9), 10) || p_sql);
            END IF;
    END;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== ' || USER || ' ===');
    probar('SELECT COUNT(*) FROM turismo_user.auditoria_tarifa', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.pago', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.tarifa', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.liquidacion_mensual', TRUE);
    probar('SELECT COUNT(*) FROM turismo_user.cliente', FALSE);
    probar('SELECT COUNT(*) FROM turismo_user.v_recepcion_clientes', FALSE);
    probar('UPDATE turismo_user.tarifa SET valor_noche = 0 WHERE 1 = 0', FALSE);
    probar('DELETE FROM turismo_user.auditoria_tarifa WHERE 1 = 0', FALSE);
    probar('DECLARE n NUMBER; BEGIN turismo_user.pkg_turismo.sp_liquidar_mes(2025, 1, n); END;', FALSE);
    ROLLBACK;

    SELECT limit INTO v_limite FROM user_resource_limits WHERE resource_name = 'SESSIONS_PER_USER';
    DBMS_OUTPUT.PUT_LINE('Perfil aplicado: SESSIONS_PER_USER = ' || v_limite);
    DBMS_OUTPUT.PUT_LINE('RESUMEN ' || USER || ': ' || v_pruebas || ' pruebas, ' || v_fallos || ' fallos');
END;
/

DISCONNECT

-- =============================================================================
-- 5. PRUEBAS MANUALES DEL PERFIL (requieren varias conexiones; resultados
--    reales en SUSTENTACION_indices_seguridad.md)
--
-- a) SESSIONS_PER_USER = 2
--    Abra 3 conexiones como USR_AUDITOR. La tercera recibe:
--    ORA-02391: exceeded simultaneous SESSIONS_PER_USER limit
--
-- b) FAILED_LOGIN_ATTEMPTS = 3
--    Intente conectarse 3 veces como USR_AUDITOR con clave incorrecta
--    (ORA-01017). El cuarto intento, incluso con la clave correcta, recibe:
--    ORA-28000: The account is locked.
--    Desbloquear como SYSTEM:  ALTER USER usr_auditor ACCOUNT UNLOCK;
--
-- c) IDLE_TIME = 15
--    Deje una sesion sin actividad mas de 15 minutos; la siguiente sentencia
--    recibe ORA-02396: exceeded maximum idle time, please connect again.
-- =============================================================================
