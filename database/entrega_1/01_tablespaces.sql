-- =============================================================================
-- PROYECTO INTEGRADOR: TurismoUQ
-- ARCHIVO: 01_tablespaces.sql
-- DESCRIPCION: Creacion idempotente del tablespace historico de reservas.
-- REQUISITO: Ejecutar en XEPDB1 con una cuenta administrativa.
-- =============================================================================

DECLARE
    v_tablespace_existe NUMBER;
    v_omf_destino       VARCHAR2(4000);
    v_users_datafile    VARCHAR2(4000);
    v_nuevo_datafile    VARCHAR2(4000);
    v_pos_separador     PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_tablespace_existe
      FROM dba_tablespaces
     WHERE tablespace_name = 'TS_HISTORICO_RESERVAS';

    IF v_tablespace_existe = 0 THEN
        SELECT value
          INTO v_omf_destino
          FROM v$parameter
         WHERE name = 'db_create_file_dest';

        IF v_omf_destino IS NOT NULL THEN
            -- Al omitir el nombre fisico, Oracle Managed Files crea y ubica el datafile.
            EXECUTE IMMEDIATE '
                CREATE TABLESPACE ts_historico_reservas
                DATAFILE SIZE 100M
                AUTOEXTEND ON
                NEXT 10M
                MAXSIZE 1G';
        ELSE
            BEGIN
                SELECT file_name
                  INTO v_users_datafile
                  FROM (
                      SELECT file_name
                        FROM dba_data_files
                       WHERE tablespace_name = 'USERS'
                       ORDER BY file_id
                  )
                 WHERE ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(
                        -20001,
                        'No se encontro un datafile del tablespace USERS para determinar la ubicacion del nuevo datafile.'
                    );
            END;

            -- Se admite tanto el separador de Windows como el de Linux/Unix.
            v_pos_separador := GREATEST(
                INSTR(v_users_datafile, '/', -1),
                INSTR(v_users_datafile, '\', -1)
            );

            IF v_pos_separador = 0 THEN
                RAISE_APPLICATION_ERROR(
                    -20002,
                    'No se pudo determinar la carpeta del datafile de USERS: ' || v_users_datafile
                );
            END IF;

            v_nuevo_datafile :=
                SUBSTR(v_users_datafile, 1, v_pos_separador) ||
                'TS_HISTORICO_RESERVAS01.DBF';

            EXECUTE IMMEDIATE
                'CREATE TABLESPACE ts_historico_reservas ' ||
                'DATAFILE ''' || REPLACE(v_nuevo_datafile, '''', '''''') || ''' ' ||
                'SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 1G';
        END IF;
    END IF;

    -- Se reafirma la cuota tanto en la primera ejecucion como en ejecuciones posteriores.
    EXECUTE IMMEDIATE '
        ALTER USER turismo_user
        QUOTA UNLIMITED ON ts_historico_reservas';
END;
/
