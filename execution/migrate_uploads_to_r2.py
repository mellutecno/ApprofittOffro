"""
Carica gli upload locali nel bucket R2 configurato senza importare l'app Flask.

Uso:
    python migrate_uploads_to_r2.py --source "..\\uploads"

Richiede:
    - R2_ACCOUNT_ID
    - R2_ACCESS_KEY_ID
    - R2_SECRET_ACCESS_KEY
    - R2_BUCKET_NAME
    - boto3 installato localmente
"""

from __future__ import annotations

import argparse
import os

import boto3


def parse_args():
    parser = argparse.ArgumentParser(description="Migra gli upload locali su Cloudflare R2.")
    parser.add_argument(
        "--source",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads")),
        help="Cartella sorgente degli upload locali.",
    )
    return parser.parse_args()


def build_r2_client():
    account_id = os.getenv("R2_ACCOUNT_ID", "").strip()
    access_key_id = os.getenv("R2_ACCESS_KEY_ID", "").strip()
    secret_access_key = os.getenv("R2_SECRET_ACCESS_KEY", "").strip()
    endpoint_url = os.getenv("R2_ENDPOINT_URL", "").strip()

    if not endpoint_url:
        if not account_id:
            raise RuntimeError("Manca R2_ACCOUNT_ID oppure R2_ENDPOINT_URL.")
        endpoint_url = f"https://{account_id}.r2.cloudflarestorage.com"

    if not access_key_id or not secret_access_key:
        raise RuntimeError("Mancano R2_ACCESS_KEY_ID o R2_SECRET_ACCESS_KEY.")

    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=access_key_id,
        aws_secret_access_key=secret_access_key,
        region_name="auto",
    )


def main():
    args = parse_args()
    source_dir = os.path.abspath(args.source)
    bucket_name = os.getenv("R2_BUCKET_NAME", "").strip()

    if not bucket_name:
        raise RuntimeError("Manca R2_BUCKET_NAME.")

    if not os.path.isdir(source_dir):
        raise FileNotFoundError(f"Cartella upload non trovata: {source_dir}")

    client = build_r2_client()
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
                client.put_object(Bucket=bucket_name, Key=relative_name, Body=handle.read())
            uploaded += 1
            print(f"[UPLOAD] {relative_name}")

    print(f"[UPLOAD] Completato. Caricati: {uploaded}, saltati: {skipped}")


if __name__ == "__main__":
    main()
