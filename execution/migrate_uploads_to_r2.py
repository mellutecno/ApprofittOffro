"""
Carica gli upload locali nel bucket R2 configurato.

Uso:
    python migrate_uploads_to_r2.py --source "..\\uploads"

Richiede:
    - APP_STORAGE_BACKEND=r2
    - R2_* valorizzate nelle env vars
"""

from __future__ import annotations

import argparse
import os

from app import app, upload_storage


def parse_args():
    parser = argparse.ArgumentParser(description="Migra gli upload locali su Cloudflare R2.")
    parser.add_argument(
        "--source",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads")),
        help="Cartella sorgente degli upload locali.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    source_dir = os.path.abspath(args.source)

    if app.config["UPLOAD_STORAGE_BACKEND"] != "r2":
        raise RuntimeError(
            "Questo script va eseguito con APP_STORAGE_BACKEND=r2 e credenziali R2 valide."
        )

    if not os.path.isdir(source_dir):
        raise FileNotFoundError(f"Cartella upload non trovata: {source_dir}")

    uploaded = 0
    skipped = 0

    for root, _, files in os.walk(source_dir):
        for name in files:
            source_path = os.path.join(root, name)
            relative_name = os.path.relpath(source_path, source_dir).replace("\\", "/")
            if relative_name == ".gitkeep":
                skipped += 1
                continue

            with open(source_path, "rb") as handle:
                upload_storage.save_bytes(relative_name, handle.read())
            uploaded += 1
            print(f"[UPLOAD] {relative_name}")

    print(f"[UPLOAD] Completato. Caricati: {uploaded}, saltati: {skipped}")


if __name__ == "__main__":
    with app.app_context():
        main()
