"""
Modelli database per ApprofittOffro.
Definisce le tabelle User, Offer e Claim.
"""

from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, timezone

db = SQLAlchemy()

# Fasce d'età disponibili
FASCE_ETA = [
    ("18-25", "18-25 anni"),
    ("26-35", "26-35 anni"),
    ("36-45", "36-45 anni"),
    ("46-55", "46-55 anni"),
    ("56-65", "56-65 anni"),
    ("65+", "65+ anni"),
]

SESSI_UTENTE = [
    ("maschio", "Maschio"),
    ("femmina", "Femmina"),
    ("non_dico", "Preferisco non dirlo"),
]

# Tipi di pasto
TIPI_PASTO = [
    ("colazione", "Colazione"),
    ("pranzo", "Pranzo"),
    ("cena", "Cena"),
    ("ape", "Aperitivo"),
]

CLAIM_STATUS_PENDING = "pending"
CLAIM_STATUS_ACCEPTED = "accepted"
CLAIM_STATUS_REJECTED = "rejected"


class User(UserMixin, db.Model):
    """Utente registrato."""
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(150), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    google_sub = db.Column(db.String(255), unique=True, nullable=True)
    foto_filename = db.Column(db.String(256), nullable=False)
    fascia_eta = db.Column(db.String(10), nullable=False)
    eta = db.Column(db.Integer, nullable=True)
    sesso = db.Column(db.String(20), nullable=True, default="non_dico")
    numero_telefono = db.Column(db.String(32), nullable=True)
    latitudine = db.Column(db.Float, nullable=False)
    longitudine = db.Column(db.Float, nullable=False)
    citta = db.Column(db.String(200), nullable=True) # Aggiunta colonna mancante per l'indirizzo testuale
    cibi_preferiti = db.Column(db.String(300), nullable=True) # Aggiunta per Profilazione
    intolleranze = db.Column(db.String(300), nullable=True) # Aggiunta per Profilazione
    bio = db.Column(db.String(500), nullable=True) # Aggiunta bio per Profilazione
    raggio_azione = db.Column(db.Integer, default=10, nullable=True) # KM raggio di spostamento

    verificato = db.Column(db.Boolean, default=False)
    verification_token = db.Column(db.String(100), unique=True, nullable=True)
    password_reset_token = db.Column(db.String(100), unique=True, nullable=True)
    password_reset_sent_at = db.Column(db.DateTime, nullable=True)
    is_admin = db.Column(db.Boolean, default=False, nullable=False)
    admin_verified_notified_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Relazioni
    offerte = db.relationship("Offer", backref="autore", lazy=True)
    claims = db.relationship("Claim", backref="utente", lazy=True)
    photos = db.relationship(
        "UserPhoto",
        backref="user",
        lazy=True,
        cascade="all, delete-orphan",
        order_by="UserPhoto.position.asc()",
    )
    following_rel = db.relationship(
        "UserFollow",
        foreign_keys="UserFollow.follower_id",
        backref="follower",
        lazy=True,
        cascade="all, delete-orphan",
    )
    followers_rel = db.relationship(
        "UserFollow",
        foreign_keys="UserFollow.followed_id",
        backref="followed",
        lazy=True,
        cascade="all, delete-orphan",
    )
    push_tokens = db.relationship(
        "DevicePushToken",
        backref="user",
        lazy=True,
        cascade="all, delete-orphan",
    )

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    @property
    def uses_google_auth(self):
        return bool(self.google_sub)

    @property
    def eta_display(self):
        """Età leggibile con fallback ai vecchi profili a fasce."""
        if self.eta is not None:
            return str(self.eta)
        return self.fascia_eta

    @property
    def gallery_filenames(self):
        photos = [photo.filename for photo in sorted(self.photos, key=lambda item: item.position)]
        if photos:
            return photos
        return [self.foto_filename] if self.foto_filename else []

    @property
    def followers_count(self):
        return len(self.followers_rel)

    @property
    def following_count(self):
        return len(self.following_rel)

    def __repr__(self):
        return f"<User {self.nome} ({self.email})>"


class Offer(db.Model):
    """Offerta di un pasto (colazione, pranzo, cena)."""
    __tablename__ = "offers"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    tipo_pasto = db.Column(db.String(20), nullable=False)  # colazione, pranzo, cena
    nome_locale = db.Column(db.String(200), nullable=False)
    indirizzo = db.Column(db.String(300), nullable=False)
    telefono_locale = db.Column(db.String(50), nullable=True)
    latitudine = db.Column(db.Float, nullable=False)
    longitudine = db.Column(db.Float, nullable=False)
    posti_totali = db.Column(db.Integer, nullable=False)
    posti_disponibili = db.Column(db.Integer, nullable=False)
    data_ora = db.Column(db.DateTime, nullable=False)
    booking_lead_override_minutes = db.Column(db.Integer, nullable=True)
    descrizione = db.Column(db.Text, nullable=True)
    foto_locale = db.Column(db.String(256), nullable=False)
    stato = db.Column(db.String(20), default="attiva")  # attiva, completata, annullata, archiviata
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Relazioni
    claims = db.relationship("Claim", backref="offerta", lazy=True)

    @property
    def is_disponibile(self):
        """Controlla se l'offerta ha ancora posti disponibili e non è scaduta."""
        now = datetime.now()
        return (
            self.stato == "attiva"
            and self.posti_disponibili > 0
            and self.data_ora > now
        )

    def __repr__(self):
        return f"<Offer {self.tipo_pasto} @ {self.nome_locale} ({self.posti_disponibili}/{self.posti_totali})>"


class UserPhoto(db.Model):
    """Foto profilo dell'utente (la prima resta la foto principale)."""
    __tablename__ = "user_photos"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    filename = db.Column(db.String(256), nullable=False)
    position = db.Column(db.Integer, default=0, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.now)

    def __repr__(self):
        return f"<UserPhoto user={self.user_id} position={self.position}>"


class UserFollow(db.Model):
    """Relazione follower -> seguito fra utenti."""
    __tablename__ = "user_follows"

    id = db.Column(db.Integer, primary_key=True)
    follower_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    followed_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.now)

    __table_args__ = (
        db.UniqueConstraint("follower_id", "followed_id", name="unique_user_follow"),
    )

    def __repr__(self):
        return f"<UserFollow follower={self.follower_id} followed={self.followed_id}>"


class DevicePushToken(db.Model):
    """Token push registrato da un dispositivo mobile."""
    __tablename__ = "device_push_tokens"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    token = db.Column(db.String(512), unique=True, nullable=False)
    platform = db.Column(db.String(32), nullable=False, default="android")
    device_label = db.Column(db.String(160), nullable=True)
    active = db.Column(db.Boolean, nullable=False, default=True)
    last_seen_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.now)

    def __repr__(self):
        return f"<DevicePushToken user={self.user_id} platform={self.platform} active={self.active}>"


class NotificationDeliveryLog(db.Model):
    """Registro dei reminder/notifiche schedulate gia' inviate, per evitare duplicati."""
    __tablename__ = "notification_delivery_logs"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    offer_id = db.Column(db.Integer, db.ForeignKey("offers.id"), nullable=False)
    reminder_type = db.Column(db.String(64), nullable=False)
    dedupe_key = db.Column(db.String(255), unique=True, nullable=False)
    sent_at = db.Column(db.DateTime, default=datetime.now, nullable=False)

    def __repr__(self):
        return (
            f"<NotificationDeliveryLog user={self.user_id} "
            f"offer={self.offer_id} type={self.reminder_type}>"
        )


class Claim(db.Model):
    """Registra quando un utente approfitta di un'offerta."""
    __tablename__ = "claims"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    offer_id = db.Column(db.Integer, db.ForeignKey("offers.id"), nullable=False)
    status = db.Column(db.String(20), nullable=False, default=CLAIM_STATUS_ACCEPTED)
    hidden_by_guest = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Vincolo: un utente può approfittare una sola volta per offerta
    __table_args__ = (
        db.UniqueConstraint("user_id", "offer_id", name="unique_claim"),
    )

    def __repr__(self):
        return f"<Claim user={self.user_id} offer={self.offer_id}>"


class Review(db.Model):
    """Recensione lasciata da un partecipante all'host di un pasto."""
    __tablename__ = "reviews"

    id = db.Column(db.Integer, primary_key=True)
    reviewer_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    reviewed_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    offer_id = db.Column(db.Integer, db.ForeignKey("offers.id"), nullable=False)
    rating = db.Column(db.Integer, nullable=False)  # da 1 a 5
    commento = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Relazioni
    # reviewer = chi scrive, reviewed = chi riceve (l'host)
    reviewer = db.relationship("User", foreign_keys=[reviewer_id], backref="reviews_scritte")
    reviewed = db.relationship("User", foreign_keys=[reviewed_id], backref="reviews_ricevute")
    offerta = db.relationship("Offer", backref="reviews")

    def __repr__(self):
        return f"<Review from={self.reviewer_id} to={self.reviewed_id} rating={self.rating}>"
