#!/usr/bin/env python3
"""
Migrazione DB: Aggiunge tabella user_reminders per salvare le preferenze di notifica.
"""
import sys
import sqlite3

def column_exists(conn, table, column):
    cur = conn.execute(f"PRAGMA table_info({table})")
    return any(row[1] == column for row in cur.fetchall())

def table_exists(conn, table):
    cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
    return cur.fetchone() is not None

def migrate(db_path):
    with sqlite3.connect(db_path) as conn:
        cur = conn.cursor()
        
        if not table_exists(conn, "user_reminders"):
            cur.execute("""
                CREATE TABLE user_reminders (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    offer_id INTEGER NOT NULL,
                    minutes_before INTEGER NOT NULL,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(user_id, offer_id, minutes_before)
                )
            """)
            print("Created table user_reminders")
        else:
            print("Table user_reminders already exists")
            
        conn.commit()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python add_reminders_table.py /path/to/db.sqlite")
        sys.exit(1)
    migrate(sys.argv[1])
