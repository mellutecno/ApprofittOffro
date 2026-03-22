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

# Tipi di pasto
TIPI_PASTO = [
    ("colazione", "Colazione"),
    ("pranzo", "Pranzo"),
    ("cena", "Cena"),
]


class User(UserMixin, db.Model):
    """Utente registrato."""
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    nome = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(150), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    foto_filename = db.Column(db.String(256), nullable=False)
    fascia_eta = db.Column(db.String(10), nullable=False)
    latitudine = db.Column(db.Float, nullable=False)
    longitudine = db.Column(db.Float, nullable=False)
    citta = db.Column(db.String(200), nullable=True) # Aggiunta colonna mancante per l'indirizzo testuale
    cibi_preferiti = db.Column(db.String(300), nullable=True) # Aggiunta per Profilazione
    intolleranze = db.Column(db.String(300), nullable=True) # Aggiunta per Profilazione
    bio = db.Column(db.String(500), nullable=True) # Aggiunta bio per Profilazione
    raggio_azione = db.Column(db.Integer, default=10, nullable=True) # KM raggio di spostamento

    verificato = db.Column(db.Boolean, default=False)
    verification_token = db.Column(db.String(100), unique=True, nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Relazioni
    offerte = db.relationship("Offer", backref="autore", lazy=True)
    claims = db.relationship("Claim", backref="utente", lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

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
    latitudine = db.Column(db.Float, nullable=False)
    longitudine = db.Column(db.Float, nullable=False)
    posti_totali = db.Column(db.Integer, nullable=False)
    posti_disponibili = db.Column(db.Integer, nullable=False)
    data_ora = db.Column(db.DateTime, nullable=False)
    descrizione = db.Column(db.Text, nullable=True)
    foto_locale = db.Column(db.String(256), nullable=False)
    stato = db.Column(db.String(20), default="attiva")  # attiva, completata, annullata
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


class Claim(db.Model):
    """Registra quando un utente approfitta di un'offerta."""
    __tablename__ = "claims"

    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    offer_id = db.Column(db.Integer, db.ForeignKey("offers.id"), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.now)

    # Vincolo: un utente può approfittare una sola volta per offerta
    __table_args__ = (
        db.UniqueConstraint("user_id", "offer_id", name="unique_claim"),
    )

    def __repr__(self):
        return f"<Claim user={self.user_id} offer={self.offer_id}>"
