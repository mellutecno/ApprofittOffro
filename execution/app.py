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
    DevicePushToken,
    NotificationDeliveryLog,
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
app.config["MAX_CONTENT_LENGTH"] = 64 * 1024 * 1024  # 64 MB max upload (telefoni moderni)
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

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
MAX_PROFILE_PHOTOS = 5
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
DEFAULT_USER_LATITUDE = 41.9028
DEFAULT_USER_LONGITUDE = 12.4964
DEFAULT_PROFILE_PLACEHOLDER_FILENAME = "user_placeholder.png"
COMMUNITY_GENDER_FILTERS = [
    ("", "Tutti"),
    ("maschio", "Maschi"),
    ("femmina", "Femmine"),
]
PUSH_PLATFORM_ANDROID = "android"
PUSH_DEEP_LINK_BASE = "approfittoffro://"
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
PUSH_CHANNEL_ID = "approfittoffro_alerts"
UPCOMING_EVENT_REMINDER_HOURS = 2
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

    return {
        "id": offer.id,
        "tipo_pasto": offer.tipo_pasto,
        "nome_locale": offer.nome_locale,
        "indirizzo": offer.indirizzo,
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
        "foto_locale": getattr(offer, "foto_locale", "nessuna.jpg"),
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
        "partecipanti": [
            {
                "id": claim.utente.id,
                "nome": claim.utente.nome,
                "foto": claim.utente.foto_filename,
                "whatsapp_link": build_whatsapp_offer_link(viewer, claim.utente, offer)
                if viewer and getattr(viewer, "is_authenticated", False) and is_own
                else "",
            }
            for claim in accepted_claims
            if claim.utente
        ],
        "is_own": is_own,
        "already_claimed": already_claimed,
        "can_claim": can_claim,
        "claim_status": claim_status,
        "claim_id": current_claim.id if current_claim is not None else 0,
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
        data_evento = format_offer_datetime_label(offer.data_ora, now=now)
        host_key = build_notification_dedupe_key(
            "event_imminent_host",
            offer_id=offer.id,
            user_id=offer.user_id,
        )
        if notification_delivery_exists(host_key):
            skipped["already_sent"] += 1
        elif dry_run:
            sent["host"] += 1
        else:
            push_sent = send_push_to_user(
                offer.autore,
                title="Evento tra poco",
                body=f"Il tuo {offer.tipo_pasto} da {offer.nome_locale} inizia {data_evento}.",
                target="profile",
                extra_data={
                    "offer_id": offer.id,
                    "event_reminder": "true",
                    "role": "host",
                },
            )
            if push_sent > 0:
                record_notification_delivery(
                    user_id=offer.user_id,
                    offer_id=offer.id,
                    reminder_type="event_imminent_host",
                    dedupe_key=host_key,
                )
                sent["host"] += 1
            else:
                skipped["missing_token"] += 1

        for claim in get_offer_accepted_claims(offer):
            participant = claim.utente
            if not participant:
                continue
            participant_key = build_notification_dedupe_key(
                "event_imminent_guest",
                offer_id=offer.id,
                user_id=participant.id,
            )
            if notification_delivery_exists(participant_key):
                skipped["already_sent"] += 1
                continue
            if dry_run:
                sent["participants"] += 1
                continue
            push_sent = send_push_to_user(
                participant,
                title="Evento tra poco",
                body=f"Il tuo {offer.tipo_pasto} da {offer.nome_locale} inizia {data_evento}.",
                target="profile",
                extra_data={
                    "offer_id": offer.id,
                    "event_reminder": "true",
                    "role": "guest",
                },
            )
            if push_sent > 0:
                record_notification_delivery(
                    user_id=participant.id,
                    offer_id=offer.id,
                    reminder_type="event_imminent_guest",
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
                ("raggio_azione", "ALTER TABLE users ADD COLUMN raggio_azione INTEGER DEFAULT 10"),
                ("verificato", "ALTER TABLE users ADD COLUMN verificato INTEGER DEFAULT 0"),
                ("verification_token", "ALTER TABLE users ADD COLUMN verification_token VARCHAR(100)"),
                ("password_reset_token", "ALTER TABLE users ADD COLUMN password_reset_token VARCHAR(100)"),
                ("password_reset_sent_at", "ALTER TABLE users ADD COLUMN password_reset_sent_at DATETIME"),
                ("is_admin", "ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0"),
                ("admin_verified_notified_at", "ALTER TABLE users ADD COLUMN admin_verified_notified_at DATETIME"),
            ],
            "offers": [
                ("foto_locale", "ALTER TABLE offers ADD COLUMN foto_locale VARCHAR(256)"),
                ("stato", "ALTER TABLE offers ADD COLUMN stato VARCHAR(20) DEFAULT 'attiva'"),
                ("telefono_locale", "ALTER TABLE offers ADD COLUMN telefono_locale VARCHAR(50)"),
                ("booking_lead_override_minutes", "ALTER TABLE offers ADD COLUMN booking_lead_override_minutes INTEGER"),
            ],
            "claims": [
                ("status", "ALTER TABLE claims ADD COLUMN status VARCHAR(20) DEFAULT 'accepted'"),
                ("hidden_by_guest", "ALTER TABLE claims ADD COLUMN hidden_by_guest INTEGER DEFAULT 0"),
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

        if table_exists("users"):
            cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_sub ON users (google_sub)")

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
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(100)"
            )
            conn.exec_driver_sql(
                "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_sent_at DATETIME"
            )
            conn.exec_driver_sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_google_sub ON users (google_sub)"
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


def send_push_to_user(user, *, title, body, target="login", extra_data=None):
    if not user:
        return 0
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

def process_image(file_storage, filename, size=(800, 800), return_payload=False):
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
        img.save(output, "JPEG", quality=85)
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


def save_profile_gallery_files(user_key, photos, require_primary_face=True):
    """Salva fino a MAX_PROFILE_PHOTOS immagini profilo e verifica il volto sulla prima."""
    if not photos:
        return [], []

    errors = []
    if len(photos) > MAX_PROFILE_PHOTOS:
        errors.append(f"Puoi caricare al massimo {MAX_PROFILE_PHOTOS} foto profilo.")

    for photo in photos:
        if not allowed_file(photo.filename):
            errors.append("Formato foto non valido. Usa JPG, PNG o WEBP.")
            break

    if errors:
        return [], errors

    saved_filenames = []
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
                return [], [
                    "La prima foto deve mostrare chiaramente il volto della persona. "
                    "Carica come prima immagine una foto reale, frontale o comunque ben visibile. "
                    f"Dettaglio: {dettaglio}"
                ]

        upload_storage.save_bytes(
            image_payload["filename"],
            image_payload["bytes"],
            image_payload.get("content_type"),
        )
        saved_filenames.append(image_payload["filename"])

    return saved_filenames, []


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


def validate_profile_update_input(user, source, *, foto_files=None, require_primary_face=True):
    uploaded_gallery_filenames = []
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
        uploaded_gallery_filenames, photo_errors = save_profile_gallery_files(
            user.id,
            foto_files,
            require_primary_face=require_primary_face and not existing_gallery_filenames,
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
    }

    return payload, errors


def save_profile_update_for_user(user, payload, *, verified=None):
    old_gallery_filenames = []
    uploaded_gallery_filenames = payload.get("uploaded_gallery_filenames", [])
    final_gallery_filenames = payload.get("final_gallery_filenames", list(user.gallery_filenames))

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
    if payload.get("new_password"):
        user.set_password(payload["new_password"])
        clear_password_reset_state(user)

    if verified is not None:
        user.verificato = bool(verified)

    if final_gallery_filenames != list(user.gallery_filenames):
        old_gallery_filenames = replace_user_gallery(user, final_gallery_filenames)

    try:
        db.session.commit()
    except Exception as exc:
        db.session.rollback()
        delete_upload_files(uploaded_gallery_filenames)
        return False, [f"Errore nel salvataggio del profilo: {exc}"], []

    db.session.refresh(user)
    db.session.expire(user, ["photos"])
    delete_upload_files(old_gallery_filenames)
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
    )


def is_admin_user(user):
    return bool(getattr(user, "is_admin", False))


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
        if not is_admin_user(current_user):
            if request.path.startswith("/api/"):
                return jsonify({"success": False, "error": "Area riservata agli amministratori."}), 403
            flash("Area riservata agli amministratori.", "error")
            return redirect(url_for("dashboard"))
        return f(*args, **kwargs)
    return decorated_function


def require_complete_profile_json():
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
    """Normalizza un recapito telefonico per un uso futuro in chat/WhatsApp."""
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
    """Crea un link WhatsApp diretto solo se entrambi gli utenti hanno un recapito valido."""
    if not sender_user or not recipient_user or not offer:
        return ""
    if not getattr(sender_user, "numero_telefono", None) or not getattr(recipient_user, "numero_telefono", None):
        return ""

    recipient_digits = phone_to_whatsapp_digits(recipient_user.numero_telefono)
    if not recipient_digits:
        return ""

    tipo_pasto_label = dict(TIPI_PASTO).get(offer.tipo_pasto, offer.tipo_pasto).lower()
    message = (
        f"Ciao {recipient_user.nome}, sono {sender_user.nome} da ApprofittOffro. "
        f"Ti scrivo per il {tipo_pasto_label} da {offer.nome_locale} del "
        f"{offer.data_ora.strftime('%d/%m/%Y alle %H:%M')}."
    )
    return f"https://wa.me/{recipient_digits}?text={quote(message)}"


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
    raw_address = str(address_text or "").strip()
    if not raw_address:
        return ""

    parts = [part.strip() for part in raw_address.split(",") if part.strip()]
    if len(parts) >= 2:
        return parts[-1]
    return raw_address


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
        "uses_google_auth": bool(user.google_sub) if include_private else False,
        "can_change_password": user_can_change_password(user) if include_private else False,
        "followers_count": user.followers_count,
        "following_count": user.following_count,
        "rating_average": rating_info["average"],
        "rating_count": rating_info["count"],
        "is_following": is_following,
        "is_self": is_self,
    }
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
        "verificato": bool(user.verificato),
        "is_admin": bool(user.is_admin),
        "created_at": user.created_at.isoformat() if user.created_at else "",
        "offers_count": len(user.offerte),
        "claims_count": len(user.claims),
        "reviews_count": len(user.reviews_ricevute),
        "rating_average": rating_info["average"],
        "rating_count": rating_info["count"],
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
        and (offer.user_id == user.id or is_admin_user(user))
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
        offer.foto_locale
        for offer in owned_offers
        if getattr(offer, "foto_locale", None)
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
        offer.foto_locale
        for offer in owned_offers
        if getattr(offer, "foto_locale", None)
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

        # Controlla email duplicata
        if User.query.filter_by(email=email).first():
            errors.append("Questa email è già registrata.")

        # Controlla foto
        foto_files = extract_uploaded_photos("foto")
        if not foto_files:
            errors.append("Carica almeno una foto profilo.")

        if errors:
            return jsonify({"success": False, "errors": errors}), 400

        photo_filenames, photo_errors = save_profile_gallery_files("new", foto_files, require_primary_face=True)
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
            verificato=False,
            verification_token=token_verifica
        )
        user.set_password(password)

        db.session.add(user)
        db.session.flush()
        replace_user_gallery(user, photo_filenames)
        db.session.commit()

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
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    user = User.query.filter_by(email=email).first()

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
    tipo = request.args.get("tipo", "")
    radius_str = request.args.get("radius", "")
    limit_str = request.args.get("limit", "").strip()
    now = local_now()
    threshold = now - timedelta(hours=3)
    query = Offer.query.options(
        selectinload(Offer.autore).selectinload(User.photos),
        selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
    ).filter(
        Offer.stato.in_(["attiva", "completata"]),
        Offer.data_ora > threshold,
    )

    if tipo:
        query = query.filter(Offer.tipo_pasto == tipo)

    offers = query.order_by(Offer.data_ora.asc()).all()

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
        
        # Scarta l'offerta se si trova oltre il raggio specificato dal filtro
        if radius_km is not None:
            if dist > radius_km:
                continue

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

        result.append({
            "id": o.id,
            "tipo_pasto": o.tipo_pasto,
            "nome_locale": o.nome_locale,
            "indirizzo": o.indirizzo,
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
            "foto_locale": getattr(o, "foto_locale", "nessuna.jpg"),
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
            "partecipanti": [
                {
                    "id": claim.utente.id,
                    "nome": claim.utente.nome,
                    "foto": claim.utente.foto_filename,
                    "whatsapp_link": build_whatsapp_offer_link(current_user, claim.utente, o)
                    if current_user.is_authenticated and is_own
                    else "",
                }
                for claim in accepted_claims
                if claim.utente
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
            from sqlalchemy import or_
            offers_query = offers_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()
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
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
            from sqlalchemy import or_
            claims_query = claims_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
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

    remove_offer_with_notifications(
        offer,
        motivazione,
        acting_admin=current_user if is_admin_user(current_user) else None,
        notify_owner=is_admin_user(current_user) and offer.user_id != current_user.id,
        preserve_review_history=is_admin_user(current_user),
    )
    db.session.commit()
    
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
    if not is_admin_user(current_user):
        return redirect(url_for("index"))
    if not can_manage_offer(offer, current_user):
        flash("Non puoi modificare le offerte altrui.", "error")
        return redirect(url_for("dashboard"))
    allow_admin_timing_bypass = is_admin_user(current_user) and request.args.get("from") == "admin"
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
    foto_locale = request.files.get("foto_locale")
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
    if not descrizione or len(descrizione) < 30:
        errors.append("La descrizione è obbligatoria e deve contenere almeno 30 caratteri.")

    if foto_locale and foto_locale.filename:
        if not allowed_file(foto_locale.filename):
            errors.append("Formato foto non valido (usa JPG, PNG o WEBP).")

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
        (not is_admin_user(current_user))
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

    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        filename = f"offer_{offer.user_id}_{int(datetime.now().timestamp())}.{ext}"
        offer.foto_locale = process_image(foto_locale, filename)

    offer.tipo_pasto = tipo_pasto
    offer.nome_locale = nome_locale
    offer.indirizzo = indirizzo
    offer.telefono_locale = telefono_locale
    offer.latitudine = float(lat)
    offer.longitudine = float(lon)
    
    diff_posti = requested_posti - offer.posti_totali
    offer.posti_totali = requested_posti
    offer.posti_disponibili = max(0, offer.posti_disponibili + diff_posti)
    
    offer.data_ora = data_ora
    offer.booking_lead_override_minutes = (
        get_short_notice_booking_lead_minutes_for_meal_type(tipo_pasto)
        if requires_short_notice_override
        else None
    )
    offer.descrizione = descrizione

    db.session.commit()
    notify_claimants_for_offer_update(offer, previous_state, current_user)
    return jsonify({"success": True, "message": "Offerta aggiornata con successo!", "offer_id": offer.id})


@app.route("/api/offers/<int:offer_id>/archive", methods=["POST"])
@login_required
def api_archive_offer(offer_id):
    """Archivia un'offerta passata da parte dell'host."""
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

    tipo_pasto = request.form.get("tipo_pasto", "")
    nome_locale = request.form.get("nome_locale", "").strip()
    indirizzo = request.form.get("indirizzo", "").strip()
    telefono_locale = request.form.get("telefono_locale", "").strip()
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    posti = request.form.get("posti_totali")
    data_ora_str = request.form.get("data_ora", "")
    descrizione = request.form.get("descrizione", "").strip()
    foto_locale = request.files.get("foto_locale")
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
    if not descrizione or len(descrizione) < 30:
        errors.append("La descrizione è obbligatoria e deve contenere almeno 30 caratteri.")
    if foto_locale and foto_locale.filename:
        if not allowed_file(foto_locale.filename):
            errors.append("Formato foto non valido (usa JPG, PNG o WEBP).")

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

    # Salvataggio Immagine locale (opzionale)
    filename = 'nessuna.jpg'
    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        temp_filename = f"offer_{current_user.id}_{int(datetime.now().timestamp())}.{ext}"
        filename = process_image(foto_locale, temp_filename)

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
    db.session.commit()
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
        if relation.follower and not is_admin_user(relation.follower)
    ]
    following = [
        relation.followed
        for relation in sorted(
            current_user.following_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.followed and not is_admin_user(relation.followed)
    ]
    met_users = get_met_users_for_user(current_user)
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

    return jsonify({
        "success": True,
        "user": user_payload,
    })


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

    req_lat = (request.args.get("lat") or "").strip()
    req_lon = (request.args.get("lon") or "").strip()
    search_lat = current_user.latitudine or DEFAULT_USER_LATITUDE
    search_lon = current_user.longitudine or DEFAULT_USER_LONGITUDE
    if req_lat and req_lon:
        try:
            search_lat = float(req_lat.replace(",", "."))
            search_lon = float(req_lon.replace(",", "."))
        except ValueError:
            return jsonify({
                "success": False,
                "error": "Le coordinate community non sono valide.",
            }), 400

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
    if radius_km is not None:
        people = [
            person
            for person in people
            if person.latitudine is not None
            and person.longitudine is not None
            and calculate_distance(
                search_lat,
                search_lon,
                person.latitudine,
                person.longitudine,
            ) <= radius_km
        ]
    followed_user_ids = get_followed_user_ids(current_user.id)

    return jsonify({
        "success": True,
        "selected_age_range": selected_age_range,
        "selected_gender": selected_gender,
        "selected_radius": radius_km,
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

    user = User.query.options(selectinload(User.photos)).filter(
        User.id == user_id,
        User.is_admin.is_(False),
    ).first_or_404()

    followed_user_ids = get_followed_user_ids(current_user.id)
    followers = [
        relation.follower
        for relation in sorted(
            user.followers_rel,
            key=lambda item: item.created_at or datetime.min,
            reverse=True,
        )
        if relation.follower and not is_admin_user(relation.follower)
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

    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi seguire te stesso."}), 400
    if user.is_admin:
        return jsonify({"success": False, "error": "Non puoi seguire un amministratore."}), 400

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

    return jsonify({
        "success": True,
        "stats": {
            "users": len(users),
            "admins": admins_count,
            "future_offers": len(upcoming_offers),
            "past_offers": len(past_offers),
        },
        "users": [
            serialize_admin_user_summary(user)
            for user in users
        ],
        "future_offers": [
            serialize_admin_offer_summary(offer)
            for offer in upcoming_offers
        ],
        "past_offers": [
            serialize_admin_offer_summary(offer)
            for offer in past_offers
        ],
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

    data = request.get_json(silent=True) or {}
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
        foto_files=[],
        require_primary_face=False,
    )
    if errors:
        delete_upload_files(payload.get("uploaded_gallery_filenames", []))
        return jsonify({"success": False, "errors": errors}), 400

    verified_value = bool(data.get("verificato", user.verificato))
    success, save_errors, _ = save_profile_update_for_user(
        user,
        payload,
        verified=verified_value,
    )
    if not success:
        return jsonify({"success": False, "errors": save_errors}), 400

    return jsonify({
        "success": True,
        "message": f"Profilo di {user.nome} aggiornato con successo.",
        "user": serialize_admin_user_detail(user),
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
        "primary_photo_url": url_for(
            "uploaded_file",
            filename=current_user.gallery_filenames[0],
            _external=False,
        ) if current_user.gallery_filenames else "",
    })


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
    if app.config["UPLOAD_STORAGE_BACKEND"] == "local":
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
            abort(404)

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
