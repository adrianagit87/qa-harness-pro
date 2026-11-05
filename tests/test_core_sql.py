#!/usr/bin/env python3
"""Gate de SQL: solo la base de prueba declarada, solo pg_execute_query, solo leer."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.gates import sql  # noqa: E402

CONFIG = {
    "environments": {
        "list": [
            {"key": "DEV", "database": "postgres-dev", "production": False},
            {"key": "STG", "urls": ["https://stg.acme.test"]},
            {"key": "PROD", "database": "postgres-prod", "production": True},
        ]
    }
}
BASES = sql.bases_de_config(CONFIG)
LEER = "mcp__postgres-dev__pg_execute_query"


def consulta(query: str, **extra: object) -> dict:
    return {"operation": "select", "query": query, **extra}


class QueBase(unittest.TestCase):
    def test_la_config_separa_prueba_de_produccion(self) -> None:
        self.assertEqual(BASES.prueba, frozenset({"postgres-dev"}))
        self.assertEqual(BASES.produccion, frozenset({"postgres-prod"}))

    def test_una_base_declarada_en_produccion_es_produccion(self) -> None:
        config = {"environments": {"list": [
            {"key": "A", "database": "pg-x"},
            {"key": "B", "database": "pg-x", "production": True},
        ]}}
        bases = sql.bases_de_config(config)
        self.assertEqual(bases.prueba, frozenset())
        self.assertEqual(bases.produccion, frozenset({"pg-x"}))

    def test_la_base_de_prueba_se_lee(self) -> None:
        self.assertEqual(sql.revisar_accion(LEER, consulta("SELECT id FROM botones"), BASES).decision, "permitir")

    def test_produccion_se_bloquea_siempre_aunque_sea_un_select(self) -> None:
        veredicto = sql.revisar_accion("mcp__postgres-prod__pg_execute_query", consulta("SELECT 1"), BASES)
        self.assertTrue(veredicto.bloquea)
        self.assertIn("PRODUCCIÓN", veredicto.motivo)

    def test_un_server_no_declarado_se_bloquea(self) -> None:
        self.assertTrue(sql.revisar_accion("mcp__postgres-otro__pg_execute_query", consulta("SELECT 1"), BASES).bloquea)

    def test_sin_config_falla_cerrado(self) -> None:
        self.assertTrue(sql.revisar_accion(LEER, consulta("SELECT 1"), sql.Bases(error="sin config")).bloquea)

    def test_lo_que_no_es_de_postgres_no_es_asunto_de_este_gate(self) -> None:
        for nombre in ("mcp__playwright__browser_click", "Bash", None, "mcp__postgres-dev__query"):
            with self.subTest(nombre=nombre):
                self.assertTrue(sql.revisar_accion(nombre, {}, BASES).se_abstiene)


class QueHerramienta(unittest.TestCase):
    def test_solo_pg_execute_query(self) -> None:
        for tool in ("pg_execute_sql", "pg_execute_mutation", "pg_manage_users", "pg_manage_schema",
                     "pg_import_table_data", "pg_copy_between_databases", "pg_export_table_data"):
            with self.subTest(tool=tool):
                self.assertTrue(sql.revisar_accion(f"mcp__postgres-dev__{tool}", consulta("SELECT 1"), BASES).bloquea)

    def test_connection_string_se_rechaza_aunque_este_vacio(self) -> None:
        for valor in ("postgresql://u:p@prod/db", ""):
            with self.subTest(valor=valor):
                veredicto = sql.revisar_accion(LEER, consulta("SELECT 1", connectionString=valor), BASES)
                self.assertTrue(veredicto.bloquea)
                self.assertIn("connectionString", veredicto.motivo)

    def test_operation_tiene_que_ser_de_lectura(self) -> None:
        self.assertTrue(sql.revisar_accion(LEER, {"operation": "delete", "query": "SELECT 1"}, BASES).bloquea)
        self.assertTrue(sql.revisar_accion(LEER, "SELECT 1", BASES).bloquea)
        for operacion in ("select", "count", "exists"):
            with self.subTest(operacion=operacion):
                entrada = {"operation": operacion, "query": "SELECT 1"}
                self.assertEqual(sql.revisar_accion(LEER, entrada, BASES).decision, "permitir")


class QueConsulta(unittest.TestCase):
    def permite(self, query: str) -> bool:
        return sql.revisar_consulta(query).decision == "permitir"

    def test_lecturas_normales_pasan(self) -> None:
        for query in (
            "SELECT * FROM botones WHERE cliente_id = $1",
            "select count(*) from botones;",
            "WITH x AS (SELECT id FROM t) SELECT * FROM x",
            "(SELECT 1) UNION (SELECT 2)",
            "SELECT id FROM t WHERE estado = 'deleted' AND nota = 'update; drop table x'",
            'SELECT "update", comment, lock FROM t -- insert en un comentario',
            "SELECT id /* delete */ FROM t ORDER BY id LIMIT 10",
            "SELECT * FROM t WHERE nombre = 'O''Brien'",
        ):
            with self.subTest(query=query):
                self.assertTrue(self.permite(query), sql.revisar_consulta(query).motivo)

    def test_escrituras_y_bloqueos_se_frenan(self) -> None:
        for query in (
            "UPDATE botones SET nombre = 'x'",
            "DELETE FROM botones",
            "DROP TABLE botones",
            "INSERT INTO t VALUES (1)",
            "WITH borrado AS (DELETE FROM t RETURNING *) SELECT * FROM borrado",
            "WITH x AS (UPDATE t SET a = 1 RETURNING a) SELECT a FROM x",
            "SELECT * INTO copia FROM t",
            "SELECT * FROM t FOR UPDATE",
            "SELECT * FROM t FOR NO KEY UPDATE",
            "SELECT * FROM t FOR SHARE",
            "SELECT * FROM t FOR KEY SHARE",
            "MERGE INTO t USING s ON true WHEN MATCHED THEN DELETE",
            "SET ROLE postgres",
            "EXPLAIN ANALYZE DELETE FROM t",
        ):
            with self.subTest(query=query):
                self.assertFalse(self.permite(query))

    def test_mas_de_una_sentencia_se_frena(self) -> None:
        for query in ("SELECT 1; DELETE FROM t", "SELECT 1;;", "SELECT 1; SELECT 2"):
            with self.subTest(query=query):
                self.assertFalse(self.permite(query))

    def test_funciones_peligrosas_se_frenan(self) -> None:
        for query in (
            "SELECT pg_read_file('/etc/passwd')",
            "SELECT * FROM dblink('host=prod', 'DELETE FROM t') AS x(a int)",
            "SELECT query_to_xml('DELETE FROM t', true, false, '')",
            "SELECT set_config('role', 'postgres', false)",
            "SELECT nextval('seq')",
            "SELECT pg_sleep(600)",
            "SELECT pg_terminate_backend(123)",
            "SELECT lo_import('/etc/passwd')",
            "SELECT pg_advisory_lock(1)",
            "SELECT pg_ls_dir('.')",
        ):
            with self.subTest(query=query):
                self.assertFalse(self.permite(query))

    def test_lo_que_no_se_puede_revisar_se_frena(self) -> None:
        for query in (
            "",
            "   ",
            None,
            "SELECT $$; DELETE FROM t; $$",
            "SELECT $tag$x$tag$",
            "SELECT 'sin cerrar",
            'SELECT "sin cerrar',
            "SELECT 1 /* sin cerrar",
            "SELECT 1 /* a /* anidado */ DELETE */",
            "SELECT " + "x," * 10_000 + "1",
        ):
            with self.subTest(query=str(query)[:40]):
                self.assertFalse(self.permite(query))


if __name__ == "__main__":
    unittest.main(verbosity=2)
