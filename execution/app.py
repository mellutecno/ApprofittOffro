"""
ApprofittOffro — Server Flask principale.
Applicazione web per offrire e approfittare di pasti.
"""

import os
import uuid
from datetime import datetime, timezone
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
from flask_login import (
    LoginManager,
    login_user,
    logout_user,
    login_required,
    current_user,
)
from werkzeug.utils import secure_filename
from PIL import Image

from models import db, User, Offer, Claim, FASCE_ETA, TIPI_PASTO
from verify_photo import verifica_volto

# ---------------------------------------------------------------------------
# Configurazione
# ---------------------------------------------------------------------------
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))

app = Flask(
    __name__,
    template_folder="templates",
    static_folder="static",
)

app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "approfittoffro-dev-key-change-me")
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///" + os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "approfittoffro.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024  # 8 MB max upload

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}

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


# ---------------------------------------------------------------------------
# Crea le tabelle al primo avvio
# ---------------------------------------------------------------------------
with app.app_context():
    db.create_all()


# ===================================================================
# PAGINE (Template)
# ===================================================================


@app.route("/")
def index():
    if current_user.is_authenticated:
        return redirect(url_for("dashboard"))
    return render_template("index.html")


@app.route("/register")
def register_page():
    return render_template("register.html", fasce_eta=FASCE_ETA)


@app.route("/login")
def login_page():
    return render_template("index.html")


@app.route("/dashboard")
@login_required
def dashboard():
    return render_template("dashboard.html", tipi_pasto=TIPI_PASTO)


@app.route("/new-offer")
@login_required
def new_offer_page():
    return render_template("create_offer.html", tipi_pasto=TIPI_PASTO)


@app.route("/profile")
@login_required
def profile_page():
    my_offers = Offer.query.filter_by(user_id=current_user.id).order_by(
        Offer.created_at.desc()
    ).all()
    my_claims = Claim.query.filter_by(user_id=current_user.id).order_by(
        Claim.created_at.desc()
    ).all()
    return render_template(
        "profile.html",
        my_offers=my_offers,
        my_claims=my_claims,
        fasce_eta=FASCE_ETA,
    )


# ===================================================================
# API — Autenticazione
# ===================================================================


@app.route("/api/register", methods=["POST"])
def api_register():
    """Registra un nuovo utente con verifica foto."""
    nome = request.form.get("nome", "").strip()
    email = request.form.get("email", "").strip().lower()
    password = request.form.get("password", "")
    fascia_eta = request.form.get("fascia_eta", "")
    lat = request.form.get("latitudine")
    lon = request.form.get("longitudine")
    citta = request.form.get("citta", "").strip()

    # Validazione campi
    errors = []
    if not nome:
        errors.append("Il nome è obbligatorio.")
    if not email or "@" not in email:
        errors.append("Inserisci un'email valida.")
    if len(password) < 6:
        errors.append("La password deve avere almeno 6 caratteri.")
    if fascia_eta not in [f[0] for f in FASCE_ETA]:
        errors.append("Seleziona una fascia d'età valida.")
    if not lat or not lon:
        errors.append("Seleziona la tua posizione sulla mappa.")

    # Controlla email duplicata
    if User.query.filter_by(email=email).first():
        errors.append("Questa email è già registrata.")

    # Controlla foto
    foto = request.files.get("foto")
    if not foto or not foto.filename:
        errors.append("La foto è obbligatoria.")
    elif not allowed_file(foto.filename):
        errors.append("Formato foto non valido. Usa JPG, PNG o WebP.")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    # Salva la foto temporaneamente per la verifica
    foto_ext = foto.filename.rsplit(".", 1)[1].lower()
    foto_filename = f"{uuid.uuid4().hex}.{foto_ext}"
    foto_path = os.path.join(app.config["UPLOAD_FOLDER"], foto_filename)
    foto.save(foto_path)

    # Ridimensiona la foto (max 800x800)
    try:
        img = Image.open(foto_path)
        img.thumbnail((800, 800), Image.LANCZOS)
        img.save(foto_path)
    except Exception:
        pass

    # Verifica volto
    verifica = verifica_volto(foto_path)
    if not verifica["valida"]:
        os.remove(foto_path)  # Elimina foto non valida
        return jsonify({
            "success": False,
            "errors": [verifica["errore"]],
        }), 400

    # Crea l'utente
    user = User(
        nome=nome,
        email=email,
        foto_filename=foto_filename,
        fascia_eta=fascia_eta,
        latitudine=float(lat),
        longitudine=float(lon),
        citta=citta,
        verificato=True,  # Verificato perché la foto ha un volto
    )
    user.set_password(password)

    db.session.add(user)
    db.session.commit()

    return jsonify({"success": True, "message": "Registrazione completata! Ora puoi accedere."})


@app.route("/api/login", methods=["POST"])
def api_login():
    """Login utente."""
    data = request.get_json() if request.is_json else request.form
    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    user = User.query.filter_by(email=email).first()

    if not user or not user.check_password(password):
        return jsonify({"success": False, "errors": ["Email o password non corretti."]}), 401

    login_user(user, remember=True)
    return jsonify({"success": True, "redirect": url_for("dashboard")})


@app.route("/api/logout", methods=["POST"])
@login_required
def api_logout():
    logout_user()
    return jsonify({"success": True, "redirect": url_for("index")})


# ===================================================================
# API — Offerte
# ===================================================================


@app.route("/api/offers", methods=["GET"])
@login_required
def api_get_offers():
    """Restituisce le offerte attive, filtrabili per tipo pasto."""
    tipo = request.args.get("tipo", "")
    now = datetime.now()

    query = Offer.query.filter(
        Offer.stato == "attiva",
        Offer.posti_disponibili > 0,
        Offer.data_ora > now,
    )

    if tipo and tipo in [t[0] for t in TIPI_PASTO]:
        query = query.filter(Offer.tipo_pasto == tipo)

    offers = query.order_by(Offer.data_ora.asc()).all()

    result = []
    for o in offers:
        # Controlla se l'utente corrente ha già approfittato
        already_claimed = Claim.query.filter_by(
            user_id=current_user.id, offer_id=o.id
        ).first() is not None

        result.append({
            "id": o.id,
            "tipo_pasto": o.tipo_pasto,
            "nome_locale": o.nome_locale,
            "indirizzo": o.indirizzo,
            "lat": o.latitudine,
            "lon": o.longitudine,
            "posti_totali": o.posti_totali,
            "posti_disponibili": o.posti_disponibili,
            "data_ora": o.data_ora.isoformat(),
            "descrizione": o.descrizione or "",
            "autore": o.autore.nome,
            "autore_id": o.autore.id,
            "autore_foto": o.autore.foto_filename,
            "autore_fascia_eta": o.autore.fascia_eta,
            "is_own": o.user_id == current_user.id,
            "already_claimed": already_claimed,
        })

    return jsonify({"success": True, "offers": result})


@app.route("/api/offers", methods=["POST"])
@login_required
def api_create_offer():
    """Crea una nuova offerta."""
    data = request.get_json() if request.is_json else request.form

    tipo_pasto = data.get("tipo_pasto", "")
    nome_locale = data.get("nome_locale", "").strip()
    indirizzo = data.get("indirizzo", "").strip()
    lat = data.get("latitudine")
    lon = data.get("longitudine")
    posti = data.get("posti_totali")
    data_ora_str = data.get("data_ora", "")
    descrizione = data.get("descrizione", "").strip()

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
    if not posti or int(posti) < 1:
        errors.append("Indica almeno 1 posto disponibile.")
    if not data_ora_str:
        errors.append("Seleziona data e ora.")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    # Parsa la data
    try:
        data_ora = datetime.fromisoformat(data_ora_str)
    except (ValueError, TypeError):
        return jsonify({"success": False, "errors": ["Formato data non valido."]}), 400

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
    )

    db.session.add(offer)
    db.session.commit()

    return jsonify({"success": True, "message": "Offerta creata con successo!", "offer_id": offer.id})


@app.route("/api/offers/<int:offer_id>/claim", methods=["POST"])
@login_required
def api_claim_offer(offer_id):
    """Approfitta di un'offerta — decrementa posti disponibili."""
    offer = db.session.get(Offer, offer_id)

    if not offer:
        return jsonify({"success": False, "errors": ["Offerta non trovata."]}), 404

    # Controlli
    if offer.user_id == current_user.id:
        return jsonify({"success": False, "errors": ["Non puoi approfittare della tua stessa offerta."]}), 400

    if not offer.is_disponibile:
        return jsonify({"success": False, "errors": ["Offerta non più disponibile."]}), 400

    # Controlla se ha già approfittato
    existing = Claim.query.filter_by(user_id=current_user.id, offer_id=offer_id).first()
    if existing:
        return jsonify({"success": False, "errors": ["Hai già approfittato di questa offerta."]}), 400

    # Crea il claim e decrementa i posti
    claim = Claim(user_id=current_user.id, offer_id=offer_id)
    offer.posti_disponibili -= 1

    if offer.posti_disponibili == 0:
        offer.stato = "completata"

    db.session.add(claim)
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "Hai approfittato dell'offerta!",
        "posti_disponibili": offer.posti_disponibili,
    })


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
            "foto": current_user.foto_filename,
            "fascia_eta": current_user.fascia_eta,
            "lat": current_user.latitudine,
            "lon": current_user.longitudine,
            "citta": current_user.citta,
            "verificato": current_user.verificato,
        },
    })


# ===================================================================
# Servire le foto caricate
# ===================================================================


@app.route("/uploads/<filename>")
def uploaded_file(filename):
    from flask import send_from_directory
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


# ===================================================================
# Avvio
# ===================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("DEBUG", "true").lower() == "true"
    app.run(host="0.0.0.0", port=port, debug=debug)
