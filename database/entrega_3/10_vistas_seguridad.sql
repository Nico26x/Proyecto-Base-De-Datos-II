-- =============================================================================
-- TURISMOUQ - ENTREGA 3 - SEGURIDAD: VISTAS DE RECEPCION Y PRIVILEGIOS
-- EJECUTAR COMO: TURISMO_USER (dueno de las tablas), despues de 09_roles.sql.
-- Idempotente: CREATE OR REPLACE conserva los GRANT y GRANT repetido no falla.
--
-- Regla clave: ROL_RECEPCION recibe privilegios SOLO sobre vistas V_RECEPCION_*.
-- Nunca recibe privilegios sobre tablas. Las vistas ocultan pagos, tarifas,
-- auditoria y datos internos.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- VISTAS DE RECEPCION
-- -----------------------------------------------------------------------------

-- Clientes: vista sobre una sola tabla, por eso admite INSERT/UPDATE.
-- WITH CHECK OPTION no aplica (no hay WHERE); se exponen solo datos de contacto.
CREATE OR REPLACE VIEW v_recepcion_clientes AS
SELECT id_cliente, tipo_identificacion, identificacion, nombre_completo, email
  FROM cliente;

-- Habitaciones con su alojamiento y municipio, para ofrecer opciones al cliente.
CREATE OR REPLACE VIEW v_recepcion_habitaciones AS
SELECT h.id_habitacion, h.numero, h.capacidad,
       a.id_alojamiento, a.nombre AS alojamiento, a.direccion, a.telefono,
       ta.nombre AS tipo_alojamiento,
       m.nombre AS municipio
  FROM habitacion h
  JOIN alojamiento a       ON a.id_alojamiento = h.id_alojamiento
  JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
  JOIN municipio m         ON m.id_municipio = a.id_municipio
  WITH READ ONLY;

-- Reservas para check-in/check-out. Sin pagos ni metodos de pago.
CREATE OR REPLACE VIEW v_recepcion_reservas AS
SELECT r.id_reserva, r.estado, r.fecha_creacion,
       c.identificacion, c.nombre_completo AS cliente,
       h.id_habitacion, h.numero AS habitacion,
       a.nombre AS alojamiento, m.nombre AS municipio,
       rh.fecha_checkin, rh.fecha_checkout,
       TRUNC(rh.fecha_checkout) - TRUNC(rh.fecha_checkin) AS noches,
       rh.subtotal_calculado AS valor_estadia
  FROM reserva r
  JOIN cliente c             ON c.id_cliente = r.id_cliente
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  JOIN habitacion h          ON h.id_habitacion = rh.id_habitacion
  JOIN alojamiento a         ON a.id_alojamiento = h.id_alojamiento
  JOIN municipio m           ON m.id_municipio = a.id_municipio
  WITH READ ONLY;

-- -----------------------------------------------------------------------------
-- ROL_RECEPCION: solo vistas.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON v_recepcion_clientes     TO rol_recepcion;
GRANT SELECT                 ON v_recepcion_habitaciones TO rol_recepcion;
GRANT SELECT                 ON v_recepcion_reservas     TO rol_recepcion;

-- -----------------------------------------------------------------------------
-- ROL_ADMIN_ALOJAMIENTO: mantiene la oferta (alojamientos, habitaciones,
-- tarifas, servicios). Ve la ocupacion pero no la modifica. Sin DELETE, sin
-- pagos, sin datos personales de clientes, sin auditoria.
-- Cada cambio de TARIFA queda registrado por TRG_AUDITORIA_TARIFA con su usuario.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON alojamiento TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON habitacion  TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON tarifa      TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON servicio    TO rol_admin_alojamiento;
GRANT SELECT ON municipio          TO rol_admin_alojamiento;
GRANT SELECT ON tipo_alojamiento   TO rol_admin_alojamiento;
GRANT SELECT ON temporada          TO rol_admin_alojamiento;
GRANT SELECT ON reserva_habitacion TO rol_admin_alojamiento;
GRANT SELECT ON reserva_servicio   TO rol_admin_alojamiento;

-- -----------------------------------------------------------------------------
-- ROL_GERENTE: lectura de todo el negocio + ejecutar el paquete (liquidacion
-- mensual). No hace DML directo: la liquidacion escribe a traves de
-- PKG_TURISMO con los derechos del dueno. No ve auditoria ni usuarios.
-- -----------------------------------------------------------------------------
GRANT SELECT ON municipio           TO rol_gerente;
GRANT SELECT ON tipo_alojamiento    TO rol_gerente;
GRANT SELECT ON alojamiento         TO rol_gerente;
GRANT SELECT ON habitacion          TO rol_gerente;
GRANT SELECT ON temporada           TO rol_gerente;
GRANT SELECT ON tarifa              TO rol_gerente;
GRANT SELECT ON cliente             TO rol_gerente;
GRANT SELECT ON servicio            TO rol_gerente;
GRANT SELECT ON reserva             TO rol_gerente;
GRANT SELECT ON reserva_habitacion  TO rol_gerente;
GRANT SELECT ON reserva_servicio    TO rol_gerente;
GRANT SELECT ON pago                TO rol_gerente;
GRANT SELECT ON resena              TO rol_gerente;
GRANT SELECT ON liquidacion_mensual TO rol_gerente;
GRANT EXECUTE ON pkg_turismo        TO rol_gerente;

-- -----------------------------------------------------------------------------
-- ROL_AUDITOR: solo lectura de lo que se audita (dinero y cambios de tarifa).
-- No ejecuta procedimientos ni modifica nada.
-- -----------------------------------------------------------------------------
GRANT SELECT ON auditoria_tarifa    TO rol_auditor;
GRANT SELECT ON tarifa              TO rol_auditor;
GRANT SELECT ON pago                TO rol_auditor;
GRANT SELECT ON reserva             TO rol_auditor;
GRANT SELECT ON reserva_habitacion  TO rol_auditor;
GRANT SELECT ON liquidacion_mensual TO rol_auditor;

-- -----------------------------------------------------------------------------
-- VERIFICACION: privilegios otorgados por rol.
-- -----------------------------------------------------------------------------
COLUMN grantee    FORMAT A22
COLUMN table_name FORMAT A26
COLUMN privilegios FORMAT A30

SELECT grantee, table_name,
       LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) AS privilegios
  FROM user_tab_privs_made
 WHERE grantee LIKE 'ROL\_%' ESCAPE '\'
 GROUP BY grantee, table_name
 ORDER BY grantee, table_name;
