-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
-- PRUEBAS: fn_valor_estadia
-- =============================================================================

SET SERVEROUTPUT ON;

-- PRUEBA 1: Estadia dentro de una sola temporada baja.
DECLARE
    v_resultado NUMBER;
BEGIN
    v_resultado := fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-12');
    IF v_resultado != 415507.90 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 1 fallo. Resultado: ' || v_resultado);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 1 OK: ' || TO_CHAR(v_resultado, 'FM9999999990D00'));
END;
/

-- PRUEBA 2: Estadia dentro de una sola temporada especial.
DECLARE
    v_resultado NUMBER;
BEGIN
    v_resultado := fn_valor_estadia(1, DATE '2024-03-25', DATE '2024-03-27');
    IF v_resultado != 244250.24 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 2 fallo. Resultado: ' || v_resultado);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 2 OK: ' || TO_CHAR(v_resultado, 'FM9999999990D00'));
END;
/

-- PRUEBA 3: Estadia que cruza temporada especial y temporada baja.
DECLARE
    v_resultado NUMBER;
BEGIN
    v_resultado := fn_valor_estadia(1, DATE '2024-03-28', DATE '2024-04-03');
    IF v_resultado != 937948.66 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 3 fallo. Resultado: ' || v_resultado);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 3 OK: ' || TO_CHAR(v_resultado, 'FM9999999990D00'));
END;
/

-- PRUEBA 4: Estadia de una sola noche; el checkout no se cobra.
DECLARE
    v_resultado NUMBER;
BEGIN
    v_resultado := fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-11');
    IF v_resultado != 207753.95 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 4 fallo. Resultado: ' || v_resultado);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 4 OK: ' || TO_CHAR(v_resultado, 'FM9999999990D00'));
END;
/

-- PRUEBA 5: Check-in y checkout en el mismo dia.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-10');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 5 fallo: no se genero ORA-20104.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20104 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 5 OK: ORA-20104');
    END;
END;
/

-- PRUEBA 6: Checkout anterior al check-in.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2026-06-12', DATE '2026-06-10');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 6 fallo: no se genero ORA-20104.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20104 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 6 OK: ORA-20104');
    END;
END;
/

-- PRUEBA 7: Habitacion inexistente.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(999999, DATE '2026-06-10', DATE '2026-06-11');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 7 fallo: no se genero ORA-20105.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20105 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 7 OK: ORA-20105');
    END;
END;
/

-- PRUEBA 7A: ID de habitacion nulo.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(NULL, DATE '2026-06-10', DATE '2026-06-11');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 7A fallo: no se genero ORA-20101.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20101 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 7A OK: ORA-20101');
    END;
END;
/

-- PRUEBA 8A: Fecha de entrada nula.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(1, NULL, DATE '2026-06-11');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 8A fallo: no se genero ORA-20102.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20102 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 8A OK: ORA-20102');
    END;
END;
/

-- PRUEBA 8B: Fecha de salida nula.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2026-06-10', NULL);
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 8B fallo: no se genero ORA-20103.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20103 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 8B OK: ORA-20103');
    END;
END;
/

-- PRUEBA 9: Tarifa inexistente; el DELETE se revierte siempre.
DECLARE
    v_resultado NUMBER;
    v_codigo    NUMBER := 0;
BEGIN
    SAVEPOINT prueba_tarifa_inexistente;
    DELETE FROM tarifa
     WHERE id_habitacion = 1
       AND id_temporada = 6;

    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-11');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
    END;

    ROLLBACK TO prueba_tarifa_inexistente;

    IF v_codigo != -20108 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 9 fallo. Codigo: ' || v_codigo);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 9 OK: ORA-20108; datos revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_tarifa_inexistente;
        RAISE;
END;
/

-- PRUEBA 10: Temporada ambigua; el INSERT se revierte siempre.
DECLARE
    v_resultado NUMBER;
    v_codigo    NUMBER := 0;
BEGIN
    SAVEPOINT prueba_temporada_ambigua;
    INSERT INTO temporada (nombre, fecha_inicio, fecha_fin)
    VALUES ('Especial Temporal Prueba', DATE '2024-03-25', DATE '2024-03-25');

    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2024-03-25', DATE '2024-03-26');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
    END;

    ROLLBACK TO prueba_temporada_ambigua;

    IF v_codigo != -20107 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 10 fallo. Codigo: ' || v_codigo);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 10 OK: ORA-20107; datos revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_temporada_ambigua;
        RAISE;
END;
/

-- PRUEBA 11: Noche fuera de todas las temporadas actuales.
DECLARE
    v_resultado NUMBER;
BEGIN
    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2027-01-01', DATE '2027-01-02');
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 11 fallo: no se genero ORA-20106.');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -20106 THEN
                RAISE;
            END IF;
            DBMS_OUTPUT.PUT_LINE('PRUEBA 11 OK: ORA-20106');
    END;
END;
/

-- PRUEBA 12: Tarifa duplicada; el INSERT se revierte siempre.
DECLARE
    v_resultado NUMBER;
    v_codigo    NUMBER := 0;
BEGIN
    SAVEPOINT prueba_tarifa_duplicada;
    INSERT INTO tarifa (id_habitacion, id_temporada, valor_noche)
    SELECT id_habitacion, id_temporada, valor_noche
      FROM tarifa
     WHERE id_habitacion = 1
       AND id_temporada = 6;

    BEGIN
        v_resultado := fn_valor_estadia(1, DATE '2026-06-10', DATE '2026-06-11');
    EXCEPTION
        WHEN OTHERS THEN
            v_codigo := SQLCODE;
    END;

    ROLLBACK TO prueba_tarifa_duplicada;

    IF v_codigo != -20109 THEN
        RAISE_APPLICATION_ERROR(-20990, 'PRUEBA 12 fallo. Codigo: ' || v_codigo);
    END IF;
    DBMS_OUTPUT.PUT_LINE('PRUEBA 12 OK: ORA-20109; datos revertidos.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_tarifa_duplicada;
        RAISE;
END;
/

-- VALIDACION INDEPENDIENTE PRUEBA 3: Detalle por noche sin usar la funcion.
WITH Noches AS (
    SELECT DATE '2024-03-28' + LEVEL - 1 AS fecha_noche
    FROM dual
    CONNECT BY LEVEL <= DATE '2024-04-03' - DATE '2024-03-28'
),
Candidatas AS (
    SELECT n.fecha_noche,
           t.id_temporada,
           t.nombre AS temporada,
           CASE
               WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2
               ELSE 1
           END AS prioridad
    FROM Noches n
    JOIN temporada t
      ON n.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
),
Priorizadas AS (
    SELECT c.*,
           MIN(prioridad) OVER (PARTITION BY fecha_noche) AS prioridad_minima
    FROM Candidatas c
)
SELECT p.fecha_noche,
       p.temporada,
       p.prioridad,
       ta.valor_noche
FROM Priorizadas p
JOIN tarifa ta
  ON ta.id_habitacion = 1
 AND ta.id_temporada = p.id_temporada
WHERE p.prioridad = p.prioridad_minima
ORDER BY p.fecha_noche;

-- COMPARACION INDEPENDIENTE PRUEBA 3: Ambos valores deben ser 937948.66.
WITH Noches AS (
    SELECT DATE '2024-03-28' + LEVEL - 1 AS fecha_noche
    FROM dual
    CONNECT BY LEVEL <= DATE '2024-04-03' - DATE '2024-03-28'
),
Candidatas AS (
    SELECT n.fecha_noche,
           t.id_temporada,
           CASE
               WHEN UPPER(t.nombre) LIKE 'TEMPORADA BAJA%' THEN 2
               ELSE 1
           END AS prioridad
    FROM Noches n
    JOIN temporada t
      ON n.fecha_noche BETWEEN TRUNC(t.fecha_inicio) AND TRUNC(t.fecha_fin)
),
Priorizadas AS (
    SELECT c.*,
           MIN(prioridad) OVER (PARTITION BY fecha_noche) AS prioridad_minima
    FROM Candidatas c
),
TotalSQL AS (
    SELECT SUM(ta.valor_noche) AS total_sql
    FROM Priorizadas p
    JOIN tarifa ta
      ON ta.id_habitacion = 1
     AND ta.id_temporada = p.id_temporada
    WHERE p.prioridad = p.prioridad_minima
)
SELECT total_sql,
       fn_valor_estadia(1, DATE '2024-03-28', DATE '2024-04-03') AS total_funcion,
       total_sql - fn_valor_estadia(
           1,
           DATE '2024-03-28',
           DATE '2024-04-03'
       ) AS diferencia
FROM TotalSQL;

-- ============================================================
-- PRUEBAS TRIGGER AUDITORIA TARIFA
-- ============================================================

-- PRUEBA A: UPDATE de una tarifa y rollback de dato y auditoria.
DECLARE
    v_id_tarifa       tarifa.id_tarifa%TYPE;
    v_id_habitacion   tarifa.id_habitacion%TYPE;
    v_id_temporada    tarifa.id_temporada%TYPE;
    v_valor_anterior  tarifa.valor_noche%TYPE;
    v_valor_actual    tarifa.valor_noche%TYPE;
    v_operacion       auditoria_tarifa.operacion%TYPE;
    v_usuario_bd      auditoria_tarifa.usuario_bd%TYPE;
    v_fecha_cambio    auditoria_tarifa.fecha_cambio%TYPE;
    v_audit_habitacion auditoria_tarifa.id_habitacion%TYPE;
    v_audit_temporada  auditoria_tarifa.id_temporada%TYPE;
    v_audit_anterior   auditoria_tarifa.valor_anterior%TYPE;
    v_audit_nuevo      auditoria_tarifa.valor_nuevo%TYPE;
    v_auditorias_antes NUMBER;
    v_auditorias_final NUMBER;
BEGIN
    SAVEPOINT prueba_a_update;

    SELECT id_tarifa, id_habitacion, id_temporada, valor_noche
      INTO v_id_tarifa, v_id_habitacion, v_id_temporada, v_valor_anterior
      FROM tarifa
     WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM tarifa);

    SELECT COUNT(*)
      INTO v_auditorias_antes
      FROM auditoria_tarifa
     WHERE id_tarifa = v_id_tarifa;

    UPDATE tarifa
       SET valor_noche = v_valor_anterior + 100
     WHERE id_tarifa = v_id_tarifa;

    SELECT operacion, usuario_bd, fecha_cambio, id_habitacion,
           id_temporada, valor_anterior, valor_nuevo
      INTO v_operacion, v_usuario_bd, v_fecha_cambio, v_audit_habitacion,
           v_audit_temporada, v_audit_anterior, v_audit_nuevo
      FROM auditoria_tarifa
     WHERE id_auditoria = (
               SELECT MAX(id_auditoria)
                 FROM auditoria_tarifa
                WHERE id_tarifa = v_id_tarifa
           );

    IF v_operacion != 'UPDATE'
       OR v_usuario_bd != SYS_CONTEXT('USERENV', 'SESSION_USER')
       OR v_fecha_cambio IS NULL
       OR v_audit_habitacion != v_id_habitacion
       OR v_audit_temporada != v_id_temporada
       OR v_audit_anterior != v_valor_anterior
       OR v_audit_nuevo != v_valor_anterior + 100 THEN
        RAISE_APPLICATION_ERROR(-20980, 'PRUEBA A fallo: auditoria UPDATE incorrecta.');
    END IF;

    ROLLBACK TO prueba_a_update;

    SELECT valor_noche
      INTO v_valor_actual
      FROM tarifa
     WHERE id_tarifa = v_id_tarifa;

    SELECT COUNT(*)
      INTO v_auditorias_final
      FROM auditoria_tarifa
     WHERE id_tarifa = v_id_tarifa;

    IF v_valor_actual != v_valor_anterior
       OR v_auditorias_final != v_auditorias_antes THEN
        RAISE_APPLICATION_ERROR(-20980, 'PRUEBA A fallo: rollback incompleto.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('PRUEBA A OK: UPDATE auditado y revertido.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_a_update;
        RAISE;
END;
/

-- PRUEBA B: INSERT temporal y rollback de tarifa y auditoria.
DECLARE
    v_id_habitacion tarifa.id_habitacion%TYPE;
    v_id_temporada  tarifa.id_temporada%TYPE;
    v_operacion     auditoria_tarifa.operacion%TYPE;
    v_valor_anterior auditoria_tarifa.valor_anterior%TYPE;
    v_valor_nuevo    auditoria_tarifa.valor_nuevo%TYPE;
    v_cantidad       NUMBER;
BEGIN
    SAVEPOINT prueba_b_insert;

    SELECT id_habitacion, id_temporada
      INTO v_id_habitacion, v_id_temporada
      FROM tarifa
     WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM tarifa);

    SELECT COUNT(*)
      INTO v_cantidad
      FROM tarifa
     WHERE id_tarifa = -910001;

    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20981, 'PRUEBA B requiere libre el ID -910001.');
    END IF;

    INSERT INTO tarifa (id_tarifa, id_habitacion, id_temporada, valor_noche)
    VALUES (-910001, v_id_habitacion, v_id_temporada, 123456.78);

    SELECT operacion, valor_anterior, valor_nuevo
      INTO v_operacion, v_valor_anterior, v_valor_nuevo
      FROM auditoria_tarifa
     WHERE id_auditoria = (
               SELECT MAX(id_auditoria)
                 FROM auditoria_tarifa
                WHERE id_tarifa = -910001
           );

    IF v_operacion != 'INSERT'
       OR v_valor_anterior IS NOT NULL
       OR v_valor_nuevo != 123456.78 THEN
        RAISE_APPLICATION_ERROR(-20981, 'PRUEBA B fallo: auditoria INSERT incorrecta.');
    END IF;

    ROLLBACK TO prueba_b_insert;

    SELECT (SELECT COUNT(*) FROM tarifa WHERE id_tarifa = -910001)
         + (SELECT COUNT(*) FROM auditoria_tarifa WHERE id_tarifa = -910001)
      INTO v_cantidad
      FROM dual;

    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20981, 'PRUEBA B fallo: quedaron datos temporales.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('PRUEBA B OK: INSERT auditado y revertido.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_b_insert;
        RAISE;
END;
/

-- PRUEBA C: DELETE temporal y rollback de todos sus cambios.
DECLARE
    v_id_habitacion  tarifa.id_habitacion%TYPE;
    v_id_temporada   tarifa.id_temporada%TYPE;
    v_operacion      auditoria_tarifa.operacion%TYPE;
    v_valor_anterior auditoria_tarifa.valor_anterior%TYPE;
    v_valor_nuevo    auditoria_tarifa.valor_nuevo%TYPE;
    v_cantidad       NUMBER;
BEGIN
    SAVEPOINT prueba_c_delete;

    SELECT id_habitacion, id_temporada
      INTO v_id_habitacion, v_id_temporada
      FROM tarifa
     WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM tarifa);

    SELECT COUNT(*)
      INTO v_cantidad
      FROM tarifa
     WHERE id_tarifa = -910002;

    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20982, 'PRUEBA C requiere libre el ID -910002.');
    END IF;

    INSERT INTO tarifa (id_tarifa, id_habitacion, id_temporada, valor_noche)
    VALUES (-910002, v_id_habitacion, v_id_temporada, 234567.89);

    DELETE FROM tarifa
     WHERE id_tarifa = -910002;

    SELECT operacion, valor_anterior, valor_nuevo
      INTO v_operacion, v_valor_anterior, v_valor_nuevo
      FROM auditoria_tarifa
     WHERE id_auditoria = (
               SELECT MAX(id_auditoria)
                 FROM auditoria_tarifa
                WHERE id_tarifa = -910002
           );

    IF v_operacion != 'DELETE'
       OR v_valor_anterior != 234567.89
       OR v_valor_nuevo IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20982, 'PRUEBA C fallo: auditoria DELETE incorrecta.');
    END IF;

    ROLLBACK TO prueba_c_delete;

    SELECT (SELECT COUNT(*) FROM tarifa WHERE id_tarifa = -910002)
         + (SELECT COUNT(*) FROM auditoria_tarifa WHERE id_tarifa = -910002)
      INTO v_cantidad
      FROM dual;

    IF v_cantidad != 0 THEN
        RAISE_APPLICATION_ERROR(-20982, 'PRUEBA C fallo: quedaron datos temporales.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('PRUEBA C OK: DELETE auditado y revertido.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_c_delete;
        RAISE;
END;
/

-- PRUEBA D: un UPDATE modifica tres tarifas y genera tres auditorias.
DECLARE
    v_desde             TIMESTAMP(6) WITH TIME ZONE;
    v_cantidad_tarifas  NUMBER;
    v_cantidad_auditoria NUMBER;
    v_usuarios          NUMBER;
    v_fechas            NUMBER;
    v_valores_correctos NUMBER;
    v_suma_anterior     NUMBER;
    v_suma_final        NUMBER;
BEGIN
    SAVEPOINT prueba_d_update_multiple;

    SELECT COUNT(*), SUM(valor_noche)
      INTO v_cantidad_tarifas, v_suma_anterior
      FROM tarifa
     WHERE id_temporada = 1
       AND id_habitacion BETWEEN 1 AND 3;

    IF v_cantidad_tarifas != 3 THEN
        RAISE_APPLICATION_ERROR(-20983, 'PRUEBA D requiere tres tarifas controladas.');
    END IF;

    v_desde := SYSTIMESTAMP;

    UPDATE tarifa
       SET valor_noche = valor_noche + 10
     WHERE id_temporada = 1
       AND id_habitacion BETWEEN 1 AND 3;

    SELECT COUNT(*),
           COUNT(DISTINCT usuario_bd),
           COUNT(DISTINCT fecha_cambio),
           SUM(CASE WHEN valor_nuevo = valor_anterior + 10 THEN 1 ELSE 0 END)
      INTO v_cantidad_auditoria, v_usuarios, v_fechas, v_valores_correctos
      FROM auditoria_tarifa
     WHERE operacion = 'UPDATE'
       AND id_temporada = 1
       AND id_habitacion BETWEEN 1 AND 3
       AND fecha_cambio >= v_desde;

    IF v_cantidad_auditoria != 3
       OR v_usuarios != 1
       OR v_fechas != 1
       OR v_valores_correctos != 3 THEN
        RAISE_APPLICATION_ERROR(-20983, 'PRUEBA D fallo: auditoria multiple incorrecta.');
    END IF;

    FOR r IN (
        SELECT id_tarifa, valor_anterior, valor_nuevo,
               usuario_bd, fecha_cambio
          FROM auditoria_tarifa
         WHERE operacion = 'UPDATE'
           AND id_temporada = 1
           AND id_habitacion BETWEEN 1 AND 3
           AND fecha_cambio >= v_desde
         ORDER BY id_tarifa
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            '  Evidencia D: tarifa=' || r.id_tarifa
            || ', anterior=' || TO_CHAR(r.valor_anterior, 'FM9999999990D00')
            || ', nuevo=' || TO_CHAR(r.valor_nuevo, 'FM9999999990D00')
            || ', usuario=' || r.usuario_bd
            || ', fecha=' || TO_CHAR(r.fecha_cambio, 'YYYY-MM-DD HH24:MI:SS.FF6 TZH:TZM')
        );
    END LOOP;

    ROLLBACK TO prueba_d_update_multiple;

    SELECT SUM(valor_noche)
      INTO v_suma_final
      FROM tarifa
     WHERE id_temporada = 1
       AND id_habitacion BETWEEN 1 AND 3;

    SELECT COUNT(*)
      INTO v_cantidad_auditoria
      FROM auditoria_tarifa
     WHERE operacion = 'UPDATE'
       AND id_temporada = 1
       AND id_habitacion BETWEEN 1 AND 3
       AND fecha_cambio >= v_desde;

    IF v_suma_final != v_suma_anterior OR v_cantidad_auditoria != 0 THEN
        RAISE_APPLICATION_ERROR(-20983, 'PRUEBA D fallo: rollback incompleto.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('PRUEBA D OK: tres auditorias con usuario y timestamp comunes; rollback correcto.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_d_update_multiple;
        RAISE;
END;
/

-- PRUEBA E: la auditoria participa en la transaccion y desaparece al revertir.
DECLARE
    v_id_tarifa       tarifa.id_tarifa%TYPE;
    v_valor_anterior  tarifa.valor_noche%TYPE;
    v_auditorias_antes NUMBER;
    v_auditorias_durante NUMBER;
    v_auditorias_final NUMBER;
BEGIN
    SAVEPOINT prueba_e_rollback;

    SELECT id_tarifa, valor_noche
      INTO v_id_tarifa, v_valor_anterior
      FROM tarifa
     WHERE id_tarifa = (SELECT MIN(id_tarifa) FROM tarifa);

    SELECT COUNT(*)
      INTO v_auditorias_antes
      FROM auditoria_tarifa
     WHERE id_tarifa = v_id_tarifa;

    UPDATE tarifa
       SET valor_noche = valor_noche + 1
     WHERE id_tarifa = v_id_tarifa;

    SELECT COUNT(*)
      INTO v_auditorias_durante
      FROM auditoria_tarifa
     WHERE id_tarifa = v_id_tarifa;

    IF v_auditorias_durante != v_auditorias_antes + 1 THEN
        RAISE_APPLICATION_ERROR(-20984, 'PRUEBA E fallo: auditoria no visible en la transaccion.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        '  Evidencia E: auditorias antes=' || v_auditorias_antes
        || ', durante=' || v_auditorias_durante
    );

    ROLLBACK TO prueba_e_rollback;

    SELECT COUNT(*)
      INTO v_auditorias_final
      FROM auditoria_tarifa
     WHERE id_tarifa = v_id_tarifa;

    IF v_auditorias_final != v_auditorias_antes THEN
        RAISE_APPLICATION_ERROR(-20984, 'PRUEBA E fallo: auditoria sobrevivio al rollback.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'PRUEBA E OK: auditorias despues del rollback=' || v_auditorias_final
    );
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_e_rollback;
        RAISE;
END;
/

-- VALIDACIONES FINALES: las pruebas temporales no dejan datos permanentes.
SELECT COUNT(*) AS total_tarifas_final
  FROM tarifa;

SELECT COUNT(*) AS tarifas_artificiales_final
  FROM tarifa
 WHERE id_tarifa IN (-910001, -910002);

SELECT COUNT(*) AS auditorias_artificiales_final
  FROM auditoria_tarifa
 WHERE id_tarifa IN (-910001, -910002);

SELECT COUNT(*) AS total_auditorias_final
  FROM auditoria_tarifa;

SELECT object_name, status
  FROM user_objects
 WHERE object_name = 'FN_VALOR_ESTADIA';
