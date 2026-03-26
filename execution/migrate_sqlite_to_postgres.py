"""
Migra i dati principali da SQLite a PostgreSQL usando i modelli correnti.

Uso:
    python migrate_sqlite_to_postgres.py --source "..\\approfittoffro.db"

Richiede:
    - DATABASE_URL puntato al Postgres di destinazione
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from datetime import datetime

from sqlalchemy import text

from app import app, db
from models import User, Offer, Claim, Review, UserPhoto, UserFollow


TABLES = [
    ("users", User),
    ("offers", Offer),
    ("claims", Claim),
    ("reviews", Review),
    ("user_photos", UserPhoto),
    ("user_follows", UserFollow),
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
    raise ValueError(f"Formato datetime non riconosciuto: {value}")


def normalize_row(table_name, row):
    data = dict(row)

    if table_name == "users":
        data["verificato"] = bool(data.get("verificato"))
        data["is_admin"] = bool(data.get("is_admin"))
        data["created_at"] = parse_datetime(data.get("created_at"))
    elif table_name == "offers":
        data["data_ora"] = parse_datetime(data.get("data_ora"))
        data["created_at"] = parse_datetime(data.get("created_at"))
    elif table_name in {"claims", "reviews", "user_photos", "user_follows"}:
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


def ensure_target_is_postgres():
    uri = app.config["SQLALCHEMY_DATABASE_URI"]
    if "postgresql" not in uri:
        raise RuntimeError(
            "DATABASE_URL di destinazione non punta a PostgreSQL. Ferma la migrazione."
        )


def ensure_target_empty_or_clear(force_clear):
    existing_counts = {}
    for table_name, model in TABLES:
        existing_counts[table_name] = db.session.query(model).count()

    if any(existing_counts.values()):
        if not force_clear:
            raise RuntimeError(
                "Il database di destinazione contiene già dati. "
                "Rilancia con --force-clear se vuoi svuotarlo prima."
            )

        for _, model in reversed(TABLES):
            db.session.execute(db.delete(model))
        db.session.commit()


def realign_postgres_sequences():
    for table_name, _ in TABLES:
        db.session.execute(
            text(
                f"""
                SELECT setval(
                    pg_get_serial_sequence('{table_name}', 'id'),
                    COALESCE((SELECT MAX(id) FROM {table_name}), 1),
                    COALESCE((SELECT MAX(id) FROM {table_name}), 0) > 0
                )
                """
            )
        )
    db.session.commit()


def main():
    args = parse_args()
    source_path = os.path.abspath(args.source)

    if not os.path.exists(source_path):
        raise FileNotFoundError(f"Database SQLite non trovato: {source_path}")

    with app.app_context():
        ensure_target_is_postgres()
        db.create_all()
        ensure_target_empty_or_clear(args.force_clear)

        for table_name, model in TABLES:
            rows = fetch_sqlite_rows(source_path, table_name)
            if rows:
                db.session.bulk_insert_mappings(model, rows)
                db.session.commit()
            print(f"[MIGRATION] {table_name}: importate {len(rows)} righe")

        realign_postgres_sequences()
        print("[MIGRATION] Migrazione SQLite -> PostgreSQL completata con successo.")


if __name__ == "__main__":
    main()
