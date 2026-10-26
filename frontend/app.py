"""TurismoUQ Streamlit entry point."""

import streamlit as st

from db import DatabaseConfigError, DatabaseError
from services import probar_conexion


st.set_page_config(
    page_title="TurismoUQ",
    page_icon="TU",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown(
    """
    <style>
        .block-container {max-width: 1180px; padding-top: 2.5rem;}
        [data-testid="stMetric"] {
            border: 1px solid rgba(128, 128, 128, 0.22);
            border-radius: 0.65rem;
            padding: 0.85rem 1rem;
        }
    </style>
    """,
    unsafe_allow_html=True,
)

st.sidebar.title("TurismoUQ")
st.sidebar.caption("Demostración académica sobre Oracle Database 21c XE")

st.title("TurismoUQ")
st.subheader("Plataforma de demostración para la gestión turística")
st.write(
    "Esta interfaz presenta los datos y componentes PL/SQL desarrollados para "
    "Bases de Datos II. Oracle conserva la validación, el cálculo de estadías, "
    "la disponibilidad, la auditoría y la liquidación mensual."
)

st.divider()

connection_column, architecture_column = st.columns([1, 2])

with connection_column:
    st.markdown("### Conexión")
    try:
        session = probar_conexion()
        st.success("Oracle XE conectado")
        st.caption(f"Sesión: `{session['usuario']}`")
    except DatabaseConfigError as exc:
        st.error("La configuración de Oracle está incompleta.")
        st.caption(str(exc))
    except DatabaseError as exc:
        st.error(exc.user_message)
        st.caption(f"Detalle técnico: `{exc.technical_code}`")

with architecture_column:
    st.markdown("### Arquitectura")
    st.info(
        "Streamlit actúa como capa de presentación. Las consultas se ejecutan "
        "con bind variables y las operaciones de negocio se delegan a "
        "`FN_VALOR_ESTADIA` y `PKG_TURISMO`."
    )

st.markdown("### Navegación")
st.write(
    "Usa la barra lateral para abrir el Dashboard o Crear reserva. Los módulos "
    "de consulta, liquidación y auditoría se incorporarán en las siguientes fases."
)

st.caption(
    "Proyecto TurismoUQ | Universidad del Quindío | Base de Datos II"
)
