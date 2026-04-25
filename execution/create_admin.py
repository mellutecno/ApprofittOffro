"""
Bootstrap di un account amministratore per ApprofittOffro.

Uso:
    python execution/create_admin.py --email admin@example.com --password segreta123

Se l'utente esiste già viene promosso ad amministratore.
Se non esiste viene creato con un profilo minimale e verificato.
"""

import argparse
import os

from PIL import Image, ImageDraw

HOME_DIR = os.path.expanduser("~")
os.environ.setdefault("APP_ENV_FILE", os.path.join(HOME_DIR, ".env"))
if os.name != "nt" and "APP_DATA_DIR" not in os.environ:
    # Nei deploy Linux il database e gli upload possono stare nella home utente.
    os.environ["APP_DATA_DIR"] = HOME_DIR

from app import app, db, User, UPLOAD_FOLDER


def ensure_admin_placeholder(filename="admin_placeholder.png"):
    """Crea un avatar amministratore minimale se non esiste già."""
    os.makedirs(UPLOAD_FOLDER, exist_ok=True)
    path = os.path.join(UPLOAD_FOLDER, filename)
    if os.path.exists(path):
        return filename

    image = Image.new("RGB", (512, 512), "#2D1B12")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((48, 48, 464, 464), radius=120, fill="#FF7043")
    draw.rounded_rectangle((142, 118, 370, 196), radius=28, fill="#FFF4EA")
    draw.rounded_rectangle((176, 212, 336, 370), radius=60, fill="#FFF4EA")
    image.save(path, "PNG")
    return filename


def build_parser():
    parser = argparse.ArgumentParser(description="Crea o promuove un amministratore.")
    parser.add_argument("--email", required=True, help="Email dell'amministratore")
    parser.add_argument("--password", required=True, help="Password dell'amministratore")
    parser.add_argument("--name", default="Admin ApprofittOffro", help="Nome visibile dell'admin")
    parser.add_argument("--city", default="Italia", help="Città/area dell'admin")
    parser.add_argument("--age", type=int, default=35, help="Età da usare se l'utente viene creato da zero")
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.age < 18 or args.age > 120:
        parser.error("L'età deve essere compresa tra 18 e 120.")

    placeholder_filename = ensure_admin_placeholder()

    with app.app_context():
        user = User.query.filter_by(email=args.email.strip().lower()).first()

        if user:
            user.nome = args.name
            user.is_admin = True
            user.verificato = True
            user.verification_token = None
            user.set_password(args.password)
            if not user.foto_filename:
                user.foto_filename = placeholder_filename
            if user.eta is None:
                user.eta = args.age
                user.fascia_eta = str(args.age)
            db.session.commit()
            print(f"[OK] Utente esistente promosso ad admin: {user.email}")
            print(f"[INFO] DATA_ROOT={os.getenv('APP_DATA_DIR', '')}")
            return

        user = User(
            nome=args.name,
            email=args.email.strip().lower(),
            foto_filename=placeholder_filename,
            fascia_eta=str(args.age),
            eta=args.age,
            latitudine=41.9028,
            longitudine=12.4964,
            citta=args.city,
            cibi_preferiti="Gestione piattaforma",
            intolleranze="Nessuna",
            bio="Account amministratore della piattaforma.",
            verificato=True,
            verification_token=None,
            is_admin=True,
        )
        user.set_password(args.password)
        db.session.add(user)
        db.session.commit()
        print(f"[OK] Nuovo amministratore creato: {user.email}")
        print(f"[INFO] DATA_ROOT={os.getenv('APP_DATA_DIR', '')}")


if __name__ == "__main__":
    main()
