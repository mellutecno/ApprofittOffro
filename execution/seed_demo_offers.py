"""
Genera offerte demo future usando i profili demo della community.

Uso tipico:
    python execution/seed_demo_offers.py --count 50

Opzioni utili:
    python execution/seed_demo_offers.py --count 50 --refresh-existing
    python execution/seed_demo_offers.py --dry-run

Comportamento:
- usa i profili demo già creati con email *@demo.approfittoffro.local
- crea offerte future distribuite nei prossimi mesi
- salva una foto luogo coerente col tipo pasto
- se richiesto, rimuove e rigenera le offerte demo precedenti
"""

from __future__ import annotations

import argparse
import os
import random
from datetime import timedelta
from pathlib import Path

HOME_DIR = os.path.expanduser("~")
os.environ.setdefault("APP_ENV_FILE", os.path.join(HOME_DIR, ".env"))
if os.name != "nt" and "APP_DATA_DIR" not in os.environ:
    os.environ["APP_DATA_DIR"] = HOME_DIR

from app import SQLITE_PATH, UPLOAD_FOLDER, app, db, local_now, upload_storage
from models import Claim, Offer, User


EMAIL_DOMAIN = "demo.approfittoffro.local"
RANDOM_SEED = 84
PHOTO_PREFIX = "seed_demo_offers/"

MEAL_TIMES = {
    "colazione": (8, 30),
    "pranzo": (13, 0),
    "cena": (20, 30),
}

VENUES = [
    ("Bar del Centro", "Via Roma"),
    ("Caffè Naviglio", "Corso Italia"),
    ("Pizzeria La Sosta", "Via Torino"),
    ("Pub della Piazza", "Piazza della Repubblica"),
    ("Trattoria del Borgo", "Via Mazzini"),
    ("Bistrot Milano", "Via Dante"),
    ("Osteria Due Chiacchiere", "Via Cavour"),
    ("Brunch & Co.", "Via Garibaldi"),
    ("La Cucina di Quartiere", "Via Manzoni"),
    ("Terrazza Aperitivo", "Corso Europa"),
]

DESCRIPTIONS = {
    "colazione": [
        "Colazione tranquilla per iniziare bene la giornata con due chiacchiere e un buon caffè.",
        "Mi farebbe piacere condividere una colazione semplice, rilassata e senza formalità.",
        "Cerco compagnia per una colazione lenta, brioche, cappuccino e una bella conversazione.",
    ],
    "pranzo": [
        "Pranzo informale in un posto carino, con voglia di conoscere persone nuove e stare bene.",
        "Mi va un pranzo sereno, con buona cucina e conversazione piacevole senza fretta.",
        "Pausa pranzo curata ma easy, ideale per chi ha voglia di passare un bel momento.",
    ],
    "cena": [
        "Cena rilassata in un locale accogliente, con atmosfera piacevole e buona compagnia.",
        "Serata semplice ma fatta bene, con buon cibo, chiacchiere leggere e persone positive.",
        "Mi piacerebbe organizzare una cena tranquilla per condividere un momento piacevole.",
    ],
}

PHONE_NUMBERS = [
    "0284012345",
    "0299011223",
    "0244556677",
    "0233445566",
    "0277889900",
    "0240022334",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Crea offerte demo future.")
    parser.add_argument("--count", type=int, default=50, help="Numero di offerte demo da generare.")
    parser.add_argument(
        "--refresh-existing",
        action="store_true",
        help="Rimuove e rigenera le offerte demo già presenti.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Non salva nulla: mostra solo cosa verrebbe creato.",
    )
    return parser.parse_args()


def demo_users() -> list[User]:
    return (
        User.query.filter(
            User.email.like(f"%@{EMAIL_DOMAIN}"),
            User.verificato.is_(True),
            User.is_admin.is_(False),
        )
        .order_by(User.id.asc())
        .all()
    )


def existing_seed_offers() -> list[Offer]:
    demo_user_ids = [user.id for user in demo_users()]
    if not demo_user_ids:
        return []
    return (
        Offer.query.filter(
            Offer.user_id.in_(demo_user_ids),
            Offer.foto_locale.like(f"{PHOTO_PREFIX}%"),
        )
        .order_by(Offer.id.asc())
        .all()
    )


def hero_image_for_meal(meal_type: str) -> Path:
    static_img = Path(__file__).resolve().parent / "static" / "img"
    if meal_type == "colazione":
        return static_img / "hero-brunch.jpg"
    if meal_type == "pranzo":
        return static_img / "hero-friends.jpg"
    return static_img / "hero-dinner.jpg"


def save_offer_photo(meal_type: str, offer_key: str) -> str:
    source_path = hero_image_for_meal(meal_type)
    data = source_path.read_bytes()
    target_name = f"{PHOTO_PREFIX}{offer_key}.jpg"
    return upload_storage.save_bytes(target_name, data, content_type="image/jpeg")


def build_future_datetime(index: int, meal_type: str) -> object:
    now = local_now()
    day_offset = 2 + index * 2
    hour, minute = MEAL_TIMES[meal_type]
    return (now + timedelta(days=day_offset)).replace(
        hour=hour,
        minute=minute,
        second=0,
        microsecond=0,
    )


def build_address(user: User, venue_name: str, street_name: str, index: int) -> str:
    city_label = (user.citta or "Milano").split(",")[-1].strip() or "Milano"
    civic = 5 + (index % 97)
    return f"{street_name} {civic}, {city_label}"


def build_offer_title(venue_name: str, meal_type: str, index: int) -> str:
    if meal_type == "colazione":
        return venue_name
    if meal_type == "pranzo":
        return f"{venue_name} Pranzo"
    return f"{venue_name} Dinner Club"


def remove_seed_offers() -> tuple[int, int]:
    offers = existing_seed_offers()
    removed_offers = 0
    removed_claims = 0
    for offer in offers:
        removed_claims += Claim.query.filter_by(offer_id=offer.id).delete()
        db.session.delete(offer)
        removed_offers += 1
    db.session.commit()
    return removed_offers, removed_claims


def main() -> int:
    args = parse_args()
    rng = random.Random(RANDOM_SEED)

    with app.app_context():
        users = demo_users()
        if not users:
            raise RuntimeError(
                "Non trovo profili demo. Prima esegui python execution/seed_demo_users.py."
            )

        print(
            f"[seed-demo-offers] db={SQLITE_PATH} uploads={UPLOAD_FOLDER} "
            f"demo_users={len(users)} count={args.count} dry_run={args.dry_run}"
        )

        if args.refresh_existing and not args.dry_run:
            removed_offers, removed_claims = remove_seed_offers()
            print(
                f"[seed-demo-offers] rimossi_offers={removed_offers} rimossi_claims={removed_claims}"
            )

        if args.dry_run:
            for preview_index in range(min(5, args.count)):
                meal_type = ["colazione", "pranzo", "cena"][preview_index % 3]
                venue_name, street_name = VENUES[preview_index % len(VENUES)]
                user = users[preview_index % len(users)]
                print(
                    f"preview {preview_index + 1}: {user.nome} -> "
                    f"{build_offer_title(venue_name, meal_type, preview_index)} "
                    f"({meal_type}) @ {build_address(user, venue_name, street_name, preview_index)}"
                )
            return 0

        created = 0
        for index in range(args.count):
            user = users[index % len(users)]
            meal_type = ["colazione", "pranzo", "cena"][index % 3]
            venue_name, street_name = VENUES[index % len(VENUES)]
            data_ora = build_future_datetime(index, meal_type)
            nome_locale = build_offer_title(venue_name, meal_type, index)
            indirizzo = build_address(user, venue_name, street_name, index)
            descrizione = rng.choice(DESCRIPTIONS[meal_type])
            posti_totali = 1 + (index % 3)
            foto_locale = save_offer_photo(meal_type, f"user{user.id}_offer{index+1}")

            offer = Offer(
                user_id=user.id,
                tipo_pasto=meal_type,
                nome_locale=nome_locale,
                indirizzo=indirizzo,
                telefono_locale=PHONE_NUMBERS[index % len(PHONE_NUMBERS)],
                latitudine=user.latitudine,
                longitudine=user.longitudine,
                posti_totali=posti_totali,
                posti_disponibili=posti_totali,
                data_ora=data_ora,
                descrizione=descrizione,
                foto_locale=foto_locale,
                stato="attiva",
                created_at=local_now() - timedelta(hours=index % 48),
            )
            db.session.add(offer)
            created += 1

        db.session.commit()
        print(f"[seed-demo-offers] creati={created}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
