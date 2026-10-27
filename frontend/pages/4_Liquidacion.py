"""Monthly settlement generation and read-only result view."""

from datetime import date

import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import (
    formato_moneda_colombiana,
    generar_liquidacion,
    mensaje_error_liquidacion,
    obtener_liquidacion_periodo,
    obtener_resumen_liquidacion,
)


st.set_page_config(page_title="Liquidación | TurismoUQ", page_icon="TU", layout="wide")

MESES = {
    1: "Enero",
    2: "Febrero",
    3: "Marzo",
    4: "Abril",
    5: "Mayo",
    6: "Junio",
    7: "Julio",
    8: "Agosto",
    9: "Septiembre",
    10: "Octubre",
    11: "Noviembre",
    12: "Diciembre",
}


def mostrar_error(error: Exception) -> None:
    if isinstance(error, DatabaseConfigError):
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(error))
    elif isinstance(error, DatabaseError):
        st.error(mensaje_error_liquidacion(error))
        st.caption(f"Detalle técnico: `{error.technical_code}`")
    else:
        st.error("No fue posible procesar la liquidación.")


def cambiar_periodo() -> None:
    st.session_state.pop("liquidacion_datos", None)
    st.session_state.pop("liquidacion_resumen", None)
    st.session_state.pop("liquidacion_periodo_cargado", None)
    st.session_state.pop("liquidacion_procesados", None)
    st.session_state.pop("liquidacion_mensaje", None)
    st.session_state["liquidacion_confirmar"] = False


def cargar_periodo(anio: int, mes: int) -> None:
    st.session_state["liquidacion_datos"] = obtener_liquidacion_periodo(anio, mes)
    st.session_state["liquidacion_resumen"] = obtener_resumen_liquidacion(anio, mes)
    st.session_state["liquidacion_periodo_cargado"] = (anio, mes)


current_date = date.today()
st.title("Liquidación mensual")
st.caption("Genera y consulta el consolidado mensual de ingresos por alojamiento.")

with st.expander("¿Qué ejecuta esta pantalla?", expanded=False):
    st.write(
        "La interfaz llama a `PKG_TURISMO.SP_LIQUIDAR_MES`. El procedimiento "
        "usa un cursor explícito parametrizado para procesar los alojamientos y "
        "guardar el consolidado en `LIQUIDACION_MENSUAL`. Python no calcula "
        "ingresos, noches ni reglas del periodo; únicamente presenta el resultado."
    )

st.subheader("Selección del periodo")
period_column, month_column, consult_column = st.columns([1, 1.2, 1])
with period_column:
    selected_year = st.number_input(
        "Año",
        min_value=2000,
        max_value=2100,
        value=current_date.year,
        step=1,
        key="liquidacion_anio",
        on_change=cambiar_periodo,
    )
with month_column:
    selected_month = st.selectbox(
        "Mes",
        options=list(MESES),
        index=current_date.month - 1,
        format_func=lambda value: MESES[value],
        key="liquidacion_mes",
        on_change=cambiar_periodo,
    )
with consult_column:
    st.write("")
    st.write("")
    consult = st.button("Consultar periodo", width="stretch")

if consult:
    try:
        with st.spinner("Consultando liquidación en Oracle..."):
            cargar_periodo(int(selected_year), int(selected_month))
        st.session_state["liquidacion_procesados"] = None
        st.session_state["liquidacion_mensaje"] = None
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)

st.warning(
    "Si este periodo ya fue liquidado, el resultado anterior será reemplazado."
)
confirmed = st.checkbox(
    "Confirmo que deseo recalcular este periodo",
    key="liquidacion_confirmar",
)

generate = st.button(
    "Generar liquidación",
    type="primary",
    disabled=not confirmed,
    width="stretch",
)

if generate:
    try:
        with st.spinner("Oracle está procesando los alojamientos..."):
            processed = generar_liquidacion(int(selected_year), int(selected_month))
            cargar_periodo(int(selected_year), int(selected_month))
        st.session_state["liquidacion_procesados"] = processed
        if processed == 0:
            st.session_state["liquidacion_mensaje"] = (
                "El periodo no tiene movimientos para liquidar."
            )
        else:
            st.session_state["liquidacion_mensaje"] = (
                f"Liquidación generada correctamente para {processed} alojamiento(s)."
            )
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)

loaded_period = st.session_state.get("liquidacion_periodo_cargado")
selected_period = (int(selected_year), int(selected_month))

if loaded_period == selected_period:
    data = st.session_state["liquidacion_datos"]
    summary = st.session_state["liquidacion_resumen"]
    message = st.session_state.get("liquidacion_mensaje")
    processed = st.session_state.get("liquidacion_procesados")

    if message:
        if processed == 0:
            st.info(message)
        else:
            st.success(message)

    st.divider()
    st.subheader(f"Resultado: {MESES[selected_month]} de {selected_year}")

    if data.empty:
        st.info("No hay liquidación registrada para este periodo.")
    else:
        if processed is None:
            st.info("Este periodo ya tiene una liquidación registrada.")

        metric_columns = st.columns(5)
        metric_columns[0].metric(
            "Alojamientos procesados",
            int(processed if processed is not None else summary["alojamientos"]),
        )
        metric_columns[1].metric("Noches", int(summary["noches"]))
        metric_columns[2].metric(
            "Ingreso habitaciones",
            formato_moneda_colombiana(summary["ingreso_habitaciones"]),
        )
        metric_columns[3].metric(
            "Ingreso servicios",
            formato_moneda_colombiana(summary["ingreso_servicios"]),
        )
        metric_columns[4].metric(
            "Total del periodo",
            formato_moneda_colombiana(summary["total"]),
        )

        display = data.drop(columns=["id_alojamiento"]).rename(
            columns={
                "municipio": "Municipio",
                "alojamiento": "Alojamiento",
                "periodo": "Periodo",
                "noches": "Noches",
                "ingreso_habitaciones": "Ingreso habitaciones",
                "ingreso_servicios": "Ingreso servicios",
                "total": "Total",
                "fecha_generacion": "Fecha generación",
            }
        )
        styled = display.style.format(
            {
                "Ingreso habitaciones": formato_moneda_colombiana,
                "Ingreso servicios": formato_moneda_colombiana,
                "Total": formato_moneda_colombiana,
            },
            na_rep="",
        )
        st.dataframe(
            styled,
            hide_index=True,
            width="stretch",
            height=min(620, 80 + 35 * len(display)),
            column_config={
                "Periodo": st.column_config.DateColumn(format="MM/YYYY"),
                "Noches": st.column_config.NumberColumn(format="%d"),
                "Fecha generación": st.column_config.DatetimeColumn(
                    format="DD/MM/YYYY HH:mm:ss"
                ),
            },
        )

        st.subheader("Total por alojamiento")
        chart_data = (
            data.sort_values("total", ascending=False)
            .head(10)[["alojamiento", "total"]]
            .copy()
        )
        chart_data["total"] = chart_data["total"].astype(float)
        st.bar_chart(
            chart_data,
            x="alojamiento",
            y="total",
            horizontal=True,
            color="#246B68",
        )
else:
    st.info("Consulta un periodo para visualizar una liquidación existente.")
