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
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

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


# ---------------------------------------------------------------------------
# Crea le tabelle al primo avvio
# ---------------------------------------------------------------------------
with app.app_context():
    db.create_all()


def profile_completed_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if current_user.is_authenticated:
            if not current_user.cibi_preferiti or not current_user.intolleranze or not current_user.bio:
                flash("Ciao! Completa il tuo identikit alimentare e la tua bio: sono obbligatori per poter esplorare le offerte e partecipare ai pasti. 🍽️", "warning")
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

    return render_template(
        "profile.html",
        my_offers=my_offers,
        my_claims=my_claims,
        met_users=met_users_dict.values(),
        fasce_eta=FASCE_ETA,
        rating_info=get_user_rating(current_user.id),
        now=datetime.now(),
        completion_threshold=datetime.now() - timedelta(hours=3)
    )

def get_user_rating(user_id):
    """Calcola la media delle recensioni per un utente."""
    from models import Review
    reviews = Review.query.filter_by(reviewed_id=user_id).all()
    if not reviews:
        return {"average": 0, "count": 0}
    avg = sum(r.rating for r in reviews) / len(reviews)
    return {"average": round(avg, 1), "count": len(reviews)}


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
    pending_offer = None
    if current_user.id != user_id:
        from datetime import timedelta
        now = datetime.now()
        threshold = now - timedelta(hours=3)
        
        # Caso A: Io ero l'ospite, lui l'host
        meal_as_guest = Offer.query.join(Claim).filter(
            Claim.user_id == current_user.id,
            Offer.user_id == user_id,
            Offer.data_ora < threshold
        ).order_by(Offer.data_ora.desc()).first()
        
        # Caso B: Io ero l'host, lui l'ospite
        meal_as_host = Offer.query.join(Claim).filter(
            Offer.user_id == current_user.id,
            Claim.user_id == user_id,
            Offer.data_ora < threshold
        ).order_by(Offer.data_ora.desc()).first()
        
        shared_offer = meal_as_guest or meal_as_host

        # Se non c'è una shared_offer già conclusa, cerchiamo una "pending" (pasto appena avvenuto o in corso)
        if not shared_offer:
            pending_as_guest = Offer.query.join(Claim).filter(
                Claim.user_id == current_user.id,
                Offer.user_id == user_id,
                Offer.data_ora < now,
                Offer.data_ora >= threshold
            ).first()
            pending_as_host = Offer.query.join(Claim).filter(
                Offer.user_id == current_user.id,
                Claim.user_id == user_id,
                Offer.data_ora < now,
                Offer.data_ora >= threshold
            ).first()
            pending_offer = pending_as_guest or pending_as_host
    
    return render_template(
        "public_profile.html", 
        user=user, 
        rating_info=rating_info,
        reviews=reviews,
        offerte_totali=offerte_totali,
        recuperi_effettuati=recuperi_effettuati,
        shared_offer=shared_offer,
        pending_offer=pending_offer
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

        # Salva e processa la foto
        foto_ext = foto.filename.rsplit(".", 1)[1].lower() if "." in foto.filename else "jpg"
        temp_filename = f"{uuid.uuid4().hex}.{foto_ext}"
        foto_filename = process_image(foto, temp_filename)
        foto_path = os.path.join(app.config["UPLOAD_FOLDER"], foto_filename)

        # Verifica volto
        verifica = verifica_volto(foto_path)
        if not verifica["valida"]:
            if os.path.exists(foto_path):
                os.remove(foto_path)
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
            verificato=False,
            verification_token=token_verifica
        )
        user.set_password(password)

        db.session.add(user)
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
    periodo = request.args.get("periodo", "oggi_domani")
    radius_str = request.args.get("radius", "")
    now = datetime.now()

    query = Offer.query.filter(
        Offer.stato == "attiva",
        Offer.posti_disponibili > 0,
        Offer.data_ora > now,
    )

    if tipo:
        query = query.filter(Offer.tipo_pasto == tipo)
    
    if periodo == "oggi_domani":
        # Fine di domani: 23:59:59 del giorno dopo
        fine_domani = (now + timedelta(days=1)).replace(hour=23, minute=59, second=59, microsecond=999999)
        query = query.filter(Offer.data_ora <= fine_domani)

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
            "distance_km": round(dist, 1),
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
    """Elimina definitivamente un'offerta, notificando eventuali partecipanti."""
    offer = Offer.query.get(offer_id)
    if not offer:
        return jsonify({"success": False, "error": "Offerta non trovata."}), 404
    
    if offer.user_id != current_user.id:
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    
    # Riceve la motivazione dal corpo della richiesta (JSON)
    data = request.get_json(silent=True) or {}
    motivazione = data.get("motivazione", "Nessuna motivazione specificata.").strip() or "Nessuna motivazione specificata."
    
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

    if foto_locale and foto_locale.filename:
        ext = foto_locale.filename.rsplit(".", 1)[1].lower()
        filename = f"offer_{current_user.id}_{int(datetime.now().timestamp())}.{ext}"
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
    """Aggiorna i dati anagrafici, alimentari e la foto profilo dell'utente."""
    # Gestisce sia JSON che Form Data (necessario per upload foto)
    if request.is_json:
        data = request.get_json()
    else:
        data = request.form

    # 1. Dati Anagrafici (Opzionali per l'update, ma validati se presenti)
    nome = data.get("nome", current_user.nome).strip()
    email = data.get("email", current_user.email).strip().lower()
    fascia_eta = data.get("fascia_eta", current_user.fascia_eta)
    lat = data.get("latitudine")
    lon = data.get("longitudine")
    citta = data.get("citta", current_user.citta)

    # 2. Identikit Alimentare
    pref = data.get("cibi_preferiti", current_user.cibi_preferiti or "").strip()
    intoll = data.get("intolleranze", current_user.intolleranze or "").strip()
    bio = data.get("bio", current_user.bio or "").strip()

    errors = []
    if not nome:
        errors.append("Il nome non può essere vuoto.")
    if not email or "@" not in email:
        errors.append("Inserisci un'email valida.")
    if email != current_user.email and User.query.filter_by(email=email).first():
        errors.append("Questa email è già associata a un altro account.")
    
    if len(pref) > 0 and len(pref) < 3:
        errors.append("Quali sono i tuoi cibi preferiti? Scrivi qualcosa in più.")
    if len(bio) > 0 and len(bio) < 5:
        errors.append("Raccontaci qualcosa di più nella tua Bio.")

    # 3. Gestione Foto Profilo (Opzionale nell'update)
    foto = request.files.get("foto")
    if foto and foto.filename:
        if not allowed_file(foto.filename):
            errors.append("Formato foto non valido. Usa JPG, PNG o WEBP.")
        else:
            foto_ext = foto.filename.rsplit(".", 1)[1].lower() if "." in foto.filename else "jpg"
            unique_id = str(uuid.uuid4().hex)[:8]
            temp_filename = f"user_{current_user.id}_{unique_id}.{foto_ext}"
            foto_filename = process_image(foto, temp_filename)
            foto_path = os.path.join(app.config["UPLOAD_FOLDER"], foto_filename)

            # Verifica volto (opzionale per l'update per non essere troppo bloccanti, ma sicura)
            verifica = verifica_volto(foto_path)
            if not verifica["valida"]:
                if os.path.exists(foto_path):
                    os.remove(foto_path)
                errors.append(f"Foto non valida: {verifica['errore']}")
            else:
                # Se la verifica passa, aggiorniamo il filename
                current_user.foto_filename = foto_filename

    if errors:
        return jsonify({"success": False, "errors": errors}), 400

    # 4. Salvataggio modifiche
    current_user.nome = nome
    current_user.email = email
    current_user.fascia_eta = fascia_eta
    if lat and lon:
        try:
            current_user.latitudine = float(lat)
            current_user.longitudine = float(lon)
            current_user.citta = citta
        except ValueError:
            pass
            
    current_user.cibi_preferiti = pref
    current_user.intolleranze = intoll
    current_user.bio = bio

    db.session.commit()
    return jsonify({"success": True, "message": "Profilo aggiornato con successo!"})


# ===================================================================
# API — Recensioni
# ===================================================================

@app.route("/api/reviews", methods=["POST"])
@login_required
def api_create_review():
    """Crea una nuova recensione (Host -> Guest o Guest -> Host)."""
    data = request.get_json()
    offer_id = data.get("offer_id")
    reviewed_id = data.get("reviewed_id") # Nuova specifica dell'utente da recensire
    rating = data.get("rating")
    commento = data.get("commento", "").strip()

    if not offer_id or not rating or not reviewed_id:
        return jsonify({"success": False, "error": "Dati mancanti (ID offerta, utente o punteggio)."}), 400

    try:
        rating = int(rating)
        if rating < 1 or rating > 5:
            raise ValueError()
    except ValueError:
        return jsonify({"success": False, "error": "Punteggio non valido (1-5)."}), 400

    # 1. Verifica che l'offerta esista
    offer = Offer.query.get(offer_id)
    if not offer:
        return jsonify({"success": False, "error": "Offerta non trovata."}), 404

    # 2. Verifica che l'utente non stia recensendo se stesso
    if reviewed_id == current_user.id:
        return jsonify({"success": False, "error": "Non puoi recensire te stesso."}), 400

    # 3. Verifica che l'evento sia passato (buffer 3 ore)
    from datetime import timedelta
    if offer.data_ora + timedelta(hours=3) > datetime.now():
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

    # 5. Verifica che non abbia già recensito questa specifica interazione
    from models import Review
    existing = Review.query.filter_by(reviewer_id=current_user.id, reviewed_id=reviewed_id, offer_id=offer_id).first()
    if existing:
        return jsonify({"success": False, "error": "Hai già lasciato una recensione per questo utente in questo pasto."}), 400

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
    return send_from_directory(app.config["UPLOAD_FOLDER"], filename)


# ===================================================================
# Avvio
# ===================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("DEBUG", "true").lower() == "true"
    app.run(host="0.0.0.0", port=port, debug=debug)
