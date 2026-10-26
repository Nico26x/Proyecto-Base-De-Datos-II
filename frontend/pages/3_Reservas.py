"""Read-only reservation browser."""

from datetime import date, timedelta

import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import (
    buscar_reservas,
    formato_moneda_colombiana,
    obtener_alojamientos,
    obtener_alojamientos_por_municipio,
    obtener_estados_reserva,
    obtener_municipios,
)


st.set_page_config(page_title="Reservas | TurismoUQ", page_icon="TU", layout="wide")


def mostrar_error(error: Exception) -> None:
    if isinstance(error, DatabaseConfigError):
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(error))
    elif isinstance(error, DatabaseError):
        st.error(error.user_message)
        st.caption(f"Detalle técnico: `{error.technical_code}`")
    else:
        st.error("No fue posible consultar las reservas.")


def cambiar_municipio() -> None:
    st.session_state["reservas_alojamiento"] = None


st.title("Reservas")
st.caption("Consulta y filtra las reservas registradas en TurismoUQ.")
st.info(
    "Vista de solo lectura. Cada fila representa una habitación asignada a una reserva."
)

try:
    estados = obtener_estados_reserva()
    municipios = obtener_municipios()
except (DatabaseConfigError, DatabaseError) as exc:
    mostrar_error(exc)
    st.stop()

municipality_labels = {row["id_municipio"]: row["nombre"] for row in municipios}
selected_municipality = st.selectbox(
    "Municipio",
    options=[None, *municipality_labels],
    format_func=lambda value: "Todos" if value is None else municipality_labels[value],
    key="reservas_municipio",
    on_change=cambiar_municipio,
)

try:
    lodgings = (
        obtener_alojamientos_por_municipio(selected_municipality)
        if selected_municipality is not None
        else obtener_alojamientos()
    )
except DatabaseError as exc:
    mostrar_error(exc)
    st.stop()

lodging_labels = {
    row["id_alojamiento"]: (
        f"{row['nombre']} · {row['tipo']}"
        + (f" · {row['municipio']}" if row.get("municipio") else "")
    )
    for row in lodgings
}

with st.form("form_buscar_reservas"):
    first_column, second_column, third_column = st.columns([1, 1.4, 1])
    with first_column:
        selected_status = st.selectbox(
            "Estado",
            options=[None, *estados],
            format_func=lambda value: "Todos" if value is None else value,
            key="reservas_estado",
        )
    with second_column:
        selected_lodging = st.selectbox(
            "Alojamiento",
            options=[None, *lodging_labels],
            format_func=lambda value: (
                "Todos" if value is None else lodging_labels[value]
            ),
            key="reservas_alojamiento",
        )
    with third_column:
        selected_limit = st.selectbox(
            "Límite de filas",
            options=[50, 100, 250, 500],
            index=1,
            key="reservas_limite",
        )

    client_text = st.text_input(
        "Cliente",
        placeholder="Nombre o identificación",
        key="reservas_cliente_texto",
    )

    date_from_column, date_to_column = st.columns(2)
    with date_from_column:
        use_date_from = st.checkbox(
            "Filtrar check-in desde",
            key="reservas_usar_fecha_desde",
        )
        selected_date_from = st.date_input(
            "Fecha inicial",
            value=date.today() - timedelta(days=30),
            disabled=not use_date_from,
            key="reservas_fecha_desde",
        )
    with date_to_column:
        use_date_to = st.checkbox(
            "Filtrar check-in hasta",
            key="reservas_usar_fecha_hasta",
        )
        selected_date_to = st.date_input(
            "Fecha final",
            value=date.today(),
            disabled=not use_date_to,
            key="reservas_fecha_hasta",
        )

    submitted = st.form_submit_button(
        "Buscar reservas",
        type="primary",
        width="stretch",
    )

invalid_range = (
    use_date_from
    and use_date_to
    and selected_date_from > selected_date_to
)

if submitted and invalid_range:
    st.warning("La fecha inicial no puede ser posterior a la fecha final.")
elif submitted:
    try:
        with st.spinner("Consultando reservas en Oracle..."):
            st.session_state["reservas_resultado"] = buscar_reservas(
                estado=selected_status,
                id_municipio=selected_municipality,
                id_alojamiento=selected_lodging,
                cliente_texto=client_text,
                fecha_desde=selected_date_from if use_date_from else None,
                fecha_hasta=selected_date_to if use_date_to else None,
                limite=selected_limit,
            )
        st.session_state["reservas_limite_aplicado"] = selected_limit
    except DatabaseError as exc:
        mostrar_error(exc)

if "reservas_resultado" not in st.session_state:
    try:
        with st.spinner("Cargando las reservas más recientes..."):
            st.session_state["reservas_resultado"] = buscar_reservas(limite=100)
        st.session_state["reservas_limite_aplicado"] = 100
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)
        st.stop()

results = st.session_state["reservas_resultado"]
applied_limit = st.session_state.get("reservas_limite_aplicado", 100)

st.divider()
st.subheader("Resultado visible")
st.caption(
    f"Las métricas corresponden a las filas devueltas, con un límite de {applied_limit}."
)

if results.empty:
    st.info("No se encontraron reservas con los filtros seleccionados.")
else:
    metric_columns = st.columns(4)
    metric_columns[0].metric("Filas mostradas", len(results))
    metric_columns[1].metric(
        "Reservas distintas", int(results["id_reserva"].nunique())
    )
    metric_columns[2].metric(
        "Noches visibles", int(results["noches"].sum())
    )
    metric_columns[3].metric(
        "Subtotales visibles",
        formato_moneda_colombiana(results["subtotal"].sum()),
    )

    display = results.rename(
        columns={
            "id_reserva": "Reserva",
            "fecha_reserva": "Creada",
            "cliente": "Cliente",
            "identificacion": "Identificación",
            "municipio": "Municipio",
            "alojamiento": "Alojamiento",
            "habitacion": "Habitación",
            "fecha_checkin": "Check-in",
            "fecha_checkout": "Checkout",
            "noches": "Noches",
            "estado": "Estado",
            "subtotal": "Subtotal",
        }
    )
    styled = display.style.format(
        {"Subtotal": formato_moneda_colombiana},
        na_rep="",
    )
    st.dataframe(
        styled,
        hide_index=True,
        width="stretch",
        height=min(620, 80 + 35 * len(display)),
        column_config={
            "Reserva": st.column_config.NumberColumn(format="%d"),
            "Creada": st.column_config.DatetimeColumn(format="DD/MM/YYYY HH:mm"),
            "Check-in": st.column_config.DateColumn(format="DD/MM/YYYY"),
            "Checkout": st.column_config.DateColumn(format="DD/MM/YYYY"),
            "Noches": st.column_config.NumberColumn(format="%d"),
        },
    )
