"""Read-only browser for tariff audit records."""

from datetime import date, timedelta

import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import (
    buscar_auditorias,
    formato_moneda_colombiana,
    obtener_estado_trigger_auditoria,
    obtener_operaciones_auditoria,
    obtener_resumen_auditoria,
    obtener_usuarios_auditoria,
)


st.set_page_config(page_title="Auditoría | TurismoUQ", page_icon="TU", layout="wide")


def mostrar_error(error: Exception) -> None:
    if isinstance(error, DatabaseConfigError):
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(error))
    elif isinstance(error, DatabaseError):
        st.error(error.user_message)
        st.caption(f"Detalle técnico: `{error.technical_code}`")
    else:
        st.error("No fue posible consultar la auditoría de tarifas.")


st.title("Auditoría de tarifas")
st.caption(
    "Consulta el historial de cambios registrados automáticamente sobre las tarifas."
)
st.info("Vista de solo lectura. Esta pantalla no modifica tarifas ni auditorías.")

with st.expander("¿Cómo funciona esta auditoría?", expanded=False):
    st.write(
        "`TRG_AUDITORIA_TARIFA` vigila operaciones `INSERT`, `UPDATE` y `DELETE` "
        "sobre `TARIFA`. Por cada tarifa afectada conserva el usuario Oracle, la "
        "fecha del cambio y los valores anterior y nuevo."
    )
    st.write(
        "Es un compound trigger: captura `OLD` y `NEW` por cada fila y escribe las "
        "auditorías después de finalizar la sentencia. La auditoría participa en la "
        "misma transacción; si el DML se revierte con `ROLLBACK`, sus registros de "
        "auditoría también se revierten."
    )

try:
    trigger = obtener_estado_trigger_auditoria()
    operations = obtener_operaciones_auditoria()
    users = obtener_usuarios_auditoria()
except (DatabaseConfigError, DatabaseError) as exc:
    mostrar_error(exc)
    st.stop()

st.subheader("Estado del trigger")
trigger_columns = st.columns(3)
trigger_columns[0].metric("Nombre", trigger["nombre"])
trigger_columns[1].metric("Tipo", trigger["tipo"])
trigger_columns[2].metric("Estado", trigger["estado"])

st.divider()
st.subheader("Filtros")

with st.form("form_buscar_auditorias"):
    operation_column, user_column, limit_column = st.columns([1, 1.5, 1])
    with operation_column:
        selected_operation = st.selectbox(
            "Operación",
            options=[None, *operations],
            format_func=lambda value: "Todas" if value is None else value,
            key="auditoria_operacion",
        )
    with user_column:
        selected_user = st.selectbox(
            "Usuario Oracle",
            options=[None, *users],
            format_func=lambda value: "Todos" if value is None else value,
            key="auditoria_usuario",
        )
    with limit_column:
        selected_limit = st.selectbox(
            "Límite de filas",
            options=[50, 100, 250, 500],
            index=1,
            key="auditoria_limite",
        )

    date_from_column, date_to_column = st.columns(2)
    with date_from_column:
        use_date_from = st.checkbox(
            "Filtrar fecha desde",
            key="auditoria_usar_fecha_desde",
        )
        selected_date_from = st.date_input(
            "Fecha desde",
            value=date.today() - timedelta(days=30),
            key="auditoria_fecha_desde",
        )
    with date_to_column:
        use_date_to = st.checkbox(
            "Filtrar fecha hasta",
            key="auditoria_usar_fecha_hasta",
        )
        selected_date_to = st.date_input(
            "Fecha hasta",
            value=date.today(),
            key="auditoria_fecha_hasta",
        )

    tariff_column, room_column = st.columns(2)
    with tariff_column:
        use_tariff = st.checkbox(
            "Filtrar por ID tarifa",
            key="auditoria_usar_tarifa",
        )
        selected_tariff = st.number_input(
            "ID tarifa",
            min_value=1,
            value=1,
            step=1,
            key="auditoria_tarifa",
        )
    with room_column:
        use_room = st.checkbox(
            "Filtrar por ID habitación",
            key="auditoria_usar_habitacion",
        )
        selected_room = st.number_input(
            "ID habitación",
            min_value=1,
            value=1,
            step=1,
            key="auditoria_habitacion",
        )

    search_column, refresh_column = st.columns(2)
    submitted = search_column.form_submit_button(
        "Buscar auditorías",
        type="primary",
        width="stretch",
    )
    refreshed = refresh_column.form_submit_button(
        "Actualizar",
        width="stretch",
    )

invalid_range = (
    use_date_from
    and use_date_to
    and selected_date_from > selected_date_to
)

if (submitted or refreshed) and invalid_range:
    st.warning("La fecha inicial no puede ser posterior a la fecha final.")
elif submitted or refreshed:
    try:
        with st.spinner("Consultando auditorías en Oracle..."):
            st.session_state["auditoria_resultado"] = buscar_auditorias(
                operacion=selected_operation,
                usuario=selected_user,
                fecha_desde=selected_date_from if use_date_from else None,
                fecha_hasta=selected_date_to if use_date_to else None,
                id_tarifa=int(selected_tariff) if use_tariff else None,
                id_habitacion=int(selected_room) if use_room else None,
                limite=selected_limit,
            )
        st.session_state["auditoria_limite_aplicado"] = selected_limit
        st.session_state["auditoria_hay_filtros"] = any(
            [
                selected_operation,
                selected_user,
                use_date_from,
                use_date_to,
                use_tariff,
                use_room,
            ]
        )
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)

if "auditoria_resultado" not in st.session_state:
    try:
        with st.spinner("Cargando las auditorías más recientes..."):
            st.session_state["auditoria_resultado"] = buscar_auditorias(limite=100)
        st.session_state["auditoria_limite_aplicado"] = 100
        st.session_state["auditoria_hay_filtros"] = False
    except (DatabaseConfigError, DatabaseError) as exc:
        mostrar_error(exc)
        st.stop()

results = st.session_state["auditoria_resultado"]
applied_limit = st.session_state.get("auditoria_limite_aplicado", 100)
has_filters = st.session_state.get("auditoria_hay_filtros", False)

st.divider()
st.subheader("Resultado visible")
st.caption(
    f"Las métricas corresponden solo a las filas visibles, con un límite de "
    f"{applied_limit}; no representan totales históricos."
)

if results.empty:
    if has_filters:
        st.info("No se encontraron auditorías con los filtros seleccionados.")
    else:
        st.info("Todavía no existen registros de auditoría.")
        st.caption(
            "Los registros aparecerán cuando se inserte, modifique o elimine una tarifa."
        )
else:
    summary = obtener_resumen_auditoria(results)
    metric_columns = st.columns(5)
    metric_columns[0].metric("Registros mostrados", summary["registros"])
    metric_columns[1].metric("INSERT", summary["insert"])
    metric_columns[2].metric("UPDATE", summary["update"])
    metric_columns[3].metric("DELETE", summary["delete"])
    metric_columns[4].metric("Usuarios distintos", summary["usuarios"])

    display = results.rename(
        columns={
            "id_auditoria": "ID auditoría",
            "fecha_cambio": "Fecha",
            "usuario_bd": "Usuario",
            "operacion": "Operación",
            "id_tarifa": "ID tarifa",
            "id_habitacion": "ID habitación",
            "habitacion": "Habitación",
            "alojamiento": "Alojamiento",
            "municipio": "Municipio",
            "id_temporada": "ID temporada",
            "temporada": "Temporada",
            "valor_anterior": "Valor anterior",
            "valor_nuevo": "Valor nuevo",
            "variacion": "Variación",
        }
    )
    styled = display.style.format(
        {
            "Valor anterior": formato_moneda_colombiana,
            "Valor nuevo": formato_moneda_colombiana,
            "Variación": formato_moneda_colombiana,
        },
        na_rep="—",
    )
    st.dataframe(
        styled,
        hide_index=True,
        width="stretch",
        height=min(620, 80 + 35 * len(display)),
        column_config={
            "ID auditoría": st.column_config.NumberColumn(format="%d"),
            "Fecha": st.column_config.DatetimeColumn(format="DD/MM/YYYY HH:mm:ss"),
            "ID tarifa": st.column_config.NumberColumn(format="%d"),
            "ID habitación": st.column_config.NumberColumn(format="%d"),
            "ID temporada": st.column_config.NumberColumn(format="%d"),
        },
    )

st.caption(
    "Para una demostración en vivo, puede realizarse un cambio controlado sobre "
    "TARIFA desde SQL Developer y después pulsar Actualizar. El cambio debe estar "
    "confirmado con COMMIT para que la sesión de Streamlit pueda verlo."
)
