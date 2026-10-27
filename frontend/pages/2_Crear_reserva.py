"""Interactive reservation creation backed entirely by PKG_TURISMO."""

from datetime import date, timedelta

import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import (
    calcular_valor_estadia,
    crear_reserva,
    formato_moneda_colombiana,
    mensaje_error_reserva,
    obtener_alojamientos_por_municipio,
    obtener_clientes,
    obtener_habitaciones_por_alojamiento,
    obtener_municipios,
)


st.set_page_config(page_title="Crear reserva | TurismoUQ", page_icon="TU", layout="wide")


def invalidar_cotizacion() -> None:
    if st.session_state.get("reserva_cotizacion") is not None:
        st.session_state["reserva_cotizacion_desactualizada"] = True
    st.session_state["reserva_cotizacion"] = None


def cambiar_municipio() -> None:
    st.session_state["reserva_alojamiento"] = None
    st.session_state["reserva_habitacion"] = None
    st.session_state["reserva_huespedes"] = 1
    invalidar_cotizacion()


def cambiar_alojamiento() -> None:
    st.session_state["reserva_habitacion"] = None
    st.session_state["reserva_huespedes"] = 1
    invalidar_cotizacion()


def cambiar_habitacion() -> None:
    st.session_state["reserva_huespedes"] = 1
    invalidar_cotizacion()


def mostrar_error(error: Exception) -> None:
    if isinstance(error, DatabaseConfigError):
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(error))
    elif isinstance(error, DatabaseError):
        st.error(mensaje_error_reserva(error))
        st.caption(f"Detalle técnico: `{error.technical_code}`")
    else:
        st.error("No fue posible completar la operación.")


state_defaults = {
    "reserva_cotizacion": None,
    "reserva_cotizacion_desactualizada": False,
    "reserva_ultima_creada": None,
    "reserva_fecha_in": date.today(),
    "reserva_fecha_out": date.today() + timedelta(days=1),
    "reserva_huespedes": 1,
}
for key, default in state_defaults.items():
    if key not in st.session_state:
        st.session_state[key] = default

st.title("Crear reserva")
st.caption(
    "Selecciona los datos de la estadía. Oracle calcula el valor y valida "
    "definitivamente la disponibilidad al crear la reserva."
)

last_reservation = st.session_state.get("reserva_ultima_creada")
if last_reservation:
    st.success(f"Reserva #{last_reservation['id_reserva']} creada correctamente")
    st.write(
        f"Habitación **{last_reservation['habitacion']}** · "
        f"{last_reservation['fecha_in']:%d/%m/%Y} al "
        f"{last_reservation['fecha_out']:%d/%m/%Y} · "
        f"{last_reservation['huespedes']} huésped(es) · "
        f"**{formato_moneda_colombiana(last_reservation['valor'])}**"
    )

try:
    clientes = obtener_clientes()
    municipios = obtener_municipios()
except (DatabaseConfigError, DatabaseError) as exc:
    mostrar_error(exc)
    st.stop()

client_labels = {
    row["id_cliente"]: (
        f"{row['id_cliente']} - {row['nombre_completo']} - "
        f"{row['tipo_identificacion']} {row['identificacion']}"
    )
    for row in clientes
}
municipality_labels = {row["id_municipio"]: row["nombre"] for row in municipios}

st.subheader("1. Cliente y ubicación")
client_column, municipality_column = st.columns(2)
with client_column:
    id_cliente = st.selectbox(
        "Cliente",
        options=list(client_labels),
        index=None,
        placeholder="Selecciona un cliente",
        format_func=lambda value: client_labels[value],
        key="reserva_cliente",
    )
with municipality_column:
    id_municipio = st.selectbox(
        "Municipio",
        options=list(municipality_labels),
        index=None,
        placeholder="Selecciona un municipio",
        format_func=lambda value: municipality_labels[value],
        key="reserva_municipio",
        on_change=cambiar_municipio,
    )

try:
    alojamientos = (
        obtener_alojamientos_por_municipio(id_municipio) if id_municipio else []
    )
except DatabaseError as exc:
    mostrar_error(exc)
    st.stop()

lodging_labels = {
    row["id_alojamiento"]: f"{row['nombre']} · {row['tipo']}"
    for row in alojamientos
}
id_alojamiento = st.selectbox(
    "Alojamiento",
    options=list(lodging_labels),
    index=None,
    placeholder=(
        "Selecciona un alojamiento"
        if id_municipio
        else "Primero selecciona un municipio"
    ),
    format_func=lambda value: lodging_labels[value],
    key="reserva_alojamiento",
    disabled=not id_municipio,
    on_change=cambiar_alojamiento,
)

try:
    habitaciones = (
        obtener_habitaciones_por_alojamiento(id_alojamiento)
        if id_alojamiento
        else []
    )
except DatabaseError as exc:
    mostrar_error(exc)
    st.stop()

room_by_id = {row["id_habitacion"]: row for row in habitaciones}
room_labels = {
    row["id_habitacion"]: f"Habitación {row['numero']} · capacidad {row['capacidad']}"
    for row in habitaciones
}

st.subheader("2. Habitación y fechas")
room_column, guests_column = st.columns([2, 1])
with room_column:
    id_habitacion = st.selectbox(
        "Habitación",
        options=list(room_labels),
        index=None,
        placeholder=(
            "Selecciona una habitación"
            if id_alojamiento
            else "Primero selecciona un alojamiento"
        ),
        format_func=lambda value: room_labels[value],
        key="reserva_habitacion",
        disabled=not id_alojamiento,
        on_change=cambiar_habitacion,
    )

selected_room = room_by_id.get(id_habitacion)
capacity = int(selected_room["capacidad"]) if selected_room else 1
with guests_column:
    huespedes = st.number_input(
        "Número de huéspedes",
        min_value=1,
        max_value=max(capacity, 1),
        step=1,
        key="reserva_huespedes",
        disabled=selected_room is None,
    )

date_in_column, date_out_column = st.columns(2)
with date_in_column:
    fecha_in = st.date_input(
        "Check-in",
        key="reserva_fecha_in",
        on_change=invalidar_cotizacion,
    )
with date_out_column:
    fecha_out = st.date_input(
        "Checkout",
        key="reserva_fecha_out",
        on_change=invalidar_cotizacion,
    )

valid_dates = fecha_out > fecha_in
if not valid_dates:
    st.warning("El checkout debe ser posterior al check-in.")

if st.session_state.get("reserva_cotizacion_desactualizada"):
    st.warning("Los datos cambiaron después de cotizar. Calcula nuevamente el valor.")
    st.session_state["reserva_cotizacion_desactualizada"] = False

quote_signature = (id_habitacion, fecha_in, fecha_out)
can_quote = id_habitacion is not None and valid_dates

if st.button("Calcular valor", type="secondary", disabled=not can_quote):
    try:
        with st.spinner("Oracle está calculando la estadía..."):
            value = calcular_valor_estadia(id_habitacion, fecha_in, fecha_out)
        st.session_state["reserva_cotizacion"] = {
            "firma": quote_signature,
            "valor": value,
        }
        st.session_state["reserva_cotizacion_desactualizada"] = False
    except DatabaseError as exc:
        st.session_state["reserva_cotizacion"] = None
        mostrar_error(exc)

quote = st.session_state.get("reserva_cotizacion")
quote_is_current = bool(quote and quote.get("firma") == quote_signature)
if quote_is_current:
    st.subheader("Valor estimado de la estadía")
    st.metric("Cotización Oracle", formato_moneda_colombiana(quote["valor"]))
    st.caption("El valor fue calculado por `PKG_TURISMO.VALOR_ESTADIA`.")

can_create = bool(
    id_cliente is not None
    and id_habitacion is not None
    and valid_dates
    and 1 <= huespedes <= capacity
    and quote_is_current
)

st.subheader("3. Confirmación")
with st.form("form_crear_reserva", clear_on_submit=False):
    if quote_is_current:
        selected_client_label = client_labels.get(id_cliente, "cliente pendiente")
        st.write(
            f"Se creará una reserva para **{selected_client_label}**, en "
            f"**{room_labels[id_habitacion]}**, del **{fecha_in:%d/%m/%Y}** al "
            f"**{fecha_out:%d/%m/%Y}**, por "
            f"**{formato_moneda_colombiana(quote['valor'])}**."
        )
    else:
        st.info("Calcula una cotización vigente antes de crear la reserva.")

    submitted = st.form_submit_button(
        "Crear reserva",
        type="primary",
        disabled=not can_create,
        width="stretch",
    )

if submitted:
    try:
        with st.spinner("Creando reserva en Oracle..."):
            reservation_id = crear_reserva(
                id_cliente,
                id_habitacion,
                fecha_in,
                fecha_out,
                int(huespedes),
            )
        st.session_state["reserva_ultima_creada"] = {
            "id_reserva": reservation_id,
            "habitacion": selected_room["numero"],
            "fecha_in": fecha_in,
            "fecha_out": fecha_out,
            "huespedes": int(huespedes),
            "valor": quote["valor"],
        }
        st.session_state["reserva_cotizacion"] = None
        st.session_state["reserva_cotizacion_desactualizada"] = False
        st.rerun()
    except DatabaseError as exc:
        mostrar_error(exc)
