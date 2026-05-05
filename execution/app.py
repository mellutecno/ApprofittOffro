"""
ApprofittOffro — Server Flask principale.
Applicazione web per offrire e approfittare di pasti.
"""

import os
import uuid
import math
import re
import sqlite3
import io
import tempfile
import json
import base64
from html import escape
from urllib.parse import quote
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from functools import wraps

from dotenv import load_dotenv
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token as google_id_token
from google.oauth2 import service_account
from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    jsonify,
    session,
    abort,
)
from sqlalchemy import or_
from sqlalchemy.orm import selectinload
from flask_login import (
    LoginManager,
    login_user,
    logout_user,
    login_required,
    current_user,
)
from functools import wraps
from werkzeug.utils import secure_filename
from PIL import Image, ImageDraw

from models import (
    db,
    User,
    Offer,
    OfferPhoto,
    Claim,
    CLAIM_STATUS_ACCEPTED,
    CLAIM_STATUS_PENDING,
    CLAIM_STATUS_REJECTED,
    Review,
    TIPI_PASTO,
    FASCE_ETA,
    SESSI_UTENTE,
    UserPhoto,
    UserFollow,
    UserBlock,
    ChatThread,
    ChatMessage,
    DevicePushToken,
    NotificationDeliveryLog,
    AppNotification,
    UserReminder,
    AiModerationLog,
    BugReport,
    ContentReport,
    MODERATION_STATUS_APPROVED,
    MODERATION_STATUS_REVIEW,
    MODERATION_STATUS_REJECTED,
    MODERATION_RESTRICTED_STATUSES,
    BUG_REPORT_STATUS_PENDING,
    BUG_REPORT_STATUS_APPROVED,
    BUG_REPORT_STATUS_REJECTED,
    LEGAL_TERMS_VERSION,
    LEGAL_PRIVACY_VERSION,
    CONTENT_REPORT_STATUS_PENDING,
    CONTENT_REPORT_STATUS_REVIEWED,
    CONTENT_REPORT_STATUS_DISMISSED,
    CONTENT_REPORT_TARGET_TYPES,
)
from verify_photo import verifica_volto
from upload_storage import create_upload_storage, StorageObjectNotFound

# ---------------------------------------------------------------------------
# Configurazione
# ---------------------------------------------------------------------------
EXECUTION_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(EXECUTION_DIR)


def load_app_env():
    """Carica il primo file .env disponibile, con override via APP_ENV_FILE."""
    env_candidates = [
        os.getenv("APP_ENV_FILE"),
        os.path.join(os.path.expanduser("~"), ".env"),
        os.path.join(EXECUTION_DIR, ".env"),
        os.path.join(PROJECT_ROOT, ".env"),
    ]
    for env_path in env_candidates:
        if env_path and os.path.exists(env_path):
            load_dotenv(env_path)
            return env_path
    load_dotenv()
    return None


load_app_env()

DATA_ROOT = os.path.abspath(os.getenv("APP_DATA_DIR", PROJECT_ROOT))
SQLITE_PATH = os.path.abspath(
    os.getenv("APP_DB_PATH", os.path.join(DATA_ROOT, "approfittoffro.db"))
)
UPLOAD_FOLDER = os.path.abspath(
    os.getenv("APP_UPLOAD_FOLDER", os.path.join(DATA_ROOT, "uploads"))
)
LEGACY_UPLOADS_BASE_URL = os.getenv("LEGACY_UPLOADS_BASE_URL", "").strip().rstrip("/")
APP_TIMEZONE_NAME = os.getenv("APP_TIMEZONE", "Europe/Rome")

try:
    APP_TIMEZONE = ZoneInfo(APP_TIMEZONE_NAME)
except ZoneInfoNotFoundError:
    APP_TIMEZONE = timezone.utc


def normalize_database_url(database_url):
    """Rende compatibili gli URL Postgres di Render con SQLAlchemy/psycopg."""
    if not database_url:
        return None
    if database_url.startswith("postgres://"):
        return "postgresql+psycopg://" + database_url[len("postgres://"):]
    if database_url.startswith("postgresql://") and "+psycopg" not in database_url:
        return "postgresql+psycopg://" + database_url[len("postgresql://"):]
    return database_url

# Garantisce che SQLite possa essere creato anche in deploy che puntano fuori repo.
os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)

app = Flask(
    __name__,
    template_folder="templates",
    static_folder="static",
)

# Forzatura No-Cache universale per evitare problemi di refresh template lato Client
@app.after_request
def add_header(response):
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '-1'
    return response

app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "approfittoffro-dev-key-change-me")
app.config["SQLALCHEMY_DATABASE_URI"] = normalize_database_url(
    os.getenv("DATABASE_URL")
) or ("sqlite:///" + SQLITE_PATH)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["MAX_CONTENT_LENGTH"] = 128 * 1024 * 1024  # 128 MB max upload
app.config["UPLOAD_STORAGE_BACKEND"] = os.getenv("APP_STORAGE_BACKEND", "local").strip().lower()
app.config["R2_ACCOUNT_ID"] = os.getenv("R2_ACCOUNT_ID", "")
app.config["R2_ACCESS_KEY_ID"] = os.getenv("R2_ACCESS_KEY_ID", "")
app.config["R2_SECRET_ACCESS_KEY"] = os.getenv("R2_SECRET_ACCESS_KEY", "")
app.config["R2_BUCKET_NAME"] = os.getenv("R2_BUCKET_NAME", "")
app.config["R2_ENDPOINT_URL"] = os.getenv("R2_ENDPOINT_URL", "")
app.config["GOOGLE_PLACES_API_KEY"] = os.getenv("GOOGLE_PLACES_API_KEY", "").strip()
app.config["GOOGLE_OAUTH_CLIENT_IDS"] = os.getenv(
    "GOOGLE_OAUTH_CLIENT_IDS",
    os.getenv("GOOGLE_OAUTH_CLIENT_ID", ""),
).strip()
app.config["FIREBASE_PROJECT_ID"] = os.getenv("FIREBASE_PROJECT_ID", "").strip()
app.config["FIREBASE_SERVICE_ACCOUNT_FILE"] = os.getenv(
    "FIREBASE_SERVICE_ACCOUNT_FILE",
    "",
).strip()
app.config["FIREBASE_SERVICE_ACCOUNT_JSON"] = os.getenv(
    "FIREBASE_SERVICE_ACCOUNT_JSON",
    "",
).strip()

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER
upload_storage = create_upload_storage(app.config)


def parse_float_env(name, default):
    try:
        return float(os.getenv(name, str(default)) or default)
    except (TypeError, ValueError):
        return float(default)


OPENAI_MODERATION_URL = os.getenv(
    "OPENAI_MODERATION_URL",
    "https://api.openai.com/v1/moderations",
).strip()
OPENAI_MODERATION_MODEL = os.getenv(
    "OPENAI_MODERATION_MODEL",
    "omni-moderation-latest",
).strip()
OPENAI_MODERATION_TIMEOUT_SECONDS = parse_float_env("OPENAI_MODERATION_TIMEOUT_SECONDS", 12)
OPENAI_MODERATION_REVIEW_THRESHOLD = parse_float_env("OPENAI_MODERATION_REVIEW_THRESHOLD", 0.75)
OPENAI_MODERATION_ILLICIT_REVIEW_THRESHOLD = parse_float_env(
    "OPENAI_MODERATION_ILLICIT_REVIEW_THRESHOLD",
    0.15,
)
OPENAI_MODERATION_SEXUAL_REVIEW_THRESHOLD = parse_float_env(
    "OPENAI_MODERATION_SEXUAL_REVIEW_THRESHOLD",
    0.15,
)
MODERATION_FAIL_CLOSED = os.getenv(
    "MODERATION_FAIL_CLOSED",
    "",
).strip().lower() in {"1", "true", "yes", "on"}
LOCAL_MODERATION_KEYWORDS = {
    "arma",
    "armi",
    "cocaina",
    "crack",
    "droga",
    "droghe",
    "eroina",
    "porno",
    "sesso",
    "sessuale",
    "sex",
    "spaccio",
    "spacciare",
    "spacciatore",
    "xxx",
    "nudo",
    "nuda",
    "escort",
    "massaggio erotico",
    "onlyfans",
}

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
MAX_PROFILE_PHOTOS = 5
MAX_OFFER_PHOTOS = 3
CHAT_AUDIO_ALLOWED_EXTENSIONS = {"m4a", "mp4", "aac", "ogg", "opus", "wav", "mp3"}
CHAT_AUDIO_MAX_BYTES = 5 * 1024 * 1024
CHAT_MEDIA_IMAGE_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
CHAT_MEDIA_AUDIO_EXTENSIONS = {"mp3", "m4a", "aac", "wav", "ogg", "opus", "flac"}
CHAT_MEDIA_VIDEO_EXTENSIONS = {"mp4", "m4v", "mov", "3gp", "webm", "mkv"}
CHAT_MEDIA_GENERIC_FILE_EXTENSIONS = {
    "pdf",
    "txt",
    "csv",
    "doc",
    "docx",
    "xls",
    "xlsx",
    "ppt",
    "pptx",
    "zip",
    "rar",
    "7z",
}
CHAT_MEDIA_FILE_EXTENSIONS = {
    *CHAT_MEDIA_GENERIC_FILE_EXTENSIONS,
    *CHAT_MEDIA_AUDIO_EXTENSIONS,
    *CHAT_MEDIA_VIDEO_EXTENSIONS,
}
CHAT_MEDIA_ALLOWED_EXTENSIONS = CHAT_MEDIA_IMAGE_EXTENSIONS | CHAT_MEDIA_FILE_EXTENSIONS
CHAT_MEDIA_IMAGE_MAX_BYTES = 20 * 1024 * 1024
CHAT_MEDIA_AUDIO_MAX_BYTES = 30 * 1024 * 1024
CHAT_MEDIA_GENERIC_FILE_MAX_BYTES = 30 * 1024 * 1024
CHAT_MEDIA_VIDEO_MAX_BYTES = 100 * 1024 * 1024
CHAT_MEDIA_MAX_BYTES = CHAT_MEDIA_VIDEO_MAX_BYTES
CHAT_MEDIA_IMAGE_MAX_SIDE = 1280
CHAT_MEDIA_IMAGE_JPEG_QUALITY = 78
CHAT_RETENTION_DAYS = 30
BREAKFAST_BOOKING_LEAD_HOURS = 1
MEAL_BOOKING_LEAD_HOURS = 6
SHORT_NOTICE_BREAKFAST_BOOKING_LEAD_MINUTES = 30
SHORT_NOTICE_MEAL_BOOKING_LEAD_MINUTES = 60
PASSWORD_RESET_TOKEN_HOURS = 2
PUSH_PRIMARY_EMAIL_TEMPLATES = {
    "nearby_offer_notification.html",
    "claim_notification.html",
    "claim_confirmed.html",
    "claim_rejected.html",
    "review_received.html",
    "offer_updated.html",
    "cancellation.html",
    "offer_removed_admin.html",
    "unclaim_notification.html",
    "unclaim_confirmation.html",
}
USER_SESSION_IDLE_TIMEOUT_MINUTES = 43200
ADMIN_SESSION_IDLE_TIMEOUT_MINUTES = 10
REVIEW_EDIT_WINDOW_HOURS = 3
BREAKFAST_COMMITMENT_GAP_HOURS = 3
MEAL_COMMITMENT_GAP_HOURS = 4
PROFILE_EVENT_HISTORY_HOURS = 24
PROFILE_ARCHIVE_LOOKBACK_DAYS = 30
EMPTY_OFFER_AUTOHIDE_REMINDER_TYPE = "empty_offer_autohide"
DEFAULT_USER_LATITUDE = 41.9028
DEFAULT_USER_LONGITUDE = 12.4964
COMMUNITY_LIVE_LOCATION_TTL_MINUTES = 15
DEFAULT_PROFILE_PLACEHOLDER_FILENAME = "user_placeholder.png"
COMMUNITY_GENDER_FILTERS = [
    ("", "Tutti"),
    ("maschio", "Maschi"),
    ("femmina", "Femmine"),
]
PUSH_PLATFORM_ANDROID = "android"
PUSH_DEEP_LINK_BASE = "approfittoffro://"
PUBLIC_SITE_BASE_URL = os.getenv("PUBLIC_SITE_BASE_URL", "https://www.approfittoffro.it").strip().rstrip("/")
PRIVACY_POLICY_URL = f"{PUBLIC_SITE_BASE_URL}/static/privacy_policy.html"
TERMS_AND_CONDITIONS_URL = f"{PUBLIC_SITE_BASE_URL}/static/terms_and_conditions.html"
COMMUNITY_RULES_URL = f"{PUBLIC_SITE_BASE_URL}/static/community_rules.html"
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
PUSH_CHANNEL_ID = "approfittoffro_alerts"
UPCOMING_EVENT_REMINDER_HOURS = 0.5  # 30 minuti
REVIEW_REMINDER_DELAY_HOURS = 3
REVIEW_REMINDER_LOOKBACK_HOURS = 72


def get_google_oauth_client_ids():
    """Restituisce i client OAuth Google ammessi per il login mobile."""
    raw_value = app.config.get("GOOGLE_OAUTH_CLIENT_IDS", "")
    return [item.strip() for item in re.split(r"[\s,;]+", raw_value) if item.strip()]


def google_oauth_enabled():
    return bool(get_google_oauth_client_ids())


@app.route("/api/auth/google/config", methods=["GET"])
def api_google_login_config():
    """Espone la configurazione pubblica minima necessaria al login Google mobile."""
    allowed_client_ids = get_google_oauth_client_ids()
    return jsonify(
        {
            "success": True,
            "enabled": bool(allowed_client_ids),
            "server_client_id": allowed_client_ids[0] if allowed_client_ids else "",
        }
    )


def local_now():
    """Restituisce l'ora locale dell'app come datetime naive coerente con i dati salvati."""
    return datetime.now(APP_TIMEZONE).replace(tzinfo=None)


def format_offer_datetime_label(data_ora, now=None):
    """Formatta la data per le card evento, mostrando Oggi/Domani solo per eventi futuri imminenti."""
    if now is None:
        now = local_now()

    if data_ora < now:
        return data_ora.strftime("%d/%m/%Y alle %H:%M")

    today = now.date()
    event_day = data_ora.date()

    if event_day == today:
        return f"Oggi alle {data_ora.strftime('%H:%M')}"
    if event_day == today + timedelta(days=1):
        return f"Domani alle {data_ora.strftime('%H:%M')}"

    return data_ora.strftime("%d/%m/%Y alle %H:%M")


def get_booking_lead_hours_for_meal_type(tipo_pasto):
    """Restituisce l'anticipo minimo richiesto per il tipo di pasto."""
    return BREAKFAST_BOOKING_LEAD_HOURS if tipo_pasto == "colazione" else MEAL_BOOKING_LEAD_HOURS


def get_offer_booking_lead_hours(offer):
    """Restituisce l'anticipo minimo richiesto per prenotare un'offerta."""
    return get_booking_lead_hours_for_meal_type(offer.tipo_pasto)


def get_short_notice_booking_lead_minutes_for_meal_type(tipo_pasto):
    """Restituisce l'anticipo ridotto da usare sugli eventi pubblicati in ritardo."""
    return (
        SHORT_NOTICE_BREAKFAST_BOOKING_LEAD_MINUTES
        if tipo_pasto == "colazione"
        else SHORT_NOTICE_MEAL_BOOKING_LEAD_MINUTES
    )


def get_offer_booking_lead_override_minutes(offer):
    """Recupera l'eventuale finestra di prenotazione ridotta salvata sull'offerta."""
    override_minutes = getattr(offer, "booking_lead_override_minutes", None)
    if override_minutes is not None:
        try:
            parsed_override = int(override_minutes)
        except (TypeError, ValueError):
            parsed_override = None
        if parsed_override and parsed_override > 0:
            return parsed_override

    created_at = getattr(offer, "created_at", None)
    if created_at is None:
        return None

    standard_deadline = offer.data_ora - timedelta(
        hours=get_offer_booking_lead_hours(offer)
    )
    if created_at >= standard_deadline:
        return get_short_notice_booking_lead_minutes_for_meal_type(
            offer.tipo_pasto
        )
    return None


def get_offer_booking_lead_delta(offer):
    """Restituisce il delta reale da usare per chiudere le prenotazioni."""
    override_minutes = get_offer_booking_lead_override_minutes(offer)
    if override_minutes is not None:
        return timedelta(minutes=override_minutes)
    return timedelta(hours=get_offer_booking_lead_hours(offer))


def get_offer_booking_deadline(offer):
    """Calcola il momento oltre il quale non si puo' piu' approfittare dell'offerta."""
    return offer.data_ora - get_offer_booking_lead_delta(offer)


def get_booking_deadline_for_meal_type(tipo_pasto, data_ora):
    """Calcola la scadenza prenotazioni per un nuovo evento non ancora persistito."""
    return data_ora - timedelta(hours=get_booking_lead_hours_for_meal_type(tipo_pasto))


def is_offer_booking_closed(offer, now=None):
    """Indica se la finestra per approfittare dell'offerta e' gia' chiusa."""
    if now is None:
        now = local_now()
    return now >= get_offer_booking_deadline(offer)


def is_new_offer_publication_too_late(tipo_pasto, data_ora, now=None):
    """Indica se l'offerta nascerebbe gia' con prenotazioni chiuse."""
    if now is None:
        now = local_now()
    return now >= get_booking_deadline_for_meal_type(tipo_pasto, data_ora)


def get_offer_booking_closed_message(offer):
    """Messaggio esplicativo per la chiusura delle prenotazioni."""
    override_minutes = get_offer_booking_lead_override_minutes(offer)
    if override_minutes is not None:
        if override_minutes % 60 == 0:
            hours = override_minutes // 60
            lead_copy = "1 ora" if hours == 1 else f"{hours} ore"
        else:
            lead_copy = f"{override_minutes} minuti"
        return (
            "Per questo evento le prenotazioni si chiudono "
            f"{lead_copy} prima dell'inizio."
        )
    if offer.tipo_pasto == "colazione":
        return "Le colazioni si possono approfittare solo fino a 1 ora prima dell'inizio."
    return "Pranzi e cene si possono approfittare solo fino a 6 ore prima dell'inizio."


def get_offer_publication_too_late_message(tipo_pasto):
    """Messaggio esplicativo quando si tenta di pubblicare troppo tardi."""
    if tipo_pasto == "colazione":
        return "Questa colazione verrebbe pubblicata troppo tardi: deve essere inserita almeno 1 ora prima dell'inizio."
    if tipo_pasto == "pranzo":
        return "Questo pranzo verrebbe pubblicato troppo tardi: i pranzi devono essere inseriti almeno 6 ore prima dell'inizio."
    if tipo_pasto == "ape":
        return "Questo APE verrebbe pubblicato troppo tardi: deve essere inserito almeno 6 ore prima dell'inizio."
    return "Questa cena verrebbe pubblicata troppo tardi: le cene devono essere inserite almeno 6 ore prima dell'inizio."


def parse_force_short_notice_flag(raw_value):
    """Interpreta il flag che consente di forzare un evento con poco anticipo."""
    if raw_value is None:
        return False
    return str(raw_value).strip().lower() in {"1", "true", "yes", "on", "si"}


def get_same_day_offer_conflict(user_id, tipo_pasto, data_ora, exclude_offer_id=None):
    """Trova un'altra offerta dello stesso utente, stesso pasto e stessa data."""
    day_start = data_ora.replace(hour=0, minute=0, second=0, microsecond=0)
    next_day = day_start + timedelta(days=1)

    query = Offer.query.filter(
        Offer.user_id == user_id,
        Offer.tipo_pasto == tipo_pasto,
        Offer.stato.notin_(["annullata", "archiviata_admin"]),
        Offer.data_ora >= day_start,
        Offer.data_ora < next_day,
    )

    if exclude_offer_id is not None:
        query = query.filter(Offer.id != exclude_offer_id)

    return query.order_by(Offer.data_ora.asc()).first()


def get_meal_commitment_gap_hours(tipo_pasto):
    """Restituisce il buffer minimo fra due eventi dello stesso tipo."""
    return (
        BREAKFAST_COMMITMENT_GAP_HOURS
        if tipo_pasto == "colazione"
        else MEAL_COMMITMENT_GAP_HOURS
    )


def get_user_meal_schedule_conflict(
    user_id,
    tipo_pasto,
    data_ora,
    *,
    exclude_offer_id=None,
    exclude_claim_offer_id=None,
):
    """Trova conflitti tra offerte e partecipazioni dello stesso utente nello stesso giorno."""
    day_start = data_ora.replace(hour=0, minute=0, second=0, microsecond=0)
    next_day = day_start + timedelta(days=1)
    gap_seconds = get_meal_commitment_gap_hours(tipo_pasto) * 3600

    own_offers_query = Offer.query.filter(
        Offer.user_id == user_id,
        Offer.tipo_pasto == tipo_pasto,
        Offer.stato.in_(["attiva", "completata"]),
        Offer.data_ora >= day_start,
        Offer.data_ora < next_day,
    )
    if exclude_offer_id is not None:
        own_offers_query = own_offers_query.filter(Offer.id != exclude_offer_id)

    for own_offer in own_offers_query.order_by(Offer.data_ora.asc()).all():
        delta_seconds = abs((own_offer.data_ora - data_ora).total_seconds())
        if delta_seconds <= gap_seconds:
            return {
                "kind": "offer",
                "offer": own_offer,
            }

    user_claims = (
        Claim.query.join(Offer, Claim.offer_id == Offer.id)
        .filter(
            Claim.user_id == user_id,
            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
            Offer.tipo_pasto == tipo_pasto,
            Offer.stato.in_(["attiva", "completata"]),
            Offer.data_ora >= day_start,
            Offer.data_ora < next_day,
        )
        .order_by(Offer.data_ora.asc())
        .all()
    )
    for claim in user_claims:
        if exclude_claim_offer_id is not None and claim.offer_id == exclude_claim_offer_id:
            continue
        claimed_offer = claim.offerta
        if not claimed_offer:
            continue
        delta_seconds = abs((claimed_offer.data_ora - data_ora).total_seconds())
        if delta_seconds <= gap_seconds:
            return {
                "kind": "claim",
                "offer": claimed_offer,
                "claim": claim,
            }

    return None


def build_meal_schedule_conflict_message(tipo_pasto, conflict):
    """Messaggio UX per conflitti di agenda tra eventi dello stesso tipo."""
    meal_copy = get_meal_type_copy(tipo_pasto)
    gap_hours = get_meal_commitment_gap_hours(tipo_pasto)
    conflicting_offer = conflict["offer"]
    conflict_time = conflicting_offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    return (
        f"Hai già un'altra {meal_copy['singular']} programmata per il {conflict_time}. "
        f"Tra due {meal_copy['plural']} devono passare più di {gap_hours} ore."
    )


def get_meal_type_copy(tipo_pasto):
    """Etichette testuali per messaggi UX sul tipo di pasto."""
    labels = {
        "colazione": {"singular": "colazione", "plural": "colazioni"},
        "pranzo": {"singular": "pranzo", "plural": "pranzi"},
        "cena": {"singular": "cena", "plural": "cene"},
        "ape": {"singular": "APERITIVO", "plural": "APERITIVI"},
    }
    return labels.get(tipo_pasto, {"singular": tipo_pasto, "plural": tipo_pasto})


def get_meal_type_label(tipo_pasto):
    """Restituisce il nome leggibile del tipo di pasto."""
    for value, label in TIPI_PASTO:
        if value == tipo_pasto:
            return label
    return tipo_pasto.title()


def get_spots_copy(spots_count):
    """Restituisce una label leggibile per i posti disponibili."""
    if spots_count == 1:
        return "1 posto disponibile"
    return f"{spots_count} posti disponibili"


def get_offer_accepted_claims(offer):
    """Restituisce solo i claim gia' accettati dall'host."""
    return [claim for claim in offer.claims if claim.status == CLAIM_STATUS_ACCEPTED]


def has_offer_accepted_participants(offer):
    """True se l'offerta ha almeno un partecipante accettato."""
    return any(claim.status == CLAIM_STATUS_ACCEPTED for claim in offer.claims)


def is_offer_started_without_participants(offer, *, now=None):
    """True se l'evento e' iniziato ma non ha alcun partecipante accettato."""
    now = now or local_now()
    return offer.data_ora <= now and not has_offer_accepted_participants(offer)


def notify_host_offer_started_without_participants(offer, *, now=None, dry_run=False):
    """Invia una sola push all'host quando un evento parte con zero partecipanti."""
    host = offer.autore
    if host is None:
        return False
    now = now or local_now()
    dedupe_key = build_notification_dedupe_key(
        EMPTY_OFFER_AUTOHIDE_REMINDER_TYPE,
        offer_id=offer.id,
        user_id=host.id,
    )
    if notification_delivery_exists(dedupe_key):
        return False
    if dry_run:
        return True

    data_evento = format_offer_datetime_label(offer.data_ora, now=now)
    push_sent = send_push_to_user(
        host,
        title="Evento senza partecipanti",
        body=(
            f"Il tuo {offer.tipo_pasto} da {offer.nome_locale} ({data_evento}) "
            "e' partito senza partecipanti ed e' stato nascosto dall'elenco eventi."
        ),
        target="profile",
        extra_data={
            "offer_id": offer.id,
            "offer_autohidden_empty": "true",
        },
    )
    if push_sent <= 0:
        return False

    record_notification_delivery(
        user_id=host.id,
        offer_id=offer.id,
        reminder_type=EMPTY_OFFER_AUTOHIDE_REMINDER_TYPE,
        dedupe_key=dedupe_key,
    )
    return True


def filter_visible_offers_and_notify_empty_started_hosts(
    offers,
    *,
    now=None,
    dry_run=False,
):
    """Nasconde gli eventi iniziati senza partecipanti e notifica l'host (deduplicata)."""
    now = now or local_now()
    visible = []
    hidden_count = 0
    notified_count = 0

    for offer in offers:
        if not is_offer_started_without_participants(offer, now=now):
            visible.append(offer)
            continue

        hidden_count += 1
        if notify_host_offer_started_without_participants(offer, now=now, dry_run=dry_run):
            notified_count += 1

    return visible, {"hidden": hidden_count, "notified": notified_count}


def get_offer_pending_claims(offer):
    """Restituisce solo le richieste ancora in attesa di approvazione."""
    return [claim for claim in offer.claims if claim.status == CLAIM_STATUS_PENDING]


def get_mobile_claim_status(current_claim):
    """Traduce lo stato Claim nel valore atteso dall'app mobile."""
    if current_claim is None:
        return "open"
    if current_claim.status == CLAIM_STATUS_PENDING:
        return "pending"
    if current_claim.status == CLAIM_STATUS_ACCEPTED:
        return "claimed"
    if current_claim.status == CLAIM_STATUS_REJECTED:
        return "rejected"
    return "open"


def serialize_mobile_offer(
    offer,
    *,
    viewer=None,
    current_claim=None,
    now=None,
    search_lat=None,
    search_lon=None,
):
    """Serializza un evento nel formato usato dall'app mobile."""
    now = now or local_now()

    if search_lat is None or search_lon is None:
        if viewer and getattr(viewer, "is_authenticated", False):
            search_lat = viewer.latitudine
            search_lon = viewer.longitudine
        else:
            search_lat = DEFAULT_USER_LATITUDE
            search_lon = DEFAULT_USER_LONGITUDE

    dist = calculate_distance(search_lat, search_lon, offer.latitudine, offer.longitudine)
    booking_deadline = get_offer_booking_deadline(offer)
    booking_closed = is_offer_booking_closed(offer, now)
    has_started = offer.data_ora <= now
    author_rating = get_user_rating(offer.autore.id)

    already_claimed = False
    is_own = False
    host_whatsapp_link = ""

    if viewer and getattr(viewer, "is_authenticated", False):
        if current_claim is None:
            current_claim = next(
                (claim for claim in offer.claims if claim.user_id == viewer.id),
                None,
            )
        already_claimed = (
            current_claim is not None
            and current_claim.status == CLAIM_STATUS_ACCEPTED
        )
        is_own = offer.user_id == viewer.id
        if (
            current_claim is not None
            and current_claim.status == CLAIM_STATUS_ACCEPTED
            and not is_own
        ):
            host_whatsapp_link = build_whatsapp_offer_link(viewer, offer.autore, offer)

    claim_status = get_mobile_claim_status(current_claim)
    if current_claim is None and (offer.stato != "attiva" or offer.posti_disponibili <= 0):
        claim_status = "full"
    elif current_claim is None and has_started:
        claim_status = "started"
    elif current_claim is None and booking_closed:
        claim_status = "booking_closed"

    can_claim = (not is_own) and current_claim is None and claim_status == "open"
    accepted_claims = get_offer_accepted_claims(offer)
    offer_gallery = [
        filename
        for filename in list(getattr(offer, "gallery_filenames", []))
        if filename and filename != "nessuna.jpg"
    ]
    primary_offer_photo = (
        offer_gallery[0]
        if offer_gallery
        else getattr(offer, "foto_locale", "nessuna.jpg")
    )

    user_has_reviewed = False
    reviews_received_count = 0
    if viewer and getattr(viewer, "is_authenticated", False):
        from models import Review
        user_has_reviewed = Review.query.filter_by(
            offer_id=offer.id,
            reviewer_id=viewer.id
        ).first() is not None
        reviews_received_count = Review.query.filter_by(
            offer_id=offer.id
        ).count()

    return {
        "id": offer.id,
        "tipo_pasto": offer.tipo_pasto,
        "nome_locale": offer.nome_locale,
        "indirizzo": offer.indirizzo,
        "city_label": extract_city_label(offer.indirizzo),
        "telefono_locale": getattr(offer, "telefono_locale", "") or "",
        "lat": offer.latitudine,
        "lon": offer.longitudine,
        "distance_km": round(dist, 1),
        "posti_totali": offer.posti_totali,
        "posti_disponibili": offer.posti_disponibili,
        "stato": offer.stato,
        "data_ora": offer.data_ora.isoformat(),
        "booking_deadline": booking_deadline.isoformat(),
        "booking_closed": booking_closed,
        "has_started": has_started,
        "descrizione": offer.descrizione or "",
        "foto_locale": primary_offer_photo,
        "foto_locale_gallery": offer_gallery,
        "foto_locale_count": len(offer_gallery),
        "autore": offer.autore.nome,
        "autore_id": offer.autore.id,
        "autore_foto": offer.autore.foto_filename,
        "autore_foto_gallery": offer.autore.gallery_filenames[:2],
        "autore_eta": offer.autore.eta_display,
        "autore_rating_average": author_rating["average"],
        "autore_rating_count": author_rating["count"],
        "autore_cibi_preferiti": offer.autore.cibi_preferiti or "",
        "autore_intolleranze": offer.autore.intolleranze or "",
        "host_whatsapp_link": host_whatsapp_link,
        "host_chat_enabled": already_claimed,
        "partecipanti": [
            {
                "id": claim.utente.id,
                "nome": claim.utente.nome,
                "foto": claim.utente.foto_filename,
                "chat_enabled": True,
                "whatsapp_link": build_whatsapp_offer_link(viewer, claim.utente, offer)
                if viewer and getattr(viewer, "is_authenticated", False) and is_own
                else "",
            }
            for claim in accepted_claims
            if claim.utente and is_public_user_visible_to_viewer(claim.utente, viewer)
        ],
        "is_own": is_own,
        "already_claimed": already_claimed,
        "can_claim": can_claim,
        "claim_status": claim_status,
        "claim_id": current_claim.id if current_claim is not None else 0,
        "user_has_reviewed": user_has_reviewed,
        "reviews_received_count": reviews_received_count,
    }


def get_followed_offer_notification_subject(offer):
    """Costruisce l'oggetto mail per le nuove offerte dei profili seguiti."""
    if offer.tipo_pasto == "pranzo":
        return f"{offer.autore.nome} ha pubblicato un nuovo pranzo: {offer.nome_locale}"
    return f"{offer.autore.nome} ha pubblicato una nuova {offer.tipo_pasto}: {offer.nome_locale}"


def get_followed_offer_notification_heading(offer):
    """Titolo mail con genere corretto per le offerte dei profili seguiti."""
    if offer.tipo_pasto == "pranzo":
        return f"{offer.autore.nome} ha pubblicato un nuovo pranzo"
    return f"{offer.autore.nome} ha pubblicato una nuova {offer.tipo_pasto}"


def get_followed_offer_push_body(offer, data_evento=None):
    """Corpo push sintetico per le offerte dei profili seguiti."""
    data_evento = data_evento or offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    return f"{offer.nome_locale} • {data_evento}"


def get_session_idle_timeout_seconds(user):
    """Restituisce il timeout inattivita' per il tipo di utente."""
    timeout_minutes = (
        ADMIN_SESSION_IDLE_TIMEOUT_MINUTES
        if is_admin_user(user)
        else USER_SESSION_IDLE_TIMEOUT_MINUTES
    )
    return timeout_minutes * 60


def get_followers_notification_targets(offer):
    """Trova gli utenti che seguono l'autore e devono ricevere le nuove offerte."""
    return User.query.join(
        UserFollow,
        UserFollow.follower_id == User.id,
    ).filter(
        UserFollow.followed_id == offer.user_id,
        User.verificato.is_(True),
        User.is_admin.is_(False),
        User.bio_moderation_status == MODERATION_STATUS_APPROVED,
        User.photo_moderation_status == MODERATION_STATUS_APPROVED,
        User.email.isnot(None),
        User.email != "",
        User.id != offer.user_id,
    ).all()


def get_nearby_active_push_users(offer, *, radius_km=20, excluded_user_ids=None):
    """Trova utenti con token push attivo vicini all'evento, escludendo host e follower già avvisati."""
    excluded_ids = {offer.user_id}
    excluded_ids.update(excluded_user_ids or [])

    candidates = (
        User.query.join(
            DevicePushToken,
            DevicePushToken.user_id == User.id,
        )
        .filter(
            User.verificato.is_(True),
            User.is_admin.is_(False),
            User.bio_moderation_status == MODERATION_STATUS_APPROVED,
            User.photo_moderation_status == MODERATION_STATUS_APPROVED,
            DevicePushToken.active.is_(True),
        )
        .order_by(User.nome.asc())
        .all()
    )

    nearby_users = []
    seen_ids = set()
    for user in candidates:
        if user.id in excluded_ids or user.id in seen_ids:
            continue
        seen_ids.add(user.id)
        if user.latitudine is None or user.longitudine is None:
            continue
        if calculate_distance(
            offer.latitudine,
            offer.longitudine,
            user.latitudine,
            user.longitudine,
        ) > radius_km:
            continue
        nearby_users.append(user)

    return nearby_users


def notify_followers_for_new_offer(offer):
    """Avvisa follower e utenti vicini quando nasce una nuova offerta."""
    if offer.data_ora <= local_now():
        return {
            "followers": 0,
            "emails": 0,
            "push_users": 0,
            "nearby_push_users": 0,
        }

    followers = get_followers_notification_targets(offer)
    follower_ids = {follower.id for follower in followers}
    nearby_users = get_nearby_active_push_users(
        offer,
        radius_km=20,
        excluded_user_ids=follower_ids,
    )
    if not followers and not nearby_users:
        return {
            "followers": 0,
            "emails": 0,
            "push_users": 0,
            "nearby_push_users": 0,
        }

    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    booking_rule_copy = (
        "Le colazioni si possono approfittare fino a 1 ora prima."
        if offer.tipo_pasto == "colazione"
        else "Pranzi e cene si possono approfittare fino a 6 ore prima."
    )
    meal_label = get_meal_type_label(offer.tipo_pasto)
    spots_copy = get_spots_copy(offer.posti_disponibili)
    email_count = 0
    push_users = 0
    nearby_push_users = 0
    push_title = get_followed_offer_notification_heading(offer)
    push_body = get_followed_offer_push_body(offer, data_evento=data_evento)

    for follower in followers:
        delivery = send_operational_notification(
            follower,
            push_title=push_title,
            push_body=push_body,
            target="offers",
            extra_data={
                "offer_id": offer.id,
                "author_name": offer.autore.nome if offer.autore else "",
                "meal_type": offer.tipo_pasto,
            },
            email_subject=get_followed_offer_notification_subject(offer),
            email_template="nearby_offer_notification.html",
            email_recipients=[follower.email] if follower.email else [],
            email_context={
                "user": follower,
                "offer": offer,
                "autore": offer.autore,
                "notification_heading": get_followed_offer_notification_heading(offer),
                "meal_label": meal_label,
                "data_evento": data_evento,
                "spots_copy": spots_copy,
                "booking_rule_copy": booking_rule_copy,
            },
        )
        if delivery["push_sent"] > 0:
            push_users += 1
        if delivery["email_sent"]:
            email_count += 1

    nearby_push_title = "Nuovo evento vicino a te"
    nearby_push_body = (
        f"{offer.autore.nome} ha pubblicato {offer.tipo_pasto} da "
        f"{offer.nome_locale} • {data_evento}"
    )
    for user in nearby_users:
        push_sent = send_push_to_user(
            user,
            title=nearby_push_title,
            body=nearby_push_body,
            target="offers",
            extra_data={
                "offer_id": offer.id,
                "author_name": offer.autore.nome if offer.autore else "",
                "meal_type": offer.tipo_pasto,
                "notification_scope": "nearby_users",
            },
        )
        if push_sent > 0:
            nearby_push_users += 1

    return {
        "followers": len(followers),
        "emails": email_count,
        "push_users": push_users,
        "nearby_push_users": nearby_push_users,
    }


def send_claim_request_notification_to_host(claim):
    """Avvisa l'host che e' arrivata una nuova richiesta da approvare."""
    offer = claim.offerta
    guest = claim.utente
    if not offer or not guest:
        print(
            f"[CLAIM_MAIL_SKIP] richiesta host non inviata: claim={getattr(claim, 'id', None)} offer/guest mancanti"
        )
        return
    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    send_operational_notification(
        offer.autore,
        push_title="Nuova richiesta da approvare",
        push_body=f"{guest.nome} vuole approfittare di {offer.nome_locale}.",
        target="pending-requests",
        extra_data={
            "offer_id": offer.id,
            "claim_id": claim.id,
            "guest_name": guest.nome,
        },
        email_subject=f"Nuova richiesta da approvare per '{offer.nome_locale}'",
        email_template="claim_notification.html",
        email_recipients=[offer.autore.email] if offer.autore.email else [],
        email_background=False,
        email_context={
            "user": guest,
            "offer": offer,
            "data_evento": data_evento,
        },
    )


def send_claim_accepted_email(claim):
    """Conferma al partecipante che l'host ha accettato la richiesta."""
    offer = claim.offerta
    guest = claim.utente
    if not offer or not guest:
        print(
            f"[CLAIM_MAIL_SKIP] accettazione non inviata: claim={getattr(claim, 'id', None)} offer/guest mancanti"
        )
        return
    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    send_operational_notification(
        guest,
        push_title="Richiesta accettata",
        push_body=f"{offer.autore.nome} ha accettato la tua richiesta per {offer.nome_locale}.",
        target="offers",
        extra_data={
            "offer_id": offer.id,
            "claim_id": claim.id,
            "host_name": offer.autore.nome if offer.autore else "",
        },
        email_subject=f"Richiesta accettata per '{offer.nome_locale}'",
        email_template="claim_confirmed.html",
        email_recipients=[guest.email] if guest.email else [],
        email_background=False,
        email_context={
            "user": guest,
            "offer": offer,
            "data_evento": data_evento,
        },
    )


def send_claim_rejected_email(claim):
    """Avvisa il partecipante che la richiesta e' stata rifiutata dall'host."""
    offer = claim.offerta
    guest = claim.utente
    if not offer or not guest:
        print(
            f"[CLAIM_MAIL_SKIP] rifiuto non inviato: claim={getattr(claim, 'id', None)} offer/guest mancanti"
        )
        return
    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    send_operational_notification(
        guest,
        push_title="Richiesta non accettata",
        push_body=f"{offer.autore.nome} non ha accettato la tua richiesta per {offer.nome_locale}.",
        target="offers",
        extra_data={
            "offer_id": offer.id,
            "claim_id": claim.id,
            "host_name": offer.autore.nome if offer.autore else "",
        },
        email_subject=f"Richiesta non accettata per '{offer.nome_locale}'",
        email_template="claim_rejected.html",
        email_recipients=[guest.email] if guest.email else [],
        email_background=False,
        email_context={
            "user": guest,
            "offer": offer,
            "host": offer.autore,
            "data_evento": data_evento,
        },
    )


def send_review_received_email(review, *, is_update=False):
    """Avvisa il destinatario quando riceve o vede aggiornata una recensione."""
    if not review:
        return False

    offer = review.offerta
    reviewer = review.reviewer
    reviewed = review.reviewed
    if not offer or not reviewer or not reviewed:
        print(
            f"[REVIEW_MAIL_SKIP] review={getattr(review, 'id', None)} offer/reviewer/reviewed mancanti"
        )
        return False
    data_evento = (
        offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
        if offer.data_ora
        else ""
    )
    action_label = "ha aggiornato" if is_update else "ti ha lasciato"
    push_title = "Recensione aggiornata" if is_update else "Nuova recensione ricevuta"
    push_body = (
        f"{reviewer.nome} ha aggiornato la recensione per {offer.nome_locale}."
        if is_update
        else f"{reviewer.nome} ti ha lasciato una recensione per {offer.nome_locale}."
    )
    delivery = send_operational_notification(
        reviewed,
        push_title=push_title,
        push_body=push_body,
        target="profile",
        extra_data={
            "offer_id": offer.id,
            "review_id": review.id,
            "reviewer_name": reviewer.nome,
        },
        email_subject=f"{reviewer.nome} {action_label} una recensione",
        email_template="review_received.html",
        email_recipients=[reviewed.email] if reviewed.email else [],
        email_background=False,
        email_context={
            "reviewed_user": reviewed,
            "reviewer_user": reviewer,
            "offer": offer,
            "data_evento": data_evento,
            "rating": review.rating,
            "commento": review.commento or "",
            "is_update": is_update,
        },
    )
    return delivery["email_sent"]


def send_follow_started_push(follower, followed):
    if not follower or not followed or follower.id == followed.id:
        return 0
    return send_push_to_user(
        followed,
        title="Nuovo follower",
        body=f"{follower.nome} ha iniziato a seguirti.",
        target="profile",
        extra_data={
            "follower_id": follower.id,
            "follower_name": follower.nome,
            "follow_started": "true",
        },
    )


def build_notification_dedupe_key(reminder_type, *, offer_id, user_id, related_user_id=None):
    parts = [str(reminder_type or "").strip().lower(), str(offer_id), str(user_id)]
    if related_user_id is not None:
        parts.append(str(related_user_id))
    return ":".join(parts)


def notification_delivery_exists(dedupe_key):
    if not dedupe_key:
        return False
    return (
        NotificationDeliveryLog.query.filter_by(dedupe_key=dedupe_key).first()
        is not None
    )


def record_notification_delivery(*, user_id, offer_id, reminder_type, dedupe_key):
    if not dedupe_key or notification_delivery_exists(dedupe_key):
        return False
    db.session.add(
        NotificationDeliveryLog(
            user_id=user_id,
            offer_id=offer_id,
            reminder_type=reminder_type,
            dedupe_key=dedupe_key,
        )
    )
    db.session.commit()
    return True


def send_upcoming_event_reminders(
    *,
    now=None,
    hours_ahead=UPCOMING_EVENT_REMINDER_HOURS,
    dry_run=False,
):
    now = now or local_now()
    upper_bound = now + timedelta(hours=hours_ahead)
    sent = {"host": 0, "participants": 0}
    skipped = {"already_sent": 0, "missing_token": 0}

    # Prendiamo tutti i reminder attivi che scadono entro la finestra
    # Un reminder è attivo se: now >= (evento - minuti_prima) E non è ancora stato inviato
    # Per semplicità, il cron job gira ogni 5 minuti. Controlliamo se ci sono eventi che iniziano
    # entro la finestra e se l'utente ha un reminder compatibile.
    
    # Per ottimizzare, prendiamo tutti gli eventi nella finestra
    offers = (
        Offer.query.options(
            selectinload(Offer.autore),
            selectinload(Offer.claims).selectinload(Claim.utente),
        )
        .filter(
            Offer.stato.in_(["attiva", "completata"]),
            Offer.data_ora > now,
            Offer.data_ora <= upper_bound,
        )
        .order_by(Offer.data_ora.asc())
        .all()
    )

    for offer in offers:
        # Calcola i minuti mancanti all'evento
        delta_minutes = (offer.data_ora - now).total_seconds() / 60.0
        
        # 1. Host Reminder
        # L'host ha sempre un reminder "default" se non ne ha impostati di specifici?
        # Per ora mandiamo a tutti gli host come prima, poi raffineremo.
        # Meglio: controlliamo se l'host ha impostato un reminder vicino a delta_minutes
        host_reminders = UserReminder.query.filter_by(user_id=offer.user_id, offer_id=offer.id).all()
        
        for reminder in host_reminders:
            # Se il reminder scade in questa finestra (es. mancano 30 min e l'utente ha chiesto 30 min)
            # Tolleranza di 5 minuti per il cron job
            if abs(delta_minutes - reminder.minutes_before) <= 5:
                host_key = build_notification_dedupe_key(
                    f"reminder_{reminder.minutes_before}_host",
                    offer_id=offer.id,
                    user_id=offer.user_id,
                )
                if notification_delivery_exists(host_key):
                    skipped["already_sent"] += 1
                elif dry_run:
                    sent["host"] += 1
                else:
                    data_evento = format_offer_datetime_label(offer.data_ora, now=now)
                    push_sent = send_push_to_user(
                        offer.autore,
                        title=f"Promemoria: {reminder.minutes_before} min",
                        body=f"Il tuo {offer.tipo_pasto} da {offer.nome_locale} inizia {data_evento}.",
                        target="profile",
                        extra_data={"offer_id": offer.id, "event_reminder": "true"},
                    )
                    if push_sent > 0:
                        record_notification_delivery(
                            user_id=offer.user_id, offer_id=offer.id,
                            reminder_type=f"reminder_{reminder.minutes_before}_host",
                            dedupe_key=host_key,
                        )
                        sent["host"] += 1
                    else:
                        skipped["missing_token"] += 1

        # 2. Guest Reminder
        for claim in get_offer_accepted_claims(offer):
            participant = claim.utente
            if not participant:
                continue
            
            guest_reminders = UserReminder.query.filter_by(user_id=participant.id, offer_id=offer.id).all()
            
            for reminder in guest_reminders:
                if abs(delta_minutes - reminder.minutes_before) <= 5:
                    participant_key = build_notification_dedupe_key(
                        f"reminder_{reminder.minutes_before}_guest",
                        offer_id=offer.id,
                        user_id=participant.id,
                    )
                    if notification_delivery_exists(participant_key):
                        skipped["already_sent"] += 1
                        continue
                    if dry_run:
                        sent["participants"] += 1
                        continue
                    
                    data_evento = format_offer_datetime_label(offer.data_ora, now=now)
                    push_sent = send_push_to_user(
                        participant,
                        title=f"Promemoria: {reminder.minutes_before} min",
                        body=f"Il tuo {offer.tipo_pasto} da {offer.nome_locale} inizia {data_evento}.",
                        target="profile",
                        extra_data={"offer_id": offer.id, "event_reminder": "true"},
                    )
                    if push_sent > 0:
                        record_notification_delivery(
                            user_id=participant.id, offer_id=offer.id,
                            reminder_type=f"reminder_{reminder.minutes_before}_guest",
                            dedupe_key=participant_key,
                        )
                        sent["participants"] += 1
                    else:
                        skipped["missing_token"] += 1

    return {
        "offers_considered": len(offers),
        "sent": sent,
        "skipped": skipped,
        "window_end": upper_bound.isoformat(),
    }


def send_pending_review_reminders(
    *,
    now=None,
    delay_hours=REVIEW_REMINDER_DELAY_HOURS,
    lookback_hours=REVIEW_REMINDER_LOOKBACK_HOURS,
    dry_run=False,
):
    now = now or local_now()
    threshold = now - timedelta(hours=delay_hours)
    lower_bound = now - timedelta(hours=lookback_hours)
    sent = 0
    skipped = {"already_sent": 0, "missing_token": 0}

    offers = (
        Offer.query.options(
            selectinload(Offer.autore),
            selectinload(Offer.claims).selectinload(Claim.utente),
        )
        .filter(
            Offer.stato.notin_(["annullata", "archiviata_admin"]),
            Offer.data_ora <= threshold,
            Offer.data_ora >= lower_bound,
        )
        .order_by(Offer.data_ora.desc())
        .all()
    )

    for offer in offers:
        data_evento = format_offer_datetime_label(offer.data_ora, now=now)
        host = offer.autore
        if not host:
            continue

        for claim in get_offer_accepted_claims(offer):
            guest = claim.utente
            if not guest:
                continue

            guest_review = Review.query.filter_by(
                reviewer_id=guest.id,
                reviewed_id=host.id,
                offer_id=offer.id,
            ).first()
            if not guest_review:
                guest_key = build_notification_dedupe_key(
                    "review_reminder",
                    offer_id=offer.id,
                    user_id=guest.id,
                    related_user_id=host.id,
                )
                if notification_delivery_exists(guest_key):
                    skipped["already_sent"] += 1
                elif dry_run:
                    sent += 1
                else:
                    push_sent = send_push_to_user(
                        guest,
                        title="Recensione da lasciare",
                        body=f"Non dimenticare di recensire {host.nome} per {offer.nome_locale}.",
                        target="profile",
                        extra_data={
                            "offer_id": offer.id,
                            "review_reminder": "true",
                            "review_target_id": host.id,
                        },
                    )
                    if push_sent > 0:
                        record_notification_delivery(
                            user_id=guest.id,
                            offer_id=offer.id,
                            reminder_type="review_reminder",
                            dedupe_key=guest_key,
                        )
                        sent += 1
                    else:
                        skipped["missing_token"] += 1

            host_review = Review.query.filter_by(
                reviewer_id=host.id,
                reviewed_id=guest.id,
                offer_id=offer.id,
            ).first()
            if not host_review:
                host_key = build_notification_dedupe_key(
                    "review_reminder",
                    offer_id=offer.id,
                    user_id=host.id,
                    related_user_id=guest.id,
                )
                if notification_delivery_exists(host_key):
                    skipped["already_sent"] += 1
                elif dry_run:
                    sent += 1
                else:
                    push_sent = send_push_to_user(
                        host,
                        title="Recensione da lasciare",
                        body=f"Non dimenticare di recensire {guest.nome} per {offer.nome_locale}.",
                        target="profile",
                        extra_data={
                            "offer_id": offer.id,
                            "review_reminder": "true",
                            "review_target_id": guest.id,
                        },
                    )
                    if push_sent > 0:
                        record_notification_delivery(
                            user_id=host.id,
                            offer_id=offer.id,
                            reminder_type="review_reminder",
                            dedupe_key=host_key,
                        )
                        sent += 1
                    else:
                        skipped["missing_token"] += 1

    return {
        "offers_considered": len(offers),
        "sent": sent,
        "skipped": skipped,
        "threshold": threshold.isoformat(),
    }


def snapshot_offer_notification_state(offer):
    """Cattura i campi dell'offerta utili per notificare modifiche ai partecipanti."""
    return {
        "tipo_pasto": offer.tipo_pasto,
        "nome_locale": offer.nome_locale,
        "indirizzo": offer.indirizzo,
        "data_ora": offer.data_ora,
        "posti_totali": offer.posti_totali,
        "descrizione": (offer.descrizione or "").strip(),
    }


def get_offer_update_changes(previous_state, offer):
    """Elenca i cambiamenti rilevanti per i partecipanti di un evento."""
    changes = []

    if previous_state["tipo_pasto"] != offer.tipo_pasto:
        changes.append(
            f"Tipo di pasto: {get_meal_type_label(previous_state['tipo_pasto'])} -> {get_meal_type_label(offer.tipo_pasto)}"
        )
    if previous_state["nome_locale"] != offer.nome_locale:
        changes.append(f"Locale: {previous_state['nome_locale']} -> {offer.nome_locale}")
    if previous_state["indirizzo"] != offer.indirizzo:
        changes.append(f"Indirizzo: {previous_state['indirizzo']} -> {offer.indirizzo}")
    if previous_state["data_ora"] != offer.data_ora:
        changes.append(
            f"Quando: {previous_state['data_ora'].strftime('%d/%m/%Y alle %H:%M')} -> {offer.data_ora.strftime('%d/%m/%Y alle %H:%M')}"
        )
    if previous_state["posti_totali"] != offer.posti_totali:
        changes.append(f"Posti totali: {previous_state['posti_totali']} -> {offer.posti_totali}")
    if previous_state["descrizione"] != (offer.descrizione or "").strip():
        changes.append("Descrizione aggiornata")

    return changes


def get_offer_notification_claims(offer, include_pending=False):
    """Restituisce i claim da avvisare per aggiornamenti o cancellazioni evento."""
    allowed_statuses = [CLAIM_STATUS_ACCEPTED]
    if include_pending:
        allowed_statuses.append(CLAIM_STATUS_PENDING)

    claims = (
        Claim.query.filter(Claim.offer_id == offer.id, Claim.status.in_(allowed_statuses))
        .options(selectinload(Claim.utente))
        .all()
    )
    return [claim for claim in claims if claim.utente]


def notify_claimants_for_offer_update(offer, previous_state, actor):
    """Avvisa i partecipanti quando un'offerta gia' prenotata viene modificata."""
    changes = get_offer_update_changes(previous_state, offer)
    if not changes:
        return 0

    claims = get_offer_notification_claims(offer, include_pending=False)
    if not claims:
        return 0

    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    actor_name = actor.nome if actor else offer.autore.nome

    notified = 0
    for claim in claims:
        if not claim.utente:
            continue
        if claim.utente.email:
            send_email(
                f"Evento aggiornato: {offer.nome_locale}",
                [claim.utente.email],
                "offer_updated.html",
                user=claim.utente,
                offer=offer,
                actor_name=actor_name,
                data_evento=data_evento,
                changes=changes,
            )
        send_push_to_user(
            claim.utente,
            title="Evento aggiornato",
            body=f"{actor_name} ha aggiornato {offer.nome_locale} - {data_evento}.",
            target="offers",
            extra_data={
                "offer_id": offer.id,
                "updated_by": actor_name,
                "change_count": len(changes),
            },
        )
        notified += 1

    return notified


def ensure_legacy_sqlite_compatibility(sqlite_path):
    """Aggiunge le colonne legacy mancanti per evitare crash su vecchi DB SQLite."""
    conn = sqlite3.connect(sqlite_path)
    try:
        cur = conn.cursor()

        def table_exists(table_name):
            cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (table_name,),
            )
            return cur.fetchone() is not None

        def columns_for(table_name):
            cur.execute(f"PRAGMA table_info({table_name})")
            return {row[1] for row in cur.fetchall()}

        def ensure_column(table_name, column_name, ddl):
            if not table_exists(table_name):
                return
            if column_name in columns_for(table_name):
                return
            cur.execute(ddl)

        legacy_columns = {
            "users": [
                ("eta", "ALTER TABLE users ADD COLUMN eta INTEGER"),
                ("sesso", "ALTER TABLE users ADD COLUMN sesso VARCHAR(20) DEFAULT 'non_dico'"),
                ("numero_telefono", "ALTER TABLE users ADD COLUMN numero_telefono VARCHAR(32)"),
                ("google_sub", "ALTER TABLE users ADD COLUMN google_sub VARCHAR(255)"),
                ("citta", "ALTER TABLE users ADD COLUMN citta VARCHAR(200)"),
                ("cibi_preferiti", "ALTER TABLE users ADD COLUMN cibi_preferiti VARCHAR(300)"),
                ("intolleranze", "ALTER TABLE users ADD COLUMN intolleranze VARCHAR(300)"),
                ("bio", "ALTER TABLE users ADD COLUMN bio VARCHAR(500)"),
                ("bio_moderation_status", "ALTER TABLE users ADD COLUMN bio_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'"),
                ("bio_moderation_reason", "ALTER TABLE users ADD COLUMN bio_moderation_reason VARCHAR(100)"),
                ("bio_moderation_score", "ALTER TABLE users ADD COLUMN bio_moderation_score FLOAT"),
                ("bio_moderation_checked_at", "ALTER TABLE users ADD COLUMN bio_moderation_checked_at DATETIME"),
                ("bio_moderation_provider", "ALTER TABLE users ADD COLUMN bio_moderation_provider VARCHAR(50)"),
                ("bio_moderation_model", "ALTER TABLE users ADD COLUMN bio_moderation_model VARCHAR(100)"),
                ("bio_moderation_raw_json", "ALTER TABLE users ADD COLUMN bio_moderation_raw_json TEXT"),
                ("photo_moderation_status", "ALTER TABLE users ADD COLUMN photo_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'"),
                ("photo_moderation_reason", "ALTER TABLE users ADD COLUMN photo_moderation_reason VARCHAR(100)"),
                ("photo_moderation_score", "ALTER TABLE users ADD COLUMN photo_moderation_score FLOAT"),
                ("photo_moderation_checked_at", "ALTER TABLE users ADD COLUMN photo_moderation_checked_at DATETIME"),
                ("photo_moderation_provider", "ALTER TABLE users ADD COLUMN photo_moderation_provider VARCHAR(50)"),
                ("photo_moderation_model", "ALTER TABLE users ADD COLUMN photo_moderation_model VARCHAR(100)"),
                ("photo_moderation_raw_json", "ALTER TABLE users ADD COLUMN photo_moderation_raw_json TEXT"),
                ("raggio_azione", "ALTER TABLE users ADD COLUMN raggio_azione INTEGER DEFAULT 10"),
                ("live_latitudine", "ALTER TABLE users ADD COLUMN live_latitudine FLOAT"),
                ("live_longitudine", "ALTER TABLE users ADD COLUMN live_longitudine FLOAT"),
                ("live_location_at", "ALTER TABLE users ADD COLUMN live_location_at DATETIME"),
                ("verificato", "ALTER TABLE users ADD COLUMN verificato INTEGER DEFAULT 0"),
                ("verification_token", "ALTER TABLE users ADD COLUMN verification_token VARCHAR(100)"),
                ("password_reset_token", "ALTER TABLE users ADD COLUMN password_reset_token VARCHAR(100)"),
                ("password_reset_sent_at", "ALTER TABLE users ADD COLUMN password_reset_sent_at DATETIME"),
                ("is_admin", "ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0"),
                ("admin_verified_notified_at", "ALTER TABLE users ADD COLUMN admin_verified_notified_at DATETIME"),
                ("approfittoffro_points", "ALTER TABLE users ADD COLUMN approfittoffro_points INTEGER NOT NULL DEFAULT 0"),
                ("terms_accepted_version", "ALTER TABLE users ADD COLUMN terms_accepted_version VARCHAR(32)"),
                ("terms_accepted_at", "ALTER TABLE users ADD COLUMN terms_accepted_at DATETIME"),
                ("privacy_acknowledged_version", "ALTER TABLE users ADD COLUMN privacy_acknowledged_version VARCHAR(32)"),
                ("privacy_acknowledged_at", "ALTER TABLE users ADD COLUMN privacy_acknowledged_at DATETIME"),
            ],
            "offers": [
                ("foto_locale", "ALTER TABLE offers ADD COLUMN foto_locale VARCHAR(256)"),
                ("stato", "ALTER TABLE offers ADD COLUMN stato VARCHAR(20) DEFAULT 'attiva'"),
                ("telefono_locale", "ALTER TABLE offers ADD COLUMN telefono_locale VARCHAR(50)"),
                ("booking_lead_override_minutes", "ALTER TABLE offers ADD COLUMN booking_lead_override_minutes INTEGER"),
                ("description_moderation_status", "ALTER TABLE offers ADD COLUMN description_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'"),
                ("description_moderation_reason", "ALTER TABLE offers ADD COLUMN description_moderation_reason VARCHAR(100)"),
                ("description_moderation_score", "ALTER TABLE offers ADD COLUMN description_moderation_score FLOAT"),
                ("description_moderation_checked_at", "ALTER TABLE offers ADD COLUMN description_moderation_checked_at DATETIME"),
                ("description_moderation_provider", "ALTER TABLE offers ADD COLUMN description_moderation_provider VARCHAR(50)"),
                ("description_moderation_model", "ALTER TABLE offers ADD COLUMN description_moderation_model VARCHAR(100)"),
                ("description_moderation_raw_json", "ALTER TABLE offers ADD COLUMN description_moderation_raw_json TEXT"),
                ("photo_moderation_status", "ALTER TABLE offers ADD COLUMN photo_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'"),
                ("photo_moderation_reason", "ALTER TABLE offers ADD COLUMN photo_moderation_reason VARCHAR(100)"),
                ("photo_moderation_score", "ALTER TABLE offers ADD COLUMN photo_moderation_score FLOAT"),
                ("photo_moderation_checked_at", "ALTER TABLE offers ADD COLUMN photo_moderation_checked_at DATETIME"),
                ("photo_moderation_provider", "ALTER TABLE offers ADD COLUMN photo_moderation_provider VARCHAR(50)"),
                ("photo_moderation_model", "ALTER TABLE offers ADD COLUMN photo_moderation_model VARCHAR(100)"),
                ("photo_moderation_raw_json", "ALTER TABLE offers ADD COLUMN photo_moderation_raw_json TEXT"),
            ],
            "claims": [
                ("status", "ALTER TABLE claims ADD COLUMN status VARCHAR(20) DEFAULT 'accepted'"),
                ("hidden_by_guest", "ALTER TABLE claims ADD COLUMN hidden_by_guest INTEGER DEFAULT 0"),
            ],
            "user_photos": [
                ("status", "ALTER TABLE user_photos ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'"),
                ("moderated_by", "ALTER TABLE user_photos ADD COLUMN moderated_by INTEGER"),
                ("moderated_at", "ALTER TABLE user_photos ADD COLUMN moderated_at DATETIME"),
                ("reason", "ALTER TABLE user_photos ADD COLUMN reason TEXT"),
                ("moderation_status", "ALTER TABLE user_photos ADD COLUMN moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'"),
                ("moderation_reason", "ALTER TABLE user_photos ADD COLUMN moderation_reason VARCHAR(100)"),
                ("moderation_score", "ALTER TABLE user_photos ADD COLUMN moderation_score FLOAT"),
                ("moderation_checked_at", "ALTER TABLE user_photos ADD COLUMN moderation_checked_at DATETIME"),
                ("moderation_provider", "ALTER TABLE user_photos ADD COLUMN moderation_provider VARCHAR(50)"),
                ("moderation_model", "ALTER TABLE user_photos ADD COLUMN moderation_model VARCHAR(100)"),
                ("moderation_raw_json", "ALTER TABLE user_photos ADD COLUMN moderation_raw_json TEXT"),
            ],
            "chat_threads": [
                ("admin_deleted_at", "ALTER TABLE chat_threads ADD COLUMN admin_deleted_at DATETIME"),
                ("admin_delete_after", "ALTER TABLE chat_threads ADD COLUMN admin_delete_after DATETIME"),
                ("admin_delete_reason", "ALTER TABLE chat_threads ADD COLUMN admin_delete_reason TEXT"),
                ("admin_deleted_by_id", "ALTER TABLE chat_threads ADD COLUMN admin_deleted_by_id INTEGER"),
            ],
            "bug_reports": [
                ("screenshot_filename", "ALTER TABLE bug_reports ADD COLUMN screenshot_filename VARCHAR(256)"),
                ("screenshot_original_name", "ALTER TABLE bug_reports ADD COLUMN screenshot_original_name VARCHAR(256)"),
                ("admin_archived_at", "ALTER TABLE bug_reports ADD COLUMN admin_archived_at DATETIME"),
                ("admin_archived_by_id", "ALTER TABLE bug_reports ADD COLUMN admin_archived_by_id INTEGER"),
            ],
        }

        for table_name, columns in legacy_columns.items():
            for column_name, ddl in columns:
                ensure_column(table_name, column_name, ddl)

        if not table_exists("user_photos"):
            cur.execute("""
                CREATE TABLE user_photos (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    filename VARCHAR(256) NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'pending',
                    moderated_by INTEGER,
                    moderated_at DATETIME,
                    reason TEXT,
                    moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved',
                    moderation_reason VARCHAR(100),
                    moderation_score FLOAT,
                    moderation_checked_at DATETIME,
                    moderation_provider VARCHAR(50),
                    moderation_model VARCHAR(100),
                    moderation_raw_json TEXT,
                    created_at DATETIME
                )
            """)

        if not table_exists("offer_photos"):
            cur.execute("""
                CREATE TABLE offer_photos (
                    id INTEGER PRIMARY KEY,
                    offer_id INTEGER NOT NULL,
                    filename VARCHAR(256) NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    created_at DATETIME
                )
            """)

        if not table_exists("user_follows"):
            cur.execute("""
                CREATE TABLE user_follows (
                    id INTEGER PRIMARY KEY,
                    follower_id INTEGER NOT NULL,
                    followed_id INTEGER NOT NULL,
                    created_at DATETIME,
                    CONSTRAINT unique_user_follow UNIQUE (follower_id, followed_id)
                )
            """)

        if not table_exists("ai_moderation_logs"):
            cur.execute("""
                CREATE TABLE ai_moderation_logs (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER,
                    content_type VARCHAR(50) NOT NULL,
                    content_table VARCHAR(50),
                    content_id INTEGER,
                    status VARCHAR(20) NOT NULL,
                    reason VARCHAR(100),
                    score FLOAT,
                    provider VARCHAR(50) NOT NULL DEFAULT 'openai',
                    model VARCHAR(100) NOT NULL DEFAULT 'omni-moderation-latest',
                    raw_json TEXT,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users (id)
                )
            """)

        if not table_exists("bug_reports"):
            cur.execute("""
                CREATE TABLE bug_reports (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    message TEXT NOT NULL,
                    screen_context VARCHAR(120),
                    screenshot_filename VARCHAR(256),
                    screenshot_original_name VARCHAR(256),
                    status VARCHAR(20) NOT NULL DEFAULT 'pending',
                    awarded_points INTEGER NOT NULL DEFAULT 0,
                    admin_note TEXT,
                    reviewed_by_id INTEGER,
                    reviewed_at DATETIME,
                    admin_archived_at DATETIME,
                    admin_archived_by_id INTEGER,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(user_id) REFERENCES users (id),
                    FOREIGN KEY(reviewed_by_id) REFERENCES users (id)
                )
            """)

        if not table_exists("content_reports"):
            cur.execute("""
                CREATE TABLE content_reports (
                    id INTEGER PRIMARY KEY,
                    reporter_id INTEGER NOT NULL,
                    target_type VARCHAR(40) NOT NULL,
                    target_id INTEGER,
                    reported_user_id INTEGER,
                    offer_id INTEGER,
                    chat_thread_id INTEGER,
                    message TEXT NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'pending',
                    admin_note TEXT,
                    reviewed_by_id INTEGER,
                    reviewed_at DATETIME,
                    admin_archived_at DATETIME,
                    admin_archived_by_id INTEGER,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(reporter_id) REFERENCES users (id),
                    FOREIGN KEY(reported_user_id) REFERENCES users (id),
                    FOREIGN KEY(offer_id) REFERENCES offers (id),
                    FOREIGN KEY(chat_thread_id) REFERENCES chat_threads (id),
                    FOREIGN KEY(reviewed_by_id) REFERENCES users (id)
                )
            """)

        if not table_exists("app_notifications"):
            cur.execute("""
                CREATE TABLE app_notifications (
                    id INTEGER PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    title VARCHAR(160) NOT NULL,
                    body TEXT NOT NULL,
                    target VARCHAR(64) NOT NULL DEFAULT 'notifications',
                    extra_data_json TEXT,
                    read_at DATETIME,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at DATETIME NOT NULL,
                    FOREIGN KEY(user_id) REFERENCES users (id)
                )
            """)

        if table_exists("users"):
            cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_sub ON users (google_sub)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_users_bio_moderation_status ON users (bio_moderation_status)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_users_photo_moderation_status ON users (photo_moderation_status)")
        if table_exists("offers"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_offers_description_moderation_status ON offers (description_moderation_status)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_offers_photo_moderation_status ON offers (photo_moderation_status)")
        if table_exists("user_photos"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_user_photos_moderation_status ON user_photos (moderation_status)")
        if table_exists("ai_moderation_logs"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_ai_moderation_logs_user_id ON ai_moderation_logs (user_id)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_ai_moderation_logs_content ON ai_moderation_logs (content_type, content_id)")
        if table_exists("bug_reports"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_bug_reports_user_id ON bug_reports (user_id)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_bug_reports_status ON bug_reports (status)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_bug_reports_created_at ON bug_reports (created_at)")
        if table_exists("content_reports"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_content_reports_reporter_id ON content_reports (reporter_id)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_content_reports_reported_user_id ON content_reports (reported_user_id)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_content_reports_status ON content_reports (status)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_content_reports_created_at ON content_reports (created_at)")
        if table_exists("app_notifications"):
            cur.execute("CREATE INDEX IF NOT EXISTS ix_app_notifications_user_expires ON app_notifications (user_id, expires_at)")
            cur.execute("CREATE INDEX IF NOT EXISTS ix_app_notifications_user_read ON app_notifications (user_id, read_at)")

        conn.commit()
    finally:
        conn.close()


def ensure_database_schema_compatibility():
    """Allinea i campi schema aggiunti dopo il primo deploy anche su database non-SQLite."""
    database_url = app.config["SQLALCHEMY_DATABASE_URI"]
    if database_url.startswith("sqlite:///"):
        return

    try:
        with db.engine.begin() as conn:
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub VARCHAR(255)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_verified_notified_at DATETIME"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS approfittoffro_points INTEGER NOT NULL DEFAULT 0"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_version VARCHAR(32)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMP"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_acknowledged_version VARCHAR(32)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS privacy_acknowledged_at TIMESTAMP"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(100)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_sent_at DATETIME"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS live_latitudine DOUBLE PRECISION"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS live_longitudine DOUBLE PRECISION"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS live_location_at DATETIME"
            )
            for column_sql in [
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_reason VARCHAR(100)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_score DOUBLE PRECISION",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_checked_at TIMESTAMP",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_provider VARCHAR(50)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_model VARCHAR(100)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio_moderation_raw_json TEXT",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_reason VARCHAR(100)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_score DOUBLE PRECISION",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_checked_at TIMESTAMP",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_provider VARCHAR(50)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_model VARCHAR(100)",
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_moderation_raw_json TEXT",
            ]:
                conn.exec_driver_sql(column_sql)
            conn.exec_driver_sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_sub ON users (google_sub)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_users_bio_moderation_status ON users (bio_moderation_status)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_users_photo_moderation_status ON users (photo_moderation_status)"
            )
            conn.exec_driver_sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_password_reset_token ON users (password_reset_token)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE claims ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'accepted'"
            )
            conn.exec_driver_sql(
                "ALTER TABLE claims ADD COLUMN IF NOT EXISTS hidden_by_guest BOOLEAN DEFAULT FALSE"
            )
            conn.exec_driver_sql(
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS booking_lead_override_minutes INTEGER"
            )
            for column_sql in [
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_reason VARCHAR(100)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_score DOUBLE PRECISION",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_checked_at TIMESTAMP",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_provider VARCHAR(50)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_model VARCHAR(100)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS description_moderation_raw_json TEXT",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_reason VARCHAR(100)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_score DOUBLE PRECISION",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_checked_at TIMESTAMP",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_provider VARCHAR(50)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_model VARCHAR(100)",
                "ALTER TABLE offers ADD COLUMN IF NOT EXISTS photo_moderation_raw_json TEXT",
            ]:
                conn.exec_driver_sql(column_sql)
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_offers_description_moderation_status ON offers (description_moderation_status)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_offers_photo_moderation_status ON offers (photo_moderation_status)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE chat_threads ADD COLUMN IF NOT EXISTS admin_deleted_at TIMESTAMP"
            )
            conn.exec_driver_sql(
                "ALTER TABLE chat_threads ADD COLUMN IF NOT EXISTS admin_delete_after TIMESTAMP"
            )
            conn.exec_driver_sql(
                "ALTER TABLE chat_threads ADD COLUMN IF NOT EXISTS admin_delete_reason TEXT"
            )
            conn.exec_driver_sql(
                "ALTER TABLE chat_threads ADD COLUMN IF NOT EXISTS admin_deleted_by_id INTEGER"
            )
            conn.exec_driver_sql(
                """
                CREATE TABLE IF NOT EXISTS offer_photos (
                    id SERIAL PRIMARY KEY,
                    offer_id INTEGER NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
                    filename VARCHAR(256) NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    created_at TIMESTAMP
                )
                """
            )
            for column_sql in [
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending'",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderated_by INTEGER",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderated_at TIMESTAMP",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS reason TEXT",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(20) NOT NULL DEFAULT 'approved'",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_reason VARCHAR(100)",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_score DOUBLE PRECISION",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_checked_at TIMESTAMP",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_provider VARCHAR(50)",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_model VARCHAR(100)",
                "ALTER TABLE user_photos ADD COLUMN IF NOT EXISTS moderation_raw_json TEXT",
            ]:
                conn.exec_driver_sql(column_sql)
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_user_photos_moderation_status ON user_photos (moderation_status)"
            )
            conn.exec_driver_sql(
                """
                CREATE TABLE IF NOT EXISTS ai_moderation_logs (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    content_type VARCHAR(50) NOT NULL,
                    content_table VARCHAR(50),
                    content_id INTEGER,
                    status VARCHAR(20) NOT NULL,
                    reason VARCHAR(100),
                    score DOUBLE PRECISION,
                    provider VARCHAR(50) NOT NULL DEFAULT 'openai',
                    model VARCHAR(100) NOT NULL DEFAULT 'omni-moderation-latest',
                    raw_json TEXT,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_ai_moderation_logs_user_id ON ai_moderation_logs (user_id)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_ai_moderation_logs_content ON ai_moderation_logs (content_type, content_id)"
            )
            conn.exec_driver_sql(
                """
                CREATE TABLE IF NOT EXISTS bug_reports (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    message TEXT NOT NULL,
                    screen_context VARCHAR(120),
                    screenshot_filename VARCHAR(256),
                    screenshot_original_name VARCHAR(256),
                    status VARCHAR(20) NOT NULL DEFAULT 'pending',
                    awarded_points INTEGER NOT NULL DEFAULT 0,
                    admin_note TEXT,
                    reviewed_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    reviewed_at TIMESTAMP,
                    admin_archived_at TIMESTAMP,
                    admin_archived_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            conn.exec_driver_sql(
                "ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS screenshot_filename VARCHAR(256)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS screenshot_original_name VARCHAR(256)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS admin_archived_at TIMESTAMP"
            )
            conn.exec_driver_sql(
                "ALTER TABLE bug_reports ADD COLUMN IF NOT EXISTS admin_archived_by_id INTEGER"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_bug_reports_user_id ON bug_reports (user_id)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_bug_reports_status ON bug_reports (status)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_bug_reports_created_at ON bug_reports (created_at)"
            )
            conn.exec_driver_sql(
                """
                CREATE TABLE IF NOT EXISTS content_reports (
                    id SERIAL PRIMARY KEY,
                    reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    target_type VARCHAR(40) NOT NULL,
                    target_id INTEGER,
                    reported_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    offer_id INTEGER REFERENCES offers(id) ON DELETE SET NULL,
                    chat_thread_id INTEGER REFERENCES chat_threads(id) ON DELETE SET NULL,
                    message TEXT NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'pending',
                    admin_note TEXT,
                    reviewed_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    reviewed_at TIMESTAMP,
                    admin_archived_at TIMESTAMP,
                    admin_archived_by_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_content_reports_reporter_id ON content_reports (reporter_id)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_content_reports_reported_user_id ON content_reports (reported_user_id)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_content_reports_status ON content_reports (status)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_content_reports_created_at ON content_reports (created_at)"
            )
            conn.exec_driver_sql(
                """
                CREATE TABLE IF NOT EXISTS app_notifications (
                    id SERIAL PRIMARY KEY,
                    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    title VARCHAR(160) NOT NULL,
                    body TEXT NOT NULL,
                    target VARCHAR(64) NOT NULL DEFAULT 'notifications',
                    extra_data_json TEXT,
                    read_at TIMESTAMP,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at TIMESTAMP NOT NULL
                )
                """
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_app_notifications_user_expires ON app_notifications (user_id, expires_at)"
            )
            conn.exec_driver_sql(
                "CREATE INDEX IF NOT EXISTS ix_app_notifications_user_read ON app_notifications (user_id, read_at)"
            )
    except Exception as exc:
        print(f"[SCHEMA_COMPAT_ERROR] {exc}")


if app.config["SQLALCHEMY_DATABASE_URI"].startswith("sqlite:///"):
    ensure_legacy_sqlite_compatibility(SQLITE_PATH)

# --- Email Config (Motore Flask-Mail) ---
app.config['MAIL_SERVER'] = 'smtp.gmail.com'
app.config['MAIL_PORT'] = 587
app.config['MAIL_USE_TLS'] = True
app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME', '')
app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD', '')
app.config['MAIL_DEFAULT_SENDER'] = os.getenv('MAIL_DEFAULT_SENDER', os.getenv('MAIL_USERNAME', ''))
app.config['EMAIL_PROVIDER'] = os.getenv('EMAIL_PROVIDER', 'auto').strip().lower()
app.config['RESEND_API_KEY'] = os.getenv('RESEND_API_KEY', '').strip()
app.config['RESEND_REPLY_TO'] = os.getenv('RESEND_REPLY_TO', '').strip()

from flask_mail import Mail, Message
from threading import Thread

mail = Mail(app)

def get_active_email_provider():
    configured = app.config.get("EMAIL_PROVIDER", "auto")
    if configured and configured != "auto":
        return configured
    if app.config.get("RESEND_API_KEY"):
        return "resend"
    if app.config.get("MAIL_USERNAME") and app.config.get("MAIL_PASSWORD"):
        return "smtp"
    return "disabled"


def email_delivery_enabled():
    """Indica se esiste davvero un provider pronto a spedire email."""
    return get_active_email_provider() in {"smtp", "resend"}


def deliver_smtp_email(msg):
    try:
        mail.send(msg)
        print(f"[MAIL_INVIATA] Inviata con successo a: {msg.recipients[0]}")
        return True
    except Exception as e:
        print(f"[MAIL_ERRORE] Impossibile inviare a: {msg.recipients[0]}: {e}")
        return False


def send_async_smtp_email(app, msg):
    with app.app_context():
        deliver_smtp_email(msg)


def deliver_resend_email(payload):
    try:
        api_key = app.config.get("RESEND_API_KEY", "")
        if not api_key:
            raise RuntimeError("RESEND_API_KEY mancante.")

        request_payload = {
            "from": payload["from_email"],
            "to": payload["recipients"],
            "subject": payload["subject"],
            "html": payload["html_body"],
        }
        if payload.get("reply_to"):
            request_payload["reply_to"] = payload["reply_to"]

        request = Request(
            "https://api.resend.com/emails",
            data=json.dumps(request_payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        with urlopen(request, timeout=20) as response:
            response.read()
        print(f"[MAIL_INVIATA_RESEND] Inviata con successo a: {payload['recipients'][0]}")
        return True
    except HTTPError as e:
        try:
            details = e.read().decode("utf-8", errors="ignore")
        except Exception:
            details = ""
        print(
            f"[MAIL_ERRORE_RESEND] HTTP {e.code} verso {payload['recipients'][0]}: {details}"
        )
    except URLError as e:
        print(f"[MAIL_ERRORE_RESEND] Errore di rete verso {payload['recipients'][0]}: {e}")
    except Exception as e:
        print(f"[MAIL_ERRORE_RESEND] Impossibile inviare a: {payload['recipients'][0]}: {e}")
    return False


def send_async_resend_email(app, payload):
    with app.app_context():
        deliver_resend_email(payload)


def send_email(subject, recipients, template, background=True, **kwargs):
    """Renderizza e invia un'email, in background o subito secondo il flusso."""
    try:
        allow_push_primary_fallback = bool(
            kwargs.pop("_allow_push_primary_email_fallback", False)
        )
        if (
            template in PUSH_PRIMARY_EMAIL_TEMPLATES
            and push_delivery_enabled()
            and not allow_push_primary_fallback
        ):
            print(
                f"[MAIL_SKIP_PUSH_PRIMARY] template={template} subject={subject} recipients={recipients}"
            )
            return False
        html_body = render_template(f"emails/{template}", **kwargs)
        return send_email_html(
            subject,
            recipients,
            html_body,
            background=background,
        )
    except Exception as e:
        print(f"[MAIL_ERROR] Errore preparazione email {template}: {e}")
        return False


def send_email_html(subject, recipients, html_body, background=True):
    """Invia un contenuto HTML gia' pronto tramite il provider configurato."""
    try:
        provider = get_active_email_provider()
        if provider == "smtp":
            msg = Message(subject, recipients=recipients)
            msg.html = html_body
            if background:
                Thread(target=send_async_smtp_email, args=(app, msg)).start()
                return True
            return deliver_smtp_email(msg)

        if provider == "resend":
            payload = {
                "subject": subject,
                "recipients": recipients,
                "html_body": html_body,
                "from_email": app.config.get("MAIL_DEFAULT_SENDER"),
                "reply_to": app.config.get("RESEND_REPLY_TO") or None,
            }
            if background:
                Thread(target=send_async_resend_email, args=(app, payload)).start()
                return True
            return deliver_resend_email(payload)

        print(
            f"[MAIL_SKIP] Nessun provider email configurato. Salto invio '{subject}' a {recipients}."
        )
        return False
    except Exception as e:
        print(f"[MAIL_ERROR] Errore invio email '{subject}': {e}")
        return False


_firebase_credentials_cache = None


def _load_firebase_service_account_info():
    raw_json = app.config.get("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    if raw_json:
        try:
            return json.loads(raw_json)
        except json.JSONDecodeError as exc:
            print(f"[PUSH_CONFIG_ERROR] FIREBASE_SERVICE_ACCOUNT_JSON non valido: {exc}")
            return None

    file_path = app.config.get("FIREBASE_SERVICE_ACCOUNT_FILE", "").strip()
    if not file_path:
        return None
    if not os.path.exists(file_path):
        print(f"[PUSH_CONFIG_ERROR] File service account Firebase non trovato: {file_path}")
        return None
    try:
        with open(file_path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        print(f"[PUSH_CONFIG_ERROR] Impossibile leggere il service account Firebase: {exc}")
        return None


def get_firebase_project_id():
    configured = app.config.get("FIREBASE_PROJECT_ID", "").strip()
    if configured:
        return configured
    info = _load_firebase_service_account_info() or {}
    return str(info.get("project_id", "") or "").strip()


def get_firebase_credentials():
    global _firebase_credentials_cache
    if _firebase_credentials_cache is not None:
        return _firebase_credentials_cache

    info = _load_firebase_service_account_info()
    if not info:
        return None

    try:
        _firebase_credentials_cache = service_account.Credentials.from_service_account_info(
            info,
            scopes=[FCM_SCOPE],
        )
        return _firebase_credentials_cache
    except Exception as exc:
        print(f"[PUSH_CONFIG_ERROR] Service account Firebase non utilizzabile: {exc}")
        return None


def push_delivery_enabled():
    return bool(get_firebase_project_id() and get_firebase_credentials())


def get_firebase_access_token():
    credentials = get_firebase_credentials()
    if not credentials:
        return ""

    try:
        if not credentials.valid or credentials.expired or not credentials.token:
            credentials.refresh(GoogleAuthRequest())
        return credentials.token or ""
    except Exception as exc:
        print(f"[PUSH_AUTH_ERROR] Impossibile ottenere access token Firebase: {exc}")
        return ""


def build_push_target_deeplink(target):
    normalized = str(target or "").strip().lower()
    if normalized == "pending-requests":
        return f"{PUSH_DEEP_LINK_BASE}profile/pending-requests"
    if normalized == "notifications":
        return f"{PUSH_DEEP_LINK_BASE}profile/notifications"
    if normalized == "profile":
        return f"{PUSH_DEEP_LINK_BASE}profile"
    if normalized == "offers":
        return f"{PUSH_DEEP_LINK_BASE}offers"
    return f"{PUSH_DEEP_LINK_BASE}login"


def deactivate_push_token(token_record, *, reason=""):
    if not token_record or not token_record.active:
        return
    token_record.active = False
    token_record.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.session.commit()
    print(
        f"[PUSH_TOKEN_DEACTIVATED] token_id={token_record.id} "
        f"user_id={token_record.user_id} reason={reason or '-'}"
    )


def purge_expired_app_notifications(user_id=None):
    now = datetime.now()
    query = AppNotification.query.filter(AppNotification.expires_at <= now)
    if user_id is not None:
        query = query.filter(AppNotification.user_id == user_id)
    deleted = query.delete(synchronize_session=False)
    if deleted:
        db.session.commit()
    return deleted


def create_app_notification(user, *, title, body, target="notifications", extra_data=None):
    """Salva una copia interna dell'avviso, visibile nel profilo per 24 ore."""
    if not user:
        return None
    clean_title = str(title or "").strip()[:160]
    clean_body = str(body or "").strip()
    if not clean_title and not clean_body:
        return None
    now = datetime.now()
    notification = AppNotification(
        user_id=user.id,
        title=clean_title or "ApprofittOffro",
        body=clean_body,
        target=str(target or "notifications").strip()[:64] or "notifications",
        extra_data_json=json.dumps(extra_data or {}, ensure_ascii=False),
        created_at=now,
        expires_at=now + timedelta(hours=24),
    )
    db.session.add(notification)
    db.session.commit()
    purge_expired_app_notifications(user.id)
    return notification


def user_has_accepted_current_legal(user):
    if not user:
        return False
    return (
        getattr(user, "terms_accepted_version", None) == LEGAL_TERMS_VERSION
        and getattr(user, "privacy_acknowledged_version", None) == LEGAL_PRIVACY_VERSION
        and getattr(user, "terms_accepted_at", None) is not None
        and getattr(user, "privacy_acknowledged_at", None) is not None
    )


def build_legal_status_payload(user):
    accepted = user_has_accepted_current_legal(user)
    return {
        "current_terms_version": LEGAL_TERMS_VERSION,
        "current_privacy_version": LEGAL_PRIVACY_VERSION,
        "terms_url": TERMS_AND_CONDITIONS_URL,
        "privacy_url": PRIVACY_POLICY_URL,
        "community_rules_url": COMMUNITY_RULES_URL,
        "accepted": accepted,
        "terms_accepted_version": getattr(user, "terms_accepted_version", "") or "",
        "terms_accepted_at": (
            user.terms_accepted_at.isoformat()
            if getattr(user, "terms_accepted_at", None)
            else ""
        ),
        "privacy_acknowledged_version": getattr(user, "privacy_acknowledged_version", "") or "",
        "privacy_acknowledged_at": (
            user.privacy_acknowledged_at.isoformat()
            if getattr(user, "privacy_acknowledged_at", None)
            else ""
        ),
    }


def accept_current_legal_for_user(user):
    now = datetime.now()
    user.terms_accepted_version = LEGAL_TERMS_VERSION
    user.terms_accepted_at = now
    user.privacy_acknowledged_version = LEGAL_PRIVACY_VERSION
    user.privacy_acknowledged_at = now


def require_legal_acceptance_json(user=None):
    target_user = user or current_user
    if is_admin_user(target_user) or user_has_accepted_current_legal(target_user):
        return None
    return jsonify({
        "success": False,
        "error": "Prima di continuare devi accettare Termini, Regolamento Community e Informativa privacy.",
        "legal_required": True,
        "legal": build_legal_status_payload(target_user),
    }), 403


def send_push_to_user(user, *, title, body, target="login", extra_data=None):
    if not user:
        return 0
    create_app_notification(
        user,
        title=title,
        body=body,
        target=target,
        extra_data=extra_data,
    )
    if not push_delivery_enabled():
        print(
            f"[PUSH_SKIP] Firebase non configurato. user={getattr(user, 'id', None)} title={title}"
        )
        return 0

    project_id = get_firebase_project_id()
    access_token = get_firebase_access_token()
    if not project_id or not access_token:
        print(
            f"[PUSH_SKIP] Credenziali Firebase incomplete. user={getattr(user, 'id', None)} title={title}"
        )
        return 0

    tokens = (
        DevicePushToken.query.filter_by(user_id=user.id, active=True)
        .order_by(
            DevicePushToken.last_seen_at.desc(),
            DevicePushToken.created_at.desc(),
        )
        .all()
    )
    if not tokens:
        print(f"[PUSH_SKIP] Nessun token attivo per user={user.id} title={title}")
        return 0

    payload_data = {
        "target": str(target or "login"),
        "deep_link": build_push_target_deeplink(target),
    }
    for key, value in (extra_data or {}).items():
        payload_data[str(key)] = str(value)

    endpoint = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    success_count = 0

    for token_record in tokens:
        body_payload = {
            "message": {
                "token": token_record.token,
                "notification": {
                    "title": title,
                    "body": body,
                },
                "data": payload_data,
                "android": {
                    "priority": "high",
                    "notification": {
                        "channel_id": PUSH_CHANNEL_ID,
                        "click_action": "FLUTTER_NOTIFICATION_CLICK",
                    },
                },
            }
        }
        request_body = json.dumps(body_payload).encode("utf-8")
        req = Request(
            endpoint,
            data=request_body,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json; charset=utf-8",
            },
            method="POST",
        )
        try:
            with urlopen(req, timeout=20) as response:
                response.read()
            token_record.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)
            db.session.commit()
            success_count += 1
            print(
                f"[PUSH_SENT] user={user.id} token_id={token_record.id} target={target} title={title}"
            )
        except HTTPError as exc:
            details = ""
            try:
                details = exc.read().decode("utf-8", errors="replace")
            except Exception:
                details = ""
            print(
                f"[PUSH_ERROR] user={user.id} token_id={token_record.id} status={exc.code} body={details}"
            )
            if "UNREGISTERED" in details or "registration-token-not-registered" in details:
                deactivate_push_token(token_record, reason="unregistered")
            elif "INVALID_ARGUMENT" in details and "token" in details.lower():
                deactivate_push_token(token_record, reason="invalid-token")
        except Exception as exc:
            print(
                f"[PUSH_ERROR] user={user.id} token_id={token_record.id} "
                f"target={target} error={exc}"
            )

    return success_count


def send_operational_notification(
    user,
    *,
    push_title,
    push_body,
    target="login",
    extra_data=None,
    email_subject=None,
    email_template=None,
    email_recipients=None,
    email_background=False,
    email_context=None,
):
    """Invia prima una push e usa la mail solo come fallback se la push non parte."""
    push_sent = send_push_to_user(
        user,
        title=push_title,
        body=push_body,
        target=target,
        extra_data=extra_data,
    )

    email_sent = False
    recipients = [item for item in (email_recipients or []) if item]
    if push_sent <= 0 and recipients and email_subject and email_template:
        email_sent = bool(
            send_email(
                email_subject,
                recipients,
                email_template,
                background=email_background,
                _allow_push_primary_email_fallback=True,
                **(email_context or {}),
            )
        )
    return {"push_sent": push_sent, "email_sent": email_sent}


def build_verification_email_html(user, link_verifica):
    """Costruisce un contenuto di verifica robusto e pulito, anche come fallback."""
    return render_template(
        "emails/verification.html",
        user=user,
        link_verifica=link_verifica,
    )


def send_registration_verification_email(user, link_verifica):
    """Invia la mail di verifica con un fallback semplificato se il template fallisce."""
    subject = "Benvenuto su ApprofittOffro! Conferma la tua email"

    try:
        html_body = build_verification_email_html(user, link_verifica)
    except Exception as exc:
        print(f"[MAIL_ERROR] Template verification.html non renderizzabile: {exc}")
        html_body = f"""
        <html>
          <body style="font-family: Arial, sans-serif; background:#F2EEEC; padding:24px; color:#2B2D42;">
            <div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:18px;padding:32px;border:1px solid #E5E0DC;">
              <h1 style="margin-top:0;">Benvenuto in ApprofittOffro, {escape(user.nome)}!</h1>
              <p>Per iniziare a usare la community in sicurezza, conferma il tuo indirizzo email.</p>
              <p>
                <a href="{escape(link_verifica)}" style="display:inline-block;background:#0EA5E9;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:bold;">
                  Conferma la mia email
                </a>
              </p>
              <p style="font-size:13px;color:#6B7280;">Se non hai richiesto tu l'iscrizione, ignora semplicemente questa email.</p>
            </div>
          </body>
        </html>
        """

    return send_email_html(
        subject,
        [user.email],
        html_body,
        background=False,
    )


def user_can_change_password(user):
    return bool(user) and not bool(getattr(user, "google_sub", None))


def build_password_reset_link(token):
    return url_for("password_reset_page", token=token, _external=True)


def get_password_reset_deadline(sent_at):
    if not sent_at:
        return None
    return sent_at + timedelta(hours=PASSWORD_RESET_TOKEN_HOURS)


def get_user_by_valid_password_reset_token(token):
    raw_token = str(token or "").strip()
    if not raw_token:
        return None
    user = User.query.filter_by(password_reset_token=raw_token).first()
    if not user:
        return None
    deadline = get_password_reset_deadline(user.password_reset_sent_at)
    if not deadline or deadline < local_now():
        return None
    return user


def clear_password_reset_state(user):
    if not user:
        return
    user.password_reset_token = None
    user.password_reset_sent_at = None


def build_password_reset_email_html(user, link_reset, valid_for_hours):
    return render_template(
        "emails/password_reset.html",
        user=user,
        link_reset=link_reset,
        valid_for_hours=valid_for_hours,
    )


def send_password_reset_email(user):
    if not user or not user.email:
        return False

    link_reset = build_password_reset_link(user.password_reset_token)
    subject = "ApprofittOffro - Reimposta la tua password"

    try:
        html_body = build_password_reset_email_html(
            user,
            link_reset,
            PASSWORD_RESET_TOKEN_HOURS,
        )
    except Exception as exc:
        print(f"[MAIL_ERROR] Template password_reset.html non renderizzabile: {exc}")
        html_body = f"""
        <html>
          <body style="font-family: Arial, sans-serif; background:#F2EEEC; padding:24px; color:#2B2D42;">
            <div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:18px;padding:32px;border:1px solid #E5E0DC;">
              <h1 style="margin-top:0;">Reimposta la tua password</h1>
              <p>Ciao {escape(user.nome)}, abbiamo ricevuto una richiesta di recupero password per ApprofittOffro.</p>
              <p>
                <a href="{escape(link_reset)}" style="display:inline-block;background:#0EA5E9;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:bold;">
                  Scegli una nuova password
                </a>
              </p>
              <p style="font-size:13px;color:#6B7280;">Il link resta valido per {PASSWORD_RESET_TOKEN_HOURS} ore. Se non hai richiesto tu il reset, puoi ignorare questa email.</p>
            </div>
          </body>
        </html>
        """

    return send_email_html(
        subject,
        [user.email],
        html_body,
        background=False,
    )


def notify_admin_for_verified_user(user, source="email"):
    """Avvisa l'amministratore quando un utente risulta verificato."""
    admin_email = os.getenv("ADMIN_EMAIL")
    if not admin_email:
        print("[MAIL_SKIP] ADMIN_EMAIL non configurata, notifica admin saltata.")
        return False
    if getattr(user, "admin_verified_notified_at", None):
        print(
            f"[ADMIN_VERIFY_MAIL] user={getattr(user, 'id', None)} "
            f"email={getattr(user, 'email', '')} source={source} sent=False already_notified=True"
        )
        return False

    source_label = "Google" if source == "google" else "Email"
    created_at = getattr(user, "created_at", None)
    created_at_text = (
        created_at.strftime("%d/%m/%Y %H:%M")
        if created_at is not None
        else datetime.now().strftime("%d/%m/%Y %H:%M")
    )
    html_body = f"""
    <html>
      <body style="font-family: Arial, sans-serif; background:#F2EEEC; padding:24px; color:#2B2D42;">
        <div style="max-width:600px;margin:0 auto;background:#ffffff;border-radius:18px;padding:32px;border:1px solid #E5E0DC;">
          <h1 style="margin-top:0;">Nuovo utente verificato</h1>
          <p>Un nuovo utente si è registrato ed è già verificato su <b>ApprofittOffro</b>.</p>
          <div style="background:#F8F5F2;border:1px solid #E5E0DC;border-radius:14px;padding:16px;">
            <p><b>Nome:</b> {escape(user.nome or '')}</p>
            <p><b>Email:</b> {escape(user.email or '')}</p>
            <p><b>Metodo:</b> {escape(source_label)}</p>
            <p><b>Registrato il:</b> {escape(created_at_text)}</p>
          </div>
        </div>
      </body>
    </html>
    """
    sent = send_email_html(
        subject=f"Nuovo Utente Verificato: {user.nome}",
        recipients=[admin_email],
        html_body=html_body,
        background=False,
    )
    if sent:
        user.admin_verified_notified_at = datetime.now()
        db.session.commit()
    print(
        f"[ADMIN_VERIFY_MAIL] user={getattr(user, 'id', None)} email={getattr(user, 'email', '')} "
        f"source={source_label} sent={sent}"
    )
    return sent

def process_image(file_storage, filename, size=(800, 800), return_payload=False, quality=85):
    """Ruota (EXIF), ridimensiona e salva un'immagine sul backend attivo."""
    payload = None

    try:
        from PIL import ImageOps

        if hasattr(file_storage, "stream") and hasattr(file_storage.stream, "seek"):
            file_storage.stream.seek(0)
            source_stream = file_storage.stream
        else:
            source_stream = file_storage

        img = Image.open(source_stream)
        img = ImageOps.exif_transpose(img)
        if img.mode != "RGB":
            img = img.convert("RGB")
        img.thumbnail(size, Image.LANCZOS)

        final_filename = filename.rsplit(".", 1)[0] + ".jpg"
        output = io.BytesIO()
        img.save(output, "JPEG", quality=quality)
        payload = {
            "filename": final_filename,
            "bytes": output.getvalue(),
            "content_type": "image/jpeg",
        }
    except Exception as e:
        print(f"[IMAGE_ERROR] Errore processamento {filename}: {e}")
        if hasattr(file_storage, "stream") and hasattr(file_storage.stream, "seek"):
            file_storage.stream.seek(0)
            raw_bytes = file_storage.stream.read()
        else:
            raw_bytes = file_storage.read()

        payload = {
            "filename": filename,
            "bytes": raw_bytes,
            "content_type": getattr(file_storage, "mimetype", None) or "application/octet-stream",
        }
    finally:
        if hasattr(file_storage, "stream") and hasattr(file_storage.stream, "seek"):
            file_storage.stream.seek(0)

    if return_payload:
        return payload

    upload_storage.save_bytes(
        payload["filename"],
        payload["bytes"],
        payload.get("content_type"),
    )
    return payload["filename"]


class MemoryUpload:
    """Wrapper minimale per trattare bytes remoti come upload locale."""

    def __init__(self, data, content_type="application/octet-stream"):
        self.stream = io.BytesIO(data)
        self.mimetype = content_type

    def read(self):
        return self.stream.read()


def verify_image_payload_has_face(image_payload):
    """Verifica il volto su un file temporaneo locale ricavato dal payload elaborato."""
    suffix = os.path.splitext(image_payload["filename"])[1] or ".jpg"
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as handle:
            handle.write(image_payload["bytes"])
            temp_path = handle.name
        return verifica_volto(temp_path)
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


def ensure_default_profile_placeholder(filename=DEFAULT_PROFILE_PLACEHOLDER_FILENAME):
    """Crea un avatar neutro per i profili generati via provider esterni."""
    try:
        upload_storage.read(filename)
        return filename
    except StorageObjectNotFound:
        pass

    image = Image.new("RGB", (512, 512), "#F6EFE6")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((48, 48, 464, 464), radius=140, fill="#E56F36")
    draw.ellipse((168, 118, 344, 294), fill="#FFF8F1")
    draw.rounded_rectangle((132, 286, 380, 430), radius=84, fill="#FFF8F1")

    output = io.BytesIO()
    image.save(output, "PNG")
    upload_storage.save_bytes(filename, output.getvalue(), "image/png")
    return filename


def is_placeholder_profile_photo(filename):
    """Indica se un filename corrisponde all'avatar neutro generato dal backend."""
    return str(filename or "").strip().lower() == DEFAULT_PROFILE_PLACEHOLDER_FILENAME


def filter_visible_profile_photos(filenames):
    """Esclude placeholder e valori vuoti dalle foto considerate valide per il profilo."""
    return [
        filename
        for filename in (str(item or "").strip() for item in filenames or [])
        if filename and not is_placeholder_profile_photo(filename)
    ]


def get_visible_profile_gallery_filenames(user, *, include_gallery=False):
    """Restituisce solo le foto profilo reali e visibili per API e onboarding."""
    filenames = list(user.gallery_filenames if include_gallery else user.gallery_filenames[:2])
    return filter_visible_profile_photos(filenames)


def get_primary_photo_filename(user):
    """Restituisce la foto principale reale da usare nelle preview chat/profili."""
    if not user:
        return ""

    direct_photo = str(getattr(user, "foto_filename", "") or "").strip()
    if direct_photo and not is_placeholder_profile_photo(direct_photo):
        return direct_photo

    visible_gallery = get_visible_profile_gallery_filenames(user, include_gallery=True)
    if visible_gallery:
        return visible_gallery[0]
    return ""


def user_has_visible_profile_photo(user):
    """Indica se il profilo possiede almeno una foto reale e non un placeholder."""
    return bool(filter_visible_profile_photos(user.gallery_filenames))


def download_google_profile_photo(picture_url, user_key):
    """Scarica e salva l'avatar Google, se disponibile."""
    if not picture_url:
        return None

    try:
        response = urlopen(
            Request(
                picture_url,
                headers={"User-Agent": "ApprofittOffro/1.0"},
            ),
            timeout=8,
        )
        content_type = response.headers.get_content_type() or "image/jpeg"
        image_bytes = response.read()
        if not image_bytes:
            return None

        extension = "png" if "png" in content_type else "jpg"
        payload = process_image(
            MemoryUpload(image_bytes, content_type),
            f"user_google_{user_key}_{uuid.uuid4().hex[:10]}.{extension}",
            return_payload=True,
        )
        verifica = verify_image_payload_has_face(payload)
        if not verifica["valida"]:
            print(
                "[GOOGLE_PHOTO_INVALID] "
                f"user_key={user_key} detail={verifica.get('errore', 'volto non riconosciuto')}"
            )
            return None
        upload_storage.save_bytes(
            payload["filename"],
            payload["bytes"],
            payload.get("content_type"),
        )
        return payload["filename"]
    except Exception as exc:
        print(f"[GOOGLE_PHOTO_ERROR] {exc}")
        return None

# ---------------------------------------------------------------------------
# Inizializzazione
# ---------------------------------------------------------------------------
db.init_app(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = "login_page"
login_manager.login_message = "Devi effettuare il login per accedere."


@login_manager.user_loader
def load_user(user_id):
    return db.session.get(User, int(user_id))


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def extract_uploaded_photos(field_name="foto"):
    """Recupera le foto caricate da un input multiplo, ignorando elementi vuoti."""
    return [photo for photo in request.files.getlist(field_name) if photo and photo.filename]


def delete_upload_files(filenames):
    """Elimina una lista di file caricati, ignorando silenziosamente quelli mancanti."""
    for filename in {name for name in filenames if name and name != "nessuna.jpg"}:
        upload_storage.delete(filename)


def save_profile_gallery_files(user_key, photos, require_primary_face=True, return_moderation=False):
    """Salva fino a MAX_PROFILE_PHOTOS immagini profilo e verifica il volto sulla prima."""
    def result(filenames, errors, moderation_results=None):
        moderation_results = moderation_results or []
        if return_moderation:
            return filenames, errors, moderation_results
        return filenames, errors

    if not photos:
        return result([], [])

    errors = []
    if len(photos) > MAX_PROFILE_PHOTOS:
        errors.append(f"Puoi caricare al massimo {MAX_PROFILE_PHOTOS} foto profilo.")

    for photo in photos:
        if not allowed_file(photo.filename):
            errors.append("Formato foto non valido. Usa JPG, PNG o WEBP.")
            break

    if errors:
        return result([], errors)

    saved_filenames = []
    moderation_results = []
    for index, photo in enumerate(photos):
        ext = photo.filename.rsplit(".", 1)[1].lower() if "." in photo.filename else "jpg"
        image_payload = process_image(
            photo,
            f"user_{user_key}_{uuid.uuid4().hex[:10]}.{ext}",
            return_payload=True,
        )

        if index == 0 and require_primary_face:
            verifica = verify_image_payload_has_face(image_payload)
            if not verifica["valida"]:
                delete_upload_files(saved_filenames)
                dettaglio = verifica.get("errore", "Il volto non e stato riconosciuto in modo affidabile.")
                return result([], [
                    "La prima foto deve mostrare chiaramente il volto della persona. "
                    "Carica come prima immagine una foto reale, frontale o comunque ben visibile. "
                    f"Dettaglio: {dettaglio}"
                ])

        moderation_results.append({
            "filename": image_payload["filename"],
            "result": moderate_image_payload(image_payload),
        })

        upload_storage.save_bytes(
            image_payload["filename"],
            image_payload["bytes"],
            image_payload.get("content_type"),
        )
        saved_filenames.append(image_payload["filename"])

    return result(saved_filenames, [], moderation_results)


def replace_user_gallery(user, filenames):
    """Sostituisce la galleria utente mantenendo la prima foto come avatar principale."""
    old_filenames = list(user.gallery_filenames)
    for photo in list(user.photos):
        db.session.delete(photo)
    db.session.flush()

    for position, filename in enumerate(filenames):
        db.session.add(UserPhoto(user_id=user.id, filename=filename, position=position))

    user.foto_filename = filenames[0]
    db.session.flush()
    db.session.expire(user, ["photos"])
    return [filename for filename in old_filenames if filename not in filenames]


def save_offer_gallery_files(user_key, photos):
    """Salva fino a MAX_OFFER_PHOTOS immagini evento, restituendo i filename finali."""
    if not photos:
        return [], []

    errors = []
    if len(photos) > MAX_OFFER_PHOTOS:
        errors.append(f"Puoi caricare al massimo {MAX_OFFER_PHOTOS} foto evento.")

    for photo in photos:
        if not allowed_file(photo.filename):
            errors.append("Formato foto evento non valido. Usa JPG, PNG o WEBP.")
            break

    if errors:
        return [], errors

    saved_filenames = []
    for photo in photos:
        ext = photo.filename.rsplit(".", 1)[1].lower() if "." in photo.filename else "jpg"
        image_payload = process_image(
            photo,
            f"offer_{user_key}_{uuid.uuid4().hex[:10]}.{ext}",
            return_payload=True,
        )
        upload_storage.save_bytes(
            image_payload["filename"],
            image_payload["bytes"],
            image_payload.get("content_type"),
        )
        saved_filenames.append(image_payload["filename"])

    return saved_filenames, []


def replace_offer_gallery(offer, filenames):
    """Sostituisce la galleria evento mantenendo la prima foto come principale."""
    old_filenames = list(offer.gallery_filenames)
    for photo in list(offer.photos):
        db.session.delete(photo)
    db.session.flush()

    for position, filename in enumerate(filenames):
        db.session.add(OfferPhoto(offer_id=offer.id, filename=filename, position=position))

    offer.foto_locale = filenames[0] if filenames else "nessuna.jpg"
    db.session.flush()
    db.session.expire(offer, ["photos"])
    return [filename for filename in old_filenames if filename not in filenames]


def build_google_display_name(identity_payload):
    """Determina un nome utente pulito a partire dai dati Google."""
    raw_name = str(identity_payload.get("name", "") or "").strip()
    if raw_name:
        return raw_name[:100]

    email = str(identity_payload.get("email", "") or "").strip().lower()
    local_part = email.split("@", 1)[0] if "@" in email else email
    fallback = local_part.replace(".", " ").replace("_", " ").strip()
    return (fallback.title() or "Nuovo utente")[:100]


def verify_google_identity_token(raw_token):
    """Verifica il token Google e restituisce i claim essenziali."""
    if not google_oauth_enabled():
        raise ValueError("Login Google non configurato su questo ambiente.")
    if not raw_token:
        raise ValueError("Token Google mancante.")

    try:
        identity_payload = google_id_token.verify_oauth2_token(
            raw_token,
            GoogleAuthRequest(),
            audience=None,
        )
    except Exception as exc:
        raise ValueError("Token Google non valido.") from exc

    allowed_client_ids = get_google_oauth_client_ids()
    audience = str(identity_payload.get("aud", "") or "").strip()
    issuer = str(identity_payload.get("iss", "") or "").strip()
    email = str(identity_payload.get("email", "") or "").strip().lower()
    google_sub = str(identity_payload.get("sub", "") or "").strip()

    if audience not in allowed_client_ids:
        raise ValueError("Client Google non autorizzato.")
    if issuer not in {"accounts.google.com", "https://accounts.google.com"}:
        raise ValueError("Token Google non valido.")
    if not identity_payload.get("email_verified"):
        raise ValueError("L'account Google deve avere un'email verificata.")
    if not email or not google_sub:
        raise ValueError("Google non ha restituito dati sufficienti per il login.")

    return {
        "sub": google_sub,
        "email": email,
        "name": build_google_display_name(identity_payload),
        "picture": str(identity_payload.get("picture", "") or "").strip(),
    }


def resolve_google_user(identity_payload):
    """Trova o crea l'utente associato all'identità Google verificata."""
    google_sub = identity_payload["sub"]
    email = identity_payload["email"]
    display_name = identity_payload["name"]
    picture_url = identity_payload.get("picture", "")

    user = User.query.filter_by(google_sub=google_sub).first()
    if user:
        if is_admin_user(user):
            raise ValueError("Per ora l'accesso Google non è disponibile per gli account admin.")
        if user.email != email:
            conflicting_user = User.query.filter_by(email=email).first()
            if conflicting_user and conflicting_user.id != user.id:
                raise ValueError("Questa email Google è già collegata a un altro account.")
            user.email = email
        if not user.nome:
            user.nome = display_name
        should_notify_admin = user.admin_verified_notified_at is None
        user.verificato = True
        user.verification_token = None
        db.session.commit()
        return user, False, should_notify_admin

    user = User.query.filter_by(email=email).first()
    if user:
        if is_admin_user(user):
            raise ValueError("Per ora l'accesso Google non è disponibile per gli account admin.")
        if user.google_sub and user.google_sub != google_sub:
            raise ValueError("Questo account è già collegato a un altro accesso Google.")
        user.google_sub = google_sub
        if not user.nome:
            user.nome = display_name
        should_notify_admin = user.admin_verified_notified_at is None
        user.verificato = True
        user.verification_token = None
        db.session.commit()
        return user, False, should_notify_admin

    photo_filename = download_google_profile_photo(picture_url, google_sub[:10]) or ""

    user = User(
        nome=display_name,
        email=email,
        password_hash="",
        google_sub=google_sub,
        foto_filename=photo_filename,
        fascia_eta="18-25",
        eta=None,
        sesso="non_dico",
        numero_telefono=None,
        latitudine=DEFAULT_USER_LATITUDE,
        longitudine=DEFAULT_USER_LONGITUDE,
        citta="",
        cibi_preferiti="",
        intolleranze="",
        bio="",
        verificato=True,
        verification_token=None,
        is_admin=False,
    )
    user.set_password(uuid.uuid4().hex)
    db.session.add(user)
    db.session.flush()
    if photo_filename:
        replace_user_gallery(user, [photo_filename])
        photo_moderation_result = apply_user_photo_moderation(
            user,
            [{
                "filename": photo_filename,
                "result": moderate_saved_profile_photo(photo_filename),
            }],
            allow_auto_approve=True,
        )
        notify_admin_for_user_moderation(
            user,
            photo_moderation_result,
            content_label="Foto profilo",
        )
    db.session.commit()
    return user, True, True


def get_followed_user_ids(user_id):
    return {
        row.followed_id
        for row in UserFollow.query.filter_by(follower_id=user_id).all()
    }


def get_profile_form_values(user, source=None):
    has_source = source is not None
    source = source or {}
    eta_value = user.eta if user.eta is not None else str(user.fascia_eta).split("-", 1)[0].replace("+", "")
    return {
        "nome": (source.get("nome") if source else user.nome) or user.nome,
        "email": (source.get("email") if source else user.email) or user.email,
        "eta": (source.get("eta") if source else eta_value) or eta_value,
        "numero_telefono": (source.get("numero_telefono") if source else (user.numero_telefono or "")) or "",
        "citta": (source.get("citta") if source else (user.citta or "")) or "",
        "latitudine": source.get("latitudine") if has_source else user.latitudine,
        "longitudine": source.get("longitudine") if has_source else user.longitudine,
        "cibi_preferiti": (source.get("cibi_preferiti") if source else (user.cibi_preferiti or "")) or "",
        "intolleranze": (source.get("intolleranze") if source else (user.intolleranze or "")) or "",
        "bio": (source.get("bio") if source else (user.bio or "")) or "",
        "verificato": (
            str(source.get("verificato", "")).lower() in {"1", "true", "on", "yes"}
            if source
            else bool(user.verificato)
        ),
    }


def is_moderation_status_restricted(status):
    return str(status or MODERATION_STATUS_APPROVED).strip().lower() in MODERATION_RESTRICTED_STATUSES


def is_user_moderation_restricted(user):
    if not user or is_admin_user(user):
        return False
    return (
        is_moderation_status_restricted(getattr(user, "bio_moderation_status", MODERATION_STATUS_APPROVED))
        or is_moderation_status_restricted(getattr(user, "photo_moderation_status", MODERATION_STATUS_APPROVED))
    )


def apply_public_user_visibility_filters(query):
    return query.filter(
        User.bio_moderation_status == MODERATION_STATUS_APPROVED,
        User.photo_moderation_status == MODERATION_STATUS_APPROVED,
    )


def is_public_user_visible_to_viewer(user, viewer=None):
    if not user:
        return False
    if viewer and getattr(viewer, "is_authenticated", False):
        if is_admin_user(viewer) or viewer.id == user.id:
            return True
    return not is_user_moderation_restricted(user)


def get_user_moderation_block_message(user):
    if not user:
        return "Profilo in revisione."
    if is_moderation_status_restricted(getattr(user, "photo_moderation_status", MODERATION_STATUS_APPROVED)):
        return (
            "Il tuo profilo e' temporaneamente in revisione per una foto. "
            "Attendi la verifica dell'amministratore."
        )
    if is_moderation_status_restricted(getattr(user, "bio_moderation_status", MODERATION_STATUS_APPROVED)):
        return (
            "Il tuo profilo e' temporaneamente in revisione per la bio. "
            "Attendi la verifica dell'amministratore."
        )
    return "Profilo in revisione."


def require_moderation_clear_json(user=None):
    checked_user = user or current_user
    if not getattr(checked_user, "is_authenticated", True):
        return None
    if not is_user_moderation_restricted(checked_user):
        return None
    message = get_user_moderation_block_message(checked_user)
    return jsonify({
        "success": False,
        "error": message,
        "errors": [message],
        "moderation_status": "review",
    }), 403


def local_moderation_keyword_reason(text):
    lowered = (text or "").lower()
    for keyword in sorted(LOCAL_MODERATION_KEYWORDS, key=len, reverse=True):
        if keyword in lowered:
            return f"keyword:{keyword}"
    return ""


def extract_moderation_reason_and_score(result):
    categories = result.get("categories") or {}
    scores = result.get("category_scores") or {}
    flagged_categories = [
        name for name, flagged in categories.items()
        if bool(flagged)
    ]
    if flagged_categories:
        top_reason = max(
            flagged_categories,
            key=lambda name: float(scores.get(name, 0) or 0),
        )
        return top_reason, float(scores.get(top_reason, 0) or 0)
    if scores:
        top_reason = max(scores, key=lambda name: float(scores.get(name, 0) or 0))
        return top_reason, float(scores.get(top_reason, 0) or 0)
    return "", None


def moderation_score_requires_review(reason, score):
    if score is None:
        return False
    normalized_reason = str(reason or "").strip().lower()
    threshold = OPENAI_MODERATION_REVIEW_THRESHOLD
    if normalized_reason.startswith("illicit"):
        threshold = OPENAI_MODERATION_ILLICIT_REVIEW_THRESHOLD
    elif normalized_reason.startswith("sexual"):
        threshold = OPENAI_MODERATION_SEXUAL_REVIEW_THRESHOLD
    return float(score or 0) >= threshold


def call_openai_moderation_api(moderation_input):
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return None, "missing_api_key"

    payload = json.dumps({
        "model": OPENAI_MODERATION_MODEL,
        "input": moderation_input if moderation_input is not None else "",
    }).encode("utf-8")
    request_obj = Request(
        OPENAI_MODERATION_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request_obj, timeout=OPENAI_MODERATION_TIMEOUT_SECONDS) as response:
            body = response.read().decode("utf-8", errors="replace")
        return json.loads(body), ""
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
        return None, f"http_{exc.code}:{body[:180]}"
    except (URLError, TimeoutError, ValueError) as exc:
        return None, f"{type(exc).__name__}:{str(exc)[:180]}"


def build_moderation_result(api_result, api_error, *, checked_at, keyword_reason=""):
    provider = "openai"
    model = OPENAI_MODERATION_MODEL
    raw_json = None
    reason = ""
    score = None
    status = MODERATION_STATUS_APPROVED

    if api_result:
        raw_json = json.dumps(api_result, ensure_ascii=False)
        results = api_result.get("results") or []
        first_result = results[0] if results else {}
        reason, score = extract_moderation_reason_and_score(first_result)
        if keyword_reason:
            reason = keyword_reason
            score = max(float(score or 0), 1.0)
            status = MODERATION_STATUS_REVIEW
        elif bool(first_result.get("flagged")):
            status = MODERATION_STATUS_REVIEW
        elif moderation_score_requires_review(reason, score):
            status = MODERATION_STATUS_REVIEW
        if status == MODERATION_STATUS_REVIEW and not reason:
            reason = "openai_flagged"
    elif keyword_reason:
        provider = "local"
        model = "keyword-fallback"
        reason = keyword_reason
        score = 1.0
        raw_json = json.dumps({"fallback": "keyword", "reason": reason})
        status = MODERATION_STATUS_REVIEW
    elif api_error and MODERATION_FAIL_CLOSED:
        reason = "moderation_unavailable"
        raw_json = json.dumps({"error": api_error})
        status = MODERATION_STATUS_REVIEW
    elif api_error:
        raw_json = json.dumps({"error": api_error})
        if keyword_reason is not None:
            provider = "local"
            model = "keyword-fallback"

    return {
        "status": status,
        "reason": reason or "",
        "score": score,
        "checked_at": checked_at,
        "provider": provider,
        "model": model,
        "raw_json": raw_json,
        "api_error": api_error,
    }


def add_ai_moderation_log(result, *, user=None, content_type="bio", content_table=None, content_id=None):
    db.session.add(AiModerationLog(
        user_id=getattr(user, "id", None),
        content_type=content_type,
        content_table=content_table,
        content_id=content_id,
        status=result["status"],
        reason=result["reason"] or None,
        score=result["score"],
        provider=result["provider"],
        model=result["model"],
        raw_json=result["raw_json"],
        created_at=result["checked_at"],
    ))


def moderate_text_content(text, *, user=None, content_type="bio", content_table=None, content_id=None):
    cleaned_text = (text or "").strip()
    checked_at = datetime.now()

    keyword_reason = local_moderation_keyword_reason(cleaned_text)
    api_result, api_error = call_openai_moderation_api(cleaned_text)
    result = build_moderation_result(
        api_result,
        api_error,
        checked_at=checked_at,
        keyword_reason=keyword_reason,
    )
    add_ai_moderation_log(
        result,
        user=user,
        content_type=content_type,
        content_table=content_table,
        content_id=content_id,
    )
    return result


def moderate_image_payload(image_payload):
    checked_at = datetime.now()
    image_bytes = image_payload.get("bytes") or b""
    image_content_type = image_payload.get("content_type") or "image/jpeg"
    data_url = (
        f"data:{image_content_type};base64,"
        f"{base64.b64encode(image_bytes).decode('ascii')}"
    )
    api_result, api_error = call_openai_moderation_api([
        {
            "type": "image_url",
            "image_url": {"url": data_url},
        }
    ])
    return build_moderation_result(
        api_result,
        api_error,
        checked_at=checked_at,
        keyword_reason=None,
    )


def apply_user_bio_moderation(user, bio_text, *, allow_auto_approve=False):
    result = moderate_text_content(
        bio_text,
        user=user,
        content_type="bio",
        content_table="users",
        content_id=getattr(user, "id", None),
    )
    previous_status = getattr(user, "bio_moderation_status", MODERATION_STATUS_APPROVED)
    approved = result["status"] == MODERATION_STATUS_APPROVED
    if approved and is_moderation_status_restricted(previous_status) and not allow_auto_approve:
        user.bio_moderation_status = MODERATION_STATUS_REVIEW
        user.bio_moderation_reason = "pending_admin_approval"
    else:
        user.bio_moderation_status = result["status"]
        user.bio_moderation_reason = result["reason"]
    user.bio_moderation_score = result["score"]
    user.bio_moderation_checked_at = result["checked_at"]
    user.bio_moderation_provider = result["provider"]
    user.bio_moderation_model = result["model"]
    user.bio_moderation_raw_json = result["raw_json"]
    return result


def photo_moderation_state_from_photo(photo):
    return {
        "status": getattr(photo, "moderation_status", MODERATION_STATUS_APPROVED),
        "reason": getattr(photo, "moderation_reason", "") or "",
        "score": getattr(photo, "moderation_score", None),
        "checked_at": getattr(photo, "moderation_checked_at", None),
        "provider": getattr(photo, "moderation_provider", None),
        "model": getattr(photo, "moderation_model", None),
        "raw_json": getattr(photo, "moderation_raw_json", None),
        "status_field": getattr(photo, "status", "approved"),
        "reason_field": getattr(photo, "reason", "") or "",
        "moderated_by": getattr(photo, "moderated_by", None),
        "moderated_at": getattr(photo, "moderated_at", None),
    }


def apply_photo_moderation_state(photo, state):
    status = state.get("status") or MODERATION_STATUS_APPROVED
    reason = state.get("reason") or ""
    photo.moderation_status = status
    photo.moderation_reason = reason
    photo.moderation_score = state.get("score")
    photo.moderation_checked_at = state.get("checked_at")
    photo.moderation_provider = state.get("provider")
    photo.moderation_model = state.get("model")
    photo.moderation_raw_json = state.get("raw_json")
    photo.status = state.get("status_field") or ("approved" if status == MODERATION_STATUS_APPROVED else status)
    photo.reason = state.get("reason_field") or reason
    photo.moderated_by = state.get("moderated_by")
    photo.moderated_at = state.get("moderated_at")


def choose_restricted_photo_state(photo_states):
    restricted_states = [
        state
        for state in photo_states
        if is_moderation_status_restricted(state.get("status"))
    ]
    if not restricted_states:
        return None
    return max(
        restricted_states,
        key=lambda state: float(state.get("score") or 0),
    )


def apply_user_photo_moderation(
    user,
    uploaded_photo_moderation_results,
    *,
    previous_photo_states=None,
    allow_auto_approve=False,
):
    previous_photo_states = previous_photo_states or {}
    results_by_filename = {
        item.get("filename"): item.get("result")
        for item in uploaded_photo_moderation_results or []
        if item.get("filename") and item.get("result")
    }
    db.session.flush()

    photo_states = []
    for photo in list(getattr(user, "photos", [])):
        result = results_by_filename.get(photo.filename)
        if result:
            state = {
                "status": result["status"],
                "reason": result["reason"],
                "score": result["score"],
                "checked_at": result["checked_at"],
                "provider": result["provider"],
                "model": result["model"],
                "raw_json": result["raw_json"],
                "status_field": "approved" if result["status"] == MODERATION_STATUS_APPROVED else result["status"],
                "reason_field": result["reason"],
                "moderated_by": None,
                "moderated_at": None,
            }
            apply_photo_moderation_state(photo, state)
            add_ai_moderation_log(
                result,
                user=user,
                content_type="profile_photo",
                content_table="user_photos",
                content_id=photo.id,
            )
        elif photo.filename in previous_photo_states:
            state = previous_photo_states[photo.filename]
            apply_photo_moderation_state(photo, state)
        else:
            state = photo_moderation_state_from_photo(photo)
        photo_states.append(state)

    previous_status = getattr(user, "photo_moderation_status", MODERATION_STATUS_APPROVED)
    restricted_state = choose_restricted_photo_state(photo_states)
    if restricted_state:
        user.photo_moderation_status = restricted_state.get("status") or MODERATION_STATUS_REVIEW
        user.photo_moderation_reason = restricted_state.get("reason") or "openai_flagged"
        user.photo_moderation_score = restricted_state.get("score")
        user.photo_moderation_checked_at = restricted_state.get("checked_at")
        user.photo_moderation_provider = restricted_state.get("provider")
        user.photo_moderation_model = restricted_state.get("model")
        user.photo_moderation_raw_json = restricted_state.get("raw_json")
    elif is_moderation_status_restricted(previous_status) and not allow_auto_approve:
        user.photo_moderation_status = MODERATION_STATUS_REVIEW
        user.photo_moderation_reason = "pending_admin_approval"
        user.photo_moderation_score = None
        user.photo_moderation_checked_at = datetime.now()
        user.photo_moderation_provider = "admin"
        user.photo_moderation_model = "manual"
        user.photo_moderation_raw_json = None
    else:
        user.photo_moderation_status = MODERATION_STATUS_APPROVED
        user.photo_moderation_reason = ""
        user.photo_moderation_score = None
        user.photo_moderation_checked_at = datetime.now()
        user.photo_moderation_provider = "openai"
        user.photo_moderation_model = OPENAI_MODERATION_MODEL
        user.photo_moderation_raw_json = None

    return {
        "status": user.photo_moderation_status,
        "reason": user.photo_moderation_reason or "",
        "score": user.photo_moderation_score,
        "checked_at": user.photo_moderation_checked_at,
        "provider": user.photo_moderation_provider or "openai",
        "model": user.photo_moderation_model or OPENAI_MODERATION_MODEL,
        "raw_json": user.photo_moderation_raw_json,
        "api_error": "",
    }


def moderate_saved_profile_photo(filename):
    try:
        image_bytes, content_type = upload_storage.read(filename)
    except Exception as exc:
        return build_moderation_result(
            None,
            f"read_error:{str(exc)[:180]}",
            checked_at=datetime.now(),
            keyword_reason=None,
        )
    return moderate_image_payload({
        "filename": filename,
        "bytes": image_bytes,
        "content_type": content_type,
    })


def notify_admin_for_user_moderation(user, result, *, content_label="Bio"):
    if result.get("status") != MODERATION_STATUS_REVIEW:
        return False
    admin_email = os.getenv("ADMIN_EMAIL")
    if not admin_email:
        return False
    try:
        safe_nome = escape(user.nome or "Utente senza nome")
        safe_email = escape(user.email or "Email non disponibile")
        safe_reason = escape(result.get("reason") or "Da verificare")
        safe_score = "" if result.get("score") is None else f"{result['score']:.3f}"
        safe_bio = escape((user.bio or "")[:1200])
        send_email_html(
            f"{content_label} in revisione su ApprofittOffro",
            [admin_email],
            f"""
            <h2>{content_label} in revisione</h2>
            <p><b>Utente:</b> {safe_nome}</p>
            <p><b>Email:</b> {safe_email}</p>
            <p><b>ID utente:</b> {user.id}</p>
            <p><b>Motivo:</b> {safe_reason}</p>
            <p><b>Score:</b> {safe_score}</p>
            <p><b>Bio:</b></p>
            <blockquote>{safe_bio}</blockquote>
            <p>L'utente e' temporaneamente nascosto e bloccato dalle azioni pubbliche.</p>
            """,
            background=True,
        )
        return True
    except Exception as exc:
        print("[MODERATION_ADMIN_EMAIL_ERROR]", exc)
        return False


def validate_profile_update_input(user, source, *, foto_files=None, require_primary_face=True):
    uploaded_gallery_filenames = []
    photo_moderation_results = []
    source = source or {}

    nome = str(source.get("nome", user.nome) or "").strip()
    email = str(source.get("email", user.email) or "").strip().lower()
    numero_telefono_raw = source.get("numero_telefono", user.numero_telefono or "")
    eta_raw = source.get(
        "eta",
        user.eta if user.eta is not None else user.fascia_eta,
    )
    sesso_raw = source.get("sesso", user.sesso or "non_dico")
    raggio_raw = source.get("raggio_azione", user.raggio_azione or 15)
    lat_raw = str(source.get("latitudine", "") or "").strip()
    lon_raw = str(source.get("longitudine", "") or "").strip()
    citta = str(source.get("citta", user.citta or "") or "").strip()
    pref = str(source.get("cibi_preferiti", user.cibi_preferiti or "") or "").strip()
    intoll = str(source.get("intolleranze", user.intolleranze or "") or "").strip()
    bio = str(source.get("bio", user.bio or "") or "").strip()
    current_password = str(source.get("current_password", "") or "")
    new_password = str(source.get("new_password", "") or "")
    confirm_new_password = str(source.get("confirm_new_password", "") or "")
    existing_gallery_raw = source.get("existing_gallery_filenames")

    if isinstance(existing_gallery_raw, str) and existing_gallery_raw.strip():
        try:
            requested_existing_gallery = json.loads(existing_gallery_raw)
        except Exception:
            requested_existing_gallery = []
    elif isinstance(existing_gallery_raw, (list, tuple)):
        requested_existing_gallery = list(existing_gallery_raw)
    else:
        requested_existing_gallery = list(user.gallery_filenames)

    current_gallery = list(user.gallery_filenames)
    existing_gallery_filenames = [
        filename
        for filename in current_gallery
        if filename in {str(item) for item in requested_existing_gallery if str(item).strip()}
    ]

    errors = []
    if not nome:
        errors.append("Il nome non può essere vuoto.")
    if not email or "@" not in email:
        errors.append("Inserisci un'email valida.")

    numero_telefono, phone_error = normalize_phone_number(numero_telefono_raw)
    if phone_error:
        errors.append(phone_error)

    eta, eta_error = parse_age_value(eta_raw)
    if eta_error:
        errors.append(eta_error)
    sesso, sesso_error = parse_gender_value(sesso_raw)
    if sesso_error:
        errors.append(sesso_error)
    try:
        raggio_azione = int(float(str(raggio_raw).replace(",", ".").strip()))
        if raggio_azione == 999:
            pass
        elif raggio_azione < 1 or raggio_azione > 500:
            raise ValueError()
    except Exception:
        errors.append(
            "Il raggio d'azione deve essere un numero tra 1 e 500 km."
        )
        raggio_azione = None

    existing_user = User.query.filter_by(email=email).first()
    if email != user.email and existing_user and existing_user.id != user.id:
        errors.append("Questa email è già associata a un altro account.")

    if len(pref) > 0 and len(pref) < 3:
        errors.append("Quali sono i tuoi cibi preferiti? Scrivi qualcosa in più.")
    if len(bio) > 0 and len(bio) < 5:
        errors.append("Raccontaci qualcosa di più nella Bio.")

    password_change_requested = bool(
        current_password or new_password or confirm_new_password
    )
    if password_change_requested:
        if not user_can_change_password(user):
            errors.append("Questo account usa Google: la password non si modifica da qui.")
        else:
            if not current_password:
                errors.append("Inserisci la password attuale per cambiarla.")
            elif not user.check_password(current_password):
                errors.append("La password attuale non è corretta.")

            if len(new_password) < 6:
                errors.append("La nuova password deve avere almeno 6 caratteri.")
            if new_password != confirm_new_password:
                errors.append("Le due nuove password non coincidono.")
            if current_password and new_password and current_password == new_password:
                errors.append("La nuova password deve essere diversa da quella attuale.")

    latitudine = None
    longitudine = None
    if lat_raw or lon_raw:
        if not lat_raw or not lon_raw:
            errors.append("Inserisci sia latitudine che longitudine, oppure lascia entrambi invariati.")
        else:
            try:
                latitudine = float(lat_raw)
                longitudine = float(lon_raw)
            except ValueError:
                errors.append("Latitudine e longitudine devono essere numeri validi.")

    if foto_files:
        uploaded_gallery_filenames, photo_errors, photo_moderation_results = save_profile_gallery_files(
            user.id,
            foto_files,
            require_primary_face=require_primary_face and not existing_gallery_filenames,
            return_moderation=True,
        )
        errors.extend(photo_errors)

    final_gallery_filenames = existing_gallery_filenames + uploaded_gallery_filenames
    if len(final_gallery_filenames) > MAX_PROFILE_PHOTOS:
        errors.append(f"Puoi tenere al massimo {MAX_PROFILE_PHOTOS} foto profilo.")
    if not final_gallery_filenames:
        errors.append("Devi tenere almeno una foto profilo.")

    payload = {
        "nome": nome,
        "email": email,
        "eta": eta if not eta_error else None,
        "sesso": sesso,
        "raggio_azione": raggio_azione,
        "numero_telefono": numero_telefono,
        "citta": citta,
        "latitudine": latitudine,
        "longitudine": longitudine,
        "cibi_preferiti": pref,
        "intolleranze": intoll,
        "bio": bio,
        "new_password": new_password if password_change_requested else "",
        "final_gallery_filenames": final_gallery_filenames,
        "uploaded_gallery_filenames": uploaded_gallery_filenames,
        "photo_moderation_results": photo_moderation_results,
    }

    return payload, errors


def save_profile_update_for_user(user, payload, *, verified=None, allow_moderation_auto_approve=False):
    old_gallery_filenames = []
    uploaded_gallery_filenames = payload.get("uploaded_gallery_filenames", [])
    final_gallery_filenames = payload.get("final_gallery_filenames", list(user.gallery_filenames))
    photo_moderation_results = payload.get("photo_moderation_results", [])
    previous_photo_states = {
        photo.filename: photo_moderation_state_from_photo(photo)
        for photo in list(getattr(user, "photos", []))
    }
    photo_moderation_result = None

    user.nome = payload["nome"]
    user.email = payload["email"]
    user.fascia_eta = str(payload["eta"])
    user.eta = payload["eta"]
    user.sesso = payload["sesso"]
    user.raggio_azione = payload["raggio_azione"]
    user.numero_telefono = payload["numero_telefono"]
    user.citta = payload["citta"]
    if payload["latitudine"] is not None and payload["longitudine"] is not None:
        user.latitudine = payload["latitudine"]
        user.longitudine = payload["longitudine"]

    user.cibi_preferiti = payload["cibi_preferiti"]
    user.intolleranze = payload["intolleranze"]
    user.bio = payload["bio"]
    bio_moderation_result = apply_user_bio_moderation(
        user,
        payload["bio"] or "",
        allow_auto_approve=allow_moderation_auto_approve,
    )

    if payload.get("new_password"):
        user.set_password(payload["new_password"])
        clear_password_reset_state(user)

    if verified is not None:
        user.verificato = bool(verified)

    if final_gallery_filenames != list(user.gallery_filenames):
        old_gallery_filenames = replace_user_gallery(user, final_gallery_filenames)
        photo_moderation_result = apply_user_photo_moderation(
            user,
            photo_moderation_results,
            previous_photo_states=previous_photo_states,
            allow_auto_approve=allow_moderation_auto_approve,
        )

    try:
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        delete_upload_files(uploaded_gallery_filenames)
        return False, [f"Errore nel salvataggio del profilo: {exc}"], []

    db.session.refresh(user)
    db.session.expire(user, ["photos"])
    delete_upload_files(old_gallery_filenames)
    notify_admin_for_user_moderation(user, bio_moderation_result, content_label="Bio")
    if photo_moderation_result:
        notify_admin_for_user_moderation(
            user,
            photo_moderation_result,
            content_label="Foto profilo",
        )
    return True, [], old_gallery_filenames


# ---------------------------------------------------------------------------
# Crea le tabelle al primo avvio
# ---------------------------------------------------------------------------
with app.app_context():
    db.create_all()
    ensure_database_schema_compatibility()


def profile_completed_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if current_user.is_authenticated:
            if is_admin_user(current_user):
                return f(*args, **kwargs)
            if is_user_moderation_restricted(current_user):
                flash(get_user_moderation_block_message(current_user), "warning")
                return redirect(url_for('profile_page'))
            if not is_profile_complete(current_user):
                flash("Ciao! Completa il tuo numero di cellulare, l'identikit alimentare e la tua bio: sono obbligatori per poter pubblicare offerte, partecipare ai pasti e vedere i profili completi. 🍽️", "warning")
                return redirect(url_for('profile_page'))
        return f(*args, **kwargs)
    return decorated_function


def is_profile_complete(user):
    return bool(
        user_has_visible_profile_photo(user)
        and user.numero_telefono
        and user.cibi_preferiti
        and user.intolleranze
        and user.bio
        and not is_user_moderation_restricted(user)
    )


def is_admin_user(user):
    return bool(getattr(user, "is_admin", False))


def get_admin_delegate_emails():
    raw_emails = os.getenv("ADMIN_DELEGATE_EMAILS", "")
    return {
        item.strip().lower()
        for item in re.split(r"[\s,;]+", raw_emails)
        if item.strip()
    }


def can_access_admin_area(user):
    if not user or not getattr(user, "is_authenticated", True):
        return False
    if is_admin_user(user):
        return True
    email = str(getattr(user, "email", "") or "").strip().lower()
    return bool(email and email in get_admin_delegate_emails())


@app.before_request
def enforce_session_timeout():
    if request.endpoint == "static":
        return None

    if not current_user.is_authenticated:
        session.pop("last_activity_at", None)
        session.pop("login_at", None)
        return None

    now_ts = int(datetime.now(timezone.utc).timestamp())
    last_activity_at = session.get("last_activity_at")
    timeout_seconds = get_session_idle_timeout_seconds(current_user)

    if last_activity_at and now_ts - int(last_activity_at) > timeout_seconds:
        logout_user()
        session.clear()
        message = "Sessione scaduta per inattivita'. Effettua di nuovo il login."
        if request.path.startswith("/api/"):
            return jsonify({
                "success": False,
                "error": message,
                "redirect": url_for("login_page"),
            }), 401
        flash(message, "warning")
        return redirect(url_for("login_page"))

    session["last_activity_at"] = now_ts
    session.setdefault("login_at", now_ts)
    return None


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated:
            return login_manager.unauthorized()
        if not can_access_admin_area(current_user):
            if request.path.startswith("/api/"):
                return jsonify({"success": False, "error": "Area riservata agli amministratori."}), 403
            flash("Area riservata agli amministratori.", "error")
            return redirect(url_for("dashboard"))
        return f(*args, **kwargs)
    return decorated_function


def require_complete_profile_json():
    if current_user.is_authenticated and not is_admin_user(current_user):
        moderation_error = require_moderation_clear_json(current_user)
        if moderation_error:
            return moderation_error
    if current_user.is_authenticated and not is_admin_user(current_user) and not is_profile_complete(current_user):
        return jsonify({
            "success": False,
            "error": "Completa almeno una foto profilo reale, numero di cellulare, bio e identikit alimentare prima di partecipare o pubblicare offerte.",
        }), 403
    return None


def parse_age_value(age_raw):
    """Valida e converte l'età inserita dall'utente."""
    normalized_age = str(age_raw).strip()
    legacy_match = re.match(r"^(\d{1,3})", normalized_age)

    try:
        age = int(legacy_match.group(1) if legacy_match else normalized_age)
    except (TypeError, ValueError, AttributeError):
        return None, "Inserisci un'età valida."

    if age < 18:
        return None, "Per usare ApprofittOffro devi avere almeno 18 anni."
    if age > 120:
        return None, "Inserisci un'età realistica."
    return age, None


def normalize_phone_number(phone_raw):
    """Normalizza un recapito telefonico per il profilo utente."""
    normalized_phone = str(phone_raw or "").strip()
    if not normalized_phone:
        return None, "Inserisci un numero di cellulare valido."

    compact_phone = re.sub(r"[\s().-]+", "", normalized_phone)
    if compact_phone.startswith("00"):
        compact_phone = f"+{compact_phone[2:]}"

    if compact_phone.startswith("+"):
        digit_block = compact_phone[1:]
    else:
        digit_block = compact_phone

    if not digit_block.isdigit():
        return None, "Il numero di cellulare può contenere solo cifre, spazi, trattini e il prefisso +."

    if len(digit_block) < 8 or len(digit_block) > 15:
        return None, "Inserisci un numero di cellulare reale, con almeno 8 cifre."

    if not compact_phone.startswith("+") and digit_block.startswith("3") and len(digit_block) in {9, 10}:
        return f"+39{digit_block}", None

    return f"+{digit_block}" if compact_phone.startswith("+") else digit_block, None


def phone_to_whatsapp_digits(phone_raw):
    normalized_phone, phone_error = normalize_phone_number(phone_raw)
    if phone_error or not normalized_phone:
        return ""
    return re.sub(r"\D", "", normalized_phone)


def build_whatsapp_offer_link(sender_user, recipient_user, offer):
    """Compat legacy: non esponiamo piu' numeri o link WhatsApp al client."""
    return ""


def parse_optional_age_bound(age_raw, label):
    normalized_age = str(age_raw or "").strip()
    if not normalized_age:
        return None, None
    try:
        age = int(normalized_age)
    except (TypeError, ValueError):
        return None, f"Inserisci un valore valido per {label}."
    if age < 18 or age > 120:
        return None, f"{label.capitalize()} deve essere compresa tra 18 e 120."
    return age, None


def parse_age_range_filter(age_range_raw):
    age_range = str(age_range_raw or "").strip()
    if not age_range:
        return "", None, None

    valid_ranges = {value: label for value, label in FASCE_ETA}
    if age_range not in valid_ranges:
        return "", None, "Seleziona una fascia d'età valida."

    if age_range.endswith("+"):
        min_age = int(age_range[:-1])
        return age_range, min_age, None

    try:
        min_age, max_age = [int(value) for value in age_range.split("-", 1)]
    except ValueError:
        return "", None, "Seleziona una fascia d'età valida."

    return age_range, (min_age, max_age), None


def parse_gender_value(gender_raw, *, default="non_dico", allow_empty=False):
    gender = str(gender_raw if gender_raw is not None else default).strip().lower()
    valid_values = {value for value, _ in SESSI_UTENTE}
    if allow_empty and not gender:
        return "", None
    if not gender:
        gender = default
    if gender not in valid_values:
        return default, "Seleziona un sesso valido."
    return gender, None


def parse_community_gender_filter(gender_raw):
    gender = str(gender_raw or "").strip().lower()
    valid_values = {value for value, _ in COMMUNITY_GENDER_FILTERS}
    if gender not in valid_values:
        return "", "Seleziona un filtro sesso valido."
    return gender, None


def get_safe_next_url(default_endpoint="people_page"):
    next_url = str(request.form.get("next", "") or request.args.get("next", "")).strip()
    if next_url.startswith("/"):
        return next_url
    return url_for(default_endpoint)


def extract_city_label(address_text):
    import re
    raw_address = str(address_text or "").strip()
    if not raw_address:
        return ""
    
    # Split by comma
    parts = [p.strip() for p in raw_address.split(",")]
    
    # Find country index
    country_idx = -1
    for i, part in enumerate(parts):
        if part.lower() in ("italy", "italia", "italie"):
            country_idx = i
            break
    
    if country_idx > 0:
        # Get the part before country
        city_part = parts[country_idx - 1]
        # Remove CAP (5 digits at start)
        city_part = re.sub(r'^\d{5}\s*', '', city_part)
        # Remove province (2 uppercase letters at end)
        city_part = re.sub(r'\s+[A-Z]{2}$', '', city_part).strip()
        if city_part:
            return city_part
    
    # Fallback: return last part that's not just numbers
    for part in reversed(parts):
        if re.search(r'[a-zA-Z]', part):
            cleaned = re.sub(r'^\d+\s*', '', part)
            cleaned = re.sub(r'\s+[A-Z]{2}$', '', cleaned).strip()
            if cleaned:
                return cleaned
    
    return parts[0] if parts else raw_address


def render_public_landing():
    """Mostra la landing pubblica, lasciando l'uso del prodotto alla sola app."""
    return render_template(
        "landing.html",
        play_store_url=os.getenv("PLAY_STORE_URL", "").strip(),
    )

# ===================================================================
# PAGINE (Template)
# ===================================================================

@app.route("/")
def index():
    return render_public_landing()


@app.route("/favicon.ico")
def favicon():
    return redirect(url_for("static", filename="favicon.ico"))


@app.route("/register")
def register_page():
    return redirect(url_for("index"))

@app.route("/login")
def login_page():
    return redirect(url_for("index"))

@app.route("/dashboard")
def dashboard():
    if current_user.is_authenticated and is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))
    return redirect(url_for("index"))


@app.route("/people")
@login_required
@profile_completed_required
def people_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))
    return redirect(url_for("index"))


@app.route("/admin")
@admin_required
def admin_dashboard():
    now = local_now()
    all_offers = Offer.query.filter(
        Offer.stato != "archiviata_admin"
    ).order_by(Offer.data_ora.desc()).all()
    upcoming_offers = [offer for offer in all_offers if offer.data_ora >= now]
    past_offers = [offer for offer in all_offers if offer.data_ora < now]
    users = User.query.options(selectinload(User.photos)).filter_by(is_admin=False).order_by(User.created_at.desc()).all()
    admins = User.query.filter_by(is_admin=True).order_by(User.created_at.desc()).all()

    stats = {
        "users": len(users),
        "admins": len(admins),
        "future_offers": len(upcoming_offers),
        "past_offers": len(past_offers),
    }

    return render_template(
        "admin.html",
        users=users,
        upcoming_offers=upcoming_offers,
        past_offers=past_offers,
        stats=stats,
        now=now,
    )


@app.route("/admin/users/<int:user_id>/edit", methods=["GET", "POST"])
@admin_required
def admin_edit_user_page(user_id):
    user = User.query.options(selectinload(User.photos)).get_or_404(user_id)

    if is_admin_user(user):
        flash("Per ora puoi modificare solo i profili utenti standard.", "warning")
        return redirect(url_for("admin_dashboard"))

    if request.method == "POST":
        foto_files = extract_uploaded_photos("foto")
        payload, errors = validate_profile_update_input(
            user,
            request.form,
            foto_files=foto_files,
            require_primary_face=True,
        )
        verified_value = str(request.form.get("verificato", "")).lower() in {"1", "true", "on", "yes"}

        if errors:
            delete_upload_files(payload.get("uploaded_gallery_filenames", []))
            for error in errors:
                flash(error, "error")
            return render_template(
                "admin_edit_user.html",
                user=user,
                form_values=get_profile_form_values(user, request.form),
            )

        success, save_errors, _ = save_profile_update_for_user(
            user,
            payload,
            verified=verified_value,
            allow_moderation_auto_approve=True,
        )
        if not success:
            for error in save_errors:
                flash(error, "error")
            return render_template(
                "admin_edit_user.html",
                user=user,
                form_values=get_profile_form_values(user, request.form),
            )

        flash(f"Profilo di {user.nome} aggiornato con successo.", "success")
        return redirect(url_for("admin_edit_user_page", user_id=user.id))

    return render_template(
        "admin_edit_user.html",
        user=user,
        form_values=get_profile_form_values(user),
    )

@app.route("/verify/<token>")
def verify_email(token):
    user = User.query.filter_by(verification_token=token).first()
    if not user:
        flash("Link di verifica non valido o già utilizzato.", "error")
        return redirect(url_for("index"))
    
    user.verificato = True
    user.verification_token = None
    db.session.commit()

    notify_admin_for_verified_user(user)
    
    flash("Email verificata con successo! Ora puoi accedere.", "success")
    return redirect(url_for("login_page"))


@app.route("/reset-password/<token>", methods=["GET", "POST"])
def password_reset_page(token):
    user = get_user_by_valid_password_reset_token(token)
    error_message = ""
    success_message = ""

    if request.method == "POST":
        if not user:
            error_message = "Il link non e' valido o e' scaduto. Richiedi un nuovo recupero password dall'app."
        else:
            password = request.form.get("password", "")
            confirm_password = request.form.get("confirm_password", "")

            if len(password) < 6:
                error_message = "La nuova password deve avere almeno 6 caratteri."
            elif password != confirm_password:
                error_message = "Le due password non coincidono."
            else:
                user.set_password(password)
                clear_password_reset_state(user)
                db.session.commit()
                success_message = "Password aggiornata con successo. Ora puoi tornare nell'app ed entrare di nuovo."

    return render_template(
        "password_reset.html",
        token=token,
        token_is_valid=user is not None,
        error_message=error_message,
        success_message=success_message,
        password_reset_hours=PASSWORD_RESET_TOKEN_HOURS,
        play_store_url=os.getenv("PLAY_STORE_URL", "").strip(),
    )

@app.route("/new-offer")
@login_required
@profile_completed_required
def new_offer_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))
    return redirect(url_for("index"))


@app.route("/profile")
@login_required
def profile_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))
    return redirect(url_for("index"))

    my_offers = Offer.query.filter_by(user_id=current_user.id).order_by(
        Offer.created_at.desc()
    ).all()
    my_claims = Claim.query.filter_by(
        user_id=current_user.id,
        status=CLAIM_STATUS_ACCEPTED,
    ).order_by(
        Claim.created_at.desc()
    ).all()

    # Logica "Persone incontrate": raccogliamo utenti unici con cui c'è stata interazione
    # 1. Host che ho incontrato (da miei claims)
    met_users_dict = {}
    for c in my_claims:
        host = c.offerta.autore
        if host.id not in met_users_dict:
            met_users_dict[host.id] = host

    # 2. Ospiti che mi hanno fatto visita (da mie offerte)
    for o in my_offers:
        for c in get_offer_accepted_claims(o):
            guest = c.utente
            if guest.id not in met_users_dict:
                met_users_dict[guest.id] = guest

    followers = [
        relation.follower
        for relation in sorted(
            current_user.followers_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.follower and not is_admin_user(relation.follower)
    ]

    return render_template(
        "profile.html",
        my_offers=my_offers,
        my_claims=my_claims,
        met_users=met_users_dict.values(),
        followers=followers,
        rating_info=get_user_rating(current_user.id),
        now=local_now(),
        completion_threshold=local_now() - timedelta(hours=3),
        review_edit_threshold=local_now() - timedelta(hours=REVIEW_EDIT_WINDOW_HOURS),
        format_offer_datetime_label=format_offer_datetime_label,
        build_whatsapp_offer_link=build_whatsapp_offer_link,
    )

def get_user_rating(user_id):
    """Calcola la media delle recensioni per un utente."""
    reviews = Review.query.filter_by(reviewed_id=user_id).all()
    if not reviews:
        return {"average": 0, "count": 0}
    avg = sum(r.rating for r in reviews) / len(reviews)
    return {"average": round(avg, 1), "count": len(reviews)}


def serialize_user_preview(user, *, viewer=None, followed_user_ids=None, include_gallery=False, include_private=False):
    """Serializza un profilo utente in JSON per API web/mobile."""
    if not user:
        return None

    rating_info = get_user_rating(user.id)
    viewer_is_authenticated = bool(viewer and getattr(viewer, "is_authenticated", False))
    is_self = viewer_is_authenticated and viewer.id == user.id
    is_following = False

    if viewer_is_authenticated and not is_self:
        if followed_user_ids is not None:
            is_following = user.id in followed_user_ids
        else:
            is_following = UserFollow.query.filter_by(
                follower_id=viewer.id,
                followed_id=user.id,
            ).first() is not None

    gallery_filenames = get_visible_profile_gallery_filenames(
        user,
        include_gallery=include_gallery,
    )
    payload = {
        "id": user.id,
        "nome": user.nome,
        "email": user.email if include_private else "",
        "foto": gallery_filenames[0] if gallery_filenames else "",
        "gallery_filenames": gallery_filenames,
        "eta": user.eta,
        "eta_display": user.eta_display,
        "sesso": user.sesso or "non_dico",
        "citta": user.citta or "",
        "city_label": extract_city_label(user.citta),
        "bio": user.bio or "",
        "cibi_preferiti": user.cibi_preferiti or "",
        "intolleranze": user.intolleranze or "",
        "raggio_azione": int(user.raggio_azione or 15),
        "numero_telefono": user.numero_telefono if include_private else "",
        "lat": user.latitudine if include_private else None,
        "lon": user.longitudine if include_private else None,
        "verificato": bool(user.verificato),
        "is_admin": bool(user.is_admin),
        "can_access_admin": can_access_admin_area(user) if include_private else False,
        "uses_google_auth": bool(user.google_sub) if include_private else False,
        "can_change_password": user_can_change_password(user) if include_private else False,
        "approfittoffro_points": (
            int(getattr(user, "approfittoffro_points", 0) or 0)
            if include_private
            else 0
        ),
        "followers_count": user.followers_count,
        "following_count": user.following_count,
        "rating_average": rating_info["average"],
        "rating_count": rating_info["count"],
        "is_following": is_following,
        "is_self": is_self,
        "chat_enabled": bool(user.chat_enabled) if include_private else False,
    }
    if include_private or is_self or (viewer_is_authenticated and can_access_admin_area(viewer)):
        payload["moderation_restricted"] = is_user_moderation_restricted(user)
        payload["bio_moderation_status"] = getattr(user, "bio_moderation_status", MODERATION_STATUS_APPROVED)
        payload["bio_moderation_reason"] = getattr(user, "bio_moderation_reason", "") or ""
        payload["photo_moderation_status"] = getattr(user, "photo_moderation_status", MODERATION_STATUS_APPROVED)
        payload["photo_moderation_reason"] = getattr(user, "photo_moderation_reason", "") or ""
        payload["moderation_message"] = (
            get_user_moderation_block_message(user)
            if is_user_moderation_restricted(user)
            else ""
        )
    return payload


def serialize_review_preview(review, *, viewer=None):
    """Serializza una recensione con reviewer essenziale e dati evento."""
    offer = review.offerta
    return {
        "id": review.id,
        "rating": review.rating,
        "commento": review.commento or "",
        "created_at": review.created_at.isoformat() if review.created_at else "",
        "editable_until": "",
        "viewer_can_edit": bool(
            viewer
            and getattr(viewer, "is_authenticated", False)
            and review.reviewer_id == viewer.id
        ),
        "reviewer": serialize_user_preview(review.reviewer) if review.reviewer else None,
        "reviewed": serialize_user_preview(review.reviewed) if review.reviewed else None,
        "offer": {
            "id": offer.id,
            "tipo_pasto": offer.tipo_pasto,
            "nome_locale": offer.nome_locale,
            "indirizzo": offer.indirizzo,
            "data_ora": offer.data_ora.isoformat() if offer.data_ora else "",
        } if offer else None,
    }


def serialize_admin_user_summary(user):
    """Serializza i dati essenziali di un utente per il pannello admin mobile."""
    rating_info = get_user_rating(user.id)
    return {
        "id": user.id,
        "nome": user.nome,
        "email": user.email or "",
        "foto": user.foto_filename or "",
        "eta_display": user.eta_display,
        "sesso": user.sesso or "non_dico",
        "citta": user.citta or "",
        "city_label": extract_city_label(user.citta),
        "bio": user.bio or "",
        "bio_moderation_status": getattr(user, "bio_moderation_status", "approved"),
        "bio_moderation_reason": getattr(user, "bio_moderation_reason", "") or "",
        "bio_moderation_score": getattr(user, "bio_moderation_score", None),
        "bio_moderation_checked_at": (
            user.bio_moderation_checked_at.isoformat()
            if getattr(user, "bio_moderation_checked_at", None)
            else ""
        ),
        "photo_moderation_status": getattr(user, "photo_moderation_status", "approved"),
        "photo_moderation_reason": getattr(user, "photo_moderation_reason", "") or "",
        "verificato": bool(user.verificato),
        "is_admin": bool(user.is_admin),
        "created_at": user.created_at.isoformat() if user.created_at else "",
        "offers_count": len(user.offerte),
        "claims_count": len(user.claims),
        "reviews_count": len(user.reviews_ricevute),
        "rating_average": rating_info["average"],
        "rating_count": rating_info["count"],
        "approfittoffro_points": int(getattr(user, "approfittoffro_points", 0) or 0),
    }


def serialize_admin_user_detail(user):
    """Serializza tutti i campi modificabili di un utente per l'editor admin mobile."""
    return {
        "id": user.id,
        "nome": user.nome,
        "email": user.email or "",
        "foto": user.foto_filename or "",
        "gallery_filenames": list(user.gallery_filenames),
        "eta": user.eta if user.eta is not None else "",
        "eta_display": user.eta_display,
        "sesso": user.sesso or "non_dico",
        "numero_telefono": user.numero_telefono or "",
        "raggio_azione": int(user.raggio_azione or 15),
        "citta": user.citta or "",
        "lat": user.latitudine,
        "lon": user.longitudine,
        "cibi_preferiti": user.cibi_preferiti or "",
        "intolleranze": user.intolleranze or "",
        "bio": user.bio or "",
        "bio_moderation_status": getattr(user, "bio_moderation_status", "approved"),
        "bio_moderation_reason": getattr(user, "bio_moderation_reason", "") or "",
        "bio_moderation_score": getattr(user, "bio_moderation_score", None),
        "bio_moderation_checked_at": (
            user.bio_moderation_checked_at.isoformat()
            if getattr(user, "bio_moderation_checked_at", None)
            else ""
        ),
        "bio_moderation_provider": getattr(user, "bio_moderation_provider", "") or "",
        "bio_moderation_model": getattr(user, "bio_moderation_model", "") or "",
        "photo_moderation_status": getattr(user, "photo_moderation_status", "approved"),
        "photo_moderation_reason": getattr(user, "photo_moderation_reason", "") or "",
        "photo_moderation_score": getattr(user, "photo_moderation_score", None),
        "verificato": bool(user.verificato),
        "is_admin": bool(user.is_admin),
        "created_at": user.created_at.isoformat() if user.created_at else "",
    }


def serialize_admin_offer_summary(offer):
    """Serializza i dati essenziali di un evento per il pannello admin mobile."""
    accepted_claims = [
        claim for claim in offer.claims
        if claim.status == CLAIM_STATUS_ACCEPTED
    ]
    return {
        "id": offer.id,
        "tipo_pasto": offer.tipo_pasto,
        "nome_locale": offer.nome_locale,
        "indirizzo": offer.indirizzo,
        "telefono_locale": getattr(offer, "telefono_locale", "") or "",
        "lat": offer.latitudine,
        "lon": offer.longitudine,
        "data_ora": offer.data_ora.isoformat() if offer.data_ora else "",
        "stato": offer.stato or "",
        "descrizione": offer.descrizione or "",
        "foto_locale": getattr(offer, "foto_locale", "") or "",
        "posti_totali": int(offer.posti_totali or 0),
        "posti_disponibili": int(offer.posti_disponibili or 0),
        "participants_count": len(accepted_claims),
        "autore": {
            "id": offer.autore.id if offer.autore else 0,
            "nome": offer.autore.nome if offer.autore else "",
            "email": offer.autore.email if offer.autore else "",
            "foto": offer.autore.foto_filename if offer.autore else "",
        },
    }


def serialize_admin_chat_user(user):
    """Serializza un partecipante chat per il pannello admin mobile."""
    if not user:
        return {
            "id": 0,
            "nome": "Utente rimosso",
            "email": "",
            "foto": "",
        }
    return {
        "id": user.id,
        "nome": user.nome or "Utente",
        "email": user.email or "",
        "foto": get_primary_photo_filename(user) or "",
    }


def serialize_admin_chat_summary(thread):
    """Serializza una conversazione chat per il pannello admin mobile."""
    user_a = User.query.options(selectinload(User.photos)).get(thread.user_a_id)
    user_b = User.query.options(selectinload(User.photos)).get(thread.user_b_id)
    offer = Offer.query.get(thread.offer_id)
    last_activity = chat_thread_last_activity(thread)
    message_count = ChatMessage.query.filter_by(thread_id=thread.id).count()
    return {
        "id": thread.id,
        "chat_id": build_chat_thread_key(thread.offer_id, thread.user_a_id, thread.user_b_id),
        "offer_id": thread.offer_id,
        "offer_title": offer.nome_locale if offer else "Evento non disponibile",
        "offer_address": offer.indirizzo if offer else "",
        "offer_date": offer.data_ora.isoformat() if offer and offer.data_ora else "",
        "user_a": serialize_admin_chat_user(user_a),
        "user_b": serialize_admin_chat_user(user_b),
        "last_message": (thread.last_message or "").strip(),
        "last_message_type": (thread.last_message_type or "text").strip().lower(),
        "last_message_time": datetime_to_iso_z(last_activity),
        "message_count": int(message_count or 0),
        "cleared_at": datetime_to_iso_z(thread.cleared_at),
        **build_admin_deleted_chat_payload(thread),
    }


def serialize_bug_report(report):
    """Serializza una segnalazione bug con dati utente e stato validazione."""
    user = report.user
    reviewer = report.reviewed_by
    screenshot_filename = report.screenshot_filename or ""
    return {
        "id": report.id,
        "message": report.message or "",
        "screen_context": report.screen_context or "",
        "screenshot_filename": screenshot_filename,
        "screenshot_url": (
            url_for("uploaded_file", filename=screenshot_filename, _external=True)
            if screenshot_filename
            else ""
        ),
        "status": report.status or BUG_REPORT_STATUS_PENDING,
        "awarded_points": int(report.awarded_points or 0),
        "admin_note": report.admin_note or "",
        "created_at": report.created_at.isoformat() if report.created_at else "",
        "reviewed_at": report.reviewed_at.isoformat() if report.reviewed_at else "",
        "admin_archived_at": (
            report.admin_archived_at.isoformat() if report.admin_archived_at else ""
        ),
        "is_archived": report.admin_archived_at is not None,
        "user": {
            "id": user.id if user else 0,
            "nome": user.nome if user else "Utente rimosso",
            "email": user.email if user else "",
            "foto": get_primary_photo_filename(user) if user else "",
            "approfittoffro_points": int(
                getattr(user, "approfittoffro_points", 0) or 0
            ) if user else 0,
        },
        "reviewed_by": {
            "id": reviewer.id if reviewer else 0,
            "nome": reviewer.nome if reviewer else "",
        },
    }


def serialize_content_report_user(user):
    if not user:
        return {
            "id": 0,
            "nome": "Utente rimosso",
            "email": "",
            "foto": "",
        }
    return {
        "id": user.id,
        "nome": user.nome or "Utente",
        "email": user.email or "",
        "foto": get_primary_photo_filename(user) or "",
    }


def serialize_content_report(report):
    """Serializza una segnalazione contenuto per il pannello admin mobile."""
    reviewer = report.reviewed_by
    offer = report.offer
    chat_thread = report.chat_thread
    return {
        "id": report.id,
        "target_type": report.target_type or "user",
        "target_id": int(report.target_id or 0),
        "message": report.message or "",
        "status": report.status or CONTENT_REPORT_STATUS_PENDING,
        "admin_note": report.admin_note or "",
        "created_at": report.created_at.isoformat() if report.created_at else "",
        "reviewed_at": report.reviewed_at.isoformat() if report.reviewed_at else "",
        "admin_archived_at": (
            report.admin_archived_at.isoformat() if report.admin_archived_at else ""
        ),
        "is_archived": report.admin_archived_at is not None,
        "reporter": serialize_content_report_user(report.reporter),
        "reported_user": serialize_content_report_user(report.reported_user),
        "offer": {
            "id": offer.id if offer else 0,
            "nome_locale": offer.nome_locale if offer else "",
            "indirizzo": offer.indirizzo if offer else "",
            "data_ora": offer.data_ora.isoformat() if offer and offer.data_ora else "",
        },
        "chat": {
            "id": chat_thread.id if chat_thread else 0,
            "chat_id": (
                build_chat_thread_key(
                    chat_thread.offer_id,
                    chat_thread.user_a_id,
                    chat_thread.user_b_id,
                )
                if chat_thread
                else ""
            ),
        },
        "reviewed_by": {
            "id": reviewer.id if reviewer else 0,
            "nome": reviewer.nome if reviewer else "",
        },
    }


def resolve_content_report_target(data):
    """Normalizza i riferimenti di una segnalazione contenuto."""
    target_type = str(data.get("target_type", "user") or "user").strip().lower()
    if target_type not in CONTENT_REPORT_TARGET_TYPES:
        raise ValueError("Tipo segnalazione non valido.")

    def parse_optional_int(key):
        raw = data.get(key)
        if raw in (None, ""):
            return None
        try:
            value = int(raw)
        except (TypeError, ValueError):
            return None
        return value if value > 0 else None

    target_id = parse_optional_int("target_id")
    reported_user_id = parse_optional_int("reported_user_id")
    offer_id = parse_optional_int("offer_id")
    chat_thread_id = parse_optional_int("chat_thread_id")
    offer = None
    chat_thread = None
    reported_user = None

    if target_type in {"user", "profile_photo"}:
        reported_user_id = reported_user_id or target_id
        if not reported_user_id:
            raise ValueError("Utente da segnalare non valido.")
        reported_user = User.query.get(reported_user_id)
        if not reported_user or is_admin_user(reported_user):
            raise ValueError("Profilo da segnalare non trovato.")
        target_id = target_id or reported_user.id

    elif target_type in {"offer", "offer_photo"}:
        offer_id = offer_id or target_id
        offer = Offer.query.options(selectinload(Offer.autore)).get(offer_id)
        if not offer:
            raise ValueError("Evento da segnalare non trovato.")
        reported_user = offer.autore
        reported_user_id = reported_user.id if reported_user else None
        target_id = target_id or offer.id

    elif target_type in {"chat", "message"}:
        if chat_thread_id:
            chat_thread = ChatThread.query.get(chat_thread_id)
        if chat_thread is None and offer_id and reported_user_id:
            chat_thread = get_or_create_chat_thread(
                offer_id=offer_id,
                user_id=current_user.id,
                other_user_id=reported_user_id,
                create_if_missing=False,
            )
        if chat_thread:
            offer_id = chat_thread.offer_id
            if chat_thread.user_a_id == current_user.id:
                reported_user_id = chat_thread.user_b_id
            elif chat_thread.user_b_id == current_user.id:
                reported_user_id = chat_thread.user_a_id
        if not reported_user_id:
            raise ValueError("Utente della chat da segnalare non valido.")
        reported_user = User.query.get(reported_user_id)
        if not reported_user:
            raise ValueError("Utente della chat da segnalare non trovato.")
        offer = Offer.query.get(offer_id) if offer_id else None
        target_id = target_id or (chat_thread.id if chat_thread else None)

    elif target_type == "review":
        review_id = target_id
        review = Review.query.get(review_id)
        if not review:
            raise ValueError("Recensione da segnalare non trovata.")
        reported_user_id = reported_user_id or review.reviewer_id
        reported_user = User.query.get(reported_user_id)
        offer = review.offerta
        offer_id = review.offer_id

    if reported_user_id == current_user.id:
        raise ValueError("Non puoi segnalare te stesso.")

    return {
        "target_type": target_type,
        "target_id": target_id,
        "reported_user_id": reported_user_id,
        "offer_id": offer_id,
        "chat_thread_id": chat_thread.id if chat_thread else chat_thread_id,
        "reported_user": reported_user,
        "offer": offer,
        "chat_thread": chat_thread,
    }


def notify_admin_for_content_report(report):
    """Avvisa gli admin quando arriva una segnalazione contenuto."""
    title = "Nuova segnalazione contenuto"
    reporter = report.reporter
    reported = report.reported_user
    body = (
        f"{reporter.nome if reporter else 'Un utente'} ha segnalato "
        f"{reported.nome if reported else report.target_type}."
    )
    admins = User.query.filter_by(is_admin=True).all()
    push_count = 0
    for admin in admins:
        push_count += send_push_to_user(
            admin,
            title=title,
            body=body,
            target="admin",
            extra_data={
                "content_report_id": report.id,
                "target_type": report.target_type,
            },
        )

    admin_email = (
        os.getenv("CONTENT_REPORT_EMAIL")
        or os.getenv("ADMIN_EMAIL")
        or app.config.get("MAIL_USERNAME")
        or ""
    ).strip()
    email_sent = False
    if admin_email:
        safe_reporter = escape(reporter.nome if reporter else "Utente rimosso")
        safe_reported = escape(reported.nome if reported else "Contenuto")
        safe_message = escape(report.message or "").replace("\n", "<br>")
        safe_type = escape(report.target_type or "contenuto")
        html = f"""
        <h2>Nuova segnalazione contenuto ApprofittOffro</h2>
        <p><b>ID segnalazione:</b> {report.id}</p>
        <p><b>Tipo:</b> {safe_type}</p>
        <p><b>Segnalante:</b> {safe_reporter}</p>
        <p><b>Segnalato:</b> {safe_reported}</p>
        <p><b>Motivo:</b></p>
        <blockquote>{safe_message}</blockquote>
        <p>Apri il pannello admin mobile per gestirla.</p>
        """
        email_sent = send_email_html(
            title,
            [admin_email],
            html,
            background=True,
        )

    return {"push_sent": push_count > 0, "email_sent": email_sent}


def serialize_pending_claim_request(claim, *, viewer=None, followed_user_ids=None):
    """Serializza una richiesta pendente verso l'host proprietario dell'offerta."""
    offer = claim.offerta
    guest = claim.utente
    if not offer or not guest:
        return None

    return {
        "claim_id": claim.id,
        "requested_at": claim.created_at.isoformat() if claim.created_at else "",
        "offer": {
            "id": offer.id,
            "tipo_pasto": offer.tipo_pasto,
            "nome_locale": offer.nome_locale,
            "indirizzo": offer.indirizzo,
            "data_ora": offer.data_ora.isoformat() if offer.data_ora else "",
        },
        "requester": serialize_user_preview(
            guest,
            viewer=viewer,
            followed_user_ids=followed_user_ids,
        ),
    }


def serialize_pending_review_reminder(item, *, viewer=None, followed_user_ids=None):
    """Serializza un promemoria recensione per l'app mobile."""
    offer = item.get("offer")
    target_user = item.get("target_user")
    existing_review = item.get("existing_review")
    if not offer or not target_user:
        return None

    return {
        "offer": {
            "id": offer.id,
            "tipo_pasto": offer.tipo_pasto,
            "nome_locale": offer.nome_locale,
            "indirizzo": offer.indirizzo,
            "data_ora": offer.data_ora.isoformat() if offer.data_ora else "",
        },
        "target_user": serialize_user_preview(
            target_user,
            viewer=viewer,
            followed_user_ids=followed_user_ids,
        ),
        "role_label": item.get("role_label", ""),
        "existing_review": {
            "id": existing_review.id,
            "rating": existing_review.rating,
            "commento": existing_review.commento or "",
            "created_at": existing_review.created_at.isoformat() if existing_review.created_at else "",
            "editable_until": "",
        } if existing_review else None,
    }


def get_pending_review_reminders(user, now=None):
    """Restituisce le interazioni concluse da recensire, sia da ospite che da host."""
    if not user or not getattr(user, "is_authenticated", False):
        return []

    now = now or local_now()
    threshold = now - timedelta(hours=3)
    reminders = []
    seen_pairs = set()

    my_claims = Claim.query.filter_by(
        user_id=user.id,
        status=CLAIM_STATUS_ACCEPTED,
    ).order_by(Claim.created_at.desc()).all()
    for claim in my_claims:
        offer = claim.offerta
        if (
            not offer or
            offer.stato in {"annullata", "archiviata_admin"} or
            offer.data_ora > threshold
        ):
            continue

        review_key = (offer.id, offer.user_id)
        if review_key in seen_pairs:
            continue

        existing_review = Review.query.filter_by(
            reviewer_id=user.id,
            reviewed_id=offer.user_id,
            offer_id=offer.id,
        ).first()
        if existing_review:
            continue

        seen_pairs.add(review_key)
        reminders.append({
            "offer": offer,
            "target_user": offer.autore,
            "role_label": "host",
            "existing_review": existing_review,
        })

    my_offers = Offer.query.filter_by(user_id=user.id).order_by(Offer.data_ora.desc()).all()
    for offer in my_offers:
        if (
            offer.stato in {"annullata", "archiviata_admin"} or
            offer.data_ora > threshold
        ):
            continue

        for claim in get_offer_accepted_claims(offer):
            guest = claim.utente
            review_key = (offer.id, guest.id)
            if review_key in seen_pairs:
                continue

            existing_review = Review.query.filter_by(
                reviewer_id=user.id,
                reviewed_id=guest.id,
                offer_id=offer.id,
            ).first()
            if existing_review:
                continue

            seen_pairs.add(review_key)
            reminders.append({
                "offer": offer,
                "target_user": guest,
                "role_label": "guest",
                "existing_review": existing_review,
            })

    reminders.sort(key=lambda item: item["offer"].data_ora, reverse=True)
    return reminders


def get_met_users_for_user(user):
    """Restituisce gli utenti incontrati nei pasti offerti o partecipati."""
    if not user:
        return []

    met_users_dict = {}

    my_claims = Claim.query.filter_by(
        user_id=user.id,
        status=CLAIM_STATUS_ACCEPTED,
    ).all()
    for claim in my_claims:
        offer = claim.offerta
        host = offer.autore if offer else None
        if (
            host
            and host.id != user.id
            and not is_admin_user(host)
            and host.id not in met_users_dict
        ):
            met_users_dict[host.id] = host

    my_offers = Offer.query.filter_by(user_id=user.id).all()
    for offer in my_offers:
        for claim in get_offer_accepted_claims(offer):
            guest = claim.utente
            if (
                guest
                and guest.id != user.id
                and not is_admin_user(guest)
                and guest.id not in met_users_dict
            ):
                met_users_dict[guest.id] = guest

    return sorted(
        met_users_dict.values(),
        key=lambda item: (item.nome or "").lower(),
    )


def can_edit_review(review, now=None):
    """Le recensioni scritte possono essere corrette dall'autore in qualsiasi momento."""
    return bool(review)


def can_manage_offer(offer, user):
    return bool(
        user.is_authenticated
        and (offer.user_id == user.id or can_access_admin_area(user))
    )


def remove_offer_with_notifications(
    offer,
    motivazione,
    acting_admin=None,
    notify_owner=False,
    preserve_review_history=False,
):
    """Elimina un'offerta, avvisando i partecipanti e opzionalmente l'host."""
    now = local_now()
    is_past_offer = offer.data_ora < now
    claims = Claim.query.filter_by(offer_id=offer.id).all()
    notification_claims = get_offer_notification_claims(offer, include_pending=True)
    data_evento = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')
    motivazione = motivazione.strip() or "Nessuna motivazione specificata."

    if not is_past_offer:
        for claim in notification_claims:
            send_email(
            f"⚠️ Evento Annullato: {offer.nome_locale}",
            [claim.utente.email],
            "cancellation.html",
            user=claim.utente,
            offer=offer,
            data_evento=data_evento,
            motivazione=motivazione
        )

    if not is_past_offer and notify_owner and acting_admin and offer.autore.email:
        send_email(
            f"⚠️ La tua offerta è stata rimossa: {offer.nome_locale}",
            [offer.autore.email],
            "offer_removed_admin.html",
            user=offer.autore,
            offer=offer,
            data_evento=data_evento,
            motivazione=motivazione,
            admin_user=acting_admin,
        )

    if not is_past_offer:
        for claim in notification_claims:
            send_push_to_user(
                claim.utente,
                title="Evento annullato",
                body=f"{offer.nome_locale} - {data_evento} non e' piu' disponibile.",
                target="offers",
                extra_data={
                    "offer_id": offer.id,
                    "cancelled": "true",
                },
            )

    if not is_past_offer and notify_owner and acting_admin and offer.autore:
        send_push_to_user(
            offer.autore,
            title="Offerta rimossa dall'amministratore",
            body=f"{offer.nome_locale} - {data_evento} e' stata rimossa.",
            target="offers",
            extra_data={
                "offer_id": offer.id,
                "admin_removed": "true",
            },
        )

    if preserve_review_history and is_past_offer:
        accepted_claims = [claim for claim in claims if claim.status == CLAIM_STATUS_ACCEPTED]
        for claim in accepted_claims:
            if claim.utente:
                send_push_to_user(
                    claim.utente,
                    title="Evento rimosso dallo storico",
                    body=f"{offer.nome_locale} - {data_evento} non e' piu' consultabile.",
                    target="profile",
                    extra_data={
                        "offer_id": offer.id,
                        "admin_removed_archive": "true",
                    },
                )

        if notify_owner and acting_admin and offer.autore:
            send_push_to_user(
                offer.autore,
                title="Evento rimosso dallo storico",
                body=f"{offer.nome_locale} - {data_evento} non e' piu' consultabile.",
                target="profile",
                extra_data={
                    "offer_id": offer.id,
                    "admin_removed_archive": "true",
                },
            )

        offer.stato = "archiviata_admin"
        offer.posti_disponibili = 0
        return

    Review.query.filter_by(offer_id=offer.id).delete(synchronize_session=False)
    Claim.query.filter_by(offer_id=offer.id).delete(synchronize_session=False)
    db.session.delete(offer)


def remove_user_with_cleanup(user, motivazione, acting_admin):
    """Elimina un account e tutti i dati collegati, con notifiche amministrative."""
    motivazione = motivazione.strip()
    user_email = user.email
    user_nome = user.nome
    gallery_files = list(user.gallery_filenames)
    owned_offers = Offer.query.filter_by(user_id=user.id).all()
    owned_offer_photo_files = [
        filename
        for offer in owned_offers
        for filename in list(getattr(offer, "gallery_filenames", []))
        if filename and filename != "nessuna.jpg"
    ]
    owned_offer_ids = [offer.id for offer in owned_offers]
    now = local_now()

    if owned_offer_ids:
        claims_on_other_offers = Claim.query.filter(
            Claim.user_id == user.id,
            Claim.offer_id.notin_(owned_offer_ids),
        ).all()
    else:
        claims_on_other_offers = Claim.query.filter_by(user_id=user.id).all()

    for claim in claims_on_other_offers:
        offer = claim.offerta
        if offer:
            offer.posti_disponibili = min(offer.posti_totali, offer.posti_disponibili + 1)
            if offer.data_ora > now and offer.stato == "completata":
                offer.stato = "attiva"
            send_email(
                f"⚠️ Partecipazione rimossa: {offer.nome_locale}",
                [offer.autore.email],
                "claim_removed_admin.html",
                user=offer.autore,
                removed_user=user,
                offer=offer,
                data_evento=offer.data_ora.strftime('%d/%m/%Y alle %H:%M'),
                motivazione=motivazione,
                admin_user=acting_admin,
            )
        db.session.delete(claim)

    for offer in owned_offers:
        remove_offer_with_notifications(
            offer,
            motivazione,
            acting_admin=acting_admin,
            notify_owner=False,
        )

    Review.query.filter(
        or_(Review.reviewer_id == user.id, Review.reviewed_id == user.id)
    ).delete(synchronize_session=False)

    db.session.delete(user)
    db.session.commit()
    delete_upload_files(gallery_files + owned_offer_photo_files)

    if user_email:
        send_email(
            "Il tuo account ApprofittOffro è stato rimosso",
            [user_email],
            "account_deleted.html",
            user_name=user_nome,
            motivazione=motivazione,
            admin_user=acting_admin,
        )


# ===================================================================
# API — Autenticazione & Utilità
# ===================================================================

def remove_user_self_service(user):
    """Elimina il proprio account e pulisce le entita' collegate senza un amministratore."""
    if not user:
        return

    gallery_files = list(user.gallery_filenames)
    owned_offers = Offer.query.filter_by(user_id=user.id).all()
    owned_offer_ids = [offer.id for offer in owned_offers]
    owned_offer_photo_files = [
        filename
        for offer in owned_offers
        for filename in list(getattr(offer, "gallery_filenames", []))
        if filename and filename != "nessuna.jpg"
    ]
    now = local_now()

    if owned_offer_ids:
        claims_on_other_offers = Claim.query.filter(
            Claim.user_id == user.id,
            Claim.offer_id.notin_(owned_offer_ids),
        ).all()
    else:
        claims_on_other_offers = Claim.query.filter_by(user_id=user.id).all()

    for claim in claims_on_other_offers:
        offer = claim.offerta
        if offer:
            offer.posti_disponibili = min(
                offer.posti_totali,
                offer.posti_disponibili + 1,
            )
            if offer.data_ora > now and offer.stato == "completata":
                offer.stato = "attiva"
            if offer.autore and offer.autore.email:
                send_email(
                    f"Partecipazione annullata: {offer.nome_locale}",
                    [offer.autore.email],
                    "unclaim_notification.html",
                    background=False,
                    user=user,
                    offer=offer,
                    data_evento=offer.data_ora.strftime('%d/%m/%Y alle %H:%M'),
                )
        db.session.delete(claim)

    for offer in owned_offers:
        remove_offer_with_notifications(
            offer,
            "L'host ha cancellato il proprio account.",
            acting_admin=None,
            notify_owner=False,
        )

    Review.query.filter(
        or_(Review.reviewer_id == user.id, Review.reviewed_id == user.id)
    ).delete(synchronize_session=False)

    db.session.delete(user)
    db.session.commit()
    delete_upload_files(gallery_files + owned_offer_photo_files)


@app.route("/profile/<int:user_id>")
@login_required
@profile_completed_required
def public_profile(user_id):
    """Schermata pubblica dove visito le preferenze di un utente che dona cibo."""
    if not is_admin_user(current_user):
        return redirect(url_for("index"))
    from models import Review, Offer, Claim
    user = User.query.get_or_404(user_id)
    rating_info = get_user_rating(user_id)
    reviews = Review.query.filter_by(reviewed_id=user_id).order_by(Review.created_at.desc()).all()
    
    # Statistiche affidabilità
    offerte_totali = Offer.query.filter_by(user_id=user.id).count()
    recuperi_effettuati = Claim.query.filter_by(
        user_id=user.id,
        status=CLAIM_STATUS_ACCEPTED,
    ).count()

    # Logica per il pulsante "Lascia Recensione" sul profilo pubblico
    # Cerchiamo l'ultimo pasto condiviso concluso (almeno 3 ore fa)
    shared_offer = None
    editable_review = None
    pending_offer = None
    if current_user.id != user_id:
        now = local_now()
        threshold = now - timedelta(hours=3)
        
        def first_reviewable_offer(query):
            for offer in query.order_by(Offer.data_ora.desc()).all():
                existing_review = Review.query.filter_by(
                    reviewer_id=current_user.id,
                    reviewed_id=user_id,
                    offer_id=offer.id,
                ).first()
                if not existing_review:
                    return offer, None
                if can_edit_review(existing_review, now):
                    return offer, existing_review
            return None, None
        
        # Caso A: Io ero l'ospite, lui l'host
        meal_as_guest = Offer.query.join(Claim).filter(
            Claim.user_id == current_user.id,
            Claim.status == CLAIM_STATUS_ACCEPTED,
            Offer.user_id == user_id,
            Offer.data_ora < threshold
        )
        
        # Caso B: Io ero l'host, lui l'ospite
        meal_as_host = Offer.query.join(Claim).filter(
            Offer.user_id == current_user.id,
            Claim.user_id == user_id,
            Claim.status == CLAIM_STATUS_ACCEPTED,
            Offer.data_ora < threshold
        )
        
        shared_offer, editable_review = first_reviewable_offer(meal_as_guest)
        if not shared_offer:
            shared_offer, editable_review = first_reviewable_offer(meal_as_host)

        # Se non c'è una shared_offer già conclusa, cerchiamo una "pending" (pasto appena avvenuto o in corso)
        if not shared_offer:
            pending_as_guest = Offer.query.join(Claim).filter(
                Claim.user_id == current_user.id,
                Claim.status == CLAIM_STATUS_ACCEPTED,
                Offer.user_id == user_id,
                Offer.data_ora < now,
                Offer.data_ora >= threshold
            ).order_by(Offer.data_ora.desc()).first()
            pending_as_host = Offer.query.join(Claim).filter(
                Offer.user_id == current_user.id,
                Claim.user_id == user_id,
                Claim.status == CLAIM_STATUS_ACCEPTED,
                Offer.data_ora < now,
                Offer.data_ora >= threshold
            ).order_by(Offer.data_ora.desc()).first()
            pending_offer = pending_as_guest or pending_as_host
    
    return render_template(
        "public_profile.html", 
        user=user, 
        rating_info=rating_info,
        reviews=reviews,
        offerte_totali=offerte_totali,
        recuperi_effettuati=recuperi_effettuati,
        shared_offer=shared_offer,
        editable_review=editable_review,
        pending_offer=pending_offer,
        review_edit_threshold=local_now() - timedelta(hours=REVIEW_EDIT_WINDOW_HOURS),
        is_following=UserFollow.query.filter_by(
            follower_id=current_user.id,
            followed_id=user_id,
        ).first() is not None if current_user.id != user_id else False,
    )


@app.route("/users/<int:user_id>/follow", methods=["POST"])
@login_required
@profile_completed_required
def follow_user(user_id):
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))

    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        flash("Non puoi seguire te stesso.", "warning")
        return redirect(get_safe_next_url())
    if user.is_admin:
        flash("Non puoi seguire un amministratore.", "warning")
        return redirect(get_safe_next_url())

    existing_follow = UserFollow.query.filter_by(
        follower_id=current_user.id,
        followed_id=user.id,
    ).first()
    if not existing_follow:
        db.session.add(UserFollow(follower_id=current_user.id, followed_id=user.id))
        db.session.commit()
        send_follow_started_push(current_user, user)
        flash(f"Ora segui {user.nome}. Riceverai le sue nuove offerte via email.", "success")

    return redirect(get_safe_next_url())


@app.route("/users/<int:user_id>/unfollow", methods=["POST"])
@login_required
@profile_completed_required
def unfollow_user(user_id):
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))

    user = User.query.get_or_404(user_id)
    existing_follow = UserFollow.query.filter_by(
        follower_id=current_user.id,
        followed_id=user.id,
    ).first()
    if existing_follow:
        db.session.delete(existing_follow)
        db.session.commit()
        flash(f"Non segui più {user.nome}.", "success")

    return redirect(get_safe_next_url())

@app.errorhandler(413)
def request_entity_too_large(error):
    return jsonify({"success": False, "errors": ["Le foto sono troppo pesanti (Max 64MB complessivi). Compressione fallita."]}), 413


def google_places_enabled():
    return bool(app.config.get("GOOGLE_PLACES_API_KEY"))


GOOGLE_PLACES_ALLOWED_PRIMARY_TYPES = {
    "restaurant",
    "cafe",
    "bar",
    "bakery",
    "meal_takeaway",
    "pizza_restaurant",
    "coffee_shop",
    "fast_food_restaurant",
    "brunch_restaurant",
    "sandwich_shop",
}

GOOGLE_PLACES_INCLUDED_TYPE_GROUPS = (
    (
        "restaurant",
        "pizza_restaurant",
        "brunch_restaurant",
        "fast_food_restaurant",
    ),
    (
        "cafe",
        "coffee_shop",
        "bakery",
        "sandwich_shop",
    ),
    (
        "bar",
        "meal_takeaway",
    ),
)

GOOGLE_PLACES_EXCLUDED_PRIMARY_TYPES = {
    "shopping_mall",
    "supermarket",
    "grocery_store",
    "convenience_store",
    "market",
    "store",
    "department_store",
}

GOOGLE_PLACES_EXCLUDED_KEYWORDS = (
    "centro commerciale",
    "shopping center",
    "shopping mall",
    "supermercato",
    "ipermercato",
    "minimarket",
    "market",
    "iper ",
)


def is_google_place_relevant(place_name, place_address, primary_type):
    """Filtra solo i locali coerenti con colazione, pranzo e cena."""
    normalized_type = (primary_type or "").strip().lower()
    normalized_name = (place_name or "").strip().lower()
    normalized_address = (place_address or "").strip().lower()
    haystack = f"{normalized_name} {normalized_address}"

    if normalized_type in GOOGLE_PLACES_EXCLUDED_PRIMARY_TYPES:
        return False

    if any(keyword in haystack for keyword in GOOGLE_PLACES_EXCLUDED_KEYWORDS):
        return False

    if normalized_type in GOOGLE_PLACES_ALLOWED_PRIMARY_TYPES:
        return True

    # Fallback prudente: alcuni locali buoni arrivano con type generico ma nome parlante.
    useful_keywords = (
        "ristor",
        "pizzer",
        "pizza",
        "bar",
        "pub",
        "caff",
        "cafeter",
        "brunch",
        "oster",
        "trattor",
        "bistrot",
        "bakery",
    )
    return any(keyword in haystack for keyword in useful_keywords)


def _google_places_nearby_request(latitude, longitude, radius, included_types, max_results):
    api_key = app.config.get("GOOGLE_PLACES_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Google Places non configurato.")

    request_url = "https://places.googleapis.com/v1/places:searchNearby"
    request_payload = {
        "includedTypes": list(included_types),
        "excludedTypes": [
            "shopping_mall",
            "supermarket",
            "grocery_store",
            "market",
            "department_store",
            "convenience_store",
        ],
        "maxResultCount": max(1, min(int(max_results), 20)),
        "locationRestriction": {
            "circle": {
                "center": {
                    "latitude": float(latitude),
                    "longitude": float(longitude),
                },
                "radius": float(max(100, min(radius, 8000))),
            }
        },
        "rankPreference": "DISTANCE",
        "languageCode": "it",
        "regionCode": "IT",
    }
    req = Request(
        request_url,
        data=json.dumps(request_payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": ",".join([
                "places.id",
                "places.displayName",
                "places.formattedAddress",
                "places.location",
                "places.primaryType",
            ]),
        },
        method="POST",
    )

    try:
        with urlopen(req, timeout=12) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        details = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Google Places HTTP {exc.code}: {details}") from exc
    except URLError as exc:
        raise RuntimeError(f"Google Places non raggiungibile: {exc}") from exc

    return payload.get("places", [])


def search_google_nearby_places(latitude, longitude, radius=7000, max_results=36):
    """Cerca locali vicini tramite Google Places API (New)."""
    places_by_id = {}
    last_error = None

    for included_types in GOOGLE_PLACES_INCLUDED_TYPE_GROUPS:
        try:
            raw_places = _google_places_nearby_request(
                latitude,
                longitude,
                radius=radius,
                included_types=included_types,
                max_results=max_results,
            )
        except Exception as exc:
            print(f"[GOOGLE_PLACES_GROUP_ERROR] types={included_types} error={exc}")
            last_error = exc
            continue
        for place in raw_places:
            location = place.get("location") or {}
            display_name = place.get("displayName") or {}
            lat = location.get("latitude")
            lon = location.get("longitude")
            if lat is None or lon is None:
                continue
            place_name = display_name.get("text", "").strip()
            place_address = (place.get("formattedAddress") or "").strip()
            primary_type = (place.get("primaryType") or "").strip()
            if not is_google_place_relevant(place_name, place_address, primary_type):
                continue
            place_id = (place.get("id") or "").strip()
            if not place_id or place_id in places_by_id:
                continue
            places_by_id[place_id] = {
                "id": place_id,
                "name": place_name,
                "address": place_address,
                "latitude": float(lat),
                "longitude": float(lon),
                "primary_type": primary_type,
                "_distance_km": calculate_distance(
                    float(latitude),
                    float(longitude),
                    float(lat),
                    float(lon),
                ),
            }

    places = []
    for place in sorted(
        places_by_id.values(),
        key=lambda item: (item["_distance_km"], item["name"].lower()),
    ):
        normalized_place = dict(place)
        normalized_place.pop("_distance_km", None)
        places.append(normalized_place)
        if len(places) >= max(1, min(int(max_results), 60)):
            break

    if not places and last_error is not None:
        raise last_error

    return places


def get_google_place_details(place_id):
    """Recupera dettagli mirati del locale selezionato."""
    api_key = app.config.get("GOOGLE_PLACES_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Google Places non configurato.")

    safe_place_id = quote(place_id.strip(), safe="")
    request_url = f"https://places.googleapis.com/v1/places/{safe_place_id}"
    req = Request(
        request_url,
        headers={
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": ",".join(
                [
                    "id",
                    "displayName",
                    "formattedAddress",
                    "location",
                    "primaryType",
                    "nationalPhoneNumber",
                    "internationalPhoneNumber",
                ]
            ),
        },
        method="GET",
    )

    try:
        with urlopen(req, timeout=12) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        details = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Google Places HTTP {exc.code}: {details}") from exc
    except URLError as exc:
        raise RuntimeError(f"Google Places non raggiungibile: {exc}") from exc

    location = payload.get("location") or {}
    display_name = payload.get("displayName") or {}
    return {
        "id": payload.get("id", ""),
        "name": display_name.get("text", "").strip(),
        "address": (payload.get("formattedAddress") or "").strip(),
        "latitude": float(location.get("latitude") or 0),
        "longitude": float(location.get("longitude") or 0),
        "primary_type": (payload.get("primaryType") or "").strip(),
        "phone_number": (
            (payload.get("nationalPhoneNumber") or "").strip()
            or (payload.get("internationalPhoneNumber") or "").strip()
        ),
    }


@app.route("/api/geocode")
def api_geocode():
    """Proxy sicuro per l'API di Reverse Geocoding per aggirare Adblockers da cellulare e Rate Limit IP."""
    import urllib.request
    import json
    lat = request.args.get("lat")
    lon = request.args.get("lon")
    if not lat or not lon:
        return jsonify({"address": "Zona Sconosciuta"})
        
    url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&zoom=18&addressdetails=1"
    req = urllib.request.Request(url, headers={'User-Agent': 'ApprofittOffro/1.0 (approfittoffro_utente@test.com)'})
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            data = json.loads(response.read().decode())
            addr_data = data.get("address", {})
            
            road = addr_data.get("road", "")
            hon = addr_data.get("house_number") or addr_data.get("building") or ""
            
            # Se hon è ancora vuoto (es. in alcuni POI), proviamo a estrarlo dalle prime parti del display_name
            display_name = data.get("display_name", "")
            if not hon and display_name:
                parts = [p.strip() for p in display_name.split(',')]
                for p in parts[:2]:
                    # Cerca una parte che inizi con un numero (es. "1", "1/A", "10 bis")
                    if any(c.isdigit() for c in p) and len(p) < 10:
                        hon = p
                        break
            
            # Priorità per la città
            city = addr_data.get("city") or addr_data.get("town") or addr_data.get("village") or addr_data.get("hamlet") or addr_data.get("suburb") or ""
            
            if road:
                # Formato Italiano: Via Strada Numero, Città
                full_addr = f"{road}"
                if hon and hon.lower() not in road.lower(): 
                   full_addr += f" {hon}"
                if city: 
                   full_addr += f", {city}"
                return jsonify({"address": full_addr})
            
            # Fallback se non c'è la strada (usa le prime 3 parti del display_name)
            if display_name:
                parts = [p.strip() for p in display_name.split(',')]
                return jsonify({"address": ", ".join(parts[:3])})
    except Exception:
        pass
    
    return jsonify({"address": "Posizione Mappa"})


@app.route("/api/places/nearby", methods=["GET"])
@login_required
def api_places_nearby():
    """Restituisce locali Google Places vicini al punto richiesto."""
    lat = request.args.get("lat", "").strip()
    lon = request.args.get("lon", "").strip()
    radius = request.args.get("radius", "7000").strip()
    max_results = request.args.get("max_results", "36").strip()

    if not google_places_enabled():
        return jsonify({
            "success": False,
            "error": "Google Places non configurato su questo ambiente.",
        }), 503

    try:
        latitude = float(lat.replace(",", "."))
        longitude = float(lon.replace(",", "."))
        radius_m = int(float(radius.replace(",", ".")))
        max_results_value = int(float(max_results.replace(",", ".")))
    except ValueError:
        return jsonify({
            "success": False,
            "error": "Coordinate, raggio o numero risultati non validi.",
        }), 400

    try:
        places = search_google_nearby_places(
            latitude,
            longitude,
            radius=radius_m,
            max_results=max_results_value,
        )
    except Exception as exc:
        print(f"[GOOGLE_PLACES_ERROR] {exc}")
        return jsonify({
            "success": False,
            "error": "Impossibile recuperare i locali vicini in questo momento.",
        }), 502

    return jsonify({
        "success": True,
        "places": places,
    })


@app.route("/api/places/<path:place_id>", methods=["GET"])
@login_required
def api_place_details(place_id):
    """Restituisce i dettagli essenziali del locale Google selezionato."""
    if not google_places_enabled():
        return jsonify({
            "success": False,
            "error": "Google Places non configurato su questo ambiente.",
        }), 503

    safe_place_id = (place_id or "").strip()
    if not safe_place_id:
        return jsonify({
            "success": False,
            "error": "Identificativo locale mancante.",
        }), 400

    try:
        place = get_google_place_details(safe_place_id)
    except Exception as exc:
        print(f"[GOOGLE_PLACE_DETAILS_ERROR] {exc}")
        return jsonify({
            "success": False,
            "error": str(exc),
        }), 502

    if not is_google_place_relevant(
        place.get("name"),
        place.get("address"),
        place.get("primary_type"),
    ):
        return jsonify({
            "success": False,
            "error": "Seleziona solo bar, ristoranti, pizzerie o pub.",
        }), 422

    return jsonify({
        "success": True,
        "place": place,
    })


@app.route("/api/register", methods=["POST"])
def api_register():
    """Registra un nuovo utente con verifica foto. Forza il logout di sessioni esistenti."""
    from flask_login import logout_user
    logout_user() # Assicura che la registrazione parta da un contesto pulito (Shared Device Fix)
    photo_filenames = []
    photo_moderation_results = []
    try:
        nome = request.form.get("nome", "").strip()
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        conferma_password = request.form.get("conferma_password", "")
        numero_telefono_raw = request.form.get("numero_telefono", "")
        eta_raw = request.form.get("eta", "")
        sesso_raw = request.form.get("sesso", "non_dico")
        lat = request.form.get("latitudine")
        lon = request.form.get("longitudine")
        citta = request.form.get("citta", "").strip()
        bio = request.form.get("bio", "").strip()
        accepted_terms = str(request.form.get("accepted_terms", "")).strip().lower() in {"1", "true", "yes", "on"}
        accepted_privacy = str(request.form.get("accepted_privacy", "")).strip().lower() in {"1", "true", "yes", "on"}
        accepted_rules = str(request.form.get("accepted_community_rules", "")).strip().lower() in {"1", "true", "yes", "on"}
        eta, eta_error = parse_age_value(eta_raw)
        sesso, sesso_error = parse_gender_value(sesso_raw)
        numero_telefono, phone_error = normalize_phone_number(numero_telefono_raw)

        # Validazione campi
        errors = []
        if not nome:
            errors.append("Il nome è obbligatorio.")
        if not email or "@" not in email:
            errors.append("Inserisci un'email valida.")
        if phone_error:
            errors.append(phone_error)
        if len(password) < 6:
            errors.append("La password deve avere almeno 6 caratteri.")
        if password != conferma_password:
            errors.append("Le due password non coincidono.")
        if eta_error:
            errors.append(eta_error)
        if sesso_error:
            errors.append(sesso_error)
        if not lat or not lon:
            errors.append("Seleziona la tua posizione sulla mappa.")
        if len(bio) > 0 and len(bio) < 5:
            errors.append("Raccontaci qualcosa di piu nella Bio.")
        if not (accepted_terms and accepted_privacy and accepted_rules):
            errors.append("Per registrarti devi accettare Termini, Privacy e Regolamento Community.")

        # Controlla email duplicata
        if User.query.filter_by(email=email).first():
            errors.append("Questa email è già registrata.")

        # Controlla foto
        foto_files = extract_uploaded_photos("foto")
        if not foto_files:
            errors.append("Carica almeno una foto profilo.")

        if errors:
            return jsonify({"success": False, "errors": errors}), 400

        photo_filenames, photo_errors, photo_moderation_results = save_profile_gallery_files(
            "new",
            foto_files,
            require_primary_face=True,
            return_moderation=True,
        )
        if photo_errors:
            return jsonify({"success": False, "errors": photo_errors}), 400

        # Crea l'utente
        token_verifica = uuid.uuid4().hex
        user = User(
            nome=nome,
            email=email,
            foto_filename=photo_filenames[0],
            fascia_eta=str(eta),
            eta=eta,
            sesso=sesso,
            numero_telefono=numero_telefono,
            latitudine=float(lat),
            longitudine=float(lon),
            citta=citta,
            bio=bio,
            verificato=False,
            verification_token=token_verifica
        )
        user.set_password(password)
        accept_current_legal_for_user(user)

        db.session.add(user)
        db.session.flush()
        replace_user_gallery(user, photo_filenames)
        photo_moderation_result = apply_user_photo_moderation(
            user,
            photo_moderation_results,
            allow_auto_approve=True,
        )
        bio_moderation_result = None
        if bio:
            bio_moderation_result = apply_user_bio_moderation(
                user,
                bio,
                allow_auto_approve=True,
            )
        db.session.commit()
        if bio_moderation_result:
            notify_admin_for_user_moderation(
                user,
                bio_moderation_result,
                content_label="Bio",
            )
        notify_admin_for_user_moderation(
            user,
            photo_moderation_result,
            content_label="Foto profilo",
        )

        # La verifica registrazione merita un invio immediato, non solo su thread.
        link_verifica = url_for('verify_email', token=token_verifica, _external=True)
        verification_sent = send_email(
            "Benvenuto su ApprofittOffro! Conferma la tua email 🍽️",
            [user.email],
            "verification.html",
            background=False,
            user=user,
            link_verifica=link_verifica
        )
        if not verification_sent:
            verification_sent = send_registration_verification_email(
                user,
                link_verifica,
            )
        print(
            f"[REGISTER_VERIFICATION_MAIL] user={user.id} email={user.email} sent={verification_sent} provider={get_active_email_provider()}"
        )

        return jsonify({
            "success": True, 
            "message": "Registrazione completata! Controlla la tua email per confermare l'account prima di accedere."
        })
    except Exception as super_err:
        db.session.rollback()
        delete_upload_files(photo_filenames)
        return jsonify({"success": False, "errors": [f"Errore gravissimo server: {str(super_err)}"]}), 500


@app.route("/api/login", methods=["POST"])
def api_login():
    """Login utente."""
    data = request.get_json() if request.is_json else request.form
    login_input = data.get("email", "").strip()
    password = data.get("password", "")

    # Cerca per email oppure per alias (utile per admin)
    user = User.query.filter(
        (User.email == login_input.lower()) | (User.alias == login_input)
    ).first()

    if not user or not user.check_password(password):
        return jsonify({"success": False, "errors": ["Email o password non corretti."]}), 401

    if not user.verificato:
        return jsonify({"success": False, "errors": ["Devi prima confermare la tua email! Controlla la posta."]}), 401

    session.clear()
    login_user(user, remember=False)
    now_ts = int(datetime.now(timezone.utc).timestamp())
    session["last_activity_at"] = now_ts
    session["login_at"] = now_ts
    return jsonify({
        "success": True,
        "redirect": url_for("admin_dashboard") if is_admin_user(user) else url_for("dashboard"),
    })


@app.route("/api/password/forgot", methods=["POST"])
def api_password_forgot():
    """Invia un link di recupero password agli account registrati via email."""
    data = request.get_json(silent=True) or request.form or {}
    email = str(data.get("email", "") or "").strip().lower()

    if not email or "@" not in email:
        return jsonify({
            "success": False,
            "errors": ["Inserisci un'email valida per recuperare la password."],
        }), 400

    user = User.query.filter_by(email=email).first()
    reset_requested = False

    if user and user_can_change_password(user) and user.verificato:
        user.password_reset_token = uuid.uuid4().hex
        user.password_reset_sent_at = local_now()
        db.session.commit()
        reset_requested = send_password_reset_email(user)
        print(
            f"[PASSWORD_RESET_REQUEST] user={user.id} email={user.email} sent={reset_requested}"
        )

    return jsonify({
        "success": True,
        "message": (
            "Se l'account puo' essere recuperato via password, ti abbiamo inviato un link per sceglierne una nuova."
        ),
    })


@app.route("/api/auth/google", methods=["POST"])
def api_google_login():
    """Login mobile via Google ID token verificato lato server."""
    data = request.get_json(silent=True) or {}
    raw_token = str(data.get("id_token", "") or "").strip()

    try:
        identity_payload = verify_google_identity_token(raw_token)
        user, created, admin_notification_required = resolve_google_user(identity_payload)
    except ValueError as exc:
        return jsonify({"success": False, "errors": [str(exc)]}), 400
    except Exception as exc:
        print(f"[GOOGLE_LOGIN_ERROR] {exc}")
        return jsonify({
            "success": False,
            "errors": ["Non riesco a completare l'accesso Google adesso."],
        }), 500

    print(
        f"[GOOGLE_SIGNUP_FLOW] user={getattr(user, 'id', None)} email={getattr(user, 'email', '')} "
        f"created={created} admin_notification_required={admin_notification_required}"
    )
    if admin_notification_required:
        notify_admin_for_verified_user(user, source="google")

    session.clear()
    login_user(user, remember=False)
    now_ts = int(datetime.now(timezone.utc).timestamp())
    session["last_activity_at"] = now_ts
    session["login_at"] = now_ts

    return jsonify({
        "success": True,
        "created": created,
        "redirect": url_for("admin_dashboard") if is_admin_user(user) else url_for("dashboard"),
    })


@app.route("/logout", methods=["GET"])
@login_required
def web_logout():
    logout_user()
    session.clear()
    return redirect(url_for('index'))

@app.route("/api/logout", methods=["POST"])
def api_logout():
    logout_user()
    session.clear()
    return jsonify({"success": True, "redirect": url_for("index")})


# ===================================================================
# API — Offerte
# ===================================================================
@app.route("/api/offers", methods=["GET"])
def api_get_offers():
    """Recupera le offerte attualmente valide e visibili."""
    if current_user.is_authenticated and not is_admin_user(current_user):
        moderation_error = require_moderation_clear_json(current_user)
        if moderation_error:
            return moderation_error

    tipo = request.args.get("tipo", "")
    radius_str = request.args.get("radius", "")
    limit_str = request.args.get("limit", "").strip()
    now = local_now()
    threshold = now - timedelta(hours=3)
    query = Offer.query.options(
        selectinload(Offer.autore).selectinload(User.photos),
        selectinload(Offer.photos),
        selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
    ).filter(
        Offer.stato.in_(["attiva", "completata"]),
        Offer.data_ora > threshold,
    )

    if tipo:
        query = query.filter(Offer.tipo_pasto == tipo)

    offers = query.order_by(Offer.data_ora.asc()).all()
    offers, _visibility_stats = filter_visible_offers_and_notify_empty_started_hosts(
        offers,
        now=now,
    )

    # Applica filtro per Raggio se specificato
    radius_km = None
    if radius_str:
        try:
            radius_km = float(radius_str.replace(",", "."))
        except ValueError:
            radius_km = None
    elif current_user.is_authenticated:
        try:
            radius_km = float(current_user.raggio_azione or 15)
        except (TypeError, ValueError):
            radius_km = 15

    if radius_km is not None and radius_km >= 999:
        radius_km = None

    limit = None
    if limit_str:
        try:
            parsed_limit = int(limit_str)
            if parsed_limit > 0:
                limit = parsed_limit
        except ValueError:
            limit = None

    # Centro di ricerca (predefinito: utente loggato, altrimenti Roma)
    if current_user.is_authenticated:
        search_lat = current_user.latitudine
        search_lon = current_user.longitudine
    else:
        search_lat = 41.9
        search_lon = 12.5
    
    req_lat = request.args.get("lat")
    req_lon = request.args.get("lon")
    if req_lat and req_lon:
        try:
            search_lat = float(req_lat)
            search_lon = float(req_lon)
        except ValueError:
            pass

    result = []
    for o in offers:
        dist = calculate_distance(search_lat, search_lon, o.latitudine, o.longitudine)
        booking_deadline = get_offer_booking_deadline(o)
        booking_closed = is_offer_booking_closed(o, now)
        has_started = o.data_ora <= now
        author_rating = get_user_rating(o.autore.id)
        
        # Controlla se l'utente corrente ha già approfittato
        current_claim = None
        already_claimed = False
        is_own = False
        host_whatsapp_link = ""
        if current_user.is_authenticated:
            current_claim = next(
                (claim for claim in o.claims if claim.user_id == current_user.id),
                None,
            )
            if (
                current_claim is not None
                and current_claim.status == CLAIM_STATUS_REJECTED
                and bool(getattr(current_claim, "hidden_by_guest", False))
            ):
                continue
            already_claimed = (
                current_claim is not None
                and current_claim.status == CLAIM_STATUS_ACCEPTED
            )
            is_own = o.user_id == current_user.id
            if (
                current_claim is not None
                and current_claim.status == CLAIM_STATUS_ACCEPTED
                and not is_own
            ):
                host_whatsapp_link = build_whatsapp_offer_link(current_user, o.autore, o)

        if is_user_moderation_restricted(o.autore) and not is_own:
            continue

        # Il raggio filtra gli eventi degli altri; i propri restano nel payload
        # per tenere sempre visibile il promemoria di gestione nel menu Approfitta.
        if radius_km is not None and not is_own and dist > radius_km:
            continue

        claim_status = get_mobile_claim_status(current_claim)
        if current_claim is None and (o.stato != "attiva" or o.posti_disponibili <= 0):
            claim_status = "full"
        elif current_claim is None and has_started:
            claim_status = "started"
        elif current_claim is None and booking_closed:
            claim_status = "booking_closed"

        can_claim = (
            (not is_own)
            and current_claim is None
            and claim_status == "open"
        )

        accepted_claims = get_offer_accepted_claims(o)
        offer_gallery = [
            filename
            for filename in list(getattr(o, "gallery_filenames", []))
            if filename and filename != "nessuna.jpg"
        ]
        primary_offer_photo = (
            offer_gallery[0]
            if offer_gallery
            else getattr(o, "foto_locale", "nessuna.jpg")
        )

        result.append({
            "id": o.id,
            "tipo_pasto": o.tipo_pasto,
            "nome_locale": o.nome_locale,
            "indirizzo": o.indirizzo,
            "city_label": extract_city_label(o.indirizzo),
            "telefono_locale": getattr(o, "telefono_locale", "") or "",
            "lat": o.latitudine,
            "lon": o.longitudine,
            "distance_km": round(dist, 1),
            "posti_totali": o.posti_totali,
            "posti_disponibili": o.posti_disponibili,
            "stato": o.stato,
            "data_ora": o.data_ora.isoformat(),
            "booking_deadline": booking_deadline.isoformat(),
            "booking_closed": booking_closed,
            "has_started": has_started,
            "descrizione": o.descrizione or "",
            "foto_locale": primary_offer_photo,
            "foto_locale_gallery": offer_gallery,
            "foto_locale_count": len(offer_gallery),
            "autore": o.autore.nome,
            "autore_id": o.autore.id,
            "autore_foto": o.autore.foto_filename,
            "autore_foto_gallery": o.autore.gallery_filenames[:2],
            "autore_eta": o.autore.eta_display,
            "autore_rating_average": author_rating["average"],
            "autore_rating_count": author_rating["count"],
            "autore_cibi_preferiti": o.autore.cibi_preferiti or "",
            "autore_intolleranze": o.autore.intolleranze or "",
            "host_whatsapp_link": host_whatsapp_link,
            "host_chat_enabled": already_claimed,
            "partecipanti": [
                {
                    "id": claim.utente.id,
                    "nome": claim.utente.nome,
                    "foto": claim.utente.foto_filename,
                    "chat_enabled": True,
                    "whatsapp_link": build_whatsapp_offer_link(current_user, claim.utente, o)
                    if current_user.is_authenticated and is_own
                    else "",
                }
                for claim in accepted_claims
                if claim.utente and is_public_user_visible_to_viewer(claim.utente, current_user)
            ],
            "is_own": is_own,
            "already_claimed": already_claimed,
            "can_claim": can_claim,
            "claim_status": claim_status,
            "claim_id": current_claim.id if current_claim is not None else 0,
        })

        if limit is not None and len(result) >= limit:
            break

    return jsonify({"success": True, "offers": result})


@app.route("/api/offers/<int:offer_id>/reminders", methods=["POST"])
@login_required
def api_set_offer_reminders(offer_id):
    """Imposta i minuti di promemoria per un evento."""
    data = request.get_json() or {}
    minutes = data.get("minutes", [])
    
    # Validazione base
    if not isinstance(minutes, list):
        return jsonify({"success": False, "error": "Formato non valido."}), 400
    
    # Pulizia vecchi reminder
    UserReminder.query.filter_by(user_id=current_user.id, offer_id=offer_id).delete()
    db.session.flush() # Forza la cancellazione prima di inserire
    
    # Inserimento nuovi
    for m in minutes:
        try:
            m_int = int(m)
            if m_int > 0:
                db.session.add(UserReminder(user_id=current_user.id, offer_id=offer_id, minutes_before=m_int))
        except (ValueError, TypeError):
            pass
            
    db.session.commit()
    return jsonify({"success": True, "count": len(minutes)})


@app.route("/api/offers/<int:offer_id>/reminders", methods=["GET"])
@login_required
def api_get_offer_reminders(offer_id):
    """Ottiene i minuti di promemoria salvati per un evento."""
    reminders = UserReminder.query.filter_by(user_id=current_user.id, offer_id=offer_id).all()
    return jsonify({"success": True, "minutes": [r.minutes_before for r in reminders]})


@app.route("/api/user/offers", methods=["GET"])
@login_required
def api_get_user_profile_offers():
    """Restituisce offerte e approfitti visibili nel profilo per 24 ore dopo la conclusione."""
    scope = request.args.get("scope", "owned").strip().lower()
    archived = request.args.get("archived", "").strip().lower() in {"1", "true", "yes"}
    now = local_now()
    threshold = now - timedelta(hours=PROFILE_EVENT_HISTORY_HOURS)
    archive_start = now - timedelta(days=PROFILE_ARCHIVE_LOOKBACK_DAYS)

    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Offer.user_id == current_user.id,
        )
        if archived:
            from sqlalchemy import or_, and_
            offers_query = offers_query.filter(
                Offer.stato == "archiviata",
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()
        if not archived:
            for offer in offers:
                if is_offer_started_without_participants(offer, now=now):
                    notify_host_offer_started_without_participants(
                        offer,
                        now=now,
                    )
        result = [
            serialize_mobile_offer(offer, viewer=current_user, now=now)
            for offer in offers
        ]
    elif scope == "claimed":
        claims_query = Claim.query.join(Offer, Claim.offer_id == Offer.id).options(
            selectinload(Claim.utente).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Claim.user_id == current_user.id,
            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
        )
        if archived:
            from sqlalchemy import or_, and_
            claims_query = claims_query.filter(
                Offer.stato == "archiviata",
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        claims = claims_query.order_by(Offer.data_ora.desc()).all()
        result = []
        seen_offer_ids = set()
        for claim in claims:
            offer = claim.offerta
            if not offer or offer.id in seen_offer_ids:
                continue
            if not archived and is_offer_started_without_participants(offer, now=now):
                notify_host_offer_started_without_participants(offer, now=now)
                continue
            seen_offer_ids.add(offer.id)
            result.append(
                serialize_mobile_offer(
                    offer,
                    viewer=current_user,
                    current_claim=claim,
                    now=now,
                )
            )
    else:
        return jsonify({"success": False, "error": "Scope non valido."}), 400

    return jsonify(
        {
            "success": True,
            "history_hours": PROFILE_EVENT_HISTORY_HOURS,
            "archive_days": PROFILE_ARCHIVE_LOOKBACK_DAYS,
            "archived": archived,
            "offers": result,
        }
    )


@app.route("/api/offers/<int:offer_id>", methods=["DELETE"])
@login_required
def api_delete_offer(offer_id):
    """Elimina definitivamente un'offerta, notificando eventuali partecipanti."""
    offer = Offer.query.get(offer_id)
    if not offer:
        return jsonify({"success": False, "error": "Offerta non trovata."}), 404
    
    if not can_manage_offer(offer, current_user):
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    
    # Riceve la motivazione dal corpo della richiesta (JSON)
    data = request.get_json(silent=True) or {}
    motivazione = data.get("motivazione", "Nessuna motivazione specificata.").strip() or "Nessuna motivazione specificata."
    gallery_files = [
        filename
        for filename in list(getattr(offer, "gallery_filenames", []))
        if filename and filename != "nessuna.jpg"
    ]
    is_admin_action = can_access_admin_area(current_user) and offer.user_id != current_user.id

    remove_offer_with_notifications(
        offer,
        motivazione,
        acting_admin=current_user if is_admin_action else None,
        notify_owner=is_admin_action,
        preserve_review_history=is_admin_action,
    )
    db.session.commit()
    if offer.stato != "archiviata_admin":
        delete_upload_files(gallery_files)
    
    return jsonify({"success": True, "message": "Offerta eliminata e partecipanti notificati."})
    
    # Trova tutti i partecipanti (Claims)
    claims = Claim.query.filter_by(offer_id=offer.id).all()
    
    # Se ci sono partecipanti, mandiamo l'email di avviso a ciascuno
    if claims:
        data_evento = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')
        for claim in claims:
            send_email(
                f"⚠️ Evento Annullato: {offer.nome_locale}",
                [claim.utente.email],
                "cancellation.html",
                user=claim.utente,
                offer=offer,
                data_evento=data_evento,
                motivazione=motivazione
            )

    # Eliminazione effettiva
    Claim.query.filter_by(offer_id=offer.id).delete()
    db.session.delete(offer)
    db.session.commit()
    
    return jsonify({"success": True, "message": "Offerta eliminata e partecipanti notificati."})


@app.route("/edit-offer/<int:offer_id>")
@login_required
@profile_completed_required
def edit_offer_page(offer_id):
    """Schermata per la modifica di un'offerta esistente."""
    offer = Offer.query.get_or_404(offer_id)
    if not can_access_admin_area(current_user):
        return redirect(url_for("index"))
    if not can_manage_offer(offer, current_user):
        flash("Non puoi modificare le offerte altrui.", "error")
        return redirect(url_for("dashboard"))
    allow_admin_timing_bypass = can_access_admin_area(current_user) and request.args.get("from") == "admin"
    return_url = url_for("admin_dashboard") if allow_admin_timing_bypass else url_for("dashboard")
    return render_template(
        "create_offer.html",
        offer=offer,
        tipi_pasto=TIPI_PASTO,
        return_url=return_url,
        allow_admin_timing_bypass=allow_admin_timing_bypass,
    )


@app.route("/api/offers/<int:offer_id>", methods=["PUT"])
@login_required
def api_edit_offer(offer_id):
    """Applica le modifiche a un'offerta pre-esistente."""
    profile_error = require_complete_profile_json()
    if profile_error:
        return profile_error
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error

    offer = Offer.query.get_or_404(offer_id)
    if not can_manage_offer(offer, current_user):
        return jsonify({"success": False, "errors": ["Non autorizzato."]}), 403

    previous_state = snapshot_offer_notification_state(offer)

    tipo_pasto = request.form.get("tipo_pasto", "")
    nome_locale = request.form.get("nome_locale", "").strip()
    indirizzo = request.form.get("indirizzo", "").strip()
    telefono_locale = request.form.get("telefono_locale", "").strip()
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    posti = request.form.get("posti_totali")
    data_ora_str = request.form.get("data_ora", "")
    descrizione = request.form.get("descrizione", "").strip()
    foto_files = extract_uploaded_photos("foto_locale")
    existing_photo_filenames_raw = request.form.get("existing_photo_filenames", "").strip()
    if existing_photo_filenames_raw:
        try:
            existing_photo_filenames = [
                str(filename).strip()
                for filename in (json.loads(existing_photo_filenames_raw) or [])
                if str(filename).strip()
            ]
        except (TypeError, ValueError, json.JSONDecodeError):
            existing_photo_filenames = []
    else:
        existing_photo_filenames = []
    force_short_notice = parse_force_short_notice_flag(
        request.form.get("force_short_notice")
    )

    errors = []
    if tipo_pasto not in [t[0] for t in TIPI_PASTO]:
        errors.append("Seleziona un tipo di pasto valido.")
    if not nome_locale:
        errors.append("Il nome del locale è obbligatorio.")
    if not indirizzo:
        errors.append("L'indirizzo è obbligatorio.")
    if not lat or not lon:
        errors.append("Seleziona la posizione del locale sulla mappa.")
    if not data_ora_str:
        errors.append("Seleziona data e ora.")
    if not descrizione or len(descrizione) < 5:
        errors.append("La descrizione deve contenere almeno 5 caratteri.")
    current_gallery = [
        filename
        for filename in list(getattr(offer, "gallery_filenames", []))
        if filename and filename != "nessuna.jpg"
    ]
    invalid_existing_filenames = [
        filename for filename in existing_photo_filenames if filename not in current_gallery
    ]
    if invalid_existing_filenames:
        errors.append("Alcune foto evento selezionate non sono più disponibili.")
    for foto_locale in foto_files:
        if not allowed_file(foto_locale.filename):
            errors.append("Formato foto evento non valido (usa JPG, PNG o WEBP).")
            break
    if len(existing_photo_filenames) + len(foto_files) > MAX_OFFER_PHOTOS:
        errors.append(f"Puoi salvare al massimo {MAX_OFFER_PHOTOS} foto evento.")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    try:
        data_ora = datetime.fromisoformat(data_ora_str)
    except (ValueError, TypeError):
        return jsonify({"success": False, "errors": ["Formato data non valido."]}), 400

    scheduling_conflict = get_user_meal_schedule_conflict(
        offer.user_id,
        tipo_pasto,
        data_ora,
        exclude_offer_id=offer.id,
    )
    if scheduling_conflict:
        return jsonify({
            "success": False,
            "errors": [build_meal_schedule_conflict_message(tipo_pasto, scheduling_conflict)],
        }), 400

    requires_short_notice_override = is_new_offer_publication_too_late(
        tipo_pasto,
        data_ora,
    )
    if (
        (not can_access_admin_area(current_user))
        and requires_short_notice_override
        and not force_short_notice
    ):
        return jsonify({
            "success": False,
            "errors": [get_offer_publication_too_late_message(tipo_pasto)],
        }), 409

    try:
        requested_posti = int(posti)
    except (TypeError, ValueError):
        return jsonify({"success": False, "errors": ["Numero posti non valido."]}), 400

    occupied_seats = max(0, offer.posti_totali - offer.posti_disponibili)
    if requested_posti < occupied_seats:
        return jsonify({
            "success": False,
            "errors": [
                f"Non puoi scendere sotto {occupied_seats} posti: ci sono gia partecipanti confermati."
            ],
        }), 400
    uploaded_photo_filenames, photo_errors = save_offer_gallery_files(
        offer.user_id,
        foto_files,
    )
    if photo_errors:
        return jsonify({"success": False, "errors": photo_errors}), 400
    final_gallery_filenames = existing_photo_filenames + uploaded_photo_filenames

    offer.tipo_pasto = tipo_pasto
    offer.nome_locale = nome_locale
    offer.indirizzo = indirizzo
    offer.telefono_locale = telefono_locale
    offer.latitudine = float(lat)
    offer.longitudine = float(lon)
    
    diff_posti = requested_posti - offer.posti_totali
    offer.posti_totali = requested_posti
    offer.posti_disponibili = max(0, offer.posti_disponibili + diff_posti)
    
    if offer.stato == "completata" and offer.posti_disponibili > 0:
        offer.stato = "attiva"
    
    offer.data_ora = data_ora
    offer.booking_lead_override_minutes = (
        get_short_notice_booking_lead_minutes_for_meal_type(tipo_pasto)
        if requires_short_notice_override
        else None
    )
    offer.descrizione = descrizione
    old_gallery_filenames = []
    if final_gallery_filenames != current_gallery:
        old_gallery_filenames = replace_offer_gallery(offer, final_gallery_filenames)

    try:
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        delete_upload_files(uploaded_photo_filenames)
        return jsonify({"success": False, "errors": [f"Errore nel salvataggio dell'offerta: {exc}"]}), 500

    delete_upload_files(old_gallery_filenames)
    notify_claimants_for_offer_update(offer, previous_state, current_user)
    return jsonify({"success": True, "message": "Offerta aggiornata con successo!", "offer_id": offer.id})




@app.route("/api/offers/<int:offer_id>/archive", methods=["POST"])
@login_required
def api_archive_offer(offer_id):
    offer = Offer.query.get_or_404(offer_id)
    if not can_manage_offer(offer, current_user):
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    if offer.stato == "archiviata":
        return jsonify({"success": False, "error": "Offerta già archiviata."}), 400
    offer.stato = "archiviata"
    offer.posti_disponibili = 0
    db.session.commit()
    return jsonify({"success": True, "message": "Offerta archiviata.", "offer_id": offer.id})

@app.route("/api/offers", methods=["POST"])
@login_required
def api_create_offer():
    """Crea una nuova offerta con foto del locale."""
    profile_error = require_complete_profile_json()
    if profile_error:
        return profile_error
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error

    tipo_pasto = request.form.get("tipo_pasto", "")
    nome_locale = request.form.get("nome_locale", "").strip()
    indirizzo = request.form.get("indirizzo", "").strip()
    telefono_locale = request.form.get("telefono_locale", "").strip()
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    posti = request.form.get("posti_totali")
    data_ora_str = request.form.get("data_ora", "")
    descrizione = request.form.get("descrizione", "").strip()
    foto_files = extract_uploaded_photos("foto_locale")
    force_short_notice = parse_force_short_notice_flag(
        request.form.get("force_short_notice")
    )

    # Validazione
    errors = []
    if tipo_pasto not in [t[0] for t in TIPI_PASTO]:
        errors.append("Seleziona un tipo di pasto valido.")
    if not nome_locale:
        errors.append("Il nome del locale è obbligatorio.")
    if not indirizzo:
        errors.append("L'indirizzo è obbligatorio.")
    if not lat or not lon:
        errors.append("Seleziona la posizione del locale sulla mappa.")
    if not data_ora_str:
        errors.append("Seleziona data e ora.")
    if not descrizione or len(descrizione) < 5:
        errors.append("La descrizione deve contenere almeno 5 caratteri.")
    for foto_locale in foto_files:
        if not allowed_file(foto_locale.filename):
            errors.append("Formato foto evento non valido (usa JPG, PNG o WEBP).")
            break
    if len(foto_files) > MAX_OFFER_PHOTOS:
        errors.append(f"Puoi caricare al massimo {MAX_OFFER_PHOTOS} foto evento.")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    # Parsa la data
    try:
        data_ora = datetime.fromisoformat(data_ora_str)
    except (ValueError, TypeError):
        return jsonify({"success": False, "errors": ["Formato data non valido."]}), 400

    scheduling_conflict = get_user_meal_schedule_conflict(
        current_user.id,
        tipo_pasto,
        data_ora,
    )
    if scheduling_conflict:
        return jsonify({
            "success": False,
            "errors": [build_meal_schedule_conflict_message(tipo_pasto, scheduling_conflict)],
        }), 400

    requires_short_notice_override = is_new_offer_publication_too_late(
        tipo_pasto,
        data_ora,
    )
    if requires_short_notice_override and not force_short_notice:
        return jsonify({
            "success": False,
            "errors": [get_offer_publication_too_late_message(tipo_pasto)],
        }), 409

    uploaded_photo_filenames, photo_errors = save_offer_gallery_files(
        current_user.id,
        foto_files,
    )
    if photo_errors:
        return jsonify({"success": False, "errors": photo_errors}), 400
    filename = uploaded_photo_filenames[0] if uploaded_photo_filenames else 'nessuna.jpg'

    offer = Offer(
        user_id=current_user.id,
        tipo_pasto=tipo_pasto,
        nome_locale=nome_locale,
        indirizzo=indirizzo,
        telefono_locale=telefono_locale,
        latitudine=float(lat),
        longitudine=float(lon),
        posti_totali=int(posti),
        posti_disponibili=int(posti),
        data_ora=data_ora,
        booking_lead_override_minutes=(
            get_short_notice_booking_lead_minutes_for_meal_type(tipo_pasto)
            if requires_short_notice_override
            else None
        ),
        descrizione=descrizione,
        foto_locale=filename
    )

    db.session.add(offer)
    try:
        db.session.flush()
        if uploaded_photo_filenames:
            replace_offer_gallery(offer, uploaded_photo_filenames)
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        delete_upload_files(uploaded_photo_filenames)
        return jsonify({"success": False, "errors": [f"Errore nel salvataggio dell'offerta: {exc}"]}), 500
    notification_stats = notify_followers_for_new_offer(offer)
    notified_users = notification_stats["followers"]
    email_notifications = notification_stats["emails"]
    push_notifications = notification_stats["push_users"]
    nearby_push_notifications = notification_stats["nearby_push_users"]

    message = "Offerta creata con successo!"
    if notified_users == 1 and email_notifications and push_notifications:
        message += " Abbiamo avvisato 1 persona che ti segue via email e push."
    elif notified_users > 1 and email_notifications and push_notifications:
        message += f" Abbiamo avvisato {notified_users} persone che ti seguono via email e push."
    elif notified_users == 1 and push_notifications:
        message += " Abbiamo avvisato 1 persona che ti segue con una notifica push."
    elif notified_users > 1 and push_notifications:
        message += f" Abbiamo avvisato {notified_users} persone che ti seguono con una notifica push."
    elif notified_users == 1 and email_notifications:
        message += " Abbiamo avvisato 1 persona che ti segue via email."
    elif notified_users > 1:
        message += f" Abbiamo avvisato {notified_users} persone che ti seguono via email."
    elif get_followers_notification_targets(offer):
        message += " L'offerta e' pronta, ma le notifiche ai follower non sono attive su questo ambiente."
    if nearby_push_notifications == 1:
        message += " In piu', 1 persona vicina ha ricevuto una notifica push."
    elif nearby_push_notifications > 1:
        message += (
            f" In piu', {nearby_push_notifications} persone vicine hanno ricevuto "
            "una notifica push."
        )

    return jsonify({
        "success": True,
        "message": message,
        "offer_id": offer.id,
        "notified_users": notified_users,
        "email_notifications": email_notifications,
        "push_notifications": push_notifications,
        "nearby_push_notifications": nearby_push_notifications,
    })


@app.route("/api/offers/<int:offer_id>/claim", methods=["POST"])
@login_required
def api_claim_offer(offer_id):
    """Approfitta di un'offerta — decrementa posti disponibili."""
    profile_error = require_complete_profile_json()
    if profile_error:
        return profile_error
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error

    offer = db.session.get(Offer, offer_id)

    if not offer:
        return jsonify({"success": False, "errors": ["Offerta non trovata."]}), 404

    # Controlli
    if offer.user_id == current_user.id:
        return jsonify({"success": False, "errors": ["Non puoi approfittare della tua stessa offerta."]}), 400

    # Controlla se ha già una richiesta o una partecipazione.
    existing = Claim.query.filter_by(user_id=current_user.id, offer_id=offer_id).first()
    if existing:
        if existing.status == CLAIM_STATUS_PENDING:
            return jsonify({"success": False, "errors": ["Hai già inviato una richiesta per questa offerta."]}), 400
        if existing.status == CLAIM_STATUS_REJECTED:
            return jsonify({
                "success": False,
                "errors": [
                    "Questa richiesta non è stata accettata. Non puoi approfittare di nuovo lo stesso evento.",
                ],
            }), 400
        return jsonify({"success": False, "errors": ["Hai già approfittato di questa offerta."]}), 400

    now = local_now()

    if offer.stato != "attiva" or offer.posti_disponibili <= 0:
        return jsonify({"success": False, "errors": ["Offerta non più disponibile."]}), 400

    if offer.data_ora <= now:
        return jsonify({"success": False, "errors": ["Il pasto è già iniziato o concluso."]}), 400

    if is_offer_booking_closed(offer, now):
        return jsonify({"success": False, "errors": [get_offer_booking_closed_message(offer)]}), 400

    scheduling_conflict = get_user_meal_schedule_conflict(
        current_user.id,
        offer.tipo_pasto,
        offer.data_ora,
        exclude_claim_offer_id=offer.id,
    )
    if scheduling_conflict:
        return jsonify({
            "success": False,
            "errors": [build_meal_schedule_conflict_message(offer.tipo_pasto, scheduling_conflict)],
        }), 400
    # Crea una richiesta pendente senza occupare ancora il posto.
    claim = Claim(
        user_id=current_user.id,
        offer_id=offer_id,
        status=CLAIM_STATUS_PENDING,
    )

    db.session.add(claim)
    db.session.commit()

    send_claim_request_notification_to_host(claim)

    return jsonify({
        "success": True,
        "message": "Richiesta inviata! Attendi la conferma dell'organizzatore.",
        "claim_status": "pending",
        "posti_disponibili": offer.posti_disponibili,
    })


@app.route("/api/claims/<int:claim_id>/accept", methods=["POST"])
@login_required
def api_accept_claim_request(claim_id):
    """Accetta una richiesta pendente su una propria offerta."""
    claim = db.session.get(Claim, claim_id)
    if not claim:
        return jsonify({"success": False, "error": "Richiesta non trovata."}), 404

    offer = claim.offerta
    if not offer or offer.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    if claim.status != CLAIM_STATUS_PENDING:
        return jsonify({"success": False, "error": "Questa richiesta non è più pendente."}), 400

    now = local_now()
    if offer.stato != "attiva" or offer.posti_disponibili <= 0:
        return jsonify({"success": False, "error": "Offerta non più disponibile."}), 400
    if offer.data_ora <= now:
        return jsonify({"success": False, "error": "Il pasto è già iniziato o concluso."}), 400
    if is_offer_booking_closed(offer, now):
        return jsonify({"success": False, "error": get_offer_booking_closed_message(offer)}), 400

    scheduling_conflict = get_user_meal_schedule_conflict(
        claim.user_id,
        offer.tipo_pasto,
        offer.data_ora,
        exclude_claim_offer_id=offer.id,
    )
    if scheduling_conflict:
        return jsonify({
            "success": False,
            "error": build_meal_schedule_conflict_message(offer.tipo_pasto, scheduling_conflict),
        }), 400

    claim.status = CLAIM_STATUS_ACCEPTED
    offer.posti_disponibili -= 1
    if offer.posti_disponibili <= 0:
        offer.posti_disponibili = 0
        offer.stato = "completata"

    db.session.commit()
    send_claim_accepted_email(claim)

    return jsonify({"success": True, "message": "Richiesta accettata."})


@app.route("/api/claims/<int:claim_id>/reject", methods=["POST"])
@login_required
def api_reject_claim_request(claim_id):
    """Rifiuta una richiesta pendente su una propria offerta."""
    claim = db.session.get(Claim, claim_id)
    if not claim:
        return jsonify({"success": False, "error": "Richiesta non trovata."}), 404

    offer = claim.offerta
    if not offer or offer.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    if claim.status != CLAIM_STATUS_PENDING:
        return jsonify({"success": False, "error": "Questa richiesta non è più pendente."}), 400

    send_claim_rejected_email(claim)
    claim.status = CLAIM_STATUS_REJECTED
    db.session.commit()

    return jsonify({"success": True, "message": "Richiesta rifiutata."})


@app.route("/api/claims/<int:claim_id>/hide-rejected", methods=["POST"])
@login_required
def api_hide_rejected_claim(claim_id):
    """Permette al guest di nascondere dal feed un evento rifiutato."""
    claim = Claim.query.get_or_404(claim_id)

    if claim.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    if claim.status != CLAIM_STATUS_REJECTED:
        return jsonify({
            "success": False,
            "error": "Puoi nascondere solo eventi con richiesta non accettata.",
        }), 400

    claim.hidden_by_guest = True
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "Evento rimosso dal tuo feed.",
    })


@app.route("/api/claims/<int:claim_id>", methods=["DELETE"])
@login_required
def api_unclaim(claim_id):
    """Annulla la partecipazione a un'offerta e notifica l'organizzatore via email."""
    claim = db.session.get(Claim, claim_id)
    if not claim:
        return jsonify({"success": False, "error": "Partecipazione non trovata."}), 404
    if claim.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403

    offer = claim.offerta
    if claim.status == CLAIM_STATUS_PENDING:
        db.session.delete(claim)
        db.session.commit()
        return jsonify({"success": True, "message": "Richiesta annullata con successo."})

    data_formattata = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')

    # Ripristina il posto e lo stato dell'offerta
    offer.posti_disponibili = min(offer.posti_totali, offer.posti_disponibili + 1)
    if offer.stato == 'completata':
        offer.stato = 'attiva'

    db.session.delete(claim)
    db.session.commit()

    # Email all'autore dell'offerta
    send_email(
        f"⚠️ Disdetta partecipazione a '{offer.nome_locale}'",
        [offer.autore.email],
        "unclaim_notification.html",
        user=current_user,
        offer=offer,
        data_evento=data_formattata
    )
    send_push_to_user(
        offer.autore,
        title="Partecipazione annullata",
        body=f"{current_user.nome} non partecipera' piu' a {offer.nome_locale}.",
        target="profile",
        extra_data={
            "offer_id": offer.id,
            "claim_id": claim.id,
            "guest_name": current_user.nome,
            "unclaim": "true",
        },
    )

    # Email di conferma al partecipante che ha disdetto
    send_email(
        f"✅ Partecipazione annullata: '{offer.nome_locale}'",
        [current_user.email],
        "unclaim_confirmation.html",
        user=current_user,
        offer=offer,
        data_evento=data_formattata
    )
    send_push_to_user(
        current_user,
        title="Partecipazione annullata",
        body=f"Hai annullato la partecipazione a {offer.nome_locale}.",
        target="offers",
        extra_data={
            "offer_id": offer.id,
            "claim_id": claim.id,
            "unclaim": "true",
        },
    )

    return jsonify({"success": True, "message": "Partecipazione annullata con successo."})


# ===================================================================
# MATEMATICA E GEOLOCALIZZAZIONE
# ===================================================================

def calculate_distance(lat1, lon1, lat2, lon2):
    """Calcola la distanza in km tra due coordinate GPS usando la formula di Haversine."""
    R = 6371.0 # Raggio della Terra in km
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad

    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def utc_now_naive():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def parse_coordinate(raw_value, *, kind):
    raw = str(raw_value or "").strip()
    if not raw:
        raise ValueError(f"{kind}_missing")
    value = float(raw.replace(",", "."))
    if kind == "lat" and (value < -90 or value > 90):
        raise ValueError("lat_out_of_range")
    if kind == "lon" and (value < -180 or value > 180):
        raise ValueError("lon_out_of_range")
    return value


def is_live_location_fresh(user, *, now_utc=None):
    now_utc = now_utc or utc_now_naive()
    if (
        user.live_latitudine is None
        or user.live_longitudine is None
        or user.live_location_at is None
    ):
        return False
    return user.live_location_at >= (
        now_utc - timedelta(minutes=COMMUNITY_LIVE_LOCATION_TTL_MINUTES)
    )


def resolve_user_distance_coordinates(user, *, now_utc=None):
    """Restituisce coordinate da usare nei filtri community: GPS live/ultimo -> fallback profilo."""
    now_utc = now_utc or utc_now_naive()
    if user.live_latitudine is not None and user.live_longitudine is not None:
        source = "live" if is_live_location_fresh(user, now_utc=now_utc) else "last_live"
        return float(user.live_latitudine), float(user.live_longitudine), source
    if user.latitudine is not None and user.longitudine is not None:
        return float(user.latitudine), float(user.longitudine), "profile"
    return None, None, "none"

# ===================================================================
# API — Utente
# ===================================================================


@app.route("/api/user/me", methods=["GET"])
@login_required
def api_user_me():
    """Restituisce i dati dell'utente corrente."""
    followed_user_ids = get_followed_user_ids(current_user.id)
    pending_claims = (
        Claim.query.join(Offer, Claim.offer_id == Offer.id)
        .options(
            selectinload(Claim.utente).selectinload(User.photos),
            selectinload(Claim.offerta),
        )
        .filter(
            Offer.user_id == current_user.id,
            Claim.status == CLAIM_STATUS_PENDING,
        )
        .order_by(Claim.created_at.desc())
        .all()
    )
    followers = [
        relation.follower
        for relation in sorted(
            current_user.followers_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.follower
        and not is_admin_user(relation.follower)
        and is_public_user_visible_to_viewer(relation.follower, current_user)
    ]
    following = [
        relation.followed
        for relation in sorted(
            current_user.following_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.followed
        and not is_admin_user(relation.followed)
        and is_public_user_visible_to_viewer(relation.followed, current_user)
    ]
    met_users = [
        user for user in get_met_users_for_user(current_user)
        if is_public_user_visible_to_viewer(user, current_user)
    ]
    reviews_received = (
        Review.query.options(
            selectinload(Review.reviewer).selectinload(User.photos),
            selectinload(Review.reviewed).selectinload(User.photos),
            selectinload(Review.offerta),
        )
        .filter(Review.reviewed_id == current_user.id)
        .order_by(Review.created_at.desc())
        .all()
    )
    reviews_given = (
        Review.query.options(
            selectinload(Review.reviewer).selectinload(User.photos),
            selectinload(Review.reviewed).selectinload(User.photos),
            selectinload(Review.offerta),
        )
        .filter(Review.reviewer_id == current_user.id)
        .order_by(Review.created_at.desc())
        .all()
    )
    user_payload = serialize_user_preview(
        current_user,
        viewer=current_user,
        followed_user_ids=followed_user_ids,
        include_gallery=True,
        include_private=True,
    )
    user_payload["followers"] = [
        serialize_user_preview(follower, viewer=current_user, followed_user_ids=followed_user_ids)
        for follower in followers
    ]
    user_payload["following"] = [
        serialize_user_preview(followed, viewer=current_user, followed_user_ids=followed_user_ids)
        for followed in following
    ]
    user_payload["met_users"] = [
        serialize_user_preview(
            met_user,
            viewer=current_user,
            followed_user_ids=followed_user_ids,
        )
        for met_user in met_users
    ]
    user_payload["pending_claim_requests"] = [
        payload
        for payload in (
            serialize_pending_claim_request(
                claim,
                viewer=current_user,
                followed_user_ids=followed_user_ids,
            )
            for claim in pending_claims
        )
        if payload
    ]
    user_payload["pending_review_reminders"] = [
        payload
        for payload in (
            serialize_pending_review_reminder(
                reminder,
                viewer=current_user,
                followed_user_ids=followed_user_ids,
            )
            for reminder in get_pending_review_reminders(current_user)
        )
        if payload
    ]
    user_payload["reviews_received"] = [
        serialize_review_preview(review, viewer=current_user)
        for review in reviews_received
    ]
    user_payload["reviews_given"] = [
        serialize_review_preview(review, viewer=current_user)
        for review in reviews_given
    ]
    user_payload["stats"] = {
        "offerte_totali": Offer.query.filter_by(user_id=current_user.id).count(),
        "offerte_attive_da_gestire": Offer.query.filter(
            Offer.user_id == current_user.id,
            Offer.stato.in_(["attiva", "completata"]),
            Offer.data_ora > local_now() - timedelta(hours=3),
        ).count(),
        "recuperi_effettuati": Claim.query.filter_by(
            user_id=current_user.id,
            status=CLAIM_STATUS_ACCEPTED,
        ).count(),
    }
    user_payload["legal"] = build_legal_status_payload(current_user)

    return jsonify({
        "success": True,
        "user": user_payload,
    })


@app.route("/api/legal/status", methods=["GET"])
@login_required
def api_legal_status():
    """Restituisce lo stato di accettazione documenti legali per l'app."""
    return jsonify({
        "success": True,
        "legal": build_legal_status_payload(current_user),
    })


@app.route("/api/legal/accept", methods=["POST"])
@login_required
def api_legal_accept():
    """Salva accettazione di Termini, Regolamento Community e Privacy."""
    data = request.get_json(silent=True) or {}
    accepted_terms = bool(data.get("accepted_terms"))
    accepted_privacy = bool(data.get("accepted_privacy"))
    accepted_rules = bool(data.get("accepted_community_rules"))

    if not (accepted_terms and accepted_privacy and accepted_rules):
        return jsonify({
            "success": False,
            "error": "Devi confermare Termini, Privacy e Regolamento Community.",
        }), 400

    accept_current_legal_for_user(current_user)
    db.session.commit()
    return jsonify({
        "success": True,
        "message": "Accettazione salvata. Puoi continuare a usare ApprofittOffro.",
        "legal": build_legal_status_payload(current_user),
    })


def notify_admin_for_bug_report(report):
    """Invia all'admin la segnalazione bug appena creata."""
    admin_email = (
        os.getenv("BUG_REPORT_EMAIL")
        or os.getenv("ADMIN_EMAIL")
        or app.config.get("MAIL_USERNAME")
        or ""
    ).strip()
    if not admin_email:
        print(f"[BUG_REPORT_EMAIL_SKIP] report_id={report.id} nessuna email admin configurata")
        return False

    user = report.user
    safe_name = escape(user.nome if user else "Utente rimosso")
    safe_email = escape(user.email if user else "")
    safe_message = escape(report.message or "").replace("\n", "<br>")
    safe_context = escape(report.screen_context or "App")
    screenshot_link = ""
    if report.screenshot_filename:
        screenshot_url = url_for(
            "uploaded_file",
            filename=report.screenshot_filename,
            _external=True,
        )
        screenshot_link = (
            f'<p><b>Screenshot allegato:</b> '
            f'<a href="{escape(screenshot_url)}">Apri screenshot</a></p>'
        )
    html = f"""
    <h2>Nuova segnalazione bug ApprofittOffro</h2>
    <p><b>ID segnalazione:</b> {report.id}</p>
    <p><b>Utente:</b> {safe_name}</p>
    <p><b>Email:</b> {safe_email}</p>
    <p><b>Contesto:</b> {safe_context}</p>
    <p><b>Messaggio:</b></p>
    <blockquote>{safe_message}</blockquote>
    {screenshot_link}
    <p>La segnalazione e' in attesa di validazione admin prima di assegnare ApprofittOffro Points.</p>
    """
    return send_email_html(
        "Nuova segnalazione bug ApprofittOffro",
        [admin_email],
        html,
        background=True,
    )


def save_bug_report_screenshot(file_storage, report_id):
    """Salva lo screenshot allegato a una segnalazione bug nello storage upload."""
    if not file_storage or not getattr(file_storage, "filename", ""):
        return "", ""

    original_name = secure_filename(file_storage.filename or "screenshot.jpg")
    mimetype = (getattr(file_storage, "mimetype", "") or "").lower()
    extension = os.path.splitext(original_name)[1].lower() or ".jpg"
    image_extensions = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
    generic_mimetypes = {"application/octet-stream", "binary/octet-stream"}
    if (
        mimetype
        and not mimetype.startswith("image/")
        and mimetype not in generic_mimetypes
        and extension not in image_extensions
    ):
        raise ValueError("Allega un file immagine valido.")

    if extension not in image_extensions:
        extension = ".jpg"

    target_name = f"bug_reports/report_{report_id}_{uuid.uuid4().hex}{extension}"
    saved_name = process_image(
        file_storage,
        target_name,
        size=(1400, 1400),
        quality=82,
    )
    return saved_name, original_name


def serialize_app_notification(notification):
    try:
        extra_data = json.loads(notification.extra_data_json or "{}")
    except Exception:
        extra_data = {}
    return {
        "id": notification.id,
        "title": notification.title or "ApprofittOffro",
        "body": notification.body or "",
        "target": notification.target or "notifications",
        "extra_data": extra_data,
        "read_at": notification.read_at.isoformat() if notification.read_at else "",
        "created_at": notification.created_at.isoformat() if notification.created_at else "",
        "expires_at": notification.expires_at.isoformat() if notification.expires_at else "",
        "is_read": notification.read_at is not None,
    }


@app.route("/api/notifications", methods=["GET"])
@login_required
def api_list_app_notifications():
    """Centro notifiche: restituisce solo avvisi non scaduti nelle ultime 24 ore."""
    purge_expired_app_notifications(current_user.id)
    now = datetime.now()
    notifications = (
        AppNotification.query
        .filter(
            AppNotification.user_id == current_user.id,
            AppNotification.expires_at > now,
        )
        .order_by(AppNotification.created_at.desc(), AppNotification.id.desc())
        .limit(100)
        .all()
    )
    unread_count = sum(1 for item in notifications if item.read_at is None)
    return jsonify({
        "success": True,
        "notifications": [serialize_app_notification(item) for item in notifications],
        "unread_count": unread_count,
    })


@app.route("/api/notifications/<int:notification_id>/read", methods=["POST"])
@login_required
def api_mark_app_notification_read(notification_id):
    notification = AppNotification.query.filter_by(
        id=notification_id,
        user_id=current_user.id,
    ).first()
    if not notification:
        return jsonify({"success": False, "error": "Notifica non trovata."}), 404
    if notification.expires_at <= datetime.now():
        db.session.delete(notification)
        db.session.commit()
        return jsonify({"success": False, "error": "Notifica scaduta."}), 404
    if notification.read_at is None:
        notification.read_at = datetime.now()
        db.session.commit()
    return jsonify({
        "success": True,
        "notification": serialize_app_notification(notification),
    })


@app.route("/api/notifications/read-all", methods=["POST"])
@login_required
def api_mark_all_app_notifications_read():
    purge_expired_app_notifications(current_user.id)
    now = datetime.now()
    notifications = AppNotification.query.filter(
        AppNotification.user_id == current_user.id,
        AppNotification.expires_at > now,
        AppNotification.read_at.is_(None),
    ).all()
    for notification in notifications:
        notification.read_at = now
    if notifications:
        db.session.commit()
    return jsonify({"success": True, "updated": len(notifications)})


@app.route("/api/notifications/<int:notification_id>", methods=["DELETE"])
@login_required
def api_delete_app_notification(notification_id):
    notification = AppNotification.query.filter_by(
        id=notification_id,
        user_id=current_user.id,
    ).first()
    if notification:
        db.session.delete(notification)
        db.session.commit()
    return jsonify({"success": True, "message": "Notifica chiusa."})


def notify_user_for_bug_report_review(report):
    """Avvisa l'utente quando l'admin valida o respinge una segnalazione bug."""
    user = report.user
    if not user:
        return {"email_sent": False, "push_sent": 0}

    note = (report.admin_note or "").strip()
    safe_name = escape(user.nome or "Utente")
    safe_message = escape(report.message or "").replace("\n", "<br>")
    safe_note = escape(note).replace("\n", "<br>")
    points = int(report.awarded_points or 0)
    approved = report.status == BUG_REPORT_STATUS_APPROVED

    if approved:
        title = "Bug approvato"
        push_body = (
            f"L'amministratore ha approvato la tua segnalazione: "
            f"hai ricevuto {points} ApprofittOffro Points."
        )
        subject = "Segnalazione bug approvata su ApprofittOffro"
        intro = (
            f"la tua segnalazione bug e' stata approvata. "
            f"Hai ricevuto <b>{points} ApprofittOffro Points</b>."
        )
    else:
        title = "Segnalazione bug verificata"
        push_body = "L'amministratore ha verificato la tua segnalazione bug: nessun punto assegnato."
        subject = "Segnalazione bug verificata su ApprofittOffro"
        intro = (
            "la tua segnalazione bug e' stata verificata, ma non sono stati "
            "assegnati ApprofittOffro Points."
        )

    if note:
        push_body = f"{push_body} Nota: {note[:90]}"

    push_sent = send_push_to_user(
        user,
        title=title,
        body=push_body[:180],
        target="notifications",
        extra_data={
            "type": "bug_report_review",
            "bug_report_id": report.id,
            "bug_report_status": report.status,
            "awarded_points": points,
        },
    )

    email_sent = False
    if not push_sent and user.email:
        email_sent = send_email_html(
            subject,
            [user.email],
            f"""
            <h2>{escape(title)}</h2>
            <p>Ciao {safe_name}, {intro}</p>
            <p><b>La tua segnalazione:</b></p>
            <blockquote>{safe_message}</blockquote>
            {f"<p><b>Nota dell'amministratore:</b></p><blockquote>{safe_note}</blockquote>" if note else ""}
            <p>Puoi vedere il totale degli ApprofittOffro Points nel tuo profilo.</p>
            """,
            background=True,
        )

    return {"email_sent": email_sent, "push_sent": push_sent}


@app.route("/api/bug-reports", methods=["POST"])
@login_required
def api_submit_bug_report():
    """Riceve una segnalazione bug dall'app e la mette in attesa di validazione."""
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error
    if is_admin_user(current_user):
        return jsonify({
            "success": False,
            "error": "Usa un account utente standard per inviare segnalazioni bug.",
        }), 403

    if request.content_type and request.content_type.startswith("multipart/"):
        data = request.form
        screenshot_file = request.files.get("screenshot")
    else:
        data = request.get_json(silent=True) or {}
        screenshot_file = None

    message = str(data.get("message", "")).strip()
    screen_context = str(data.get("screen_context", "")).strip()[:120]

    if len(message) < 5:
        return jsonify({
            "success": False,
            "error": "Scrivi almeno qualche parola per descrivere il bug.",
        }), 400
    if len(message) > 2000:
        return jsonify({
            "success": False,
            "error": "La segnalazione deve restare entro 2000 caratteri.",
        }), 400

    report = BugReport(
        user_id=current_user.id,
        message=message,
        screen_context=screen_context or "App",
        status=BUG_REPORT_STATUS_PENDING,
        created_at=datetime.now(),
    )
    db.session.add(report)
    db.session.flush()

    if screenshot_file and getattr(screenshot_file, "filename", ""):
        if request.content_length and request.content_length > 12 * 1024 * 1024:
            db.session.rollback()
            return jsonify({
                "success": False,
                "error": "Lo screenshot e' troppo pesante. Usa un'immagine sotto i 12 MB.",
            }), 400
        try:
            screenshot_filename, screenshot_original_name = save_bug_report_screenshot(
                screenshot_file,
                report.id,
            )
        except ValueError as exc:
            db.session.rollback()
            return jsonify({"success": False, "error": str(exc)}), 400
        report.screenshot_filename = screenshot_filename
        report.screenshot_original_name = screenshot_original_name

    db.session.commit()

    notify_admin_for_bug_report(report)

    return jsonify({
        "success": True,
        "message": (
            "Segnalazione inviata. Se l'admin la conferma, riceverai "
            "ApprofittOffro Points."
        ),
        "report": serialize_bug_report(report),
    })


@app.route("/api/user/live-location", methods=["POST"])
@login_required
def api_user_live_location():
    """Aggiorna la posizione live utente usata nei filtri Community in tempo reale."""
    data = request.get_json(silent=True) or {}
    try:
        lat = parse_coordinate(data.get("latitudine"), kind="lat")
        lon = parse_coordinate(data.get("longitudine"), kind="lon")
    except Exception:
        return jsonify({"success": False, "error": "Coordinate live non valide."}), 400

    now_utc = utc_now_naive()
    current_user.live_latitudine = lat
    current_user.live_longitudine = lon
    current_user.live_location_at = now_utc
    db.session.commit()

    return jsonify(
        {
            "success": True,
            "live_latitudine": lat,
            "live_longitudine": lon,
            "live_location_at": datetime_to_iso_z(now_utc),
        }
    )


@app.route("/api/push/token", methods=["POST"])
@login_required
def api_register_push_token():
    """Registra o riattiva il token push del dispositivo corrente."""
    data = request.get_json(silent=True) or {}
    token = str(data.get("token", "")).strip()
    platform = str(data.get("platform", PUSH_PLATFORM_ANDROID)).strip().lower() or PUSH_PLATFORM_ANDROID
    device_label = str(data.get("device_label", "")).strip()[:160]

    if len(token) < 20:
        return jsonify({"success": False, "error": "Token push non valido."}), 400

    token_record = DevicePushToken.query.filter_by(token=token).first()
    if token_record is None:
        token_record = DevicePushToken(
            user_id=current_user.id,
            token=token,
            platform=platform,
            device_label=device_label or None,
            active=True,
            last_seen_at=datetime.now(timezone.utc).replace(tzinfo=None),
        )
        db.session.add(token_record)
    else:
        token_record.user_id = current_user.id
        token_record.platform = platform
        token_record.device_label = device_label or token_record.device_label
        token_record.active = True
        token_record.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)

    db.session.commit()
    return jsonify({
        "success": True,
        "message": "Token push registrato.",
        "push_enabled": push_delivery_enabled(),
    })


@app.route("/api/push/token", methods=["DELETE"])
@login_required
def api_unregister_push_token():
    """Disattiva il token push del dispositivo corrente."""
    data = request.get_json(silent=True) or {}
    token = str(data.get("token", "")).strip()
    if len(token) < 20:
        return jsonify({"success": False, "error": "Token push non valido."}), 400

    token_record = DevicePushToken.query.filter_by(
        token=token,
        user_id=current_user.id,
    ).first()
    if token_record:
        token_record.active = False
        token_record.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)
        db.session.commit()

    return jsonify({"success": True, "message": "Token push disattivato."})


def get_chat_block_status(user_id, other_user_id):
    """Restituisce lo stato blocco fra due utenti."""
    blocked_by_me = (
        UserBlock.query.filter_by(
            blocker_id=user_id,
            blocked_id=other_user_id,
        ).first()
        is not None
    )
    blocked_by_other = (
        UserBlock.query.filter_by(
            blocker_id=other_user_id,
            blocked_id=user_id,
        ).first()
        is not None
    )
    return blocked_by_me, blocked_by_other


def ensure_chat_pair_allowed(offer_id, actor_user_id, other_user_id):
    """Verifica che i due utenti possano usare la chat per quell'evento."""
    actor_user = User.query.get(actor_user_id)
    other_user = User.query.get(other_user_id)
    if is_user_moderation_restricted(actor_user):
        return None, (get_user_moderation_block_message(actor_user), 403)
    if is_user_moderation_restricted(other_user):
        return None, ("Utente non disponibile.", 403)

    offer = Offer.query.options(selectinload(Offer.claims)).get(offer_id)
    if not offer:
        return None, ("Evento non trovato.", 404)

    accepted_participants = {
        claim.user_id
        for claim in offer.claims
        if claim.status == CLAIM_STATUS_ACCEPTED
    }

    actor_is_host = offer.user_id == actor_user_id
    actor_is_accepted_guest = actor_user_id in accepted_participants

    if actor_is_host:
        if other_user_id not in accepted_participants:
            return None, ("Destinatario non autorizzato.", 403)
    elif actor_is_accepted_guest:
        if other_user_id != offer.user_id:
            return None, ("Destinatario non autorizzato.", 403)
    else:
        return None, ("Chat non disponibile per questo evento.", 403)

    return offer, None


def chat_now_utc():
    """Timestamp chat coerente in UTC (naive per compatibilita' DB esistente)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def normalize_chat_pair_ids(user_a_id, user_b_id):
    first_id, second_id = sorted((int(user_a_id), int(user_b_id)))
    return first_id, second_id


def build_chat_thread_key(offer_id, user_a_id, user_b_id):
    first_id, second_id = normalize_chat_pair_ids(user_a_id, user_b_id)
    return f"{int(offer_id)}_{first_id}_{second_id}"


def datetime_to_iso_z(value):
    if not value:
        return ""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    else:
        value = value.astimezone(timezone.utc)
    return value.isoformat().replace("+00:00", "Z")


def chat_thread_last_activity(thread):
    return thread.last_message_time or thread.updated_at or thread.created_at


def chat_thread_preference_key(thread):
    """Ordina i thread duplicati privilegiando quelli con vera attività."""
    has_real_messages = 1 if thread.last_message_time else 0
    if not has_real_messages and (thread.last_message or "").strip():
        has_real_messages = 1
    activity = chat_thread_last_activity(thread) or datetime.min
    return (has_real_messages, activity, int(thread.id or 0))


def get_or_create_chat_thread(*, offer_id, user_id, other_user_id, create_if_missing=True):
    first_id, second_id = normalize_chat_pair_ids(user_id, other_user_id)
    now = chat_now_utc()
    purged_expired = False
    threads = ChatThread.query.filter_by(
        user_a_id=first_id,
        user_b_id=second_id,
    ).all()
    active_threads = []
    for candidate in threads:
        if purge_chat_thread_if_expired(candidate, now=now):
            purged_expired = True
            continue
        active_threads.append(candidate)
    if purged_expired:
        db.session.flush()

    thread = (
        max(active_threads, key=chat_thread_preference_key)
        if active_threads
        else None
    )

    # Pulizia soft: elimina eventuali thread duplicati vuoti creati per errore.
    duplicate_pruned = False
    if thread is not None and len(active_threads) > 1:
        for candidate in active_threads:
            if candidate.id == thread.id:
                continue
            has_messages = ChatMessage.query.filter_by(thread_id=candidate.id).first() is not None
            if has_messages:
                continue
            if (candidate.last_message or "").strip():
                continue
            db.session.delete(candidate)
            duplicate_pruned = True
    if duplicate_pruned:
        db.session.flush()

    if purged_expired and not create_if_missing:
        db.session.commit()
    if thread or not create_if_missing:
        return thread

    thread = ChatThread(
        offer_id=int(offer_id),
        user_a_id=first_id,
        user_b_id=second_id,
        created_at=now,
        updated_at=now,
        last_message="",
        last_message_type="text",
    )
    db.session.add(thread)
    db.session.flush()
    return thread


def build_chat_preview_text(message_type, *, text="", media_file_name="", audio_duration_sec=0):
    kind = str(message_type or "text").strip().lower()
    if kind == "audio":
        try:
            duration_value = int(audio_duration_sec or 0)
        except (TypeError, ValueError):
            duration_value = 0
        return f"Vocale ({duration_value}s)" if duration_value > 0 else "Messaggio vocale"
    if kind == "image":
        return "Foto inviata"
    if kind == "file":
        clean_name = str(media_file_name or "").strip()
        return f"Allegato: {clean_name}" if clean_name else "Allegato inviato"
    clean_text = str(text or "").strip()
    return clean_text or "Nuovo messaggio"


def serialize_chat_message(message):
    return {
        "id": str(message.id),
        "senderId": str(message.sender_id),
        "senderName": message.sender_name or "Utente",
        "type": (message.message_type or "text").strip().lower(),
        "text": message.text or "",
        "audioPath": message.audio_path or "",
        "audioDurationSec": int(message.audio_duration_sec or 0),
        "mediaPath": message.media_path or "",
        "mediaFileName": message.media_file_name or "",
        "mediaContentType": message.media_content_type or "",
        "mediaSizeBytes": int(message.media_size_bytes or 0),
        "timestamp": datetime_to_iso_z(message.created_at),
    }


def sanitize_chat_audio_path(raw_path):
    """Normalizza e valida un path audio chat relativo all'upload storage."""
    normalized = str(raw_path or "").strip().replace("\\", "/")
    while "//" in normalized:
        normalized = normalized.replace("//", "/")
    if normalized.startswith("/"):
        normalized = normalized[1:]
    parts = [part for part in normalized.split("/") if part]
    if not parts or ".." in parts:
        return ""
    return "/".join(parts)


def build_chat_audio_prefix(offer_id, user_a_id, user_b_id):
    """Prefisso canonico dei vocali chat per coppia utenti + evento."""
    first_id, second_id = sorted((int(user_a_id), int(user_b_id)))
    return f"chat_audio/{int(offer_id)}/{first_id}_{second_id}/"


def build_chat_media_prefix(offer_id, user_a_id, user_b_id):
    """Prefisso canonico degli allegati chat per coppia utenti + evento."""
    first_id, second_id = sorted((int(user_a_id), int(user_b_id)))
    return f"chat_media/{int(offer_id)}/{first_id}_{second_id}/"


def is_chat_thread_expired(thread, *, now=None):
    now = now or chat_now_utc()
    last_activity = chat_thread_last_activity(thread)
    if not last_activity:
        return False
    return last_activity <= (now - timedelta(days=CHAT_RETENTION_DAYS))


def is_chat_thread_admin_deleted(thread):
    return bool(getattr(thread, "admin_deleted_at", None))


def is_admin_deleted_chat_notice(text):
    normalized = (
        str(text or "")
        .strip()
        .lower()
        .replace("è", "e")
        .replace("é", "e")
        .replace("’", "'")
    )
    return (
        "chat" in normalized
        and "eliminata" in normalized
        and "amministrator" in normalized
    )


def extract_admin_delete_reason_from_notice(text):
    raw = str(text or "").strip()
    lower = raw.lower()
    marker = "motivo:"
    marker_index = lower.find(marker)
    if marker_index < 0:
        return ""
    reason_start = marker_index + len(marker)
    reason = raw[reason_start:].strip()
    for end_marker in (" verra", " verrà"):
        end_index = reason.lower().find(end_marker)
        if end_index >= 0:
            reason = reason[:end_index].strip()
            break
    return reason.rstrip(". ").strip()


def hydrate_admin_deleted_chat_from_notice(thread):
    if not thread or is_chat_thread_admin_deleted(thread):
        return False

    notices = (
        ChatMessage.query.filter(
            ChatMessage.thread_id == thread.id,
            ChatMessage.message_type == "system",
        )
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
        .limit(8)
        .all()
    )
    for notice in notices:
        if not is_admin_deleted_chat_notice(notice.text):
            continue
        deleted_at = notice.created_at or chat_now_utc()
        thread.admin_deleted_at = deleted_at
        thread.admin_delete_after = deleted_at + timedelta(hours=1)
        thread.admin_delete_reason = extract_admin_delete_reason_from_notice(notice.text)
        return True
    return False


def is_chat_thread_admin_hidden(thread, *, now=None):
    now = now or chat_now_utc()
    delete_after = getattr(thread, "admin_delete_after", None)
    return bool(delete_after and delete_after <= now)


def build_admin_deleted_chat_payload(thread):
    return {
        "admin_deleted": is_chat_thread_admin_deleted(thread),
        "admin_deleted_at": datetime_to_iso_z(getattr(thread, "admin_deleted_at", None)),
        "admin_delete_after": datetime_to_iso_z(getattr(thread, "admin_delete_after", None)),
        "admin_delete_reason": getattr(thread, "admin_delete_reason", None) or "",
    }


def chat_admin_deleted_error(thread):
    if is_chat_thread_admin_hidden(thread):
        return "Chat eliminata definitivamente dall'amministratore.", 410
    return "Questa chat e' stata eliminata dall'amministratore.", 403


def chat_admin_deleted_response(offer_id, actor_user_id, other_user_id):
    thread = get_or_create_chat_thread(
        offer_id=offer_id,
        user_id=actor_user_id,
        other_user_id=other_user_id,
        create_if_missing=False,
    )
    if not thread or not is_chat_thread_admin_deleted(thread):
        if thread and hydrate_admin_deleted_chat_from_notice(thread):
            db.session.commit()
        else:
            return None
    if not is_chat_thread_admin_deleted(thread):
        return None
    message, status = chat_admin_deleted_error(thread)
    return jsonify({
        "success": False,
        "error": message,
        **build_admin_deleted_chat_payload(thread),
    }), status


def purge_chat_thread_if_expired(thread, *, now=None):
    """Elimina definitivamente thread+messaggi+file se inattivo oltre retention."""
    now = now or chat_now_utc()
    if not is_chat_thread_expired(thread, now=now):
        return False

    delete_chat_thread_payload(thread)
    db.session.delete(thread)
    return True


def delete_chat_thread_payload(thread):
    """Elimina messaggi e allegati di un thread chat, lasciando gestire il thread al chiamante."""
    expected_audio_prefix = build_chat_audio_prefix(
        thread.offer_id,
        thread.user_a_id,
        thread.user_b_id,
    )
    expected_media_prefix = build_chat_media_prefix(
        thread.offer_id,
        thread.user_a_id,
        thread.user_b_id,
    )

    audio_paths_to_delete = set()
    media_paths_to_delete = set()
    messages = ChatMessage.query.filter_by(thread_id=thread.id).all()
    deleted_messages = len(messages)
    for message in messages:
        normalized_audio = sanitize_chat_audio_path(message.audio_path)
        if normalized_audio and normalized_audio.startswith(expected_audio_prefix):
            audio_paths_to_delete.add(normalized_audio)
        normalized_media = sanitize_chat_audio_path(message.media_path)
        if normalized_media and normalized_media.startswith(expected_media_prefix):
            media_paths_to_delete.add(normalized_media)
        db.session.delete(message)

    deleted_audio_files = 0
    for audio_path in audio_paths_to_delete:
        upload_storage.delete(audio_path)
        deleted_audio_files += 1
    deleted_media_files = 0
    for media_path in media_paths_to_delete:
        upload_storage.delete(media_path)
        deleted_media_files += 1

    return {
        "deleted_messages": deleted_messages,
        "deleted_audio_files": deleted_audio_files,
        "deleted_media_files": deleted_media_files,
    }


@app.route("/api/push/chat-notification", methods=["POST"])
def api_chat_notification():
    """Endpoint chiamato dalla Cloud Function Firebase per inviare notifiche chat."""
    # Sicurezza: verifica API Key
    auth_header = request.headers.get("Authorization", "")
    expected_key = os.getenv("CHAT_NOTIFICATION_API_KEY", "")
    if not expected_key or auth_header != f"Bearer {expected_key}":
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    receiver_id = data.get("receiver_id")
    sender_id = data.get("sender_id")
    sender_name = data.get("sender_name", "Utente")
    message_text = str(data.get("message_text", "")).strip()
    message_type = str(data.get("message_type", "text")).strip().lower()
    audio_duration_sec = data.get("audio_duration_sec")
    offer_id = data.get("offer_id")

    if not receiver_id:
        return jsonify({"error": "Missing data"}), 400

    if not message_text:
        if message_type == "audio":
            try:
                duration_value = int(audio_duration_sec)
            except (TypeError, ValueError):
                duration_value = 0
            message_text = (
                f"Vocale ({duration_value}s)"
                if duration_value > 0
                else "Messaggio vocale"
            )
        else:
            return jsonify({"error": "Missing data"}), 400

    try:
        receiver_id = int(receiver_id)
        sender_id = int(sender_id) if sender_id else None
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid user id"}), 400

    user = User.query.get(receiver_id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    sender = User.query.get(sender_id) if sender_id else None
    if sender:
        sender_name = sender.nome
    sender_photo_filename = sender.foto_filename if sender and sender.foto_filename else ""

    # Invia notifica push
    send_push_to_user(
        user,
        title=f"Nuovo messaggio da {sender_name}",
        body=message_text,
        target="chat",
        extra_data={
            "offer_id": offer_id,
            "chat_with_user_id": sender_id or "",
            "chat_with_name": sender_name,
            "chat_with_photo_filename": sender_photo_filename,
            "type": "chat_message"
        },
    )

    return jsonify({"success": True})


@app.route("/api/chat/message-notification", methods=["POST"])
@login_required
def api_chat_message_notification():
    """Invia una push chat lato backend senza dipendere da Cloud Functions."""
    data = request.get_json(silent=True) or {}
    offer_id = data.get("offer_id")
    receiver_id = data.get("receiver_id")
    message_text = str(data.get("message_text", "")).strip()

    if offer_id in (None, "") or receiver_id in (None, "") or not message_text:
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(offer_id)
        receiver_id = int(receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Destinatario non valido."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status
    admin_deleted_response = chat_admin_deleted_response(
        offer_id,
        current_user.id,
        receiver_id,
    )
    if admin_deleted_response:
        return admin_deleted_response

    blocked_by_me, blocked_by_other = get_chat_block_status(
        current_user.id,
        receiver_id,
    )
    if blocked_by_me:
        return jsonify({"success": False, "error": "Hai bloccato questo utente."}), 403
    if blocked_by_other:
        return jsonify({"success": False, "error": "Questo utente ha bloccato la chat."}), 403

    receiver = User.query.get(receiver_id)
    if not receiver:
        return jsonify({"success": False, "error": "Utente destinatario non trovato."}), 404

    send_push_to_user(
        receiver,
        title=f"Nuovo messaggio da {current_user.nome}",
        body=message_text,
        target="chat",
        extra_data={
            "offer_id": offer_id,
            "chat_with_user_id": current_user.id,
            "chat_with_name": current_user.nome,
            "chat_with_photo_filename": current_user.foto_filename or "",
            "type": "chat_message",
        },
    )

    return jsonify({"success": True})


@app.route("/api/chat/clear-notification", methods=["POST"])
@login_required
def api_chat_clear_notification():
    """Notifica l'altro partecipante quando lo storico chat viene azzerato."""
    data = request.get_json(silent=True) or {}
    offer_id = data.get("offer_id")
    receiver_id = data.get("receiver_id")

    if offer_id in (None, "") or receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(offer_id)
        receiver_id = int(receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Destinatario non valido."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status
    admin_deleted_response = chat_admin_deleted_response(
        offer_id,
        current_user.id,
        receiver_id,
    )
    if admin_deleted_response:
        return admin_deleted_response

    receiver = User.query.get(receiver_id)
    if not receiver:
        return jsonify({"success": False, "error": "Utente destinatario non trovato."}), 404

    send_push_to_user(
        receiver,
        title=f"{current_user.nome} ha azzerato la chat",
        body="Cronologia rimossa per entrambi. Potete continuare a scrivervi.",
        target="chat",
        extra_data={
            "offer_id": offer_id,
            "chat_with_user_id": current_user.id,
            "chat_with_name": current_user.nome,
            "chat_with_photo_filename": current_user.foto_filename or "",
            "type": "chat_cleared",
        },
    )
    return jsonify({"success": True})


@app.route("/api/chat/audio-upload", methods=["POST"])
@login_required
def api_chat_audio_upload():
    """Upload di un messaggio vocale chat su storage backend (Hetzner/R2/local)."""
    raw_offer_id = request.form.get("offer_id")
    raw_receiver_id = request.form.get("receiver_id")
    audio_file = request.files.get("audio")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    if not audio_file or not audio_file.filename:
        return jsonify({"success": False, "error": "File audio mancante."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status
    admin_deleted_response = chat_admin_deleted_response(
        offer_id,
        current_user.id,
        receiver_id,
    )
    if admin_deleted_response:
        return admin_deleted_response

    blocked_by_me, blocked_by_other = get_chat_block_status(current_user.id, receiver_id)
    if blocked_by_me:
        return jsonify({"success": False, "error": "Hai bloccato questo utente."}), 403
    if blocked_by_other:
        return jsonify({"success": False, "error": "Questo utente ha bloccato la chat."}), 403

    original_name = secure_filename(audio_file.filename or "")
    extension = original_name.rsplit(".", 1)[1].lower() if "." in original_name else ""
    if not extension:
        mime_type = (audio_file.mimetype or "").lower()
        if "ogg" in mime_type or "opus" in mime_type:
            extension = "ogg"
        elif "wav" in mime_type:
            extension = "wav"
        elif "mp3" in mime_type or "mpeg" in mime_type:
            extension = "mp3"
        elif "aac" in mime_type:
            extension = "aac"
        else:
            extension = "m4a"

    if extension not in CHAT_AUDIO_ALLOWED_EXTENSIONS:
        return jsonify({
            "success": False,
            "error": "Formato audio non supportato.",
        }), 400

    file_bytes = audio_file.read()
    if not file_bytes:
        return jsonify({"success": False, "error": "Audio vuoto non valido."}), 400
    if len(file_bytes) > CHAT_AUDIO_MAX_BYTES:
        max_mb = CHAT_AUDIO_MAX_BYTES / (1024 * 1024)
        return jsonify({
            "success": False,
            "error": f"Audio troppo pesante (max {max_mb:.0f} MB).",
        }), 400

    content_type = (audio_file.mimetype or "").strip().lower()
    if content_type and not (
        content_type.startswith("audio/")
        or content_type == "application/octet-stream"
    ):
        return jsonify({"success": False, "error": "Tipo file audio non valido."}), 400

    prefix = build_chat_audio_prefix(offer_id, current_user.id, receiver_id)
    filename = f"{prefix}{uuid.uuid4().hex[:24]}.{extension}"
    upload_storage.save_bytes(
        filename,
        file_bytes,
        content_type or "audio/mp4",
    )

    return jsonify({
        "success": True,
        "audio_path": filename,
        "bytes": len(file_bytes),
        "content_type": content_type or "audio/mp4",
    })


@app.route("/api/chat/audio", methods=["GET", "HEAD"])
@login_required
def api_chat_audio():
    """Restituisce un vocale chat solo ai due utenti autorizzati per quell'evento."""
    raw_offer_id = request.args.get("offer_id")
    raw_other_user_id = request.args.get("other_user_id")
    raw_audio_path = request.args.get("audio_path", "")

    if raw_offer_id in (None, "") or raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or other_user_id <= 0 or other_user_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, other_user_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    audio_path = sanitize_chat_audio_path(raw_audio_path)
    if not audio_path:
        return jsonify({"success": False, "error": "Audio non valido."}), 400

    expected_prefix = build_chat_audio_prefix(offer_id, current_user.id, other_user_id)
    if not audio_path.startswith(expected_prefix):
        return jsonify({"success": False, "error": "Audio non autorizzato."}), 403

    try:
        file_bytes, content_type = upload_storage.read(audio_path)
    except StorageObjectNotFound:
        return jsonify({"success": False, "error": "Audio non trovato."}), 404

    total_size = len(file_bytes)
    range_header = request.headers.get("Range", "").strip()
    start = 0
    end = total_size - 1
    partial = False

    if range_header.startswith("bytes="):
        range_value = range_header[len("bytes="):].strip()
        if "," in range_value:
            range_value = range_value.split(",", 1)[0].strip()

        if "-" in range_value:
            raw_start, raw_end = range_value.split("-", 1)
            raw_start = raw_start.strip()
            raw_end = raw_end.strip()

            try:
                if raw_start == "":
                    # bytes=-N  (ultimi N byte)
                    suffix_len = int(raw_end)
                    if suffix_len > 0:
                        start = max(total_size - suffix_len, 0)
                        end = total_size - 1
                        partial = True
                else:
                    start = int(raw_start)
                    if raw_end != "":
                        end = int(raw_end)
                    else:
                        end = total_size - 1
                    if 0 <= start <= end < total_size:
                        partial = True
                    else:
                        start = 0
                        end = total_size - 1
                        partial = False
            except ValueError:
                start = 0
                end = total_size - 1
                partial = False

    payload = file_bytes[start : end + 1] if partial else file_bytes
    status_code = 206 if partial else 200
    response_body = b"" if request.method == "HEAD" else payload
    response = app.response_class(
        response_body,
        status=status_code,
        mimetype=content_type or "audio/mp4",
    )
    response.headers["Cache-Control"] = "private, max-age=120"
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Length"] = str(len(payload))
    if partial:
        response.headers["Content-Range"] = f"bytes {start}-{end}/{total_size}"
    return response


@app.route("/api/chat/audio-delete-batch", methods=["POST"])
@login_required
def api_chat_audio_delete_batch():
    """Elimina un batch di vocali chat legati a una conversazione autorizzata."""
    data = request.get_json(silent=True) or {}
    raw_offer_id = data.get("offer_id")
    raw_receiver_id = data.get("receiver_id")
    raw_audio_paths = data.get("audio_paths")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    if not isinstance(raw_audio_paths, list):
        return jsonify({"success": False, "error": "Lista audio non valida."}), 400

    expected_prefix = build_chat_audio_prefix(offer_id, current_user.id, receiver_id)
    deleted_count = 0
    skipped_count = 0

    for raw_path in raw_audio_paths:
        normalized = sanitize_chat_audio_path(raw_path)
        if not normalized or not normalized.startswith(expected_prefix):
            skipped_count += 1
            continue
        upload_storage.delete(normalized)
        deleted_count += 1

    return jsonify({
        "success": True,
        "deleted_count": deleted_count,
        "skipped_count": skipped_count,
    })


@app.route("/api/chat/media-upload", methods=["POST"])
@login_required
def api_chat_media_upload():
    """Upload di allegati chat (foto/file) su storage backend."""
    raw_offer_id = request.form.get("offer_id")
    raw_receiver_id = request.form.get("receiver_id")
    raw_kind = str(request.form.get("kind", "")).strip().lower()
    media_file = request.files.get("media")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    if not media_file or not media_file.filename:
        return jsonify({"success": False, "error": "Allegato mancante."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status
    admin_deleted_response = chat_admin_deleted_response(
        offer_id,
        current_user.id,
        receiver_id,
    )
    if admin_deleted_response:
        return admin_deleted_response

    blocked_by_me, blocked_by_other = get_chat_block_status(current_user.id, receiver_id)
    if blocked_by_me:
        return jsonify({"success": False, "error": "Hai bloccato questo utente."}), 403
    if blocked_by_other:
        return jsonify({"success": False, "error": "Questo utente ha bloccato la chat."}), 403

    original_name = secure_filename(media_file.filename or "").strip()
    extension = original_name.rsplit(".", 1)[1].lower() if "." in original_name else ""
    content_type = (media_file.mimetype or "").strip().lower()
    if not extension and content_type:
        mime_to_ext = {
            "image/jpeg": "jpg",
            "image/jpg": "jpg",
            "image/png": "png",
            "image/webp": "webp",
            "video/mp4": "mp4",
            "video/x-m4v": "m4v",
            "video/quicktime": "mov",
            "video/3gpp": "3gp",
            "video/webm": "webm",
            "video/x-matroska": "mkv",
            "audio/mpeg": "mp3",
            "audio/mp3": "mp3",
            "audio/mp4": "m4a",
            "audio/x-m4a": "m4a",
            "audio/aac": "aac",
            "audio/wav": "wav",
            "audio/x-wav": "wav",
            "audio/ogg": "ogg",
            "audio/opus": "opus",
            "audio/flac": "flac",
        }
        extension = mime_to_ext.get(content_type, "")
    inferred_kind = "image" if extension in CHAT_MEDIA_IMAGE_EXTENSIONS else "file"
    kind = raw_kind if raw_kind in {"image", "file"} else inferred_kind

    if extension not in CHAT_MEDIA_ALLOWED_EXTENSIONS:
        return jsonify({"success": False, "error": "Formato allegato non supportato."}), 400

    if kind == "image" and extension not in CHAT_MEDIA_IMAGE_EXTENSIONS:
        return jsonify({"success": False, "error": "Formato immagine non supportato."}), 400
    if kind == "file" and extension not in CHAT_MEDIA_FILE_EXTENSIONS:
        return jsonify({"success": False, "error": "Formato file non supportato."}), 400

    if kind == "image" and content_type and not (
        content_type.startswith("image/")
        or content_type == "application/octet-stream"
    ):
        return jsonify({"success": False, "error": "Tipo immagine non valido."}), 400

    def _max_bytes_for_chat_media(ext: str, media_kind: str) -> int:
        if media_kind == "image":
            return CHAT_MEDIA_IMAGE_MAX_BYTES
        if ext in CHAT_MEDIA_VIDEO_EXTENSIONS:
            return CHAT_MEDIA_VIDEO_MAX_BYTES
        if ext in CHAT_MEDIA_AUDIO_EXTENSIONS:
            return CHAT_MEDIA_AUDIO_MAX_BYTES
        return CHAT_MEDIA_GENERIC_FILE_MAX_BYTES

    raw_file_bytes = media_file.read()
    if not raw_file_bytes:
        return jsonify({"success": False, "error": "Allegato vuoto non valido."}), 400
    max_allowed_bytes = _max_bytes_for_chat_media(extension, kind)
    if len(raw_file_bytes) > max_allowed_bytes:
        max_mb = max_allowed_bytes / (1024 * 1024)
        return jsonify({
            "success": False,
            "error": f"Allegato troppo pesante (max {max_mb:.0f} MB).",
        }), 400

    if not original_name:
        original_name = f"allegato_{uuid.uuid4().hex[:6]}.{extension or 'bin'}"

    final_bytes = raw_file_bytes
    final_content_type = content_type or "application/octet-stream"
    final_extension = extension

    if kind == "image":
        image_payload = process_image(
            MemoryUpload(raw_file_bytes, content_type or "application/octet-stream"),
            f"chat_image_{uuid.uuid4().hex[:10]}.{extension or 'jpg'}",
            size=(CHAT_MEDIA_IMAGE_MAX_SIDE, CHAT_MEDIA_IMAGE_MAX_SIDE),
            return_payload=True,
            quality=CHAT_MEDIA_IMAGE_JPEG_QUALITY,
        )
        final_bytes = image_payload["bytes"]
        final_content_type = image_payload.get("content_type") or "image/jpeg"
        final_name = image_payload.get("filename", "")
        final_extension = (
            final_name.rsplit(".", 1)[1].lower()
            if "." in final_name
            else "jpg"
        )
        if len(final_bytes) > CHAT_MEDIA_IMAGE_MAX_BYTES:
            max_mb = CHAT_MEDIA_IMAGE_MAX_BYTES / (1024 * 1024)
            return jsonify({
                "success": False,
                "error": f"Immagine ancora troppo pesante dopo compressione (max {max_mb:.0f} MB).",
            }), 400

    prefix = build_chat_media_prefix(offer_id, current_user.id, receiver_id)
    media_path = f"{prefix}{uuid.uuid4().hex[:24]}.{final_extension}"
    upload_storage.save_bytes(
        media_path,
        final_bytes,
        final_content_type,
    )

    return jsonify({
        "success": True,
        "media_path": media_path,
        "bytes": len(final_bytes),
        "content_type": final_content_type,
        "file_name": original_name,
        "media_kind": kind,
    })


@app.route("/api/chat/media", methods=["GET", "HEAD"])
@login_required
def api_chat_media():
    """Restituisce un allegato chat (foto/file) solo ai due utenti autorizzati."""
    raw_offer_id = request.args.get("offer_id")
    raw_other_user_id = request.args.get("other_user_id")
    raw_media_path = request.args.get("media_path", "")

    if raw_offer_id in (None, "") or raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or other_user_id <= 0 or other_user_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, other_user_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    media_path = sanitize_chat_audio_path(raw_media_path)
    if not media_path:
        return jsonify({"success": False, "error": "Allegato non valido."}), 400

    expected_prefix = build_chat_media_prefix(offer_id, current_user.id, other_user_id)
    if not media_path.startswith(expected_prefix):
        return jsonify({"success": False, "error": "Allegato non autorizzato."}), 403

    try:
        file_bytes, content_type = upload_storage.read(media_path)
    except StorageObjectNotFound:
        return jsonify({"success": False, "error": "Allegato non trovato."}), 404

    total_size = len(file_bytes)
    range_header = request.headers.get("Range", "").strip()
    start = 0
    end = total_size - 1
    partial = False

    if range_header.startswith("bytes="):
        range_value = range_header[len("bytes="):].strip()
        if "," in range_value:
            range_value = range_value.split(",", 1)[0].strip()

        if "-" in range_value:
            raw_start, raw_end = range_value.split("-", 1)
            raw_start = raw_start.strip()
            raw_end = raw_end.strip()

            try:
                if raw_start == "":
                    suffix_len = int(raw_end)
                    if suffix_len > 0:
                        start = max(total_size - suffix_len, 0)
                        end = total_size - 1
                        partial = True
                else:
                    start = int(raw_start)
                    if raw_end != "":
                        end = int(raw_end)
                    else:
                        end = total_size - 1
                    if 0 <= start <= end < total_size:
                        partial = True
                    else:
                        start = 0
                        end = total_size - 1
                        partial = False
            except ValueError:
                start = 0
                end = total_size - 1
                partial = False

    payload = file_bytes[start : end + 1] if partial else file_bytes
    status_code = 206 if partial else 200
    response_body = b"" if request.method == "HEAD" else payload
    response = app.response_class(
        response_body,
        status=status_code,
        mimetype=content_type or "application/octet-stream",
    )
    response.headers["Cache-Control"] = "private, max-age=120"
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Length"] = str(len(payload))
    if partial:
        response.headers["Content-Range"] = f"bytes {start}-{end}/{total_size}"
    return response


@app.route("/api/chat/media-delete-batch", methods=["POST"])
@login_required
def api_chat_media_delete_batch():
    """Elimina un batch di allegati chat legati a una conversazione autorizzata."""
    data = request.get_json(silent=True) or {}
    raw_offer_id = data.get("offer_id")
    raw_receiver_id = data.get("receiver_id")
    raw_media_paths = data.get("media_paths")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    if not isinstance(raw_media_paths, list):
        return jsonify({"success": False, "error": "Lista allegati non valida."}), 400

    expected_prefix = build_chat_media_prefix(offer_id, current_user.id, receiver_id)
    deleted_count = 0
    skipped_count = 0

    for raw_path in raw_media_paths:
        normalized = sanitize_chat_audio_path(raw_path)
        if not normalized or not normalized.startswith(expected_prefix):
            skipped_count += 1
            continue
        upload_storage.delete(normalized)
        deleted_count += 1

    return jsonify({
        "success": True,
        "deleted_count": deleted_count,
        "skipped_count": skipped_count,
    })


@app.route("/api/chat/block-status", methods=["GET"])
@login_required
def api_chat_block_status():
    """Stato blocco chat con un utente specifico."""
    raw_other_user_id = request.args.get("other_user_id")
    if raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Utente mancante."}), 400

    try:
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Utente non valido."}), 400

    if other_user_id == current_user.id:
        return jsonify({
            "success": True,
            "blocked_by_me": False,
            "blocked_by_other": False,
        })

    other_user = User.query.get(other_user_id)
    if not other_user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    blocked_by_me, blocked_by_other = get_chat_block_status(current_user.id, other_user_id)
    return jsonify({
        "success": True,
        "blocked_by_me": blocked_by_me,
        "blocked_by_other": blocked_by_other,
    })


@app.route("/api/chat/block", methods=["POST"])
@login_required
def api_chat_block_user():
    """Blocca un utente in chat."""
    data = request.get_json(silent=True) or {}
    raw_other_user_id = data.get("other_user_id")
    if raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Utente mancante."}), 400

    try:
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Utente non valido."}), 400

    if other_user_id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi bloccare te stesso."}), 400

    other_user = User.query.get(other_user_id)
    if not other_user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    existing = UserBlock.query.filter_by(
        blocker_id=current_user.id,
        blocked_id=other_user_id,
    ).first()
    if not existing:
        db.session.add(UserBlock(
            blocker_id=current_user.id,
            blocked_id=other_user_id,
        ))
        db.session.commit()

    return jsonify({
        "success": True,
        "blocked_by_me": True,
        "blocked_by_other": False,
        "message": f"Hai bloccato {other_user.nome} in chat.",
    })


@app.route("/api/chat/unblock", methods=["POST"])
@login_required
def api_chat_unblock_user():
    """Rimuove il blocco chat verso un utente."""
    data = request.get_json(silent=True) or {}
    raw_other_user_id = data.get("other_user_id")
    if raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Utente mancante."}), 400

    try:
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Utente non valido."}), 400

    existing = UserBlock.query.filter_by(
        blocker_id=current_user.id,
        blocked_id=other_user_id,
    ).first()
    if existing:
        db.session.delete(existing)
        db.session.commit()

    blocked_by_me, blocked_by_other = get_chat_block_status(current_user.id, other_user_id)
    return jsonify({
        "success": True,
        "blocked_by_me": blocked_by_me,
        "blocked_by_other": blocked_by_other,
        "message": "Utente sbloccato in chat.",
    })


@app.route("/api/chat/thread/ensure", methods=["POST"])
@login_required
def api_chat_thread_ensure():
    """Garantisce l'esistenza del thread chat su DB server."""
    data = request.get_json(silent=True) or {}
    raw_offer_id = data.get("offer_id")
    raw_other_user_id = data.get("other_user_id")

    if raw_offer_id in (None, "") or raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or other_user_id <= 0 or other_user_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, other_user_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    thread = get_or_create_chat_thread(
        offer_id=offer_id,
        user_id=current_user.id,
        other_user_id=other_user_id,
        create_if_missing=True,
    )
    if not thread:
        return jsonify({"success": False, "error": "Thread chat non disponibile."}), 500
    if hydrate_admin_deleted_chat_from_notice(thread):
        db.session.commit()
    if is_chat_thread_admin_hidden(thread):
        message, status = chat_admin_deleted_error(thread)
        return jsonify({
            "success": False,
            "error": message,
            **build_admin_deleted_chat_payload(thread),
        }), status

    if thread.updated_at is None:
        thread.updated_at = chat_now_utc()
    db.session.commit()

    other_user = User.query.get(other_user_id)
    return jsonify({
        "success": True,
        "thread_id": thread.id,
        "chat_id": build_chat_thread_key(thread.offer_id, thread.user_a_id, thread.user_b_id),
        "offer_id": thread.offer_id,
        "other_user_id": other_user_id,
        "other_user_name": (other_user.nome.strip() if other_user and other_user.nome else "Utente"),
        "other_user_photo_filename": (
            get_primary_photo_filename(other_user) if other_user else ""
        ),
        **build_admin_deleted_chat_payload(thread),
    })


@app.route("/api/chat/messages", methods=["GET"])
@login_required
def api_chat_messages():
    """Lista messaggi chat dal DB server (ordine discendente per timestamp)."""
    raw_offer_id = request.args.get("offer_id")
    raw_other_user_id = request.args.get("other_user_id")
    raw_limit = request.args.get("limit")

    if raw_offer_id in (None, "") or raw_other_user_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        other_user_id = int(raw_other_user_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or other_user_id <= 0 or other_user_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, other_user_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    limit = 200
    if raw_limit not in (None, ""):
        try:
            limit = int(raw_limit)
        except (TypeError, ValueError):
            limit = 200
    limit = max(20, min(limit, 500))

    thread = get_or_create_chat_thread(
        offer_id=offer_id,
        user_id=current_user.id,
        other_user_id=other_user_id,
        create_if_missing=False,
    )
    if not thread:
        return jsonify({"success": True, "messages": []})
    if hydrate_admin_deleted_chat_from_notice(thread):
        db.session.commit()
    if is_chat_thread_admin_hidden(thread):
        return jsonify({
            "success": True,
            "messages": [],
            "chat_id": build_chat_thread_key(thread.offer_id, thread.user_a_id, thread.user_b_id),
            **build_admin_deleted_chat_payload(thread),
        })

    messages = (
        ChatMessage.query.filter_by(thread_id=thread.id)
        .order_by(ChatMessage.created_at.desc(), ChatMessage.id.desc())
        .limit(limit)
        .all()
    )
    return jsonify({
        "success": True,
        "messages": [serialize_chat_message(message) for message in messages],
        "chat_id": build_chat_thread_key(thread.offer_id, thread.user_a_id, thread.user_b_id),
        **build_admin_deleted_chat_payload(thread),
    })


@app.route("/api/chat/messages", methods=["POST"])
@login_required
def api_chat_send_message():
    """Salva un messaggio chat (text/audio/image/file) nel DB server."""
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error
    data = request.get_json(silent=True) or {}
    raw_offer_id = data.get("offer_id")
    raw_receiver_id = data.get("receiver_id")
    message_type = str(data.get("type", "text")).strip().lower()
    text = str(data.get("text", "")).strip()
    audio_path = str(data.get("audio_path", "")).strip()
    media_path = str(data.get("media_path", "")).strip()
    media_file_name = str(data.get("media_file_name", "")).strip()
    media_content_type = str(data.get("media_content_type", "")).strip()
    audio_duration_sec = data.get("audio_duration_sec")
    media_size_bytes = data.get("media_size_bytes")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if message_type not in {"text", "audio", "image", "file"}:
        return jsonify({"success": False, "error": "Tipo messaggio non valido."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status

    blocked_by_me, blocked_by_other = get_chat_block_status(current_user.id, receiver_id)
    if blocked_by_me:
        return jsonify({"success": False, "error": "Hai bloccato questo utente."}), 403
    if blocked_by_other:
        return jsonify({"success": False, "error": "Questo utente ha bloccato la chat."}), 403

    normalized_audio_path = ""
    normalized_media_path = ""

    if message_type == "text":
        if not text:
            return jsonify({"success": False, "error": "Messaggio vuoto."}), 400
    elif message_type == "audio":
        normalized_audio_path = sanitize_chat_audio_path(audio_path)
        if not normalized_audio_path:
            return jsonify({"success": False, "error": "Audio non valido."}), 400
        expected_audio_prefix = build_chat_audio_prefix(offer_id, current_user.id, receiver_id)
        if not normalized_audio_path.startswith(expected_audio_prefix):
            return jsonify({"success": False, "error": "Audio non autorizzato."}), 403
    else:
        normalized_media_path = sanitize_chat_audio_path(media_path)
        if not normalized_media_path:
            return jsonify({"success": False, "error": "Allegato non valido."}), 400
        expected_media_prefix = build_chat_media_prefix(offer_id, current_user.id, receiver_id)
        if not normalized_media_path.startswith(expected_media_prefix):
            return jsonify({"success": False, "error": "Allegato non autorizzato."}), 403
        if message_type == "image":
            media_extension = normalized_media_path.rsplit(".", 1)[-1].lower() if "." in normalized_media_path else ""
            if media_extension not in CHAT_MEDIA_IMAGE_EXTENSIONS:
                return jsonify({"success": False, "error": "Formato immagine non supportato."}), 400

    try:
        parsed_audio_duration = int(audio_duration_sec or 0)
    except (TypeError, ValueError):
        parsed_audio_duration = 0
    try:
        parsed_media_size = int(media_size_bytes or 0)
    except (TypeError, ValueError):
        parsed_media_size = 0

    preview_text = build_chat_preview_text(
        message_type,
        text=text,
        media_file_name=media_file_name,
        audio_duration_sec=parsed_audio_duration,
    )
    now = chat_now_utc()

    thread = get_or_create_chat_thread(
        offer_id=offer_id,
        user_id=current_user.id,
        other_user_id=receiver_id,
        create_if_missing=True,
    )
    if not thread:
        return jsonify({"success": False, "error": "Thread chat non disponibile."}), 500
    if hydrate_admin_deleted_chat_from_notice(thread):
        db.session.commit()
    if is_chat_thread_admin_deleted(thread):
        message, status = chat_admin_deleted_error(thread)
        return jsonify({
            "success": False,
            "error": message,
            **build_admin_deleted_chat_payload(thread),
        }), status

    message = ChatMessage(
        thread_id=thread.id,
        sender_id=current_user.id,
        sender_name=current_user.nome or "Utente",
        message_type=message_type,
        text=preview_text if message_type != "text" else text,
        audio_path=normalized_audio_path or None,
        audio_duration_sec=parsed_audio_duration if message_type == "audio" else None,
        media_path=normalized_media_path or None,
        media_file_name=media_file_name or None,
        media_content_type=media_content_type or None,
        media_size_bytes=parsed_media_size if parsed_media_size > 0 else None,
        created_at=now,
    )
    db.session.add(message)

    thread.last_message = preview_text
    thread.last_message_type = message_type
    thread.last_message_time = now
    thread.last_sender_id = current_user.id
    thread.updated_at = now
    thread.cleared_at = None
    thread.cleared_by_id = None

    db.session.commit()
    return jsonify({
        "success": True,
        "message": serialize_chat_message(message),
        "preview_text": preview_text,
    })


@app.route("/api/chat/clear", methods=["POST"])
@login_required
def api_chat_clear():
    """Cancella tutti i messaggi del thread chat per entrambi gli utenti."""
    data = request.get_json(silent=True) or {}
    raw_offer_id = data.get("offer_id")
    raw_receiver_id = data.get("receiver_id")

    if raw_offer_id in (None, "") or raw_receiver_id in (None, ""):
        return jsonify({"success": False, "error": "Dati chat mancanti."}), 400

    try:
        offer_id = int(raw_offer_id)
        receiver_id = int(raw_receiver_id)
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    if offer_id <= 0 or receiver_id <= 0 or receiver_id == current_user.id:
        return jsonify({"success": False, "error": "Dati chat non validi."}), 400

    _, chat_error = ensure_chat_pair_allowed(offer_id, current_user.id, receiver_id)
    if chat_error:
        message, status = chat_error
        return jsonify({"success": False, "error": message}), status
    admin_deleted_response = chat_admin_deleted_response(
        offer_id,
        current_user.id,
        receiver_id,
    )
    if admin_deleted_response:
        return admin_deleted_response

    thread = get_or_create_chat_thread(
        offer_id=offer_id,
        user_id=current_user.id,
        other_user_id=receiver_id,
        create_if_missing=False,
    )
    if not thread:
        return jsonify({
            "success": True,
            "deleted_messages": 0,
            "deleted_audio_files": 0,
            "deleted_media_files": 0,
        })

    delete_result = delete_chat_thread_payload(thread)
    now = chat_now_utc()
    thread.last_message = ""
    thread.last_message_type = "text"
    thread.last_message_time = now
    thread.last_sender_id = current_user.id
    thread.updated_at = now
    thread.cleared_at = now
    thread.cleared_by_id = current_user.id
    db.session.commit()

    return jsonify({
        "success": True,
        **delete_result,
    })


@app.route("/api/chat/inbox", methods=["GET"])
@login_required
def api_chat_inbox():
    """Restituisce la inbox chat usando esclusivamente il DB server."""
    base_query = ChatThread.query.filter(
        or_(
            ChatThread.user_a_id == current_user.id,
            ChatThread.user_b_id == current_user.id,
        )
    )
    threads = base_query.all()
    now = chat_now_utc()
    purged_any = False
    for thread in threads:
        if purge_chat_thread_if_expired(thread, now=now):
            purged_any = True
    if purged_any:
        db.session.commit()
        threads = base_query.all()
    hydrated_any = False
    for thread in threads:
        hydrated_any = hydrate_admin_deleted_chat_from_notice(thread) or hydrated_any
    if hydrated_any:
        db.session.commit()
    threads = [
        thread for thread in threads
        if not is_chat_thread_admin_hidden(thread, now=now)
    ]

    thread_by_pair = {}
    for thread in threads:
        pair_key = (int(thread.user_a_id), int(thread.user_b_id))
        existing = thread_by_pair.get(pair_key)
        if existing is None or chat_thread_preference_key(thread) > chat_thread_preference_key(existing):
            thread_by_pair[pair_key] = thread
    threads = list(thread_by_pair.values())

    if not threads:
        return jsonify({"success": True, "chats": []})

    other_user_ids = {
        thread.user_b_id if thread.user_a_id == current_user.id else thread.user_a_id
        for thread in threads
    }
    users = User.query.filter(User.id.in_(other_user_ids)).all() if other_user_ids else []
    users_by_id = {user.id: user for user in users}

    enriched = []
    for thread in threads:
        other_user_id = (
            thread.user_b_id if thread.user_a_id == current_user.id else thread.user_a_id
        )
        other_user = users_by_id.get(other_user_id)
        sort_time = thread.last_message_time or thread.updated_at or thread.created_at or datetime.min
        enriched.append((
            sort_time,
            {
                "chat_id": build_chat_thread_key(thread.offer_id, thread.user_a_id, thread.user_b_id),
                "offer_id": thread.offer_id,
                "other_user_id": int(other_user_id),
                "other_user_name": (
                    other_user.nome.strip()
                    if other_user and other_user.nome
                    else "Utente"
                ),
                "other_user_photo_filename": (
                    get_primary_photo_filename(other_user) if other_user else ""
                ),
                "last_message": (thread.last_message or "").strip(),
                "last_message_time": datetime_to_iso_z(sort_time),
                **build_admin_deleted_chat_payload(thread),
            },
        ))

    enriched.sort(key=lambda item: item[0], reverse=True)
    return jsonify({
        "success": True,
        "chats": [item[1] for item in enriched],
    })


@app.route("/api/user/reviews", methods=["GET"])
@login_required
def api_user_reviews():
    """Restituisce le recensioni ricevute e lasciate dell'utente corrente."""
    reviews_received = (
        Review.query.options(
            selectinload(Review.reviewer).selectinload(User.photos),
            selectinload(Review.reviewed).selectinload(User.photos),
            selectinload(Review.offerta),
        )
        .filter(Review.reviewed_id == current_user.id)
        .order_by(Review.created_at.desc())
        .all()
    )
    reviews_given = (
        Review.query.options(
            selectinload(Review.reviewer).selectinload(User.photos),
            selectinload(Review.reviewed).selectinload(User.photos),
            selectinload(Review.offerta),
        )
        .filter(Review.reviewer_id == current_user.id)
        .order_by(Review.created_at.desc())
        .all()
    )

    return jsonify({
        "success": True,
        "reviews_received": [
            serialize_review_preview(review, viewer=current_user)
            for review in reviews_received
        ],
        "reviews_given": [
            serialize_review_preview(review, viewer=current_user)
            for review in reviews_given
        ],
    })


@app.route("/api/people", methods=["GET"])
@login_required
def api_people():
    """Restituisce i profili community in formato JSON."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "La community non è disponibile per gli amministratori."}), 403
    moderation_error = require_moderation_clear_json(current_user)
    if moderation_error:
        return moderation_error

    selected_age_range, parsed_age_range, age_range_error = parse_age_range_filter(
        request.args.get("age_range")
    )
    if age_range_error:
        return jsonify({"success": False, "error": age_range_error}), 400
    selected_gender, gender_error = parse_community_gender_filter(
        request.args.get("gender")
    )
    if gender_error:
        return jsonify({"success": False, "error": gender_error}), 400
    radius_str = (request.args.get("radius") or "").strip()
    radius_km = None
    if radius_str:
        try:
            radius_km = float(radius_str.replace(",", "."))
            if radius_km < 5 or radius_km > 1500:
                raise ValueError()
        except Exception:
            return jsonify({
                "success": False,
                "error": "La distanza community deve essere un numero tra 5 e 1500 km.",
            }), 400

    now_utc = utc_now_naive()
    req_lat = (request.args.get("lat") or "").strip()
    req_lon = (request.args.get("lon") or "").strip()
    search_source = "profile"
    if req_lat and req_lon:
        try:
            search_lat = parse_coordinate(req_lat, kind="lat")
            search_lon = parse_coordinate(req_lon, kind="lon")
            search_source = "request_gps"
        except Exception:
            return jsonify({
                "success": False,
                "error": "Le coordinate community non sono valide.",
            }), 400
    else:
        resolved_lat, resolved_lon, resolved_source = resolve_user_distance_coordinates(
            current_user,
            now_utc=now_utc,
        )
        search_lat = resolved_lat if resolved_lat is not None else DEFAULT_USER_LATITUDE
        search_lon = resolved_lon if resolved_lon is not None else DEFAULT_USER_LONGITUDE
        search_source = resolved_source if resolved_source != "none" else "default"

    people_query = User.query.options(selectinload(User.photos)).filter(
        User.id != current_user.id,
        User.is_admin.is_(False),
        User.verificato.is_(True),
        User.bio.isnot(None),
        User.bio != "",
        User.cibi_preferiti.isnot(None),
        User.cibi_preferiti != "",
        User.intolleranze.isnot(None),
        User.intolleranze != "",
    )
    people_query = apply_public_user_visibility_filters(people_query)

    if isinstance(parsed_age_range, tuple):
        people_query = people_query.filter(
            User.eta >= parsed_age_range[0],
            User.eta <= parsed_age_range[1],
        )
    elif isinstance(parsed_age_range, int):
        people_query = people_query.filter(User.eta >= parsed_age_range)

    if selected_gender:
        people_query = people_query.filter(User.sesso == selected_gender)

    people = people_query.order_by(User.eta.asc(), User.nome.asc()).all()
    people_with_distance = []
    for person in people:
        person_lat, person_lon, person_location_source = resolve_user_distance_coordinates(
            person,
            now_utc=now_utc,
        )
        if person_lat is None or person_lon is None:
            continue
        distance_km = calculate_distance(search_lat, search_lon, person_lat, person_lon)
        if radius_km is not None and distance_km > radius_km:
            continue
        source_rank = 1 if person_location_source == "profile" else 0
        people_with_distance.append((distance_km, source_rank, person))

    people_with_distance.sort(
        key=lambda item: (item[0], item[1], item[2].nome.lower())
    )
    people = [person for _, _, person in people_with_distance]
    followed_user_ids = get_followed_user_ids(current_user.id)

    return jsonify({
        "success": True,
        "selected_age_range": selected_age_range,
        "selected_gender": selected_gender,
        "selected_radius": radius_km,
        "search_location_source": search_source,
        "age_ranges": [{"value": value, "label": label} for value, label in FASCE_ETA],
        "gender_filters": [{"value": value, "label": label} for value, label in COMMUNITY_GENDER_FILTERS],
        "people": [
            serialize_user_preview(
                person,
                viewer=current_user,
                followed_user_ids=followed_user_ids,
            )
            for person in people
        ],
    })


@app.route("/api/users/<int:user_id>", methods=["GET"])
@login_required
def api_public_user(user_id):
    """Dettaglio profilo pubblico in formato JSON."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "I profili pubblici non sono disponibili per gli amministratori."}), 403
    moderation_error = require_moderation_clear_json(current_user)
    if moderation_error:
        return moderation_error

    user = User.query.options(selectinload(User.photos)).filter(
        User.id == user_id,
        User.is_admin.is_(False),
    )
    if user_id != current_user.id:
        user = apply_public_user_visibility_filters(user)
    user = user.first_or_404()

    followed_user_ids = get_followed_user_ids(current_user.id)
    followers = [
        relation.follower
        for relation in sorted(
            user.followers_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.follower and not is_admin_user(relation.follower)
        and is_public_user_visible_to_viewer(relation.follower, current_user)
    ]
    reviews = Review.query.options(
        selectinload(Review.reviewer).selectinload(User.photos),
        selectinload(Review.offerta),
    ).filter_by(reviewed_id=user_id).order_by(Review.created_at.desc()).all()

    return jsonify({
        "success": True,
        "user": serialize_user_preview(
            user,
            viewer=current_user,
            followed_user_ids=followed_user_ids,
            include_gallery=True,
        ),
        "stats": {
            "offerte_totali": Offer.query.filter_by(user_id=user.id).count(),
            "recuperi_effettuati": Claim.query.filter_by(
                user_id=user.id,
                status=CLAIM_STATUS_ACCEPTED,
            ).count(),
        },
        "reviews": [
            serialize_review_preview(review, viewer=current_user)
            for review in reviews
        ],
        "followers": [
            serialize_user_preview(
                follower,
                viewer=current_user,
                followed_user_ids=followed_user_ids,
            )
            for follower in followers
        ],
    })


@app.route("/api/users/<int:user_id>/follow", methods=["POST"])
@login_required
def api_follow_user(user_id):
    """Segue un utente da mobile/web app JSON."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "Operazione non disponibile per gli amministratori."}), 403
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error
    moderation_error = require_moderation_clear_json(current_user)
    if moderation_error:
        return moderation_error

    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi seguire te stesso."}), 400
    if user.is_admin:
        return jsonify({"success": False, "error": "Non puoi seguire un amministratore."}), 400
    if is_user_moderation_restricted(user):
        return jsonify({"success": False, "error": "Profilo non disponibile."}), 404

    existing_follow = UserFollow.query.filter_by(
        follower_id=current_user.id,
        followed_id=user.id,
    ).first()
    if not existing_follow:
        db.session.add(UserFollow(follower_id=current_user.id, followed_id=user.id))
        db.session.commit()
        send_follow_started_push(current_user, user)

    return jsonify({
        "success": True,
        "message": f"Ora segui {user.nome}. Riceverai le sue nuove offerte via email.",
        "is_following": True,
        "followers_count": user.followers_count,
    })


@app.route("/api/users/<int:user_id>/unfollow", methods=["POST"])
@login_required
def api_unfollow_user(user_id):
    """Smette di seguire un utente da mobile/web app JSON."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "Operazione non disponibile per gli amministratori."}), 403

    user = User.query.get_or_404(user_id)
    existing_follow = UserFollow.query.filter_by(
        follower_id=current_user.id,
        followed_id=user.id,
    ).first()
    if existing_follow:
        db.session.delete(existing_follow)
        db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Non segui più {user.nome}.",
        "is_following": False,
        "followers_count": user.followers_count,
    })


@app.route("/api/users/<int:user_id>/block", methods=["POST"])
@login_required
def api_block_user(user_id):
    """Blocca un profilo dall'app, riusando la stessa protezione della chat."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "Operazione non disponibile per gli amministratori."}), 403
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error
    if user_id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi bloccare te stesso."}), 400

    user = User.query.get(user_id)
    if not user or is_admin_user(user):
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    existing = UserBlock.query.filter_by(
        blocker_id=current_user.id,
        blocked_id=user.id,
    ).first()
    if not existing:
        db.session.add(UserBlock(blocker_id=current_user.id, blocked_id=user.id))
        db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Hai bloccato {user.nome}. Non potrete scrivervi finche non lo sblocchi.",
        "blocked": True,
    })


@app.route("/api/users/<int:user_id>/unblock", methods=["POST"])
@login_required
def api_unblock_user(user_id):
    """Sblocca un profilo dall'app."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "Operazione non disponibile per gli amministratori."}), 403
    user = User.query.get(user_id)
    if not user or is_admin_user(user):
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    existing = UserBlock.query.filter_by(
        blocker_id=current_user.id,
        blocked_id=user.id,
    ).first()
    if existing:
        db.session.delete(existing)
        db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Hai sbloccato {user.nome}.",
        "blocked": False,
    })


@app.route("/api/reports", methods=["POST"])
@login_required
def api_submit_content_report():
    """Riceve segnalazioni di profili, eventi, chat o altri contenuti."""
    if is_admin_user(current_user):
        return jsonify({"success": False, "error": "Usa un account utente standard per inviare segnalazioni."}), 403
    legal_error = require_legal_acceptance_json()
    if legal_error:
        return legal_error
    moderation_error = require_moderation_clear_json(current_user)
    if moderation_error:
        return moderation_error

    data = request.get_json(silent=True) or request.form or {}
    message = str(data.get("message", "") or "").strip()
    if len(message) < 8:
        return jsonify({
            "success": False,
            "error": "Scrivi almeno qualche parola per spiegare la segnalazione.",
        }), 400
    if len(message) > 1200:
        return jsonify({
            "success": False,
            "error": "Segnalazione troppo lunga: resta entro 1200 caratteri.",
        }), 400

    try:
        target = resolve_content_report_target(data)
    except ValueError as exc:
        return jsonify({"success": False, "error": str(exc)}), 400

    report = ContentReport(
        reporter_id=current_user.id,
        target_type=target["target_type"],
        target_id=target["target_id"],
        reported_user_id=target["reported_user_id"],
        offer_id=target["offer_id"],
        chat_thread_id=target["chat_thread_id"],
        message=message,
        status=CONTENT_REPORT_STATUS_PENDING,
    )
    db.session.add(report)
    db.session.commit()
    notify_admin_for_content_report(report)

    return jsonify({
        "success": True,
        "message": "Segnalazione inviata. L'amministratore la controllera appena possibile.",
        "report": serialize_content_report(report),
    })


@app.route("/api/admin/users/<int:user_id>", methods=["DELETE"])
@admin_required
def api_admin_delete_user(user_id):
    """Elimina un account utente con motivazione obbligatoria e pulizia dati correlati."""
    user = User.query.get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    if user.id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi eliminare l'account con cui sei entrato."}), 400

    if is_admin_user(user) and User.query.filter_by(is_admin=True).count() <= 1:
        return jsonify({"success": False, "error": "Non puoi eliminare l'ultimo amministratore rimasto."}), 400

    data = request.get_json(silent=True) or {}
    motivazione = str(data.get("motivazione", "")).strip()
    if len(motivazione) < 8:
        return jsonify({"success": False, "error": "Inserisci una motivazione chiara da inviare all'utente."}), 400

    remove_user_with_cleanup(user, motivazione, current_user)
    return jsonify({"success": True, "message": "Account eliminato e utente avvisato via email."})


@app.route("/api/admin/dashboard", methods=["GET"])
@admin_required
def api_admin_dashboard():
    """Espone dati aggregati per il pannello amministratore mobile."""
    now = local_now()
    chat_threads = ChatThread.query.order_by(ChatThread.updated_at.desc()).all()
    purged_chat_threads = False
    chat_now = chat_now_utc()
    for thread in chat_threads:
        if purge_chat_thread_if_expired(thread, now=chat_now):
            purged_chat_threads = True
    if purged_chat_threads:
        db.session.commit()
        chat_threads = ChatThread.query.order_by(ChatThread.updated_at.desc()).all()

    all_offers = (
        Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims),
        )
        .filter(Offer.stato != "archiviata_admin")
        .order_by(Offer.data_ora.desc())
        .all()
    )
    upcoming_offers = [offer for offer in all_offers if offer.data_ora >= now]
    past_offers = [offer for offer in all_offers if offer.data_ora < now]
    users = (
        User.query.options(
            selectinload(User.photos),
            selectinload(User.offerte),
            selectinload(User.claims),
            selectinload(User.reviews_ricevute),
        )
        .filter_by(is_admin=False)
        .order_by(User.created_at.desc())
        .all()
    )
    admins_count = User.query.filter_by(is_admin=True).count()
    review_users = [
        user for user in users
        if is_user_moderation_restricted(user)
    ]
    bug_reports = (
        BugReport.query.options(
            selectinload(BugReport.user).selectinload(User.photos),
            selectinload(BugReport.reviewed_by),
        )
        .order_by(BugReport.created_at.desc())
        .limit(100)
        .all()
    )
    content_reports = (
        ContentReport.query.options(
            selectinload(ContentReport.reporter).selectinload(User.photos),
            selectinload(ContentReport.reported_user).selectinload(User.photos),
            selectinload(ContentReport.offer),
            selectinload(ContentReport.chat_thread),
            selectinload(ContentReport.reviewed_by),
        )
        .order_by(ContentReport.created_at.desc())
        .limit(100)
        .all()
    )
    pending_bug_reports_count = BugReport.query.filter_by(
        status=BUG_REPORT_STATUS_PENDING,
    ).count()
    pending_content_reports_count = ContentReport.query.filter_by(
        status=CONTENT_REPORT_STATUS_PENDING,
    ).count()

    return jsonify({
        "success": True,
        "stats": {
            "users": len(users),
            "admins": admins_count,
            "future_offers": len(upcoming_offers),
            "past_offers": len(past_offers),
            "chats": len(chat_threads),
            "review_users": len(review_users),
            "bug_reports_pending": pending_bug_reports_count,
            "content_reports_pending": pending_content_reports_count,
        },
        "users": [
            serialize_admin_user_summary(user)
            for user in users
        ],
        "review_users": [
            serialize_admin_user_summary(user)
            for user in review_users
        ],
        "future_offers": [
            serialize_admin_offer_summary(offer)
            for offer in upcoming_offers
        ],
        "past_offers": [
            serialize_admin_offer_summary(offer)
            for offer in past_offers
        ],
        "chats": [
            serialize_admin_chat_summary(thread)
            for thread in chat_threads
        ],
        "bug_reports": [
            serialize_bug_report(report)
            for report in bug_reports
        ],
        "content_reports": [
            serialize_content_report(report)
            for report in content_reports
        ],
    })


@app.route("/api/admin/bug-reports/<int:report_id>/review", methods=["POST"])
@admin_required
def api_admin_review_bug_report(report_id):
    """Approva o respinge una segnalazione bug e assegna punti solo se validata."""
    report = BugReport.query.options(selectinload(BugReport.user)).get(report_id)
    if not report:
        return jsonify({"success": False, "error": "Segnalazione non trovata."}), 404

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip().lower()
    note = str(data.get("admin_note", "")).strip()[:500]

    if status not in {BUG_REPORT_STATUS_APPROVED, BUG_REPORT_STATUS_REJECTED}:
        return jsonify({"success": False, "error": "Decisione non valida."}), 400

    try:
        requested_points = int(data.get("points", 0) or 0)
    except (TypeError, ValueError):
        requested_points = 0

    points = max(0, min(requested_points, 500))
    if status == BUG_REPORT_STATUS_APPROVED and points <= 0:
        return jsonify({
            "success": False,
            "error": "Inserisci almeno 1 ApprofittOffro Point da assegnare.",
        }), 400

    user = report.user
    if not user:
        return jsonify({"success": False, "error": "Utente della segnalazione non trovato."}), 404

    previous_status = report.status
    previous_points = int(report.awarded_points or 0)
    current_total = int(getattr(user, "approfittoffro_points", 0) or 0)

    if previous_status == BUG_REPORT_STATUS_APPROVED:
        current_total -= previous_points
    if status == BUG_REPORT_STATUS_APPROVED:
        current_total += points

    user.approfittoffro_points = max(0, current_total)
    report.status = status
    report.awarded_points = points if status == BUG_REPORT_STATUS_APPROVED else 0
    report.admin_note = note
    report.reviewed_by_id = current_user.id
    report.reviewed_at = datetime.now()
    db.session.commit()
    notification_result = notify_user_for_bug_report_review(report)

    message = (
        f"Segnalazione approvata: assegnati {report.awarded_points} ApprofittOffro Points."
        if status == BUG_REPORT_STATUS_APPROVED
        else "Segnalazione respinta: nessun punto assegnato."
    )
    return jsonify({
        "success": True,
        "message": message,
        "report": serialize_bug_report(report),
        "user_points": user.approfittoffro_points,
        "user_notified": bool(
            notification_result["email_sent"] or notification_result["push_sent"]
        ),
    })


@app.route("/api/admin/bug-reports/<int:report_id>/archive", methods=["POST"])
@admin_required
def api_admin_archive_bug_report(report_id):
    """Archivia o ripristina una segnalazione bug nel pannello admin."""
    report = BugReport.query.options(
        selectinload(BugReport.user),
        selectinload(BugReport.reviewed_by),
    ).get(report_id)
    if not report:
        return jsonify({"success": False, "error": "Segnalazione non trovata."}), 404

    data = request.get_json(silent=True) or {}
    archived = bool(data.get("archived", True))

    if archived:
        if report.status == BUG_REPORT_STATUS_PENDING:
            return jsonify({
                "success": False,
                "error": "Prima approva o respingi la segnalazione, poi archiviala.",
            }), 400
        report.admin_archived_at = datetime.now()
        report.admin_archived_by_id = current_user.id
        message = "Segnalazione archiviata."
    else:
        report.admin_archived_at = None
        report.admin_archived_by_id = None
        message = "Segnalazione ripristinata tra quelle gestite."

    db.session.commit()
    return jsonify({
        "success": True,
        "message": message,
        "report": serialize_bug_report(report),
    })


@app.route("/api/admin/content-reports/<int:report_id>/review", methods=["POST"])
@admin_required
def api_admin_review_content_report(report_id):
    """Gestisce una segnalazione contenuto senza assegnare punti."""
    report = ContentReport.query.options(
        selectinload(ContentReport.reporter),
        selectinload(ContentReport.reported_user),
        selectinload(ContentReport.offer),
        selectinload(ContentReport.chat_thread),
        selectinload(ContentReport.reviewed_by),
    ).get(report_id)
    if not report:
        return jsonify({"success": False, "error": "Segnalazione non trovata."}), 404

    data = request.get_json(silent=True) or {}
    status = str(data.get("status", "")).strip().lower()
    note = str(data.get("admin_note", "")).strip()[:800]
    if status not in {CONTENT_REPORT_STATUS_REVIEWED, CONTENT_REPORT_STATUS_DISMISSED}:
        return jsonify({"success": False, "error": "Decisione non valida."}), 400
    if status == CONTENT_REPORT_STATUS_REVIEWED and len(note) < 4:
        return jsonify({
            "success": False,
            "error": "Inserisci una nota admin minima su cosa hai verificato.",
        }), 400

    report.status = status
    report.admin_note = note
    report.reviewed_by_id = current_user.id
    report.reviewed_at = datetime.now()
    db.session.commit()

    if report.reporter:
        send_push_to_user(
            report.reporter,
            title="Segnalazione controllata",
            body=(
                "L'amministratore ha preso in carico la tua segnalazione."
                if status == CONTENT_REPORT_STATUS_REVIEWED
                else "La tua segnalazione e stata archiviata senza interventi."
            ),
            target="notifications",
            extra_data={"content_report_id": report.id},
        )

    return jsonify({
        "success": True,
        "message": "Segnalazione contenuto aggiornata.",
        "report": serialize_content_report(report),
    })


@app.route("/api/admin/content-reports/<int:report_id>/archive", methods=["POST"])
@admin_required
def api_admin_archive_content_report(report_id):
    """Archivia o ripristina una segnalazione contenuto nel pannello admin."""
    report = ContentReport.query.options(
        selectinload(ContentReport.reporter),
        selectinload(ContentReport.reported_user),
        selectinload(ContentReport.offer),
        selectinload(ContentReport.chat_thread),
        selectinload(ContentReport.reviewed_by),
    ).get(report_id)
    if not report:
        return jsonify({"success": False, "error": "Segnalazione non trovata."}), 404

    data = request.get_json(silent=True) or {}
    archived = bool(data.get("archived", True))
    if archived:
        if report.status == CONTENT_REPORT_STATUS_PENDING:
            return jsonify({
                "success": False,
                "error": "Prima gestisci la segnalazione, poi archiviala.",
            }), 400
        report.admin_archived_at = datetime.now()
        report.admin_archived_by_id = current_user.id
        message = "Segnalazione contenuto archiviata."
    else:
        report.admin_archived_at = None
        report.admin_archived_by_id = None
        message = "Segnalazione contenuto ripristinata."

    db.session.commit()
    return jsonify({
        "success": True,
        "message": message,
        "report": serialize_content_report(report),
    })


@app.route("/api/admin/chats/<int:thread_id>", methods=["DELETE"])
@admin_required
def api_admin_delete_chat(thread_id):
    """Svuota una chat dal pannello admin e avvisa entrambi i partecipanti."""
    thread = ChatThread.query.get(thread_id)
    if not thread:
        return jsonify({"success": False, "error": "Chat non trovata."}), 404

    if purge_chat_thread_if_expired(thread, now=chat_now_utc()):
        db.session.commit()
        return jsonify({
            "success": True,
            "message": "Chat gia' scaduta: eliminata dalla pulizia automatica a 30 giorni.",
            "deleted_messages": 0,
            "deleted_audio_files": 0,
            "deleted_media_files": 0,
            "push_sent": 0,
        })

    data = request.get_json(silent=True) or {}
    reason = str(data.get("motivazione", "")).strip()
    if len(reason) > 500:
        return jsonify({
            "success": False,
            "error": "La motivazione deve restare entro 500 caratteri.",
        }), 400

    user_a = User.query.options(selectinload(User.photos)).get(thread.user_a_id)
    user_b = User.query.options(selectinload(User.photos)).get(thread.user_b_id)
    delete_result = delete_chat_thread_payload(thread)
    now = chat_now_utc()
    delete_after = now + timedelta(hours=1)
    notice_text = "La chat e' stata eliminata dall'amministratore."
    if reason:
        notice_text = f"{notice_text} Motivo: {reason}"
    notice_text = (
        f"{notice_text} Verra' rimossa definitivamente tra 1 ora."
    )

    notice = ChatMessage(
        thread_id=thread.id,
        sender_id=current_user.id,
        sender_name="Amministrazione",
        message_type="text",
        text=notice_text,
        created_at=now,
    )
    db.session.add(notice)
    thread.last_message = "Chat eliminata dall'amministratore"
    thread.last_message_type = "text"
    thread.last_message_time = now
    thread.last_sender_id = current_user.id
    thread.updated_at = now
    thread.cleared_at = now
    thread.cleared_by_id = current_user.id
    thread.admin_deleted_at = now
    thread.admin_delete_after = delete_after
    thread.admin_delete_reason = reason or ""
    thread.admin_deleted_by_id = current_user.id
    db.session.commit()

    push_body = "Chat eliminata dall'amministratore. Apri l'app per leggere motivo e tempi."
    push_sent = 0
    participants = ((user_a, user_b), (user_b, user_a))
    for receiver, other_user in participants:
        if not receiver:
            continue
        push_sent += send_push_to_user(
            receiver,
            title="Chat eliminata dall'amministratore",
            body=push_body,
            target="chat",
            extra_data={
                "offer_id": thread.offer_id,
                "chat_with_user_id": other_user.id if other_user else "",
                "chat_with_name": other_user.nome if other_user else "Utente",
                "chat_with_photo_filename": (
                    get_primary_photo_filename(other_user) if other_user else ""
                ),
                "type": "chat_cleared",
                "admin_removed": "true",
            },
        )

    return jsonify({
        "success": True,
        "message": "Chat bloccata, avviso inviato e rimozione definitiva prevista tra 1 ora.",
        **delete_result,
        "push_sent": push_sent,
        "chat": serialize_admin_chat_summary(thread),
    })


@app.route("/api/admin/users/<int:user_id>", methods=["GET", "POST"])
@admin_required
def api_admin_user_detail(user_id):
    """Legge o aggiorna i dati di un utente standard dal pannello admin mobile."""
    user = User.query.options(selectinload(User.photos)).get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404
    if is_admin_user(user):
        return jsonify({
            "success": False,
            "error": "Per ora la modifica mobile vale solo per gli utenti standard.",
        }), 403

    if request.method == "GET":
        return jsonify({
            "success": True,
            "user": serialize_admin_user_detail(user),
        })

    if request.is_json:
        data = request.get_json(silent=True) or {}
        foto_files = []
    else:
        data = request.form
        foto_files = extract_uploaded_photos("foto")

    payload, errors = validate_profile_update_input(
        user,
        {
            "nome": data.get("nome", user.nome),
            "email": data.get("email", user.email),
            "eta": data.get("eta", user.eta if user.eta is not None else user.fascia_eta),
            "sesso": data.get("sesso", user.sesso or "non_dico"),
            "raggio_azione": data.get("raggio_azione", user.raggio_azione or 15),
            "numero_telefono": data.get("numero_telefono", user.numero_telefono or ""),
            "citta": data.get("citta", user.citta or ""),
            "latitudine": data.get("latitudine", user.latitudine),
            "longitudine": data.get("longitudine", user.longitudine),
            "cibi_preferiti": data.get("cibi_preferiti", user.cibi_preferiti or ""),
            "intolleranze": data.get("intolleranze", user.intolleranze or ""),
            "bio": data.get("bio", user.bio or ""),
            "existing_gallery_filenames": data.get(
                "existing_gallery_filenames",
                list(user.gallery_filenames),
            ),
        },
        foto_files=foto_files,
        require_primary_face=False,
    )
    if errors:
        delete_upload_files(payload.get("uploaded_gallery_filenames", []))
        return jsonify({"success": False, "errors": errors}), 400

    verified_value = str(data.get("verificato", user.verificato)).lower() in {
        "1",
        "true",
        "on",
        "yes",
    }
    success, save_errors, _ = save_profile_update_for_user(
        user,
        payload,
        verified=verified_value,
        allow_moderation_auto_approve=True,
    )
    if not success:
        return jsonify({"success": False, "errors": save_errors}), 400

    return jsonify({
        "success": True,
        "message": f"Profilo di {user.nome} aggiornato con successo.",
        "user": serialize_admin_user_detail(user),
    })


@app.route("/api/admin/users/<int:user_id>/approve-bio", methods=["POST"])
@admin_required
def api_admin_approve_user_bio(user_id):
    """Approva la bio di un utente in revisione."""
    user = User.query.get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404
    if is_admin_user(user):
        return jsonify({"success": False, "error": "Non puoi modificare un amministratore."}), 403

    user.bio_moderation_status = MODERATION_STATUS_APPROVED
    user.bio_moderation_reason = ""
    user.bio_moderation_score = None
    user.bio_moderation_checked_at = datetime.now()
    user.bio_moderation_provider = "admin"
    user.bio_moderation_model = "manual"
    user.bio_moderation_raw_json = None
    db.session.add(AiModerationLog(
        user_id=user.id,
        content_type="bio",
        content_table="users",
        content_id=user.id,
        status=MODERATION_STATUS_APPROVED,
        reason=None,
        score=None,
        provider="admin",
        model="manual",
        raw_json=json.dumps({
            "target": "bio",
            "status": MODERATION_STATUS_APPROVED,
            "admin_id": current_user.id,
        }, ensure_ascii=False),
        created_at=datetime.now(),
    ))
    db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Bio di {user.nome} approvata. L'utente può pubblicare offerte.",
        "user": serialize_admin_user_detail(user),
    })


def apply_admin_user_moderation_decision(user, *, target, status, reason=""):
    now = datetime.now()
    normalized_target = str(target or "").strip().lower()
    normalized_status = str(status or "").strip().lower()
    normalized_reason = str(reason or "").strip()[:100]

    allowed_targets = {"bio", "photo"}
    allowed_statuses = {
        MODERATION_STATUS_APPROVED,
        MODERATION_STATUS_REVIEW,
        MODERATION_STATUS_REJECTED,
        "blocked",
    }
    if normalized_target not in allowed_targets:
        return False, "Target moderazione non valido."
    if normalized_status not in allowed_statuses:
        return False, "Stato moderazione non valido."

    prefix = "bio" if normalized_target == "bio" else "photo"
    setattr(user, f"{prefix}_moderation_status", normalized_status)
    setattr(user, f"{prefix}_moderation_reason", "" if normalized_status == MODERATION_STATUS_APPROVED else normalized_reason)
    setattr(user, f"{prefix}_moderation_score", None)
    setattr(user, f"{prefix}_moderation_checked_at", now)
    setattr(user, f"{prefix}_moderation_provider", "admin")
    setattr(user, f"{prefix}_moderation_model", "manual")
    setattr(user, f"{prefix}_moderation_raw_json", None)

    if normalized_target == "photo":
        for photo in list(getattr(user, "photos", [])):
            photo.moderation_status = normalized_status
            photo.moderation_reason = "" if normalized_status == MODERATION_STATUS_APPROVED else normalized_reason
            photo.moderation_score = None
            photo.moderation_checked_at = now
            photo.moderation_provider = "admin"
            photo.moderation_model = "manual"
            photo.moderation_raw_json = None
            photo.status = "approved" if normalized_status == MODERATION_STATUS_APPROVED else normalized_status
            photo.reason = "" if normalized_status == MODERATION_STATUS_APPROVED else normalized_reason
            photo.moderated_by = current_user.id
            photo.moderated_at = now

    db.session.add(AiModerationLog(
        user_id=user.id,
        content_type=normalized_target,
        content_table="users",
        content_id=user.id,
        status=normalized_status,
        reason=normalized_reason or None,
        score=None,
        provider="admin",
        model="manual",
        raw_json=json.dumps({
            "target": normalized_target,
            "status": normalized_status,
            "reason": normalized_reason,
            "admin_id": current_user.id,
        }, ensure_ascii=False),
        created_at=now,
    ))
    return True, ""


@app.route("/api/admin/users/<int:user_id>/approve-photo", methods=["POST"])
@admin_required
def api_admin_approve_user_photo(user_id):
    """Approva le foto profilo di un utente in revisione."""
    user = User.query.options(selectinload(User.photos)).get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404
    if is_admin_user(user):
        return jsonify({"success": False, "error": "Non puoi modificare un amministratore."}), 403

    ok, error = apply_admin_user_moderation_decision(
        user,
        target="photo",
        status=MODERATION_STATUS_APPROVED,
    )
    if not ok:
        return jsonify({"success": False, "error": error}), 400
    db.session.commit()

    return jsonify({
        "success": True,
        "message": f"Foto di {user.nome} approvate.",
        "user": serialize_admin_user_detail(user),
    })


@app.route("/api/admin/users/<int:user_id>/moderation", methods=["POST"])
@admin_required
def api_admin_update_user_moderation(user_id):
    """Aggiorna manualmente lo stato di moderazione bio/foto."""
    user = User.query.options(selectinload(User.photos)).get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404
    if is_admin_user(user):
        return jsonify({"success": False, "error": "Non puoi modificare un amministratore."}), 403

    data = request.get_json(silent=True) or {}
    target = data.get("target", "")
    status = data.get("status", "")
    reason = data.get("reason", "")

    ok, error = apply_admin_user_moderation_decision(
        user,
        target=target,
        status=status,
        reason=reason,
    )
    if not ok:
        return jsonify({"success": False, "error": error}), 400
    db.session.commit()

    label = "bio" if str(target).strip().lower() == "bio" else "foto"
    return jsonify({
        "success": True,
        "message": f"Moderazione {label} aggiornata per {user.nome}.",
        "user": serialize_admin_user_detail(user),
    })


@app.route("/api/admin/users/review", methods=["GET"])
@admin_required
def api_admin_users_in_review():
    """Lista utenti con bio o foto in revisione."""
    users = (
        User.query.options(selectinload(User.photos))
        .filter(
            User.is_admin.is_(False),
            db.or_(
                User.bio_moderation_status.in_(list(MODERATION_RESTRICTED_STATUSES)),
                User.photo_moderation_status.in_(list(MODERATION_RESTRICTED_STATUSES)),
            )
        )
        .order_by(User.created_at.desc())
        .all()
    )

    return jsonify({
        "success": True,
        "users": [serialize_admin_user_summary(user) for user in users],
    })


@app.route("/api/admin/users/<int:user_id>/message", methods=["POST"])
@admin_required
def api_admin_message_user(user_id):
    """Invia una comunicazione libera da parte dell'amministratore a un utente."""
    user = User.query.get(user_id)
    if not user:
        return jsonify({"success": False, "error": "Utente non trovato."}), 404

    data = request.get_json(silent=True) or {}
    subject = str(data.get("subject", "")).strip()
    message = str(data.get("message", "")).strip()

    errors = []
    if len(subject) < 4:
        errors.append("Inserisci un oggetto più chiaro per la comunicazione.")
    if len(message) < 10:
        errors.append("Scrivi un messaggio più dettagliato da inviare all'utente.")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    send_email(
        subject,
        [user.email],
        "admin_message.html",
        user=user,
        admin_user=current_user,
        subject_line=subject,
        message_body=message,
    )
    send_push_to_user(
        user,
        title=subject,
        body=message[:140],
        target="profile",
        extra_data={
            "admin_notice": "true",
            "subject": subject,
        },
    )
    return jsonify({"success": True, "message": "Comunicazione inviata con successo."})


@app.route("/api/user/account", methods=["DELETE"])
@login_required
def api_delete_own_account():
    """Permette all'utente autenticato di cancellare definitivamente il proprio account."""
    user = db.session.get(User, current_user.id)
    if not user:
        logout_user()
        session.clear()
        return jsonify({"success": False, "error": "Account non trovato."}), 404

    if is_admin_user(user) and User.query.filter_by(is_admin=True).count() <= 1:
        return jsonify({
            "success": False,
            "error": "Non puoi eliminare l'ultimo amministratore rimasto.",
        }), 400

    remove_user_self_service(user)
    logout_user()
    session.clear()
    return jsonify({
        "success": True,
        "message": "Il tuo account Ã¨ stato eliminato definitivamente dalla community.",
    })

@app.route("/api/user/update", methods=["POST"])
@login_required
def api_user_update():
    """Aggiorna i dati anagrafici, alimentari e la foto profilo dell'utente."""
    if request.is_json:
        data = request.get_json()
        foto_files = []
    else:
        data = request.form
        foto_files = extract_uploaded_photos("foto")

    payload, errors = validate_profile_update_input(
        current_user,
        data,
        foto_files=foto_files,
        require_primary_face=True,
    )

    if errors:
        delete_upload_files(payload.get("uploaded_gallery_filenames", []))
        return jsonify({"success": False, "errors": errors}), 400

    success, save_errors, _ = save_profile_update_for_user(current_user, payload)
    if not success:
        return jsonify({"success": False, "errors": save_errors}), 500

    return jsonify({
        "success": True,
        "message": "Profilo aggiornato con successo!",
        "gallery_filenames": current_user.gallery_filenames,
        "moderation_restricted": is_user_moderation_restricted(current_user),
        "bio_moderation_status": getattr(current_user, "bio_moderation_status", MODERATION_STATUS_APPROVED),
        "bio_moderation_reason": getattr(current_user, "bio_moderation_reason", "") or "",
        "photo_moderation_status": getattr(current_user, "photo_moderation_status", MODERATION_STATUS_APPROVED),
        "photo_moderation_reason": getattr(current_user, "photo_moderation_reason", "") or "",
        "moderation_message": (
            get_user_moderation_block_message(current_user)
            if is_user_moderation_restricted(current_user)
            else ""
        ),
        "primary_photo_url": url_for(
            "uploaded_file",
            filename=current_user.gallery_filenames[0],
            _external=False,
        ) if current_user.gallery_filenames else "",
    })


@app.route("/api/user/settings/chat", methods=["POST"])
@login_required
def api_user_chat_settings():
    """Attiva/disattiva la chat interna."""
    data = request.get_json(silent=True) or {}
    chat_enabled = bool(data.get("chat_enabled", False))
    current_user.chat_enabled = chat_enabled
    db.session.commit()
    return jsonify({"success": True, "chat_enabled": chat_enabled})


@app.route("/api/chat/request-notification", methods=["POST"])
@login_required
def api_chat_request_notification():
    """Compatibilità legacy: la chat interna è sempre attiva, niente push di richiesta chat."""
    return jsonify({"success": True, "message": "Chat interna sempre attiva."})


# ===================================================================
# API — Recensioni
# ===================================================================

@app.route("/api/reviews", methods=["POST"])
@login_required
def api_create_review():
    """Crea o aggiorna una recensione (Host -> Guest o Guest -> Host)."""
    data = request.get_json(silent=True) or {}
    offer_id = data.get("offer_id")
    reviewed_id = data.get("reviewed_id")
    rating = data.get("rating")
    commento = str(data.get("commento", "")).strip()

    if offer_id in (None, "") or rating in (None, "") or reviewed_id in (None, ""):
        return jsonify({"success": False, "error": "Dati mancanti (ID offerta, utente o punteggio)."}), 400

    try:
        offer_id = int(offer_id)
        reviewed_id = int(reviewed_id)
        rating = int(rating)
        if rating < 1 or rating > 5:
            raise ValueError()
    except ValueError:
        return jsonify({"success": False, "error": "Dati recensione non validi."}), 400

    # 1. Verifica che l'offerta esista
    profile_error = require_complete_profile_json()
    if profile_error:
        return profile_error

    offer = db.session.get(Offer, offer_id)
    if not offer:
        return jsonify({"success": False, "error": "Offerta non trovata."}), 404

    # 2. Verifica che l'utente non stia recensendo se stesso
    if reviewed_id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi recensire te stesso."}), 400

    # 3. Verifica che l'evento sia passato (buffer 3 ore)
    if offer.data_ora + timedelta(hours=3) > local_now():
        return jsonify({"success": False, "error": "Puoi lasciare una recensione solo 3 ore dopo l'inizio del pasto."}), 400

    # 4. Validazione Ruoli (Bidirezionale)
    # Casi ammessi: 
    # A) Io sono Ospite (Claim), recensisco l'Host (offer.user_id)
    # B) Io sono Host (offer.user_id), recensisco un Ospite (reviewed_id ha un Claim)
    
    is_guest_reviewing_host = (
        Claim.query.filter_by(
            user_id=current_user.id,
            offer_id=offer_id,
            status=CLAIM_STATUS_ACCEPTED,
        ).first()
        is not None
        and reviewed_id == offer.user_id
    )
    
    is_host_reviewing_guest = (
        offer.user_id == current_user.id
        and Claim.query.filter_by(
            user_id=reviewed_id,
            offer_id=offer_id,
            status=CLAIM_STATUS_ACCEPTED,
        ).first()
        is not None
    )

    if not is_guest_reviewing_host and not is_host_reviewing_guest:
        return jsonify({"success": False, "error": "Non sei autorizzato a recensire questo utente per questo pasto."}), 403

    # 5. Se la recensione esiste già, viene aggiornata senza finestra temporale.
    existing = Review.query.filter_by(
        reviewer_id=current_user.id,
        reviewed_id=reviewed_id,
        offer_id=offer_id,
    ).first()
    if existing:
        existing.rating = rating
        existing.commento = commento
        db.session.commit()
        send_review_received_email(existing, is_update=True)
        return jsonify({
            "success": True,
            "message": "Recensione aggiornata con successo.",
        })

    # 6. Creazione recensione
    new_review = Review(
        reviewer_id=current_user.id,
        reviewed_id=reviewed_id,
        offer_id=offer_id,
        rating=rating,
        commento=commento
    )

    db.session.add(new_review)
    db.session.commit()
    send_review_received_email(new_review, is_update=False)

    return jsonify({"success": True, "message": "Grazie! La tua recensione è stata pubblicata."})


# ===================================================================
# Servire le foto caricate
# ===================================================================


@app.route("/uploads/<path:filename>")
def uploaded_file(filename):
    from flask import send_from_directory

    def legacy_upload_redirect():
        if not LEGACY_UPLOADS_BASE_URL:
            abort(404)
        return redirect(f"{LEGACY_UPLOADS_BASE_URL}/{quote(filename)}", code=302)

    if app.config["UPLOAD_STORAGE_BACKEND"] == "local":
        file_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
        if not os.path.exists(file_path):
            return legacy_upload_redirect()
        response = send_from_directory(
            app.config["UPLOAD_FOLDER"],
            filename,
            max_age=0,
            conditional=False,
        )
    else:
        try:
            file_bytes, content_type = upload_storage.read(filename)
        except StorageObjectNotFound:
            return legacy_upload_redirect()

        response = app.response_class(file_bytes, mimetype=content_type)

    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response


# ===================================================================
# Avvio
# ===================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("DEBUG", "true").lower() == "true"
    app.run(host="0.0.0.0", port=port, debug=debug)
