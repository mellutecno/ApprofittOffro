"""
Storage backend per gli upload di ApprofittOffro.

Supporta:
- filesystem locale (sviluppo / fallback)
- Cloudflare R2 via API S3-compatibile (produzione)
"""

from __future__ import annotations

import mimetypes
import os

try:
    import boto3
    from botocore.exceptions import ClientError
except Exception:  # pragma: no cover - opzionale in locale fino all'install
    boto3 = None
    ClientError = Exception


class StorageConfigurationError(RuntimeError):
    """Configurazione storage non valida o incompleta."""


class StorageObjectNotFound(FileNotFoundError):
    """Oggetto assente nello storage backend."""


class LocalUploadStorage:
    backend_name = "local"

    def __init__(self, upload_folder: str):
        self.upload_folder = os.path.abspath(upload_folder)
        os.makedirs(self.upload_folder, exist_ok=True)

    def save_bytes(self, filename: str, data: bytes, content_type: str | None = None) -> str:
        path = os.path.join(self.upload_folder, filename)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(data)
        return filename

    def delete(self, filename: str) -> None:
        if not filename or filename == "nessuna.jpg":
            return
        path = os.path.join(self.upload_folder, filename)
        if os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass

    def read(self, filename: str) -> tuple[bytes, str]:
        path = os.path.join(self.upload_folder, filename)
        if not os.path.exists(path):
            raise StorageObjectNotFound(filename)

        with open(path, "rb") as handle:
            data = handle.read()

        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        return data, content_type


class R2UploadStorage:
    backend_name = "r2"

    def __init__(
        self,
        bucket_name: str,
        account_id: str,
        access_key_id: str,
        secret_access_key: str,
        endpoint_url: str | None = None,
    ):
        if boto3 is None:
            raise StorageConfigurationError(
                "Il backend R2 richiede boto3 installato nelle dipendenze."
            )

        missing = []
        if not bucket_name:
            missing.append("R2_BUCKET_NAME")
        if not account_id and not endpoint_url:
            missing.append("R2_ACCOUNT_ID oppure R2_ENDPOINT_URL")
        if not access_key_id:
            missing.append("R2_ACCESS_KEY_ID")
        if not secret_access_key:
            missing.append("R2_SECRET_ACCESS_KEY")

        if missing:
            raise StorageConfigurationError(
                "Configurazione R2 incompleta: manca " + ", ".join(missing)
            )

        self.bucket_name = bucket_name
        self.endpoint_url = endpoint_url or f"https://{account_id}.r2.cloudflarestorage.com"
        self.client = boto3.client(
            "s3",
            endpoint_url=self.endpoint_url,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            region_name="auto",
        )

    def save_bytes(self, filename: str, data: bytes, content_type: str | None = None) -> str:
        payload = {
            "Bucket": self.bucket_name,
            "Key": filename,
            "Body": data,
        }
        if content_type:
            payload["ContentType"] = content_type

        self.client.put_object(**payload)
        return filename

    def delete(self, filename: str) -> None:
        if not filename or filename == "nessuna.jpg":
            return
        try:
            self.client.delete_object(Bucket=self.bucket_name, Key=filename)
        except ClientError:
            return

    def read(self, filename: str) -> tuple[bytes, str]:
        try:
            response = self.client.get_object(Bucket=self.bucket_name, Key=filename)
        except ClientError as exc:
            error = exc.response.get("Error", {}) if hasattr(exc, "response") else {}
            code = error.get("Code")
            if code in {"NoSuchKey", "404", "NotFound"}:
                raise StorageObjectNotFound(filename) from exc
            raise

        body = response["Body"].read()
        content_type = response.get("ContentType") or mimetypes.guess_type(filename)[0] or "application/octet-stream"
        return body, content_type


def create_upload_storage(config):
    backend = str(config.get("UPLOAD_STORAGE_BACKEND", "local") or "local").strip().lower()
    if backend == "r2":
        return R2UploadStorage(
            bucket_name=config.get("R2_BUCKET_NAME", ""),
            account_id=config.get("R2_ACCOUNT_ID", ""),
            access_key_id=config.get("R2_ACCESS_KEY_ID", ""),
            secret_access_key=config.get("R2_SECRET_ACCESS_KEY", ""),
            endpoint_url=config.get("R2_ENDPOINT_URL", ""),
        )

    return LocalUploadStorage(config["UPLOAD_FOLDER"])
