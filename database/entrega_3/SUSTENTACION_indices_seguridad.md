# Entrega 3 — Índices y Seguridad (TurismoUQ)

Resultados **reales**, medidos el 2026-11-20 en Oracle XE 21c (XEPDB1), con estadísticas recogidas y
este volumen: `RESERVA` 25 004 · `RESERVA_HABITACION` 25 004 · `PAGO` 25 000 · `CLIENTE` 3 000.

## Orden de ejecución

| Script | Ejecutar como | Qué hace |
|---|---|---|
| `06_indices_antes.sql` | TURISMO_USER | Quita los índices de la E3 (si existen), recoge estadísticas, captura plan y tiempo **antes** |
| `07_indices.sql` | TURISMO_USER | Crea los 5 índices (idempotente) |
| `08_indices_despues.sql` | TURISMO_USER | Mismo plan y tiempo **después** + caso donde el índice no ayuda |
| `09_roles.sql` | SYSTEM / SYS | 4 roles y 4 usuarios de demostración |
| `10_vistas_seguridad.sql` | TURISMO_USER | Vistas de recepción y todos los GRANT |
| `11_perfil.sql` | SYSTEM / SYS | Perfil con límites de sesión, asignado a los 4 usuarios |
| `12_pruebas_seguridad.sql` | cualquiera (hace CONNECT) | 45 pruebas permitido/denegado |

Los archivos 01–05 (transacciones y concurrencia) no se modificaron. Después de crear los índices se
volvieron a ejecutar: `03_pruebas_transaccion.sql` pasó sus 4 pruebas y el bloqueo con dos sesiones
se comporta igual (la sesión B esperó 6 s hasta que A liberó el `FOR UPDATE`).

---

## Índices

### Cómo se midió
- **Plan:** `EXPLAIN PLAN` + `DBMS_XPLAN.DISPLAY` (costo y operaciones).
- **Tiempo:** cada consulta se ejecuta muchas veces con valores reales dentro de un bloque PL/SQL
  (`DBMS_UTILITY.GET_TIME`), porque una sola ejecución tarda menos de 1 ms. El bloque es idéntico
  en 06 y 08.

### Resumen

| # | Consulta | Índice | Costo antes → después | ms/ejecución antes → después | Mejora |
|---|---|---|---|---|---|
| Q1 | Disponibilidad de habitación | `IDX_RESHAB_HAB_FECHAS` **(compuesto)** | 69 → 4 | 1,125 → 0,100 | ~11× |
| Q2 | Cierre de caja diario | `IDX_PAGO_DIA` **(basado en función)** | 70 → 27 | 9,39 → 0,10 | ~90× |
| Q3 | Historial de un cliente | `IDX_RESERVA_CLIENTE`, `IDX_RESHAB_RESERVA`, `IDX_PAGO_RESERVA` | 174 → 45 | 6,50 → 0,267 | ~24× |
| ✗ | Reservas por estado | `IDX_RESERVA_ESTADO` (se crea y se elimina) | 34 sin índice vs 132 forzado | 1 030 ms vs 1 330 ms (200 ejec.) | **empeora 29 %** |

### Q1 — Disponibilidad de una habitación (índice compuesto)
**Consulta original:** es la misma que usan `PKG_TURISMO.SP_CREAR_RESERVA` y el trigger
`TRG_SOLAPAMIENTO_RESERVA_HAB`, así que corre **en cada reserva**:
```sql
SELECT COUNT(*) FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = :h AND r.estado <> 'CANCELADA'
   AND TRUNC(rh.fecha_checkin) < :fout AND TRUNC(rh.fecha_checkout) > :fin;
```
- **Antes:** `TABLE ACCESS FULL RESERVA_HABITACION` (lee las 25 004 estadías para hallar las ~62 de esa habitación). Costo 69.
- **Índice:** `CREATE INDEX idx_reshab_hab_fechas ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout);`
- **Después:** `INDEX RANGE SCAN IDX_RESHAB_HAB_FECHAS` con `access(id_habitacion = :h)` y las fechas como `filter` **dentro del índice**. Costo 4.
- **Por qué mejora:** `id_habitacion` va primero porque es la condición de igualdad. Las fechas van en el índice para descartar estadías sin ir a la tabla: solo se visitan las filas que realmente se cruzan.
- **Por qué no se usa la fecha como acceso:** el código aplica `TRUNC()` a la columna. No se cambió ese código porque es de la Entrega 2.
- **Concurrencia:** el `SELECT … FOR UPDATE` bloquea la fila de `HABITACION`, no estas filas. El índice cambia el camino de lectura, no el resultado.

### Q2 — Cierre de caja diario (índice basado en función)
```sql
SELECT metodo, COUNT(*), SUM(monto) FROM pago
 WHERE TRUNC(fecha_transaccion) = :dia GROUP BY metodo;
```
- **Por qué `TRUNC`:** `SP_CREAR_RESERVA_PAGO` registra el pago con `SYSDATE`, que incluye la hora. Para obtener "todo lo del día" hay que truncar.
- **Antes:** `TABLE ACCESS FULL PAGO`, `filter(TRUNC(fecha_transaccion) = :dia)`, costo 70. Un índice normal sobre `fecha_transaccion` **no sirve**, porque la columna está dentro de una función.
- **Índice:** `CREATE INDEX idx_pago_dia ON pago (TRUNC(fecha_transaccion));`
- **Después:** `INDEX RANGE SCAN IDX_PAGO_DIA` con `access(TRUNC(fecha_transaccion) = :dia)`. Lee ~28 pagos en lugar de 25 000. Costo 27.
- **Por qué mejora:** el índice guarda ya calculado el valor `TRUNC(fecha)`, así que la condición se convierte en acceso directo.

### Q3 — Historial de un cliente (índices sobre llaves foráneas)
```sql
SELECT c.nombre_completo, r.id_reserva, r.estado, rh.fecha_checkin, rh.fecha_checkout,
       rh.subtotal_calculado, NVL(SUM(p.monto),0) pagado
  FROM cliente c JOIN reserva r ON r.id_cliente = c.id_cliente
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  LEFT JOIN pago p ON p.id_reserva = r.id_reserva
 WHERE c.identificacion = :ident GROUP BY ...;
```
- **Antes:** encuentra al cliente por su UK, pero luego hace **3 full scans** (`RESERVA`, `PAGO`, `RESERVA_HABITACION`) y dos hash joins. Costo 174.
- **Índices:** `reserva(id_cliente)`, `reserva_habitacion(id_reserva)`, `pago(id_reserva)`.
- **Después:** todo con `NESTED LOOPS` e `INDEX RANGE SCAN`, tocando solo las ~8 reservas del cliente. Costo 45.
- **Por qué mejora:** Oracle **no** crea índices automáticamente sobre las FK, solo sobre PK y UK. Además, indexar las FK evita que borrar un padre (`ON DELETE CASCADE`) bloquee toda la tabla hija.

### Caso donde el índice NO ayuda — `RESERVA(estado)`
```sql
SELECT id_reserva, id_cliente, fecha_creacion FROM reserva WHERE estado = 'PENDIENTE';
```
- `ESTADO` tiene solo 4 valores y cada uno ocupa ~25 % de las filas (6 284 de 25 004).
- Con el índice creado, **el optimizador lo ignora** y elige `TABLE ACCESS FULL` (costo 34).
- Forzado con hint `INDEX`, el costo sube a **132** y el tiempo real a **1 330 ms frente a 1 030 ms** (200 ejecuciones).
- **Por qué:** para devolver 1 de cada 4 filas, el índice obliga a ~6 300 saltos índice → tabla, uno por fila. El full scan lee los 118 bloques de la tabla con lecturas multibloque. Regla práctica: un índice B-tree conviene cuando la consulta devuelve un porcentaje pequeño de las filas.
- **Decisión:** el índice se elimina al final de `08`, porque solo agregaría costo a cada `INSERT`/`UPDATE` de `RESERVA`.

También se probó la **liquidación mensual** con índices por fecha: el costo bajó solo de 107 a 105. Las
filas de un mes están dispersas por toda la tabla (clustering factor ≈ número de filas), así que por eso
no se eligió como consulta lenta.

---

## Seguridad

### Roles y privilegios

| Rol (usuario demo) | Puede | No puede |
|---|---|---|
| **ROL_RECEPCION** (`usr_recepcion`) | `SELECT/INSERT/UPDATE` en `V_RECEPCION_CLIENTES`; `SELECT` en `V_RECEPCION_HABITACIONES` y `V_RECEPCION_RESERVAS` | Ninguna tabla. No ve pagos, tarifas ni auditoría. No borra |
| **ROL_ADMIN_ALOJAMIENTO** (`usr_admin_alojamiento`) | `SELECT/INSERT/UPDATE` en `ALOJAMIENTO`, `HABITACION`, `TARIFA`, `SERVICIO`; `SELECT` en catálogos y en la ocupación (`RESERVA_HABITACION`, `RESERVA_SERVICIO`) | `DELETE`; pagos; clientes; auditoría; ejecutar el paquete |
| **ROL_GERENTE** (`usr_gerente`) | `SELECT` en todas las tablas del negocio; `EXECUTE` en `PKG_TURISMO` (liquidación) | DML directo; `AUDITORIA_TARIFA`; `USUARIO_SISTEMA` |
| **ROL_AUDITOR** (`usr_auditor`) | `SELECT` en `AUDITORIA_TARIFA`, `TARIFA`, `PAGO`, `RESERVA`, `RESERVA_HABITACION`, `LIQUIDACION_MENSUAL` | Modificar cualquier cosa; ejecutar procedimientos; datos personales de clientes |

Todos los roles tienen únicamente `CREATE SESSION` como privilegio de sistema, así que ninguno puede crear objetos.

Por qué cada uno:
- **Recepción solo por vistas:** las vistas dejan pasar solo las columnas que necesita el mostrador. `V_RECEPCION_CLIENTES` es de una sola tabla, por eso admite `INSERT`/`UPDATE` para registrar clientes. Las otras dos llevan `WITH READ ONLY`.
- **Admin. de alojamiento:** mantiene la oferta, pero cada cambio de tarifa queda en `AUDITORIA_TARIFA` con su usuario, porque el trigger guarda `SESSION_USER`.
- **Gerente:** ve todo para decidir. Escribe la liquidación **solo** a través del paquete, que corre con los derechos del dueño; un `INSERT` directo en `LIQUIDACION_MENSUAL` le da `ORA-01031`.
- **Auditor:** solo lectura de dinero y cambios. No puede alterar la evidencia que revisa.

### Resultado de `12_pruebas_seguridad.sql` (real)
```
RESUMEN USR_RECEPCION: 13 pruebas, 0 fallos
RESUMEN USR_ADMIN_ALOJAMIENTO: 12 pruebas, 0 fallos
RESUMEN USR_GERENTE: 11 pruebas, 0 fallos
RESUMEN USR_AUDITOR: 9 pruebas, 0 fallos
```
Ejemplos: recepción → `SELECT … FROM turismo_user.cliente` = **ORA-00942** y `v_recepcion_clientes` = 3 000 filas;
gerente → `DELETE FROM pago` = **ORA-01031**; auditor → `EXECUTE pkg_turismo` = **ORA-06550**.
- `ORA-00942`: sin ningún privilegio sobre el objeto, Oracle ni siquiera revela que existe.
- `ORA-01031`: puede ver el objeto, pero le falta el privilegio para esa operación.

### Perfil `PERFIL_TURISMO_OPERATIVO` (asignado a los 4 usuarios)

| Límite | Valor | Para qué | Comprobado |
|---|---|---|---|
| `SESSIONS_PER_USER` | 2 | Evita compartir una cuenta en varios puestos | 3.ª sesión → **ORA-02391** ✅ |
| `CONNECT_TIME` | 480 min | Una sesión dura como máximo un turno | — |
| `IDLE_TIME` | 15 min | Corta sesiones de puestos abandonados | — (ORA-02396) |
| `FAILED_LOGIN_ATTEMPTS` | 3 | Frena ataques de adivinar contraseñas | 3 claves malas → **ORA-28000**, `LOCKED(TIMED)` ✅ |
| `PASSWORD_LOCK_TIME` | 1/24 (1 h) | Desbloqueo automático | — |
| `PASSWORD_LIFE_TIME` / `GRACE_TIME` | 90 / 7 días | Rotación de contraseñas | — |

Los límites de sesión solo se aplican si `RESOURCE_LIMIT = TRUE`. En esta base vale TRUE (es el valor por defecto en 21c) y `11_perfil.sql` lo muestra al final.
Para desbloquear después de la demostración: `ALTER USER usr_auditor ACCOUNT UNLOCK;`

### Advertencia aprendida en las pruebas
Cualquier DDL, como el `CREATE TABLE` usado para comprobar que recepción no puede crear objetos, hace
**COMMIT implícito antes de ejecutarse, aunque falle**. Por eso, en `12` esa prueba va **antes** del DML
de prueba; si va después, el `ROLLBACK` ya no deshace el cliente insertado.
