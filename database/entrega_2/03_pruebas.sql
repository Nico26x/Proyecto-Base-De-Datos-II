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
