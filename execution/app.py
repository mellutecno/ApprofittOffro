"""
ApprofittOffro — Server Flask principale.
Applicazione web per offrire e approfittare di pasti.
"""

import os
import uuid
import math
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from functools import wraps

from dotenv import load_dotenv
from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    jsonify,
    session,
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
from PIL import Image

from models import db, User, Offer, Claim, Review, TIPI_PASTO, FASCE_ETA, UserPhoto, UserFollow
from verify_photo import verifica_volto

# ---------------------------------------------------------------------------
# Configurazione
# ---------------------------------------------------------------------------
EXECUTION_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(EXECUTION_DIR)


def load_app_env():
    """Carica il primo file .env disponibile, con override via APP_ENV_FILE."""
    env_candidates = [
        os.getenv("APP_ENV_FILE"),
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
app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv(
    "DATABASE_URL",
    "sqlite:///" + SQLITE_PATH,
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["MAX_CONTENT_LENGTH"] = 64 * 1024 * 1024  # 64 MB max upload (telefoni moderni)

os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}
MAX_PROFILE_PHOTOS = 5
BREAKFAST_BOOKING_LEAD_HOURS = 1
MEAL_BOOKING_LEAD_HOURS = 6
USER_SESSION_IDLE_TIMEOUT_MINUTES = 60
ADMIN_SESSION_IDLE_TIMEOUT_MINUTES = 30
REVIEW_EDIT_WINDOW_HOURS = 24


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


def get_offer_booking_deadline(offer):
    """Calcola il momento oltre il quale non si puo' piu' approfittare dell'offerta."""
    return offer.data_ora - timedelta(hours=get_offer_booking_lead_hours(offer))


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


def get_same_day_offer_conflict(user_id, tipo_pasto, data_ora, exclude_offer_id=None):
    """Trova un'altra offerta dello stesso utente, stesso pasto e stessa data."""
    day_start = data_ora.replace(hour=0, minute=0, second=0, microsecond=0)
    next_day = day_start + timedelta(days=1)

    query = Offer.query.filter(
        Offer.user_id == user_id,
        Offer.tipo_pasto == tipo_pasto,
        Offer.stato != "annullata",
        Offer.data_ora >= day_start,
        Offer.data_ora < next_day,
    )

    if exclude_offer_id is not None:
        query = query.filter(Offer.id != exclude_offer_id)

    return query.order_by(Offer.data_ora.asc()).first()


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


def notify_followers_for_new_offer(offer):
    """Invia una mail ai profili che seguono l'autore quando nasce una nuova offerta."""
    if offer.data_ora <= local_now():
        return 0

    followers = get_followers_notification_targets(offer)
    if not followers:
        return 0

    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    booking_rule_copy = (
        "Le colazioni si possono approfittare fino a 1 ora prima."
        if offer.tipo_pasto == "colazione"
        else "Pranzi e cene si possono approfittare fino a 6 ore prima."
    )
    meal_label = get_meal_type_label(offer.tipo_pasto)
    spots_copy = get_spots_copy(offer.posti_disponibili)

    for follower in followers:
        send_email(
            get_followed_offer_notification_subject(offer),
            [follower.email],
            "nearby_offer_notification.html",
            user=follower,
            offer=offer,
            autore=offer.autore,
            notification_heading=get_followed_offer_notification_heading(offer),
            meal_label=meal_label,
            data_evento=data_evento,
            spots_copy=spots_copy,
            booking_rule_copy=booking_rule_copy,
        )

    return len(followers)


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


def notify_claimants_for_offer_update(offer, previous_state, actor):
    """Avvisa i partecipanti quando un'offerta gia' prenotata viene modificata."""
    changes = get_offer_update_changes(previous_state, offer)
    if not changes:
        return 0

    claims = Claim.query.filter_by(offer_id=offer.id).all()
    if not claims:
        return 0

    data_evento = offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
    actor_name = actor.nome if actor else offer.autore.nome

    notified = 0
    for claim in claims:
        if not claim.utente.email:
            continue
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
                ("citta", "ALTER TABLE users ADD COLUMN citta VARCHAR(200)"),
                ("cibi_preferiti", "ALTER TABLE users ADD COLUMN cibi_preferiti VARCHAR(300)"),
                ("intolleranze", "ALTER TABLE users ADD COLUMN intolleranze VARCHAR(300)"),
                ("bio", "ALTER TABLE users ADD COLUMN bio VARCHAR(500)"),
                ("raggio_azione", "ALTER TABLE users ADD COLUMN raggio_azione INTEGER DEFAULT 10"),
                ("verificato", "ALTER TABLE users ADD COLUMN verificato INTEGER DEFAULT 0"),
                ("verification_token", "ALTER TABLE users ADD COLUMN verification_token VARCHAR(100)"),
                ("is_admin", "ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0"),
            ],
            "offers": [
                ("foto_locale", "ALTER TABLE offers ADD COLUMN foto_locale VARCHAR(256)"),
                ("stato", "ALTER TABLE offers ADD COLUMN stato VARCHAR(20) DEFAULT 'attiva'"),
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

        conn.commit()
    finally:
        conn.close()


if app.config["SQLALCHEMY_DATABASE_URI"].startswith("sqlite:///"):
    ensure_legacy_sqlite_compatibility(SQLITE_PATH)

# --- Email Config (Motore Flask-Mail) ---
app.config['MAIL_SERVER'] = 'smtp.gmail.com'
app.config['MAIL_PORT'] = 587
app.config['MAIL_USE_TLS'] = True
app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME', '')
app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD', '')
app.config['MAIL_DEFAULT_SENDER'] = os.getenv('MAIL_DEFAULT_SENDER', os.getenv('MAIL_USERNAME', ''))

from flask_mail import Mail, Message
from threading import Thread

mail = Mail(app)

def send_async_email(app, msg):
    with app.app_context():
        try:
            mail.send(msg)
            print(f"[MAIL_INVIATA] Inviata con successo a: {msg.recipients[0]}")
        except Exception as e:
            print(f"[MAIL_ERRORE] Impossibile inviare a: {msg.recipients[0]}: {e}")

def send_email(subject, recipients, template, **kwargs):
    """Renderizza e invia un'email in background."""
    try:
        html_body = render_template(f"emails/{template}", **kwargs)
        msg = Message(subject, recipients=recipients)
        msg.html = html_body
        Thread(target=send_async_email, args=(app, msg)).start()
    except Exception as e:
        print(f"[MAIL_ERROR] Errore preparazione email {template}: {e}")

def process_image(file_storage, filename, size=(800, 800)):
    """Salva, ruota (EXIF) e ridimensiona un'immagine."""
    path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
    file_storage.save(path)
    try:
        from PIL import ImageOps
        img = Image.open(path)
        img = ImageOps.exif_transpose(img)
        if img.mode != 'RGB':
            img = img.convert('RGB')
        img.thumbnail(size, Image.LANCZOS)
        # Se vogliamo forzare JPG per risparmiare spazio
        if not filename.lower().endswith(".jpg"):
            new_filename = filename.rsplit(".", 1)[0] + ".jpg"
            new_path = os.path.join(app.config["UPLOAD_FOLDER"], new_filename)
            img.save(new_path, "JPEG", quality=85)
            if path != new_path:
                os.remove(path)
            return new_filename
        else:
            img.save(path, quality=85)
            return filename
    except Exception as e:
        print(f"[IMAGE_ERROR] Errore processamento {filename}: {e}")
        return filename

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
        path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
        if os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass


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
        filename = process_image(photo, f"user_{user_key}_{uuid.uuid4().hex[:10]}.{ext}")
        saved_filenames.append(filename)

        if index == 0 and require_primary_face:
            foto_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
            verifica = verifica_volto(foto_path)
            if not verifica["valida"]:
                delete_upload_files(saved_filenames)
                dettaglio = verifica.get("errore", "Il volto non e stato riconosciuto in modo affidabile.")
                return [], [
                    "La prima foto deve mostrare chiaramente il volto della persona. "
                    "Carica come prima immagine una foto reale, frontale o comunque ben visibile. "
                    f"Dettaglio: {dettaglio}"
                ]

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
    return old_filenames


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
    eta_raw = source.get(
        "eta",
        user.eta if user.eta is not None else user.fascia_eta,
    )
    lat_raw = str(source.get("latitudine", "") or "").strip()
    lon_raw = str(source.get("longitudine", "") or "").strip()
    citta = str(source.get("citta", user.citta or "") or "").strip()
    pref = str(source.get("cibi_preferiti", user.cibi_preferiti or "") or "").strip()
    intoll = str(source.get("intolleranze", user.intolleranze or "") or "").strip()
    bio = str(source.get("bio", user.bio or "") or "").strip()

    errors = []
    if not nome:
        errors.append("Il nome non può essere vuoto.")
    if not email or "@" not in email:
        errors.append("Inserisci un'email valida.")

    eta, eta_error = parse_age_value(eta_raw)
    if eta_error:
        errors.append(eta_error)

    existing_user = User.query.filter_by(email=email).first()
    if email != user.email and existing_user and existing_user.id != user.id:
        errors.append("Questa email è già associata a un altro account.")

    if len(pref) > 0 and len(pref) < 3:
        errors.append("Quali sono i tuoi cibi preferiti? Scrivi qualcosa in più.")
    if len(bio) > 0 and len(bio) < 5:
        errors.append("Raccontaci qualcosa di più nella Bio.")

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
            require_primary_face=require_primary_face,
        )
        errors.extend(photo_errors)

    payload = {
        "nome": nome,
        "email": email,
        "eta": eta if not eta_error else None,
        "citta": citta,
        "latitudine": latitudine,
        "longitudine": longitudine,
        "cibi_preferiti": pref,
        "intolleranze": intoll,
        "bio": bio,
        "uploaded_gallery_filenames": uploaded_gallery_filenames,
    }

    return payload, errors


def save_profile_update_for_user(user, payload, *, verified=None):
    old_gallery_filenames = []
    uploaded_gallery_filenames = payload.get("uploaded_gallery_filenames", [])

    user.nome = payload["nome"]
    user.email = payload["email"]
    user.fascia_eta = str(payload["eta"])
    user.eta = payload["eta"]
    user.citta = payload["citta"]
    if payload["latitudine"] is not None and payload["longitudine"] is not None:
        user.latitudine = payload["latitudine"]
        user.longitudine = payload["longitudine"]

    user.cibi_preferiti = payload["cibi_preferiti"]
    user.intolleranze = payload["intolleranze"]
    user.bio = payload["bio"]

    if verified is not None:
        user.verificato = bool(verified)

    if uploaded_gallery_filenames:
        old_gallery_filenames = replace_user_gallery(user, uploaded_gallery_filenames)

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


def profile_completed_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if current_user.is_authenticated:
            if is_admin_user(current_user):
                return f(*args, **kwargs)
            if not is_profile_complete(current_user):
                flash("Ciao! Completa il tuo identikit alimentare e la tua bio: sono obbligatori per poter pubblicare offerte, partecipare ai pasti e vedere i profili completi. 🍽️", "warning")
                return redirect(url_for('profile_page'))
        return f(*args, **kwargs)
    return decorated_function


def is_profile_complete(user):
    return bool(user.cibi_preferiti and user.intolleranze and user.bio)


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
            "error": "Completa il profilo prima di partecipare o pubblicare offerte.",
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

# ===================================================================
# PAGINE (Template)
# ===================================================================

@app.route("/")
def index():
    return redirect(url_for("dashboard"))

@app.route("/register")
def register_page():
    return render_template("register.html")

@app.route("/login")
def login_page():
    return render_template("index.html")

@app.route("/dashboard")
def dashboard():
    if current_user.is_authenticated and is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))

    is_authenticated = current_user.is_authenticated
    pending_review_reminders = (
        get_pending_review_reminders(current_user)
        if is_authenticated
        else []
    )
    has_user_location = (
        is_authenticated
        and current_user.latitudine is not None
        and current_user.longitudine is not None
    )
    default_lat = (
        current_user.latitudine
        if is_authenticated and current_user.latitudine is not None
        else 41.9
    )
    default_lon = (
        current_user.longitudine
        if is_authenticated and current_user.longitudine is not None
        else 12.5
    )
    can_participate = is_authenticated and is_profile_complete(current_user)

    return render_template(
        "dashboard.html",
        tipi_pasto=TIPI_PASTO,
        is_authenticated=is_authenticated,
        can_participate=can_participate,
        has_user_location=has_user_location,
        default_lat=default_lat,
        default_lon=default_lon,
        pending_review_reminders=pending_review_reminders,
        format_offer_datetime_label=format_offer_datetime_label,
    )


@app.route("/people")
@login_required
@profile_completed_required
def people_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))

    selected_age_range, parsed_age_range, age_range_error = parse_age_range_filter(
        request.args.get("age_range")
    )

    if age_range_error:
        flash(age_range_error, "error")

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

    people = people_query.order_by(User.eta.asc(), User.nome.asc()).all()
    followed_user_ids = get_followed_user_ids(current_user.id)

    return render_template(
        "people.html",
        people=people,
        extract_city_label=extract_city_label,
        age_ranges=FASCE_ETA,
        selected_age_range=selected_age_range,
        followed_user_ids=followed_user_ids,
    )


@app.route("/admin")
@admin_required
def admin_dashboard():
    now = local_now()
    all_offers = Offer.query.order_by(Offer.data_ora.desc()).all()
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

    # Notifica Amministratore
    admin_email = os.getenv("ADMIN_EMAIL")
    if admin_email:
        send_email(
            subject=f"Nuovo Utente Verificato: {user.nome}",
            recipients=[admin_email],
            template="new_user_notification.html",
            user=user
        )
    
    flash("Email verificata con successo! Ora puoi accedere.", "success")
    return redirect(url_for("login_page"))

@app.route("/new-offer")
@login_required
@profile_completed_required
def new_offer_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))
    return render_template("create_offer.html", tipi_pasto=TIPI_PASTO, allow_admin_timing_bypass=False)


@app.route("/profile")
@login_required
def profile_page():
    if is_admin_user(current_user):
        return redirect(url_for("admin_dashboard"))

    my_offers = Offer.query.filter_by(user_id=current_user.id).order_by(
        Offer.created_at.desc()
    ).all()
    my_claims = Claim.query.filter_by(user_id=current_user.id).order_by(
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
        for c in o.claims:
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
    )

def get_user_rating(user_id):
    """Calcola la media delle recensioni per un utente."""
    reviews = Review.query.filter_by(reviewed_id=user_id).all()
    if not reviews:
        return {"average": 0, "count": 0}
    avg = sum(r.rating for r in reviews) / len(reviews)
    return {"average": round(avg, 1), "count": len(reviews)}


def get_pending_review_reminders(user, now=None):
    """Restituisce le interazioni concluse da recensire, sia da ospite che da host."""
    if not user or not getattr(user, "is_authenticated", False):
        return []

    now = now or local_now()
    threshold = now - timedelta(hours=3)
    reminders = []
    seen_pairs = set()

    my_claims = Claim.query.filter_by(user_id=user.id).order_by(Claim.created_at.desc()).all()
    for claim in my_claims:
        offer = claim.offerta
        if not offer or offer.stato == "annullata" or offer.data_ora > threshold:
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
        })

    my_offers = Offer.query.filter_by(user_id=user.id).order_by(Offer.data_ora.desc()).all()
    for offer in my_offers:
        if offer.stato == "annullata" or offer.data_ora > threshold:
            continue

        for claim in offer.claims:
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
            })

    reminders.sort(key=lambda item: item["offer"].data_ora, reverse=True)
    return reminders


def can_edit_review(review, now=None):
    """Permette di correggere una recensione solo entro una finestra limitata."""
    if not review:
        return False
    now = now or local_now()
    return review.created_at + timedelta(hours=REVIEW_EDIT_WINDOW_HOURS) > now


def can_manage_offer(offer, user):
    return bool(
        user.is_authenticated
        and (offer.user_id == user.id or is_admin_user(user))
    )


def remove_offer_with_notifications(offer, motivazione, acting_admin=None, notify_owner=False):
    """Elimina un'offerta, avvisando i partecipanti e opzionalmente l'host."""
    claims = Claim.query.filter_by(offer_id=offer.id).all()
    data_evento = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')
    motivazione = motivazione.strip() or "Nessuna motivazione specificata."

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

    if notify_owner and acting_admin and offer.autore.email:
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
    delete_upload_files(gallery_files)

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

@app.route("/profile/<int:user_id>")
@login_required
@profile_completed_required
def public_profile(user_id):
    """Schermata pubblica dove visito le preferenze di un utente che dona cibo."""
    from models import Review, Offer, Claim
    user = User.query.get_or_404(user_id)
    rating_info = get_user_rating(user_id)
    reviews = Review.query.filter_by(reviewed_id=user_id).order_by(Review.created_at.desc()).all()
    
    # Statistiche affidabilità
    offerte_totali = Offer.query.filter_by(user_id=user.id).count()
    recuperi_effettuati = Claim.query.filter_by(user_id=user.id).count()

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
            Offer.user_id == user_id,
            Offer.data_ora < threshold
        )
        
        # Caso B: Io ero l'host, lui l'ospite
        meal_as_host = Offer.query.join(Claim).filter(
            Offer.user_id == current_user.id,
            Claim.user_id == user_id,
            Offer.data_ora < threshold
        )
        
        shared_offer, editable_review = first_reviewable_offer(meal_as_guest)
        if not shared_offer:
            shared_offer, editable_review = first_reviewable_offer(meal_as_host)

        # Se non c'è una shared_offer già conclusa, cerchiamo una "pending" (pasto appena avvenuto o in corso)
        if not shared_offer:
            pending_as_guest = Offer.query.join(Claim).filter(
                Claim.user_id == current_user.id,
                Offer.user_id == user_id,
                Offer.data_ora < now,
                Offer.data_ora >= threshold
            ).order_by(Offer.data_ora.desc()).first()
            pending_as_host = Offer.query.join(Claim).filter(
                Offer.user_id == current_user.id,
                Claim.user_id == user_id,
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
        eta_raw = request.form.get("eta", "")
        lat = request.form.get("latitudine")
        lon = request.form.get("longitudine")
        citta = request.form.get("citta", "").strip()
        eta, eta_error = parse_age_value(eta_raw)

        # Validazione campi
        errors = []
        if not nome:
            errors.append("Il nome è obbligatorio.")
        if not email or "@" not in email:
            errors.append("Inserisci un'email valida.")
        if len(password) < 6:
            errors.append("La password deve avere almeno 6 caratteri.")
        if password != conferma_password:
            errors.append("Le due password non coincidono.")
        if eta_error:
            errors.append(eta_error)
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

        # Invio VERA Email in background
        link_verifica = url_for('verify_email', token=token_verifica, _external=True)
        send_email(
            "Benvenuto su ApprofittOffro! Conferma la tua email 🍽️",
            [user.email],
            "verification.html",
            user=user,
            link_verifica=link_verifica
        )

        return jsonify({
            "success": True, 
            "message": "Registrazione completata! Controlla la tua email (o il terminale) per confermare l'account prima di accedere."
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
    if radius_str and radius_str.isdigit():
        radius_km = float(radius_str)

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
        author_rating = get_user_rating(o.autore.id)
        
        # Scarta l'offerta se si trova oltre il raggio specificato dal filtro
        if radius_km is not None:
            if dist > radius_km:
                continue

        # Controlla se l'utente corrente ha già approfittato
        already_claimed = False
        is_own = False
        if current_user.is_authenticated:
            already_claimed = Claim.query.filter_by(
                user_id=current_user.id, offer_id=o.id
            ).first() is not None
            is_own = o.user_id == current_user.id

        result.append({
            "id": o.id,
            "tipo_pasto": o.tipo_pasto,
            "nome_locale": o.nome_locale,
            "indirizzo": o.indirizzo,
            "lat": o.latitudine,
            "lon": o.longitudine,
            "distance_km": round(dist, 1),
            "posti_totali": o.posti_totali,
            "posti_disponibili": o.posti_disponibili,
            "stato": o.stato,
            "data_ora": o.data_ora.isoformat(),
            "booking_deadline": booking_deadline.isoformat(),
            "booking_closed": booking_closed,
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
            "partecipanti": [
                {
                    "id": claim.utente.id,
                    "nome": claim.utente.nome,
                    "foto": claim.utente.foto_filename,
                }
                for claim in o.claims
                if claim.utente
            ],
            "is_own": is_own,
            "already_claimed": already_claimed,
        })

    return jsonify({"success": True, "offers": result})


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
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    posti = request.form.get("posti_totali")
    data_ora_str = request.form.get("data_ora", "")
    descrizione = request.form.get("descrizione", "").strip()
    foto_locale = request.files.get("foto_locale")

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

    conflicting_offer = get_same_day_offer_conflict(
        offer.user_id,
        tipo_pasto,
        data_ora,
        exclude_offer_id=offer.id,
    )
    if conflicting_offer:
        data_conflitto = conflicting_offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
        meal_copy = get_meal_type_copy(tipo_pasto)
        return jsonify({
            "success": False,
            "errors": [
                f"Hai già pubblicato un'offerta di {meal_copy['singular']} per questa data ({data_conflitto}). Non puoi offrire due {meal_copy['plural']} nello stesso giorno."
            ],
        }), 400

    if (not is_admin_user(current_user)) and is_new_offer_publication_too_late(tipo_pasto, data_ora):
        return jsonify({
            "success": False,
            "errors": [get_offer_publication_too_late_message(tipo_pasto)],
        }), 400

    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        filename = f"offer_{offer.user_id}_{int(datetime.now().timestamp())}.{ext}"
        offer.foto_locale = process_image(foto_locale, filename)

    offer.tipo_pasto = tipo_pasto
    offer.nome_locale = nome_locale
    offer.indirizzo = indirizzo
    offer.latitudine = float(lat)
    offer.longitudine = float(lon)
    
    diff_posti = int(posti) - offer.posti_totali
    offer.posti_totali = int(posti)
    offer.posti_disponibili = max(0, offer.posti_disponibili + diff_posti)
    
    offer.data_ora = data_ora
    offer.descrizione = descrizione

    db.session.commit()
    notify_claimants_for_offer_update(offer, previous_state, current_user)
    return jsonify({"success": True, "message": "Offerta aggiornata con successo!", "offer_id": offer.id})


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
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    posti = request.form.get("posti_totali")
    data_ora_str = request.form.get("data_ora", "")
    descrizione = request.form.get("descrizione", "").strip()
    foto_locale = request.files.get("foto_locale")

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

    conflicting_offer = get_same_day_offer_conflict(
        current_user.id,
        tipo_pasto,
        data_ora,
    )
    if conflicting_offer:
        data_conflitto = conflicting_offer.data_ora.strftime("%d/%m/%Y alle %H:%M")
        meal_copy = get_meal_type_copy(tipo_pasto)
        return jsonify({
            "success": False,
            "errors": [
                f"Hai già pubblicato un'offerta di {meal_copy['singular']} per questa data ({data_conflitto}). Non puoi offrire due {meal_copy['plural']} nello stesso giorno."
            ],
        }), 400

    if is_new_offer_publication_too_late(tipo_pasto, data_ora):
        return jsonify({
            "success": False,
            "errors": [get_offer_publication_too_late_message(tipo_pasto)],
        }), 400

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
        latitudine=float(lat),
        longitudine=float(lon),
        posti_totali=int(posti),
        posti_disponibili=int(posti),
        data_ora=data_ora,
        descrizione=descrizione,
        foto_locale=filename
    )

    db.session.add(offer)
    db.session.commit()
    notified_users = notify_followers_for_new_offer(offer)

    message = "Offerta creata con successo!"
    if notified_users == 1:
        message += " Abbiamo avvisato 1 persona che ti segue via email."
    elif notified_users > 1:
        message += f" Abbiamo avvisato {notified_users} persone che ti seguono via email."

    return jsonify({
        "success": True,
        "message": message,
        "offer_id": offer.id,
        "notified_users": notified_users,
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

    # Controlla se ha già approfittato
    existing = Claim.query.filter_by(user_id=current_user.id, offer_id=offer_id).first()
    if existing:
        return jsonify({"success": False, "errors": ["Hai già approfittato di questa offerta."]}), 400

    now = local_now()

    if offer.stato != "attiva" or offer.posti_disponibili <= 0:
        return jsonify({"success": False, "errors": ["Offerta non più disponibile."]}), 400

    if offer.data_ora <= now:
        return jsonify({"success": False, "errors": ["Il pasto è già iniziato o concluso."]}), 400

    if is_offer_booking_closed(offer, now):
        return jsonify({"success": False, "errors": [get_offer_booking_closed_message(offer)]}), 400
    # Crea il claim e decrementa i posti
    claim = Claim(user_id=current_user.id, offer_id=offer_id)
    offer.posti_disponibili -= 1

    if offer.posti_disponibili == 0:
        offer.stato = "completata"

    db.session.add(claim)
    db.session.commit()

    # ---- Invio Email di Notifica ----
    data_formattata = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')
    
    # Email al partecipante (claimer)
    send_email(
        f"🎉 Sei dentro! Hai approfittato di '{offer.nome_locale}'",
        [current_user.email],
        "claim_confirmed.html",
        user=current_user,
        offer=offer,
        data_evento=data_formattata
    )

    # Email all'autore dell'offerta
    send_email(
        f"🔔 Nuova partecipazione a '{offer.nome_locale}'!",
        [offer.autore.email],
        "claim_notification.html",
        user=current_user,
        offer=offer,
        data_evento=data_formattata
    )

    return jsonify({
        "success": True,
        "message": "Hai approfittato dell'offerta!",
        "posti_disponibili": offer.posti_disponibili,
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

    # Email di conferma al partecipante che ha disdetto
    send_email(
        f"✅ Partecipazione annullata: '{offer.nome_locale}'",
        [current_user.email],
        "unclaim_confirmation.html",
        user=current_user,
        offer=offer,
        data_evento=data_formattata
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
    return jsonify({
        "success": True,
        "user": {
            "id": current_user.id,
            "nome": current_user.nome,
            "email": current_user.email,
            "is_admin": is_admin_user(current_user),
            "foto": current_user.foto_filename,
            "eta": current_user.eta,
            "eta_display": current_user.eta_display,
            "lat": current_user.latitudine,
            "lon": current_user.longitudine,
            "citta": current_user.citta,
            "verificato": current_user.verificato,
            "cibi_preferiti": current_user.cibi_preferiti or "",
            "intolleranze": current_user.intolleranze or "",
        },
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
    return jsonify({"success": True, "message": "Comunicazione inviata con successo."})

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
        Claim.query.filter_by(user_id=current_user.id, offer_id=offer_id).first() is not None
        and reviewed_id == offer.user_id
    )
    
    is_host_reviewing_guest = (
        offer.user_id == current_user.id
        and Claim.query.filter_by(user_id=reviewed_id, offer_id=offer_id).first() is not None
    )

    if not is_guest_reviewing_host and not is_host_reviewing_guest:
        return jsonify({"success": False, "error": "Non sei autorizzato a recensire questo utente per questo pasto."}), 403

    # 5. Se la recensione esiste già, può essere corretta solo entro una finestra limitata
    existing = Review.query.filter_by(
        reviewer_id=current_user.id,
        reviewed_id=reviewed_id,
        offer_id=offer_id,
    ).first()
    if existing:
        if not can_edit_review(existing):
            return jsonify({
                "success": False,
                "error": f"Hai già lasciato una recensione per questo utente in questo pasto. Puoi modificarla solo entro {REVIEW_EDIT_WINDOW_HOURS} ore.",
            }), 400

        existing.rating = rating
        existing.commento = commento
        db.session.commit()
        return jsonify({"success": True, "message": "Recensione aggiornata con successo."})

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

    return jsonify({"success": True, "message": "Grazie! La tua recensione è stata pubblicata."})


# ===================================================================
# Servire le foto caricate
# ===================================================================


@app.route("/uploads/<filename>")
def uploaded_file(filename):
    from flask import send_from_directory
    response = send_from_directory(
        app.config["UPLOAD_FOLDER"],
        filename,
        max_age=0,
        conditional=False,
    )
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
