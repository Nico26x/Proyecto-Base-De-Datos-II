-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ - Entrega 2
-- FUNCION: fn_valor_estadia
-- DESCRIPCION: Calcula el valor de una estadia noche por noche segun temporada.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_valor_estadia(
    p_id_habitacion IN NUMBER,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
) RETURN NUMBER
IS
    v_fecha_in               DATE;
    v_fecha_out              DATE;
    v_fecha_noche            DATE;
    v_cantidad_noches        PLS_INTEGER;
    v_total                  NUMBER := 0;
    v_habitacion_existe      PLS_INTEGER;
    v_temporadas_aplicables  PLS_INTEGER;
    v_prioridad_minima       PLS_INTEGER;
    v_temporadas_prioritarias PLS_INTEGER;
    v_id_temporada           temporada.id_temporada%TYPE;
    v_cantidad_tarifas       PLS_INTEGER;
    v_valor_noche            tarifa.valor_noche%TYPE;
BEGIN
    IF p_id_habitacion IS NULL THEN
        RAISE_APPLICATION_ERROR(-20101, 'El ID de la habitacion no puede ser nulo.');
    END IF;

    IF p_fecha_in IS NULL THEN
        RAISE_APPLICATION_ERROR(-20102, 'La fecha de entrada no puede ser nula.');
    END IF;

    IF p_fecha_out IS NULL THEN
        RAISE_APPLICATION_ERROR(-20103, 'La fecha de salida no puede ser nula.');
    END IF;

    v_fecha_in := TRUNC(p_fecha_in);
    v_fecha_out := TRUNC(p_fecha_out);

    IF v_fecha_out <= v_fecha_in THEN
        RAISE_APPLICATION_ERROR(
            -20104,
            'La fecha de salida debe ser posterior a la fecha de entrada.'
        );
    END IF;

    SELECT COUNT(*)
      INTO v_habitacion_existe
      FROM habitacion
     WHERE id_habitacion = p_id_habitacion;

    IF v_habitacion_existe = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20105,
            'La habitacion ' || p_id_habitacion || ' no existe.'
        );
    END IF;

    v_cantidad_noches := v_fecha_out - v_fecha_in;

    FOR i IN 0 .. v_cantidad_noches - 1 LOOP
        v_fecha_noche := v_fecha_in + i;

        SELECT COUNT(*),
               MIN(
                   CASE
                       WHEN UPPER(nombre) LIKE 'TEMPORADA BAJA%' THEN 2
                       ELSE 1
                   END
               )
          INTO v_temporadas_aplicables,
               v_prioridad_minima
          FROM temporada
         WHERE v_fecha_noche BETWEEN TRUNC(fecha_inicio) AND TRUNC(fecha_fin);

        IF v_temporadas_aplicables = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20106,
                'La noche ' || TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') ||
                ' no pertenece a ninguna temporada.'
            );
        END IF;

        SELECT COUNT(*)
          INTO v_temporadas_prioritarias
          FROM temporada
         WHERE v_fecha_noche BETWEEN TRUNC(fecha_inicio) AND TRUNC(fecha_fin)
           AND CASE
                   WHEN UPPER(nombre) LIKE 'TEMPORADA BAJA%' THEN 2
                   ELSE 1
               END = v_prioridad_minima;

        IF v_temporadas_prioritarias > 1 THEN
            RAISE_APPLICATION_ERROR(
                -20107,
                'La noche ' || TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') ||
                ' tiene varias temporadas con prioridad ' || v_prioridad_minima || '.'
            );
        END IF;

        SELECT id_temporada
          INTO v_id_temporada
          FROM temporada
         WHERE v_fecha_noche BETWEEN TRUNC(fecha_inicio) AND TRUNC(fecha_fin)
           AND CASE
                   WHEN UPPER(nombre) LIKE 'TEMPORADA BAJA%' THEN 2
                   ELSE 1
               END = v_prioridad_minima;

        SELECT COUNT(*)
          INTO v_cantidad_tarifas
          FROM tarifa
         WHERE id_habitacion = p_id_habitacion
           AND id_temporada = v_id_temporada;

        IF v_cantidad_tarifas = 0 THEN
            RAISE_APPLICATION_ERROR(
                -20108,
                'La habitacion ' || p_id_habitacion ||
                ' no tiene tarifa para la temporada ' || v_id_temporada ||
                ' en la noche ' || TO_CHAR(v_fecha_noche, 'YYYY-MM-DD') || '.'
            );
        END IF;

        IF v_cantidad_tarifas > 1 THEN
            RAISE_APPLICATION_ERROR(
                -20109,
                'La habitacion ' || p_id_habitacion ||
                ' tiene varias tarifas para la temporada ' || v_id_temporada || '.'
            );
        END IF;

        SELECT valor_noche
          INTO v_valor_noche
          FROM tarifa
         WHERE id_habitacion = p_id_habitacion
           AND id_temporada = v_id_temporada;

        v_total := v_total + v_valor_noche;
    END LOOP;

    RETURN v_total;
END fn_valor_estadia;
/

SHOW ERRORS FUNCTION fn_valor_estadia;
