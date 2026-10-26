"""Small Oracle access layer shared by the Streamlit application."""

from __future__ import annotations

import os
from collections.abc import Sequence
from typing import Any

import oracledb
import streamlit as st


class DatabaseConfigError(RuntimeError):
    """Raised when the local Oracle configuration is incomplete."""


class DatabaseError(RuntimeError):
    """Safe application error that preserves Oracle diagnostic information."""

    def __init__(
        self,
        user_message: str,
        *,
        code: int | None = None,
        full_code: str | None = None,
        oracle_message: str | None = None,
    ) -> None:
        super().__init__(user_message)
        self.user_message = user_message
        self.code = code
        self.full_code = full_code
        self.oracle_message = oracle_message

    @property
    def technical_code(self) -> str:
        if self.full_code:
            return self.full_code
        if self.code:
            return f"ORA-{self.code:05d}"
        return "ORACLE"


def _read_config() -> dict[str, str]:
    variable_names = ("ORACLE_USER", "ORACLE_PASSWORD", "ORACLE_DSN")
    values = {name: os.getenv(name, "").strip() for name in variable_names}
    missing = [name for name, value in values.items() if not value]

    if missing:
        raise DatabaseConfigError(
            "Faltan variables de entorno para Oracle: " + ", ".join(missing)
        )

    return values


def _translate_error(exc: oracledb.Error) -> DatabaseError:
    details = exc.args[0] if exc.args else None
    code = getattr(details, "code", None)
    full_code = getattr(details, "full_code", None)
    oracle_message = getattr(details, "message", None) or str(exc)
    normalized_code = full_code or (f"ORA-{code:05d}" if code else "")

    is_connection_error = (
        code == 1017
        or (isinstance(code, int) and 12500 <= code < 12600)
        or normalized_code.startswith("DPY-")
    )

    if is_connection_error:
        user_message = (
            "No fue posible conectar con Oracle. Verifica que XE esté iniciado "
            "y que las variables de conexión sean correctas."
        )
    elif isinstance(code, int) and 20000 <= code <= 20999:
        # RAISE_APPLICATION_ERROR messages are safe business feedback.
        user_message = oracle_message.splitlines()[0]
    else:
        user_message = "No fue posible completar la operación en Oracle."

    return DatabaseError(
        user_message,
        code=code,
        full_code=full_code,
        oracle_message=oracle_message,
    )


@st.cache_resource(show_spinner=False)
def get_pool() -> oracledb.ConnectionPool:
    """Create one process-wide pool; individual connections are never cached."""
    config = _read_config()
    try:
        return oracledb.create_pool(
            user=config["ORACLE_USER"],
            password=config["ORACLE_PASSWORD"],
            dsn=config["ORACLE_DSN"],
            min=1,
            max=4,
            increment=1,
            getmode=oracledb.POOL_GETMODE_WAIT,
        )
    except oracledb.Error as exc:
        raise _translate_error(exc) from exc


def fetch_all(
    sql: str, parameters: dict[str, Any] | None = None
) -> list[dict[str, Any]]:
    """Execute a SELECT and return rows detached from cursor and connection."""
    try:
        with get_pool().acquire() as connection:
            with connection.cursor() as cursor:
                cursor.execute(sql, parameters or {})
                columns = [column[0].lower() for column in cursor.description]
                return [dict(zip(columns, row, strict=True)) for row in cursor]
    except DatabaseConfigError:
        raise
    except oracledb.Error as exc:
        raise _translate_error(exc) from exc


def fetch_one(
    sql: str, parameters: dict[str, Any] | None = None
) -> dict[str, Any] | None:
    rows = fetch_all(sql, parameters)
    return rows[0] if rows else None


def call_function(
    name: str,
    return_type: Any,
    parameters: Sequence[Any] | None = None,
) -> Any:
    """Call a stored function without opening a write transaction."""
    try:
        with get_pool().acquire() as connection:
            with connection.cursor() as cursor:
                return cursor.callfunc(name, return_type, list(parameters or []))
    except DatabaseConfigError:
        raise
    except oracledb.Error as exc:
        raise _translate_error(exc) from exc


def call_procedure(
    name: str,
    input_parameters: Sequence[Any] | None = None,
    output_types: Sequence[Any] | None = None,
) -> list[Any]:
    """Call a procedure transactionally and return trailing OUT values."""
    try:
        with get_pool().acquire() as connection:
            try:
                with connection.cursor() as cursor:
                    output_variables = [
                        cursor.var(output_type) for output_type in (output_types or [])
                    ]
                    cursor.callproc(
                        name,
                        [*(input_parameters or []), *output_variables],
                    )
                    output_values = [variable.getvalue() for variable in output_variables]
                connection.commit()
                return output_values
            except Exception:
                connection.rollback()
                raise
    except DatabaseConfigError:
        raise
    except oracledb.Error as exc:
        raise _translate_error(exc) from exc


def test_connection() -> dict[str, Any]:
    row = fetch_one(
        """
        SELECT SYS_CONTEXT('USERENV', 'SESSION_USER') AS usuario,
               SYSTIMESTAMP AS hora_oracle
          FROM dual
        """
    )
    if row is None:
        raise DatabaseError("Oracle no devolvió información de sesión.")
    return row
