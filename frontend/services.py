"""Oracle queries and application operations used by the Streamlit frontend."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from decimal import Decimal, InvalidOperation
from typing import Any

import oracledb
import pandas as pd
import streamlit as st

from db import DatabaseError, call_function, call_procedure, fetch_all, fetch_one, test_connection


def formato_moneda_colombiana(value: Any) -> str:
    """Format a numeric value for display without changing its stored type."""
    try:
        amount = Decimal(str(value or 0)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError, TypeError):
        amount = Decimal("0.00")
    formatted = f"{amount:,.2f}".replace(",", "_").replace(".", ",").replace("_", ".")
    return f"${formatted}"


def _oracle_date(value: date) -> datetime:
    return datetime.combine(value, time.min)


def mensaje_error_reserva(error: DatabaseError) -> str:
    messages = {
        20201: "La habitación no está disponible para las fechas seleccionadas.",
        20202: "El checkout debe ser posterior al check-in.",
        20203: "El número de huéspedes supera la capacidad permitida.",
        20204: "Faltan datos válidos o alguna entidad ya no existe.",
        20205: "La reserva se cruza con otra reserva existente.",
        20106: "No existe una temporada configurada para alguna noche.",
        20107: "Existe una configuración ambigua de temporadas.",
        20108: "No existe tarifa para alguna noche de la estadía.",
        20109: "Existen tarifas duplicadas para la habitación y temporada.",
    }
    return messages.get(error.code, error.user_message)


@st.cache_data(ttl=60, show_spinner=False)
def obtener_metricas() -> dict[str, Any]:
    row = fetch_one(
        """
        WITH ingresos_habitaciones AS (
            SELECT NVL(SUM(rh.subtotal_calculado), 0) AS total
              FROM reserva_habitacion rh
              JOIN reserva r ON r.id_reserva = rh.id_reserva
             WHERE r.estado <> 'CANCELADA'
        ),
        ingresos_servicios AS (
            SELECT NVL(SUM(rs.subtotal), 0) AS total
              FROM reserva_servicio rs
              JOIN reserva r ON r.id_reserva = rs.id_reserva
             WHERE r.estado <> 'CANCELADA'
        )
        SELECT (SELECT COUNT(*) FROM municipio) AS municipios,
               (SELECT COUNT(*) FROM alojamiento) AS alojamientos,
               (SELECT COUNT(*) FROM habitacion) AS habitaciones,
               (SELECT COUNT(*) FROM cliente) AS clientes,
               (SELECT COUNT(*) FROM reserva) AS reservas,
               ih.total AS ingresos_habitaciones,
               ise.total AS ingresos_servicios,
               ih.total + ise.total AS ingresos_historicos
          FROM ingresos_habitaciones ih
          CROSS JOIN ingresos_servicios ise
        """
    )
    return row or {}


@st.cache_data(ttl=60, show_spinner=False)
def obtener_reservas_por_estado() -> pd.DataFrame:
    rows = fetch_all(
        """
        SELECT estado, COUNT(*) AS cantidad
          FROM reserva
         GROUP BY estado
         ORDER BY cantidad DESC, estado
        """
    )
    return pd.DataFrame(rows, columns=["estado", "cantidad"])


@st.cache_data(ttl=60, show_spinner=False)
def obtener_reservas_por_municipio(limite: int = 12) -> pd.DataFrame:
    rows = fetch_all(
        """
        SELECT municipio, cantidad
          FROM (
              SELECT m.nombre AS municipio,
                     COUNT(DISTINCT r.id_reserva) AS cantidad
                FROM reserva r
                JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
                JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
                JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
                JOIN municipio m ON m.id_municipio = a.id_municipio
               GROUP BY m.id_municipio, m.nombre
               ORDER BY cantidad DESC, m.nombre
          )
         WHERE ROWNUM <= :limite
        """,
        {"limite": limite},
    )
    return pd.DataFrame(rows, columns=["municipio", "cantidad"])


@st.cache_data(ttl=60, show_spinner=False)
def obtener_evolucion_mensual() -> pd.DataFrame:
    rows = fetch_all(
        """
        SELECT TRUNC(fecha_creacion, 'MM') AS periodo,
               COUNT(*) AS cantidad
          FROM reserva
         GROUP BY TRUNC(fecha_creacion, 'MM')
         ORDER BY periodo
        """
    )
    return pd.DataFrame(rows, columns=["periodo", "cantidad"])


@st.cache_data(ttl=60, show_spinner=False)
def obtener_top_alojamientos(limite: int = 10) -> pd.DataFrame:
    rows = fetch_all(
        """
        WITH habitaciones AS (
            SELECT h.id_alojamiento,
                   SUM(rh.subtotal_calculado) AS ingreso_habitaciones
              FROM reserva_habitacion rh
              JOIN reserva r ON r.id_reserva = rh.id_reserva
              JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
             WHERE r.estado <> 'CANCELADA'
             GROUP BY h.id_alojamiento
        ),
        servicios AS (
            SELECT s.id_alojamiento,
                   SUM(rs.subtotal) AS ingreso_servicios
              FROM reserva_servicio rs
              JOIN reserva r ON r.id_reserva = rs.id_reserva
              JOIN servicio s ON s.id_servicio = rs.id_servicio
             WHERE r.estado <> 'CANCELADA'
             GROUP BY s.id_alojamiento
        )
        SELECT alojamiento, municipio, ingreso_habitaciones,
               ingreso_servicios, total
          FROM (
              SELECT a.nombre AS alojamiento,
                     m.nombre AS municipio,
                     NVL(h.ingreso_habitaciones, 0) AS ingreso_habitaciones,
                     NVL(s.ingreso_servicios, 0) AS ingreso_servicios,
                     NVL(h.ingreso_habitaciones, 0)
                       + NVL(s.ingreso_servicios, 0) AS total
                FROM alojamiento a
                JOIN municipio m ON m.id_municipio = a.id_municipio
                LEFT JOIN habitaciones h ON h.id_alojamiento = a.id_alojamiento
                LEFT JOIN servicios s ON s.id_alojamiento = a.id_alojamiento
               WHERE h.id_alojamiento IS NOT NULL OR s.id_alojamiento IS NOT NULL
               ORDER BY total DESC, a.nombre
          )
         WHERE ROWNUM <= :limite
        """,
        {"limite": limite},
    )
    return pd.DataFrame(
        rows,
        columns=[
            "alojamiento",
            "municipio",
            "ingreso_habitaciones",
            "ingreso_servicios",
            "total",
        ],
    )


def obtener_clientes() -> list[dict[str, Any]]:
    return fetch_all(
        """
        SELECT id_cliente,
               nombre_completo,
               tipo_identificacion,
               identificacion
          FROM cliente
         ORDER BY nombre_completo, id_cliente
        """
    )


@st.cache_data(ttl=300, show_spinner=False)
def obtener_municipios() -> list[dict[str, Any]]:
    return fetch_all(
        """
        SELECT id_municipio, nombre
          FROM municipio
         ORDER BY nombre
        """
    )


@st.cache_data(ttl=120, show_spinner=False)
def obtener_estados_reserva() -> list[str]:
    rows = fetch_all(
        """
        SELECT DISTINCT estado
          FROM reserva
         ORDER BY estado
        """
    )
    return [row["estado"] for row in rows]


@st.cache_data(ttl=300, show_spinner=False)
def obtener_alojamientos() -> list[dict[str, Any]]:
    return fetch_all(
        """
        SELECT a.id_alojamiento,
               a.id_municipio,
               a.nombre,
               m.nombre AS municipio,
               ta.nombre AS tipo
          FROM alojamiento a
          JOIN municipio m ON m.id_municipio = a.id_municipio
          JOIN tipo_alojamiento ta
            ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
         ORDER BY m.nombre, a.nombre, a.id_alojamiento
        """
    )


@st.cache_data(ttl=300, show_spinner=False)
def obtener_alojamientos_por_municipio(id_municipio: int) -> list[dict[str, Any]]:
    return fetch_all(
        """
        SELECT a.id_alojamiento,
               a.nombre,
               ta.nombre AS tipo
          FROM alojamiento a
          JOIN tipo_alojamiento ta
            ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
         WHERE a.id_municipio = :id_municipio
         ORDER BY a.nombre, a.id_alojamiento
        """,
        {"id_municipio": id_municipio},
    )


def buscar_reservas(
    *,
    estado: str | None = None,
    id_municipio: int | None = None,
    id_alojamiento: int | None = None,
    cliente_texto: str | None = None,
    fecha_desde: date | None = None,
    fecha_hasta: date | None = None,
    limite: int = 100,
) -> pd.DataFrame:
    """Return filtered room assignments; all filtering and limiting happens in Oracle."""
    conditions: list[str] = []
    binds: dict[str, Any] = {}

    if estado:
        conditions.append("r.estado = :estado")
        binds["estado"] = estado
    if id_municipio is not None:
        conditions.append("m.id_municipio = :id_municipio")
        binds["id_municipio"] = id_municipio
    if id_alojamiento is not None:
        conditions.append("a.id_alojamiento = :id_alojamiento")
        binds["id_alojamiento"] = id_alojamiento

    normalized_client = (cliente_texto or "").strip().upper()
    if normalized_client:
        conditions.append(
            "(UPPER(c.nombre_completo) LIKE :cliente "
            "OR UPPER(c.identificacion) LIKE :cliente)"
        )
        binds["cliente"] = f"%{normalized_client}%"

    if fecha_desde is not None:
        conditions.append("rh.fecha_checkin >= :fecha_desde")
        binds["fecha_desde"] = _oracle_date(fecha_desde)
    if fecha_hasta is not None:
        conditions.append("rh.fecha_checkin < :fecha_hasta_exclusiva")
        binds["fecha_hasta_exclusiva"] = _oracle_date(fecha_hasta + timedelta(days=1))

    safe_limit = max(1, min(int(limite), 500))
    binds["limite"] = safe_limit
    where_clause = "\n           AND ".join(conditions)
    if where_clause:
        where_clause = "AND " + where_clause

    rows = fetch_all(
        f"""
        SELECT id_reserva,
               fecha_reserva,
               cliente,
               identificacion,
               municipio,
               alojamiento,
               habitacion,
               fecha_checkin,
               fecha_checkout,
               noches,
               estado,
               subtotal
          FROM (
              SELECT r.id_reserva,
                     r.fecha_creacion AS fecha_reserva,
                     c.nombre_completo AS cliente,
                     c.identificacion,
                     m.nombre AS municipio,
                     a.nombre AS alojamiento,
                     h.numero AS habitacion,
                     rh.fecha_checkin,
                     rh.fecha_checkout,
                     TRUNC(rh.fecha_checkout) - TRUNC(rh.fecha_checkin) AS noches,
                     r.estado,
                     rh.subtotal_calculado AS subtotal,
                     rh.id_reserva_habitacion
                FROM reserva r
                JOIN cliente c ON c.id_cliente = r.id_cliente
                JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
                JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
                JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
                JOIN municipio m ON m.id_municipio = a.id_municipio
               WHERE 1 = 1
                 {where_clause}
               ORDER BY rh.fecha_checkin DESC,
                        r.id_reserva DESC,
                        rh.id_reserva_habitacion DESC
          )
         WHERE ROWNUM <= :limite
        """,
        binds,
    )
    return pd.DataFrame(
        rows,
        columns=[
            "id_reserva",
            "fecha_reserva",
            "cliente",
            "identificacion",
            "municipio",
            "alojamiento",
            "habitacion",
            "fecha_checkin",
            "fecha_checkout",
            "noches",
            "estado",
            "subtotal",
        ],
    )


@st.cache_data(ttl=300, show_spinner=False)
def obtener_habitaciones_por_alojamiento(id_alojamiento: int) -> list[dict[str, Any]]:
    return fetch_all(
        """
        SELECT id_habitacion, numero, capacidad
          FROM habitacion
         WHERE id_alojamiento = :id_alojamiento
         ORDER BY numero, id_habitacion
        """,
        {"id_alojamiento": id_alojamiento},
    )


def calcular_valor_estadia(
    id_habitacion: int, fecha_in: date, fecha_out: date
) -> Decimal:
    value = call_function(
        "PKG_TURISMO.VALOR_ESTADIA",
        oracledb.NUMBER,
        [id_habitacion, _oracle_date(fecha_in), _oracle_date(fecha_out)],
    )
    return Decimal(str(value))


def crear_reserva(
    id_cliente: int,
    id_habitacion: int,
    fecha_in: date,
    fecha_out: date,
    huespedes: int,
) -> int:
    output_values = call_procedure(
        "PKG_TURISMO.SP_CREAR_RESERVA",
        [
            id_cliente,
            id_habitacion,
            _oracle_date(fecha_in),
            _oracle_date(fecha_out),
            huespedes,
        ],
        [oracledb.NUMBER],
    )
    limpiar_cache_dashboard()
    return int(output_values[0])


def mensaje_error_liquidacion(error: DatabaseError) -> str:
    if error.code == 20206:
        return "El año o mes seleccionado no es válido."
    return error.user_message


def generar_liquidacion(anio: int, mes: int) -> int:
    output_values = call_procedure(
        "PKG_TURISMO.SP_LIQUIDAR_MES",
        [int(anio), int(mes)],
        [oracledb.NUMBER],
    )
    return int(output_values[0])


def obtener_liquidacion_periodo(anio: int, mes: int) -> pd.DataFrame:
    periodo = datetime(int(anio), int(mes), 1)
    rows = fetch_all(
        """
        SELECT lm.id_alojamiento,
               m.nombre AS municipio,
               a.nombre AS alojamiento,
               lm.periodo,
               lm.noches,
               lm.ingreso_habitaciones,
               lm.ingreso_servicios,
               lm.total,
               lm.fecha_generacion
          FROM liquidacion_mensual lm
          JOIN alojamiento a ON a.id_alojamiento = lm.id_alojamiento
          JOIN municipio m ON m.id_municipio = a.id_municipio
         WHERE lm.periodo = :periodo
         ORDER BY lm.total DESC, a.nombre
        """,
        {"periodo": periodo},
    )
    return pd.DataFrame(
        rows,
        columns=[
            "id_alojamiento",
            "municipio",
            "alojamiento",
            "periodo",
            "noches",
            "ingreso_habitaciones",
            "ingreso_servicios",
            "total",
            "fecha_generacion",
        ],
    )


def obtener_resumen_liquidacion(anio: int, mes: int) -> dict[str, Any]:
    periodo = datetime(int(anio), int(mes), 1)
    row = fetch_one(
        """
        SELECT COUNT(*) AS alojamientos,
               NVL(SUM(noches), 0) AS noches,
               NVL(SUM(ingreso_habitaciones), 0) AS ingreso_habitaciones,
               NVL(SUM(ingreso_servicios), 0) AS ingreso_servicios,
               NVL(SUM(total), 0) AS total,
               MAX(fecha_generacion) AS ultima_generacion
          FROM liquidacion_mensual
         WHERE periodo = :periodo
        """,
        {"periodo": periodo},
    )
    return row or {
        "alojamientos": 0,
        "noches": 0,
        "ingreso_habitaciones": 0,
        "ingreso_servicios": 0,
        "total": 0,
        "ultima_generacion": None,
    }


def obtener_operaciones_auditoria() -> list[str]:
    rows = fetch_all(
        """
        SELECT DISTINCT operacion
          FROM auditoria_tarifa
         ORDER BY operacion
        """
    )
    return [row["operacion"] for row in rows]


def obtener_usuarios_auditoria() -> list[str]:
    rows = fetch_all(
        """
        SELECT DISTINCT usuario_bd
          FROM auditoria_tarifa
         ORDER BY usuario_bd
        """
    )
    return [row["usuario_bd"] for row in rows]


def buscar_auditorias(
    *,
    operacion: str | None = None,
    usuario: str | None = None,
    fecha_desde: date | None = None,
    fecha_hasta: date | None = None,
    id_tarifa: int | None = None,
    id_habitacion: int | None = None,
    limite: int = 100,
) -> pd.DataFrame:
    conditions: list[str] = []
    binds: dict[str, Any] = {}

    if operacion:
        conditions.append("au.operacion = :operacion")
        binds["operacion"] = operacion
    if usuario:
        conditions.append("au.usuario_bd = :usuario")
        binds["usuario"] = usuario
    if fecha_desde is not None:
        conditions.append("au.fecha_cambio >= :fecha_desde")
        binds["fecha_desde"] = _oracle_date(fecha_desde)
    if fecha_hasta is not None:
        conditions.append("au.fecha_cambio < :fecha_hasta_exclusiva")
        binds["fecha_hasta_exclusiva"] = _oracle_date(fecha_hasta + timedelta(days=1))
    if id_tarifa is not None:
        conditions.append("au.id_tarifa = :id_tarifa")
        binds["id_tarifa"] = int(id_tarifa)
    if id_habitacion is not None:
        conditions.append("au.id_habitacion = :id_habitacion")
        binds["id_habitacion"] = int(id_habitacion)

    binds["limite"] = max(1, min(int(limite), 500))
    where_clause = "\n           AND ".join(conditions)
    if where_clause:
        where_clause = "AND " + where_clause

    rows = fetch_all(
        f"""
        SELECT id_auditoria,
               fecha_cambio,
               usuario_bd,
               operacion,
               id_tarifa,
               id_habitacion,
               habitacion,
               alojamiento,
               municipio,
               id_temporada,
               temporada,
               valor_anterior,
               valor_nuevo,
               variacion
          FROM (
              SELECT au.id_auditoria,
                     au.fecha_cambio,
                     au.usuario_bd,
                     au.operacion,
                     au.id_tarifa,
                     au.id_habitacion,
                     h.numero AS habitacion,
                     a.nombre AS alojamiento,
                     m.nombre AS municipio,
                     au.id_temporada,
                     t.nombre AS temporada,
                     au.valor_anterior,
                     au.valor_nuevo,
                     CASE
                         WHEN au.valor_anterior IS NOT NULL
                          AND au.valor_nuevo IS NOT NULL
                         THEN au.valor_nuevo - au.valor_anterior
                     END AS variacion
                FROM auditoria_tarifa au
                LEFT JOIN habitacion h
                  ON h.id_habitacion = au.id_habitacion
                LEFT JOIN alojamiento a
                  ON a.id_alojamiento = h.id_alojamiento
                LEFT JOIN municipio m
                  ON m.id_municipio = a.id_municipio
                LEFT JOIN temporada t
                  ON t.id_temporada = au.id_temporada
               WHERE 1 = 1
                 {where_clause}
               ORDER BY au.fecha_cambio DESC, au.id_auditoria DESC
          )
         WHERE ROWNUM <= :limite
        """,
        binds,
    )
    return pd.DataFrame(
        rows,
        columns=[
            "id_auditoria",
            "fecha_cambio",
            "usuario_bd",
            "operacion",
            "id_tarifa",
            "id_habitacion",
            "habitacion",
            "alojamiento",
            "municipio",
            "id_temporada",
            "temporada",
            "valor_anterior",
            "valor_nuevo",
            "variacion",
        ],
    )


def obtener_resumen_auditoria(data: pd.DataFrame) -> dict[str, int]:
    if data.empty:
        return {
            "registros": 0,
            "insert": 0,
            "update": 0,
            "delete": 0,
            "usuarios": 0,
        }
    operation_counts = data["operacion"].value_counts()
    return {
        "registros": len(data),
        "insert": int(operation_counts.get("INSERT", 0)),
        "update": int(operation_counts.get("UPDATE", 0)),
        "delete": int(operation_counts.get("DELETE", 0)),
        "usuarios": int(data["usuario_bd"].nunique()),
    }


def obtener_estado_trigger_auditoria() -> dict[str, Any]:
    row = fetch_one(
        """
        SELECT object_name AS nombre,
               object_type AS tipo,
               status AS estado
          FROM user_objects
         WHERE object_name = 'TRG_AUDITORIA_TARIFA'
           AND object_type = 'TRIGGER'
        """
    )
    return row or {
        "nombre": "TRG_AUDITORIA_TARIFA",
        "tipo": "TRIGGER",
        "estado": "NO EXISTE",
    }


@st.cache_data(ttl=30, show_spinner=False)
def obtener_estado_sistema() -> pd.DataFrame:
    rows = fetch_all(
        """
        WITH esperados (objeto, tipo) AS (
            SELECT 'FN_VALOR_ESTADIA', 'FUNCTION' FROM dual UNION ALL
            SELECT 'PKG_TURISMO', 'PACKAGE' FROM dual UNION ALL
            SELECT 'PKG_TURISMO', 'PACKAGE BODY' FROM dual UNION ALL
            SELECT 'TRG_AUDITORIA_TARIFA', 'TRIGGER' FROM dual UNION ALL
            SELECT 'TRG_SOLAPAMIENTO_RESERVA_HAB', 'TRIGGER' FROM dual
        )
        SELECT e.objeto,
               e.tipo,
               NVL(o.status, 'NO EXISTE') AS estado
          FROM esperados e
          LEFT JOIN user_objects o
            ON o.object_name = e.objeto
           AND o.object_type = e.tipo
         ORDER BY e.objeto, e.tipo
        """
    )
    return pd.DataFrame(rows, columns=["objeto", "tipo", "estado"])


@st.cache_data(ttl=30, show_spinner=False)
def obtener_info_sesion() -> dict[str, Any]:
    row = fetch_one(
        """
        SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS usuario,
               SYSTIMESTAMP AS hora_oracle,
               (SELECT COUNT(*) FROM user_errors) AS errores_compilacion,
               (SELECT COUNT(*) FROM user_tables
                 WHERE table_name = 'AUDITORIA_TARIFA') AS existe_auditoria,
               (SELECT COUNT(*) FROM user_tables
                 WHERE table_name = 'LIQUIDACION_MENSUAL') AS existe_liquidacion
          FROM dual
        """
    )
    return row or {}


def probar_conexion() -> dict[str, Any]:
    return test_connection()


def limpiar_cache_dashboard() -> None:
    obtener_metricas.clear()
    obtener_reservas_por_estado.clear()
    obtener_reservas_por_municipio.clear()
    obtener_evolucion_mensual.clear()
    obtener_top_alojamientos.clear()
    obtener_estado_sistema.clear()
    obtener_info_sesion.clear()
