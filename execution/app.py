"""
ApprofittOffro — Server Flask principale.
Applicazione web per offrire e approfittare di pasti.
"""

import os
import uuid
import math
from datetime import datetime, timedelta
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
from functools import wraps
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

# Forzatura No-Cache universale per evitare problemi di refresh template lato Client
@app.after_request
def add_header(response):
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '-1'
    return response

app.config["SECRET_KEY"] = os.getenv("SECRET_KEY", "approfittoffro-dev-key-change-me")
app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///" + os.path.join(
    os.path.dirname(os.path.dirname(__file__)), "approfittoffro.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["MAX_CONTENT_LENGTH"] = 64 * 1024 * 1024  # 64 MB max upload (telefoni moderni)

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(__file__)), "uploads")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config["UPLOAD_FOLDER"] = UPLOAD_FOLDER

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp"}

# --- Email Config (Motore Flask-Mail) ---
app.config['MAIL_SERVER'] = 'smtp.gmail.com'
app.config['MAIL_PORT'] = 587
app.config['MAIL_USE_TLS'] = True
app.config['MAIL_USERNAME'] = os.getenv('MAIL_USERNAME', '')
app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD', '')
app.config['MAIL_DEFAULT_SENDER'] = os.getenv('MAIL_USERNAME', '')

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


def profile_completed_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if current_user.is_authenticated:
            if not current_user.cibi_preferiti or not current_user.intolleranze or not current_user.bio or not current_user.raggio_azione:
                flash("Devi completare il tuo identikit alimentare e la tua bio prima di esplorare l'app.", "warning")
                return redirect(url_for('profile_page'))
        return f(*args, **kwargs)
    return decorated_function

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
@profile_completed_required
def dashboard():
    return render_template("dashboard.html", tipi_pasto=TIPI_PASTO)

@app.route("/verify/<token>")
def verify_email(token):
    user = User.query.filter_by(verification_token=token).first()
    if not user:
        flash("Link di verifica non valido o già utilizzato.", "error")
        return redirect(url_for("index"))
    
    user.verificato = True
    user.verification_token = None
    db.session.commit()
    
    flash("Email verificata con successo! Ora puoi accedere.", "success")
    return redirect(url_for("index"))

@app.route("/new-offer")
@login_required
@profile_completed_required
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
# API — Autenticazione & Utilità
# ===================================================================

@app.route("/profile/<int:user_id>")
def public_profile(user_id):
    """Schermata pubblica dove visito le preferenze di un utente che dona cibo."""
    user = User.query.get_or_404(user_id)
    
    # Previene l'accesso se lui stesso non ha completato il suo profilo base
    if not current_user.is_authenticated:
        flash("Accedi prima per visualizzare i profili degli utenti.", "info")
        return redirect(url_for('index'))
    if not current_user.bio or not current_user.raggio_azione:
        flash("Completa prima il tuo Profilo per poter vedere quello degli altri!", "warning")
        return redirect(url_for('profile_page'))

    # Visualizza quante offerte/richieste ha completato per dare un rating di affidabilità
    offerte_totali = Offer.query.filter_by(user_id=user.id).count()
    recuperi_effettuati = Claim.query.filter_by(user_id=user.id).count()

    return render_template(
        "public_profile.html", 
        user=user, 
        offerte_totali=offerte_totali, 
        recuperi_effettuati=recuperi_effettuati
    )

@app.errorhandler(413)
def request_entity_too_large(error):
    return jsonify({"success": False, "errors": ["La foto è troppo pesante (Max 64MB). Compressione fallita."]}), 413


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
        with urllib.request.urlopen(req, timeout=8) as response:
            data = json.loads(response.read().decode())
            display_name = data.get("display_name", "")
            if display_name:
                parts = [p.strip() for p in display_name.split(',')]
                nome_luogo = ", ".join(parts[:2]) # Tipicamente contiene Via e Numero Civico
                return jsonify({"address": nome_luogo})
    except Exception:
        pass
    
    return jsonify({"address": "Posizione Mappa"})


@app.route("/api/register", methods=["POST"])
def api_register():
    """Registra un nuovo utente con verifica foto."""
    try:
        nome = request.form.get("nome", "").strip()
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        conferma_password = request.form.get("conferma_password", "")
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
        if password != conferma_password:
            errors.append("Le due password non coincidono.")
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
            errors.append("Formato foto non valido. Ammessi JPG, PNG, WEBP, o scatta direttamente un selfie.")

        if errors:
            return jsonify({"success": False, "errors": errors}), 400

        # Salva la foto temporaneamente per la verifica
        foto_ext = foto.filename.rsplit(".", 1)[1].lower() if "." in foto.filename else "jpg"
        foto_filename = f"{uuid.uuid4().hex}.{foto_ext}"
        foto_path = os.path.join(app.config["UPLOAD_FOLDER"], foto_filename)
        foto.save(foto_path)

        # Ridimensiona la foto (max 800x800)
        try:
            img = Image.open(foto_path)
            # Rimuove l'informazione EXIF che ruota le foto HEIF da cellulare
            from PIL import ImageOps
            img = ImageOps.exif_transpose(img)
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
        token_verifica = uuid.uuid4().hex
        user = User(
            nome=nome,
            email=email,
            foto_filename=foto_filename,
            fascia_eta=fascia_eta,
            latitudine=float(lat),
            longitudine=float(lon),
            citta=citta,
            verificato=True,  # MODIFICATO PER FASE DI TEST: Auto-approvazione utente
            verification_token=token_verifica
        )
        user.set_password(password)

        db.session.add(user)
        db.session.commit()

        # Invio VERA Email in background tramite Flask-Mail
        link_verifica = url_for('verify_email', token=token_verifica, _external=True)
        html_body = render_template('emails/verification.html', user=user, link_verifica=link_verifica)
        
        msg = Message("Benvenuto su ApprofittOffro! Conferma la tua email 🍽️", recipients=[user.email])
        msg.html = html_body
        Thread(target=send_async_email, args=(app, msg)).start()

        return jsonify({
            "success": True, 
            "message": "Registrazione completata! Controlla la tua email (o il terminale) per confermare l'account prima di accedere."
        })
    except Exception as super_err:
        db.session.rollback()
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

    login_user(user, remember=True)
    return jsonify({"success": True, "redirect": url_for("dashboard")})


@app.route("/logout", methods=["GET"])
@login_required
def web_logout():
    logout_user()
    return redirect(url_for('index'))

@app.route("/api/logout", methods=["POST"])
def api_logout():
    logout_user()
    return jsonify({"success": True, "redirect": url_for("index")})


# ===================================================================
# API — Offerte
# ===================================================================
@app.route("/api/offers", methods=["GET"])
@login_required
def api_get_offers():
    """Recupera le offerte attualmente valide e visibili."""
    tipo = request.args.get("tipo", "")
    radius_str = request.args.get("radius", "")
    now = datetime.now()

    query = Offer.query.filter(
        Offer.stato == "attiva",
        Offer.posti_disponibili > 0,
        Offer.data_ora > now,
    )

    if tipo:
        query = query.filter(Offer.tipo_pasto == tipo)

    offers = query.order_by(Offer.data_ora.asc()).all()

    # Applica filtro per Raggio se specificato
    radius_km = None
    if radius_str and radius_str.isdigit():
        radius_km = float(radius_str)

    # Centro di ricerca (predefinito: registrazione dell'utente)
    search_lat = current_user.latitudine
    search_lon = current_user.longitudine
    
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
        
        # Scarta l'offerta se si trova oltre il raggio specificato dal filtro
        if radius_km is not None:
            if dist > radius_km:
                continue

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
            "distance_km": round(float(dist), 1),
            "posti_totali": o.posti_totali,
            "posti_disponibili": o.posti_disponibili,
            "data_ora": o.data_ora.isoformat(),
            "descrizione": o.descrizione or "",
            "foto_locale": getattr(o, "foto_locale", "nessuna.jpg"),
            "autore": o.autore.nome,
            "autore_id": o.autore.id,
            "autore_foto": o.autore.foto_filename,
            "autore_fascia_eta": o.autore.fascia_eta,
            "autore_cibi_preferiti": o.autore.cibi_preferiti or "",
            "autore_intolleranze": o.autore.intolleranze or "",
            "is_own": o.user_id == current_user.id,
            "already_claimed": already_claimed,
        })

    return jsonify({"success": True, "offers": result})


@app.route("/api/offers/<int:offer_id>", methods=["DELETE"])
@login_required
def api_delete_offer(offer_id):
    """Elimina definitivamente un'offerta se se ne è l'autore."""
    offer = Offer.query.get_or_404(offer_id)
    if offer.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    
    Claim.query.filter_by(offer_id=offer.id).delete()
    db.session.delete(offer)
    db.session.commit()
    return jsonify({"success": True})


@app.route("/edit-offer/<int:offer_id>")
@login_required
@profile_completed_required
def edit_offer_page(offer_id):
    """Schermata per la modifica di un'offerta esistente."""
    offer = Offer.query.get_or_404(offer_id)
    if offer.user_id != current_user.id:
        flash("Non puoi modificare le offerte altrui.", "error")
        return redirect(url_for("dashboard"))
    return render_template("create_offer.html", offer=offer, tipi_pasto=TIPI_PASTO)


@app.route("/api/offers/<int:offer_id>", methods=["PUT"])
@login_required
def api_edit_offer(offer_id):
    """Applica le modifiche a un'offerta pre-esistente."""
    offer = Offer.query.get_or_404(offer_id)
    if offer.user_id != current_user.id:
        return jsonify({"success": False, "errors": ["Non autorizzato."]}), 403

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
    if not posti or int(posti) < 1:
        errors.append("Indica almeno 1 posto disponibile.")
    if not data_ora_str:
        errors.append("Seleziona data e ora.")

    if foto_locale and foto_locale.filename:
        if not allowed_file(foto_locale.filename):
            errors.append("Formato foto non valido (usa JPG, PNG o WEBP).")

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    try:
        data_ora = datetime.fromisoformat(data_ora_str)
    except (ValueError, TypeError):
        return jsonify({"success": False, "errors": ["Formato data non valido."]}), 400

    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        filename = secure_filename(f"offer_{current_user.id}_{int(datetime.now().timestamp())}.{ext}")
        foto_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
        foto_locale.save(foto_path)
        try:
            img = Image.open(foto_path)
            if img.mode != 'RGB':
                img = img.convert('RGB')
            img.thumbnail((800, 800))
            img.save(foto_path, "JPEG", quality=85)
            filename = filename.rsplit(".", 1)[0] + ".jpg"
            offer.foto_locale = filename
        except Exception as e:
            print("Errore compressione foto offerta:", e)

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
    return jsonify({"success": True, "message": "Offerta aggiornata con successo!", "offer_id": offer.id})


@app.route("/api/offers", methods=["POST"])
@login_required
def api_create_offer():
    """Crea una nuova offerta con foto del locale."""
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
    if not posti or int(posti) < 1:
        errors.append("Indica almeno 1 posto disponibile.")
    if not data_ora_str:
        errors.append("Seleziona data e ora.")
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

    # Salvataggio Immagine locale (opzionale)
    filename = 'nessuna.jpg'
    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        filename = secure_filename(f"offer_{current_user.id}_{int(datetime.now().timestamp())}.{ext}")
        foto_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
        foto_locale.save(foto_path)

        # Elaborazione Immagine (Compressione + Fix Rotazione EXIF da mobile)
        try:
            from PIL import ImageOps
            img = Image.open(foto_path)
            img = ImageOps.exif_transpose(img)  # Corregge la rotazione EXIF (foto da mobile)
            if img.mode != 'RGB':
                img = img.convert('RGB')
            img.thumbnail((800, 800))
            img.save(foto_path, "JPEG", quality=85)
            filename = filename.rsplit(".", 1)[0] + ".jpg"
        except Exception as e:
            print("Errore compressione foto offerta:", e)

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

    # ---- Invio Email di Notifica (Asincrono) ----
    data_formattata = offer.data_ora.strftime('%d/%m/%Y alle %H:%M')
    
    # Email al partecipante (claimer)
    try:
        msg_claimer = Message(
            subject=f"🎉 Sei dentro! Hai approfittato di '{offer.nome_locale}'",
            recipients=[current_user.email],
            html=f"""
            <div style="font-family:sans-serif; max-width:600px; margin:0 auto; background:#f9fafb; padding:32px; border-radius:16px;">
                <h2 style="color:#ef4444;">🍽️ ApprofittOffro</h2>
                <h3>Ottimo, {current_user.nome}! Sei confermato/a!</h3>
                <p>Hai prenotato il tuo posto per:</p>
                <div style="background:white; padding:20px; border-radius:12px; border-left:4px solid #ef4444; margin:16px 0;">
                    <b style="font-size:1.2rem;">{offer.nome_locale}</b><br>
                    📍 {offer.indirizzo}<br>
                    📅 {data_formattata}<br>
                    {'☕' if offer.tipo_pasto == 'colazione' else '🌙' if offer.tipo_pasto == 'cena' else '🍝'} {offer.tipo_pasto.capitalize()}
                </div>
                <p>Ricordati di presentarti puntuale! In caso di imprevisti, contatta l'organizzatore direttamente tramite la piattaforma.</p>
                <p style="color:#6b7280; font-size:0.85rem;">— Il Team di ApprofittOffro</p>
            </div>
            """
        )
        Thread(target=send_async_email, args=(app, msg_claimer)).start()
    except Exception as e:
        print(f"[MAIL_CLAIM_CLAIMER] Errore invio email: {e}")

    # Email all'autore dell'offerta
    try:
        msg_autore = Message(
            subject=f"🔔 Nuova partecipazione a '{offer.nome_locale}'!",
            recipients=[offer.autore.email],
            html=f"""
            <div style="font-family:sans-serif; max-width:600px; margin:0 auto; background:#f9fafb; padding:32px; border-radius:16px;">
                <h2 style="color:#ef4444;">🍽️ ApprofittOffro</h2>
                <h3>Ciao {offer.autore.nome}, hai un nuovo partecipante!</h3>
                <p><b>{current_user.nome}</b> si è appena prenotato/a per la tua offerta:</p>
                <div style="background:white; padding:20px; border-radius:12px; border-left:4px solid #10b981; margin:16px 0;">
                    <b style="font-size:1.2rem;">{offer.nome_locale}</b><br>
                    📅 {data_formattata}<br>
                    👥 Posti rimanenti: <b>{offer.posti_disponibili}</b>
                </div>
                <p style="color:#6b7280; font-size:0.85rem;">— Il Team di ApprofittOffro</p>
            </div>
            """
        )
        Thread(target=send_async_email, args=(app, msg_autore)).start()
    except Exception as e:
        print(f"[MAIL_CLAIM_AUTORE] Errore invio email: {e}")

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
    try:
        msg = Message(
            subject=f"⚠️ Disdetta partecipazione a '{offer.nome_locale}'",
            recipients=[offer.autore.email],
            html=f"""
            <div style="font-family:sans-serif; max-width:600px; margin:0 auto; background:#f9fafb; padding:32px; border-radius:16px;">
                <h2 style="color:#ef4444;">🍽️ ApprofittOffro</h2>
                <h3>Ciao {offer.autore.nome}, una disdetta!</h3>
                <p><b>{current_user.nome}</b> ha annullato la sua partecipazione al tuo evento:</p>
                <div style="background:white; padding:20px; border-radius:12px; border-left:4px solid #f59e0b; margin:16px 0;">
                    <b style="font-size:1.2rem;">{offer.nome_locale}</b><br>
                    📅 {data_formattata}<br>
                    👥 Posti ora disponibili: <b>{offer.posti_disponibili}/{offer.posti_totali}</b>
                </div>
                <p>Il posto è stato liberato automaticamente: altri utenti potranno ora prenotarsi.</p>
                <p style="color:#6b7280; font-size:0.85rem;">— Il Team di ApprofittOffro</p>
            </div>
            """
        )
        Thread(target=send_async_email, args=(app, msg)).start()
    except Exception as e:
        print(f"[MAIL_UNCLAIM] Errore: {e}")

    # Email di conferma al partecipante che ha disdetto
    try:
        msg_user = Message(
            subject=f"✅ Partecipazione annullata: '{offer.nome_locale}'",
            recipients=[current_user.email],
            html=f"""
            <div style="font-family:sans-serif; max-width:600px; margin:0 auto; background:#f9fafb; padding:32px; border-radius:16px;">
                <h2 style="color:#ef4444;">🍽️ ApprofittOffro</h2>
                <h3>Partecipazione annullata, {current_user.nome}.</h3>
                <p>La tua partecipazione a <b>{offer.nome_locale}</b> ({data_formattata}) è stata annullata con successo.</p>
                <p style="color:#6b7280; font-size:0.85rem;">— Il Team di ApprofittOffro</p>
            </div>
            """
        )
        Thread(target=send_async_email, args=(app, msg_user)).start()
    except Exception as e:
        print(f"[MAIL_UNCLAIM_USER] Errore: {e}")

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
            "foto": current_user.foto_filename,
            "fascia_eta": current_user.fascia_eta,
            "lat": current_user.latitudine,
            "lon": current_user.longitudine,
            "citta": current_user.citta,
            "verificato": current_user.verificato,
            "cibi_preferiti": current_user.cibi_preferiti or "",
            "intolleranze": current_user.intolleranze or "",
        },
    })

@app.route("/api/user/update", methods=["POST"])
@login_required
def api_user_update():
    """Aggiorna le preferenze alimentari e profilo dell'utente."""
    data = request.get_json() if request.is_json else request.form
    pref = data.get("cibi_preferiti", "").strip()
    intoll = data.get("intolleranze", "").strip()
    bio = data.get("bio", "").strip()
    raggio = data.get("raggio_azione", "10").strip()

    if not pref or len(pref) < 3:
        return jsonify({"success": False, "errors": ["Quali sono i tuoi cibi preferiti? Scrivi qualcosa in più."]}), 400
    if not intoll:
        return jsonify({"success": False, "errors": ["Inserisci le tue intolleranze o allergie. Se non ne hai, scrivi 'Nessuna'."]}), 400
    if not bio or len(bio) < 5:
        return jsonify({"success": False, "errors": ["Raccontaci qualcosa di te nella Bio."]}), 400

    try:
        raggio_int = int(raggio)
        if raggio_int <= 0:
            raise ValueError()
    except Exception:
        return jsonify({"success": False, "errors": ["Raggio d'azione non valido."]}), 400

    current_user.cibi_preferiti = pref
    current_user.intolleranze = intoll
    current_user.bio = bio
    current_user.raggio_azione = raggio_int
    db.session.commit()

    return jsonify({"success": True, "message": "Profilo e Identikit aggiornati!"})


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
