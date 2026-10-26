"""Main analytical dashboard for TurismoUQ."""

import pandas as pd
import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import (
    limpiar_cache_dashboard,
    obtener_estado_sistema,
    obtener_evolucion_mensual,
    obtener_info_sesion,
    obtener_metricas,
    obtener_reservas_por_estado,
    obtener_reservas_por_municipio,
    obtener_top_alojamientos,
    formato_moneda_colombiana,
)


st.set_page_config(page_title="Dashboard | TurismoUQ", page_icon="TU", layout="wide")


def mostrar_error(exc: Exception) -> None:
    if isinstance(exc, DatabaseConfigError):
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(exc))
    elif isinstance(exc, DatabaseError):
        st.error(exc.user_message)
        st.caption(f"Detalle técnico: `{exc.technical_code}`")
    else:
        st.error("No fue posible cargar el Dashboard.")


title_column, refresh_column = st.columns([5, 1])
with title_column:
    st.title("Dashboard")
    st.caption("Indicadores históricos agregados directamente en Oracle")
with refresh_column:
    if st.button("Actualizar", width="stretch"):
        limpiar_cache_dashboard()
        st.rerun()

try:
    with st.spinner("Consultando indicadores..."):
        metrics = obtener_metricas()
        by_status = obtener_reservas_por_estado()
        by_municipality = obtener_reservas_por_municipio()
        monthly = obtener_evolucion_mensual()
        top_lodgings = obtener_top_alojamientos()
except (DatabaseConfigError, DatabaseError) as exc:
    mostrar_error(exc)
    st.stop()

metric_columns = st.columns(5)
metric_columns[0].metric("Municipios", f"{int(metrics.get('municipios', 0)):,}")
metric_columns[1].metric("Alojamientos", f"{int(metrics.get('alojamientos', 0)):,}")
metric_columns[2].metric("Habitaciones", f"{int(metrics.get('habitaciones', 0)):,}")
metric_columns[3].metric("Clientes", f"{int(metrics.get('clientes', 0)):,}")
metric_columns[4].metric("Reservas", f"{int(metrics.get('reservas', 0)):,}")

st.metric(
    "Ingresos históricos",
    formato_moneda_colombiana(metrics.get("ingresos_historicos")),
)

st.caption(
    "Ingresos históricos = subtotales de habitaciones + servicios de reservas no canceladas."
)

st.divider()
status_column, municipality_column = st.columns(2)

with status_column:
    st.subheader("Reservas por estado")
    if by_status.empty:
        st.info("No hay reservas para mostrar.")
    else:
        st.bar_chart(by_status.set_index("estado")["cantidad"], color="#246B68")

with municipality_column:
    st.subheader("Reservas por municipio")
    st.caption(
        "Cuenta reservas distintas. Una reserva con habitaciones en varios municipios "
        "puede aparecer una vez en cada municipio."
    )
    if by_municipality.empty:
        st.info("No hay asignaciones de habitaciones para mostrar.")
    else:
        st.bar_chart(
            by_municipality.set_index("municipio")["cantidad"],
            color="#B06A3C",
        )

st.divider()
monthly_column, ranking_column = st.columns([1, 1.35])

with monthly_column:
    st.subheader("Evolución mensual de reservas")
    st.caption("Cantidad de reservas según su fecha de creación.")
    if monthly.empty:
        st.info("No hay historia mensual para mostrar.")
    else:
        monthly_chart = monthly.copy()
        monthly_chart["periodo"] = pd.to_datetime(monthly_chart["periodo"])
        st.line_chart(
            monthly_chart.set_index("periodo")["cantidad"],
            color="#246B68",
        )

with ranking_column:
    st.subheader("Top 10 alojamientos por ingreso")
    if top_lodgings.empty:
        st.info("No hay ingresos para mostrar.")
    else:
        ranking = top_lodgings.copy()
        for column in ("ingreso_habitaciones", "ingreso_servicios", "total"):
            ranking[column] = ranking[column].map(formato_moneda_colombiana)
        st.dataframe(
            ranking,
            hide_index=True,
            width="stretch",
            column_config={
                "alojamiento": "Alojamiento",
                "municipio": "Municipio",
                "ingreso_habitaciones": "Habitaciones",
                "ingreso_servicios": "Servicios",
                "total": "Total",
            },
        )

st.divider()
with st.expander("Estado técnico de Oracle", expanded=False):
    try:
        objects = obtener_estado_sistema()
        session = obtener_info_sesion()

        technical_columns = st.columns(4)
        technical_columns[0].metric("Usuario", session.get("usuario", "N/D"))
        technical_columns[1].metric(
            "Errores de compilación", int(session.get("errores_compilacion", 0))
        )
        technical_columns[2].metric(
            "AUDITORIA_TARIFA",
            "Disponible" if session.get("existe_auditoria") else "No existe",
        )
        technical_columns[3].metric(
            "LIQUIDACION_MENSUAL",
            "Disponible" if session.get("existe_liquidacion") else "No existe",
        )

        st.caption(f"Hora de Oracle: {session.get('hora_oracle', 'N/D')}")
        st.dataframe(objects, hide_index=True, width="stretch")
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)
