"""
Migra i dati principali da SQLite a PostgreSQL senza importare l'app Flask.

Uso:
    python migrate_sqlite_to_postgres.py --source "..\\approfittoffro.db"

Richiede:
    - DATABASE_URL puntato al Postgres di destinazione
    - psycopg installato localmente
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from datetime import datetime

import psycopg


TABLES = [
    "users",
    "offers",
    "claims",
    "reviews",
    "user_photos",
    "user_follows",
]


INSERT_COLUMNS = {
    "users": [
        "id",
        "nome",
        "email",
        "password_hash",
        "foto_filename",
        "fascia_eta",
        "eta",
        "numero_telefono",
        "latitudine",
        "longitudine",
        "citta",
        "cibi_preferiti",
        "intolleranze",
        "bio",
        "raggio_azione",
        "verificato",
        "verification_token",
        "is_admin",
        "created_at",
    ],
    "offers": [
        "id",
        "user_id",
        "tipo_pasto",
        "nome_locale",
        "indirizzo",
        "latitudine",
        "longitudine",
        "posti_totali",
        "posti_disponibili",
        "data_ora",
        "descrizione",
        "foto_locale",
        "stato",
        "created_at",
    ],
    "claims": ["id", "user_id", "offer_id", "created_at"],
    "reviews": [
        "id",
        "reviewer_id",
        "reviewed_id",
        "offer_id",
        "rating",
        "commento",
        "created_at",
    ],
    "user_photos": ["id", "user_id", "filename", "position", "created_at"],
    "user_follows": ["id", "follower_id", "followed_id", "created_at"],
}


DELETE_ORDER = [
    "reviews",
    "claims",
    "user_photos",
    "user_follows",
    "offers",
    "users",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Migra i dati da SQLite a PostgreSQL.")
    parser.add_argument(
        "--source",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "approfittoffro.db")),
        help="Percorso del database SQLite sorgente.",
    )
    parser.add_argument(
        "--force-clear",
        action="store_true",
        help="Svuota il database di destinazione prima della migrazione.",
    )
    return parser.parse_args()


def normalize_database_url(database_url: str) -> str:
    if database_url.startswith("postgresql+psycopg://"):
        return "postgresql://" + database_url[len("postgresql+psycopg://"):]
    return database_url


def parse_datetime(value):
    if value in (None, ""):
        return None
    if isinstance(value, datetime):
        return value
    text_value = str(value).strip()
    if not text_value:
        return None
    try:
        return datetime.fromisoformat(text_value)
    except ValueError:
        for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
            try:
                return datetime.strptime(text_value, fmt)
            except ValueError:
                continue
    return text_value


def normalize_row(table_name, row):
    data = dict(row)

    if table_name == "users":
        data["verificato"] = bool(data.get("verificato"))
        data["is_admin"] = bool(data.get("is_admin"))
        data["created_at"] = parse_datetime(data.get("created_at"))
    elif table_name == "offers":
        data["data_ora"] = parse_datetime(data.get("data_ora"))
        data["created_at"] = parse_datetime(data.get("created_at"))
    else:
        data["created_at"] = parse_datetime(data.get("created_at"))

    return data


def fetch_sqlite_rows(source_path, table_name):
    conn = sqlite3.connect(source_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(f"SELECT * FROM {table_name} ORDER BY id ASC").fetchall()
        return [normalize_row(table_name, row) for row in rows]
    finally:
        conn.close()


def ensure_target_is_postgres(database_url):
    lowered = database_url.lower()
    if not (lowered.startswith("postgres://") or lowered.startswith("postgresql://")):
        raise RuntimeError(
            "DATABASE_URL di destinazione non punta a PostgreSQL. Ferma la migrazione."
        )


def table_count(conn, table_name):
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) FROM {table_name}")
        return cur.fetchone()[0]


def ensure_target_empty_or_clear(conn, force_clear):
    counts = {table_name: table_count(conn, table_name) for table_name in TABLES}
    if not any(counts.values()):
        return

    if not force_clear:
        raise RuntimeError(
            "Il database di destinazione contiene già dati. "
            "Rilancia con --force-clear se vuoi svuotarlo prima."
        )

    with conn.cursor() as cur:
        for table_name in DELETE_ORDER:
            cur.execute(f"DELETE FROM {table_name}")
    conn.commit()


def bulk_insert_rows(conn, table_name, rows):
    if not rows:
        return 0

    columns = INSERT_COLUMNS[table_name]
    placeholders = ", ".join(["%s"] * len(columns))
    column_list = ", ".join(columns)
    sql = f"INSERT INTO {table_name} ({column_list}) VALUES ({placeholders})"

    values = [[row.get(column) for column in columns] for row in rows]
    with conn.cursor() as cur:
        cur.executemany(sql, values)
    conn.commit()
    return len(rows)


def realign_postgres_sequences(conn):
    with conn.cursor() as cur:
        for table_name in TABLES:
            cur.execute(
                f"""
                SELECT setval(
                    pg_get_serial_sequence('{table_name}', 'id'),
                    COALESCE((SELECT MAX(id) FROM {table_name}), 1),
                    COALESCE((SELECT MAX(id) FROM {table_name}), 0) > 0
                )
                """
            )
    conn.commit()


def main():
    args = parse_args()
    source_path = os.path.abspath(args.source)
    database_url = os.getenv("DATABASE_URL", "").strip()

    if not os.path.exists(source_path):
        raise FileNotFoundError(f"Database SQLite non trovato: {source_path}")

    if not database_url:
        raise RuntimeError("DATABASE_URL non impostata nell'ambiente.")

    ensure_target_is_postgres(database_url)
    database_url = normalize_database_url(database_url)

    with psycopg.connect(database_url) as conn:
        ensure_target_empty_or_clear(conn, args.force_clear)

        for table_name in TABLES:
            rows = fetch_sqlite_rows(source_path, table_name)
            inserted = bulk_insert_rows(conn, table_name, rows)
            print(f"[MIGRATION] {table_name}: importate {inserted} righe")

        realign_postgres_sequences(conn)
        print("[MIGRATION] Migrazione SQLite -> PostgreSQL completata con successo.")


if __name__ == "__main__":
    main()
