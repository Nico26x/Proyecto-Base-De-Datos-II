-- 1. OCUPACIÓN POR MUNICIPIO Y MES (CON PIVOT)
SELECT *
FROM (
    -- 1. Consulta Base: Traemos Municipio, el Mes y el ID de la Reserva
    SELECT m.nombre AS municipio,
           TO_CHAR(rh.fecha_checkin, 'MM') AS mes,
           rh.id_reserva
    FROM municipio m
    JOIN alojamiento a ON m.id_municipio = a.id_municipio
    JOIN habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
)
PIVOT (
    -- 2. La operación: Contar las reservas que no estén repetidas
    COUNT(DISTINCT id_reserva)
    
    -- 3. Girar las filas a columnas según el mes
    FOR mes IN (
        '01' AS Ene, '02' AS Feb, '03' AS Mar, '04' AS Abr, 
        '05' AS May, '06' AS Jun, '07' AS Jul, '08' AS Ago, 
        '09' AS Sep, '10' AS Oct, '11' AS Nov, '12' AS Dic
    )
)
ORDER BY municipio;


-- 2. INGRESOS POR MUNICIPIO, TIPO DE ALOJAMIENTO Y TEMPORADA (ROLLUP CON GROUPING)
SELECT 
    CASE WHEN GROUPING(m.nombre) = 1 THEN '--- TOTAL GENERAL ---' ELSE m.nombre END AS municipio,
    CASE WHEN GROUPING(ta.nombre) = 1 THEN '--- SUBTOTAL MUNICIPIO ---' ELSE ta.nombre END AS tipo_alojamiento,
    CASE WHEN GROUPING(temp.nombre) = 1 THEN '--- SUBTOTAL TIPO ---' ELSE temp.nombre END AS temporada,
    SUM(p.monto) AS ingresos_totales
FROM municipio m
JOIN alojamiento a ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN tarifa tar ON h.id_habitacion = tar.id_habitacion
JOIN temporada temp ON tar.id_temporada = temp.id_temporada
JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN pago p ON rh.id_reserva = p.id_reserva
GROUP BY ROLLUP (m.nombre, ta.nombre, temp.nombre);


-- 3. LOS 3 ALOJAMIENTOS DE MAYOR INGRESO DENTRO DE CADA MUNICIPIO
WITH RankingIngresos AS (
    SELECT m.nombre AS municipio,
           a.nombre AS alojamiento,
           SUM(p.monto) AS ingresos_totales,
           RANK() OVER (PARTITION BY m.nombre ORDER BY SUM(p.monto) DESC) AS ranking
    FROM municipio m
    JOIN alojamiento a ON m.id_municipio = a.id_municipio
    JOIN habitacion h ON a.id_alojamiento = h.id_alojamiento
    JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
    JOIN pago p ON rh.id_reserva = p.id_reserva
    GROUP BY m.nombre, a.nombre
)
SELECT municipio, alojamiento, ingresos_totales, ranking
FROM RankingIngresos
WHERE ranking <= 3
ORDER BY municipio, ranking;


-- 4. VARIACIÓN DE INGRESOS MES CONTRA MES (LAG)
WITH IngresosMensuales AS (
    SELECT TRUNC(p.fecha_transaccion, 'MM') AS mes_anio,
           SUM(p.monto) AS ingresos_mes
    FROM pago p
    GROUP BY TRUNC(p.fecha_transaccion, 'MM')
)
SELECT 
    TO_CHAR(mes_anio, 'YYYY-MM') AS mes,
    ingresos_mes,
    LAG(ingresos_mes, 1) OVER (ORDER BY mes_anio) AS ingresos_mes_anterior,
    ROUND(ingresos_mes - LAG(ingresos_mes, 1) OVER (ORDER BY mes_anio), 2) AS variacion_absoluta,
    ROUND(((ingresos_mes - LAG(ingresos_mes, 1) OVER (ORDER BY mes_anio)) / 
           NULLIF(LAG(ingresos_mes, 1) OVER (ORDER BY mes_anio), 0)) * 100, 2) || '%' AS variacion_porcentual
FROM IngresosMensuales
ORDER BY mes_anio;


-- 5. CONSULTA PARAMETRIZADA CON RANGO DE FECHAS (CORREGIDA)
SELECT r.id_reserva,
       c.nombre_completo AS cliente,
       a.nombre AS alojamiento,
       rh.fecha_checkin,
       rh.fecha_checkout,
       r.estado
FROM reserva r
JOIN cliente c ON r.id_cliente = c.id_cliente
JOIN reserva_habitacion rh ON r.id_reserva = rh.id_reserva
JOIN habitacion h ON rh.id_habitacion = h.id_habitacion
JOIN alojamiento a ON h.id_alojamiento = a.id_alojamiento
WHERE rh.fecha_checkin >= TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
  AND rh.fecha_checkout <= TO_DATE(:fecha_fin, 'YYYY-MM-DD')
ORDER BY rh.fecha_checkin;


-- 6. VISTA MATERIALIZADA DE OCUPACIÓN MENSUAL CON POLÍTICA DE REFRESCO

-- Paso 1: Si ya existía de pruebas anteriores, la borramos para evitar errores.
DROP MATERIALIZED VIEW mv_ocupacion_mensual;

-- Paso 2: Creación de la Vista Materializada
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    m.nombre AS municipio,
    TO_CHAR(rh.fecha_checkin, 'YYYY-MM') AS mes,
    COUNT(DISTINCT rh.id_reserva) AS total_reservas,
    COUNT(DISTINCT rh.id_habitacion) AS total_habitaciones_reservadas
FROM municipio m
JOIN alojamiento a ON m.id_municipio = a.id_municipio
JOIN habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
GROUP BY m.nombre, TO_CHAR(rh.fecha_checkin, 'YYYY-MM');

/*
   JUSTIFICACIÓN DE LA POLÍTICA DE REFRESCO (Exigido en la rúbrica):
   
   1. ¿Por qué REFRESH COMPLETE? 
      Porque al agrupar por mes y contar elementos únicos (COUNT DISTINCT), 
      el motor no puede usar el modo FAST (incremental) fácilmente. Un refresco completo asegura exactitud total.
      
   2. ¿Por qué ON DEMAND y no ON COMMIT?
      ON DEMAND significa que la vista solo se actualizará cuando el administrador de base de datos lo pida 
      (por ejemplo, al cierre contable de cada mes). 
      Si usáramos ON COMMIT (que se actualice cada vez que alguien haga una reserva en la plataforma), 
      saturaríamos la base de datos porque tendría que recalcular el reporte gerencial con cada transacción nueva.
*/


-- 7. UNPIVOT (Transformar columnas de métodos de pago en filas de resumen)
WITH ResumenPagos AS (
    -- 1. Simulamos tener una tabla donde los totales están en columnas
    SELECT 
        SUM(CASE WHEN metodo = 'EFECTIVO' THEN monto ELSE 0 END) AS efectivo,
        SUM(CASE WHEN metodo = 'TARJETA' THEN monto ELSE 0 END) AS tarjeta,
        SUM(CASE WHEN metodo = 'TRANSFERENCIA' THEN monto ELSE 0 END) AS transferencia,
        SUM(CASE WHEN metodo = 'PSE' THEN monto ELSE 0 END) AS pse
    FROM pago
)
-- 2. Aplicamos el UNPIVOT para volver a convertirlas en filas
SELECT metodo_pago, total_recaudado
FROM ResumenPagos
UNPIVOT (
    total_recaudado FOR metodo_pago IN (
        efectivo AS 'Efectivo',
        tarjeta AS 'Tarjeta',
        transferencia AS 'Transferencia',
        pse AS 'PSE'
    )
);


-- 8. CONSULTA LIBRE DE NEGOCIO
-- Pregunta: ¿Qué tipo de alojamiento genera mayor retención de clientes y cuál es su ticket promedio de gasto?
SELECT 
    ta.nombre AS tipo_alojamiento,
    COUNT(DISTINCT r.id_cliente) AS clientes_unicos,
    ROUND(COUNT(DISTINCT r.id_reserva) / NULLIF(COUNT(DISTINCT r.id_cliente), 0), 2) AS promedio_reservas_por_cliente,
    ROUND(AVG(p.monto), 2) AS ticket_promedio_pago
FROM tipo_alojamiento ta
JOIN alojamiento a ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
JOIN habitacion h ON a.id_alojamiento = h.id_alojamiento
JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN reserva r ON rh.id_reserva = r.id_reserva
JOIN pago p ON r.id_reserva = p.id_reserva
GROUP BY ta.nombre
ORDER BY ticket_promedio_pago DESC;