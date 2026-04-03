"""
Genera profili demo verificati per testare la community.

Uso tipico:
    python execution/seed_demo_users.py

Opzioni utili:
    python execution/seed_demo_users.py --female 30 --male 20
    python execution/seed_demo_users.py --anchor-email mellucciantonio@gmail.com
    python execution/seed_demo_users.py --dry-run

Il comando:
- crea utenti demo verificati e completi, visibili in community
- salva una foto profilo per ciascun utente
- distribuisce i profili entro un raggio configurabile intorno a un utente reale
- aggiunge alcune relazioni follower tra i profili demo, così il sistema sembra vivo
"""

from __future__ import annotations

import argparse
import math
import random
from dataclasses import dataclass
from datetime import timedelta
from html import escape
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from werkzeug.security import generate_password_hash

from app import (
    APP_TIMEZONE,
    DEFAULT_USER_LATITUDE,
    DEFAULT_USER_LONGITUDE,
    User,
    UserFollow,
    app,
    db,
    ensure_default_profile_placeholder,
    local_now,
    replace_user_gallery,
    upload_storage,
)


PASSWORD_FOR_ALL = "Demo123!"
EMAIL_DOMAIN = "demo.approfittoffro.local"
RANDOM_SEED = 42

FEMALE_NAMES = [
    "Giulia", "Chiara", "Martina", "Elisa", "Noemi", "Serena", "Arianna",
    "Valentina", "Beatrice", "Elena", "Giorgia", "Alice", "Camilla", "Ilaria",
    "Francesca", "Gaia", "Marta", "Silvia", "Nicole", "Alessia", "Federica",
    "Bianca", "Ludovica", "Vittoria", "Greta", "Sofia", "Aurora", "Emma",
    "Melissa", "Debora", "Rachele", "Vanessa", "Daniela", "Sabrina", "Paola",
]

MALE_NAMES = [
    "Marco", "Luca", "Matteo", "Simone", "Davide", "Andrea", "Gabriele",
    "Stefano", "Alessandro", "Fabio", "Christian", "Riccardo", "Emanuele",
    "Samuele", "Antonio", "Nicola", "Michele", "Daniele", "Paolo", "Giorgio",
    "Tommaso", "Federico", "Lorenzo", "Ivan", "Roberto",
]

SURNAMES = [
    "Rossi", "Bianchi", "Russo", "Romano", "Ferrari", "Esposito", "Colombo",
    "Gallo", "Conti", "Greco", "Marino", "Bruno", "Costa", "Fontana", "Moretti",
    "Lombardi", "Barbieri", "Santoro", "Rinaldi", "Caruso", "Leone", "Ricci",
    "Fiore", "Testa", "Longo",
]

FAVORITE_FOODS = [
    "pizza, brunch, aperitivi",
    "sushi, ramen, cucina fusion",
    "pasta fresca, vino rosso, dolci",
    "colazioni lente, cappuccino, brioche",
    "pub, hamburger, birre artigianali",
    "pesce, ristoranti vista lago, cucina mediterranea",
    "pizzerie napoletane, taglieri, spritz",
    "ristoranti semplici ma curati, carne alla griglia",
]

INTOLERANCES = [
    "nessuna",
    "lattosio",
    "glutine leggero",
    "frutta secca",
    "piccante molto forte",
]

BIO_TEMPLATES = [
    "Mi piace conoscere persone nuove davanti a un buon piatto e una chiacchierata tranquilla.",
    "Cerco compagnia semplice e genuina per colazioni, pranzi e cene senza troppe formalità.",
    "Amo i locali accoglienti, le conversazioni leggere e le serate fatte bene.",
    "Mi fa piacere uscire dalla routine e condividere un pasto con persone positive.",
    "Preferisco incontri rilassati, buon cibo e gente educata con cui stare bene.",
    "Mi piace alternare colazioni lente, pause pranzo curate e cene in posti carini.",
]

ADDRESS_PREFIXES = [
    "Via Roma",
    "Via Garibaldi",
    "Via Mazzini",
    "Corso Italia",
    "Via Milano",
    "Via Torino",
    "Via Dante",
    "Piazza della Repubblica",
    "Via Manzoni",
    "Via Cavour",
]


@dataclass
class AnchorLocation:
    latitude: float
    longitude: float
    address_label: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Crea profili demo per la community.")
    parser.add_argument("--female", type=int, default=30, help="Numero profili femminili.")
    parser.add_argument("--male", type=int, default=20, help="Numero profili maschili.")
    parser.add_argument(
        "--anchor-email",
        type=str,
        default="",
        help="Email di un utente reale da usare come centro geografico.",
    )
    parser.add_argument(
        "--radius-km",
        type=float,
        default=35.0,
        help="Raggio massimo intorno all'utente àncora.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Non salva nulla: mostra solo cosa verrebbe creato.",
    )
    return parser.parse_args()


def choose_anchor(anchor_email: str) -> AnchorLocation:
    query = User.query.filter(
        User.is_admin.is_(False),
        User.verificato.is_(True),
    )
    if anchor_email.strip():
        user = query.filter(User.email == anchor_email.strip().lower()).first()
        if user is None:
            raise RuntimeError(f"Nessun utente trovato con email {anchor_email!r}.")
    else:
        user = query.order_by(User.id.asc()).first()

    if user is None:
        return AnchorLocation(
            latitude=DEFAULT_USER_LATITUDE,
            longitude=DEFAULT_USER_LONGITUDE,
            address_label="Milano",
        )

    return AnchorLocation(
        latitude=user.latitudine or DEFAULT_USER_LATITUDE,
        longitude=user.longitudine or DEFAULT_USER_LONGITUDE,
        address_label=(user.citta or "Milano").split(",")[-1].strip() or "Milano",
    )


def age_to_range(age: int) -> str:
    if age <= 25:
        return "18-25"
    if age <= 35:
        return "26-35"
    if age <= 45:
        return "36-45"
    if age <= 55:
        return "46-55"
    if age <= 65:
        return "56-65"
    return "65+"


def random_point_within(anchor: AnchorLocation, radius_km: float, rng: random.Random) -> tuple[float, float]:
    distance = rng.uniform(1.5, radius_km)
    bearing = rng.uniform(0, 2 * math.pi)
    delta_lat = (distance / 111.0) * math.cos(bearing)
    cos_lat = math.cos(math.radians(anchor.latitude))
    safe_cos_lat = cos_lat if abs(cos_lat) > 0.01 else 0.01
    delta_lon = (distance / (111.0 * safe_cos_lat)) * math.sin(bearing)
    return anchor.latitude + delta_lat, anchor.longitude + delta_lon


def build_address(anchor: AnchorLocation, index: int, rng: random.Random) -> str:
    street = rng.choice(ADDRESS_PREFIXES)
    number = rng.randint(3, 140)
    suffix = "" if index % 3 else f", Interno {rng.randint(1, 9)}"
    return f"{street} {number}{suffix}, {anchor.address_label}"


def build_bio(rng: random.Random) -> str:
    return rng.choice(BIO_TEMPLATES)


def portrait_url(gender: str, index: int) -> str:
    folder = "women" if gender == "femmina" else "men"
    return f"https://randomuser.me/api/portraits/{folder}/{index % 100}.jpg"


def download_profile_photo(url: str, filename: str) -> str:
    request = Request(url, headers={"User-Agent": "ApprofittOffroSeed/1.0"})
    try:
        with urlopen(request, timeout=20) as response:
            content_type = response.headers.get_content_type() or "image/jpeg"
            data = response.read()
        return upload_storage.save_bytes(filename, data, content_type=content_type)
    except (HTTPError, URLError, TimeoutError, OSError):
        return ensure_default_profile_placeholder()


def email_for_demo_user(gender: str, index: int) -> str:
    prefix = "f" if gender == "femmina" else "m"
    return f"demo-{prefix}{index:02d}@{EMAIL_DOMAIN}"


def create_demo_user(
    *,
    gender: str,
    index: int,
    name: str,
    surname: str,
    anchor: AnchorLocation,
    radius_km: float,
    rng: random.Random,
) -> User | None:
    email = email_for_demo_user(gender, index)
    existing = User.query.filter_by(email=email).first()
    if existing is not None:
        return None

    age = rng.randint(22, 62)
    latitude, longitude = random_point_within(anchor, radius_km=radius_km, rng=rng)
    address = build_address(anchor, index, rng)
    phone_number = f"347{index:07d}"
    user = User(
        nome=f"{name} {surname}",
        email=email,
        password_hash=generate_password_hash(PASSWORD_FOR_ALL),
        google_sub=None,
        foto_filename="",
        fascia_eta=age_to_range(age),
        eta=age,
        sesso=gender,
        numero_telefono=phone_number,
        latitudine=latitude,
        longitudine=longitude,
        citta=address,
        cibi_preferiti=rng.choice(FAVORITE_FOODS),
        intolleranze=rng.choice(INTOLERANCES),
        bio=build_bio(rng),
        raggio_azione=50,
        verificato=True,
        verification_token=None,
        is_admin=False,
        admin_verified_notified_at=local_now(),
        created_at=local_now() - timedelta(days=rng.randint(0, 45), hours=rng.randint(0, 20)),
    )
    db.session.add(user)
    db.session.flush()

    saved_photo = download_profile_photo(
        portrait_url(gender, index),
        f"seed_demo_users/{email.replace('@', '_at_')}.jpg",
    )
    replace_user_gallery(user, [saved_photo])
    db.session.flush()
    return user


def attach_follow_graph(users: list[User], rng: random.Random) -> int:
    created = 0
    user_ids = [user.id for user in users if user.id]
    if len(user_ids) < 3:
        return 0

    existing_pairs = {
        (follower_id, followed_id)
        for follower_id, followed_id in db.session.query(UserFollow.follower_id, UserFollow.followed_id).filter(
            UserFollow.follower_id.in_(user_ids),
            UserFollow.followed_id.in_(user_ids),
        )
    }

    for user in users:
        candidates = [other.id for other in users if other.id != user.id]
        rng.shuffle(candidates)
        for followed_id in candidates[: rng.randint(2, 4)]:
            pair = (user.id, followed_id)
            if pair in existing_pairs:
                continue
            db.session.add(UserFollow(follower_id=user.id, followed_id=followed_id))
            existing_pairs.add(pair)
            created += 1
    return created


def build_name_pool(gender: str, count: int, rng: random.Random) -> list[tuple[str, str]]:
    first_names = FEMALE_NAMES if gender == "femmina" else MALE_NAMES
    pool: list[tuple[str, str]] = []
    while len(pool) < count:
        rng.shuffle(first_names)
        rng.shuffle(SURNAMES)
        for first_name in first_names:
            for surname in SURNAMES:
                pool.append((first_name, surname))
                if len(pool) >= count:
                    return pool
    return pool


def main() -> int:
    args = parse_args()
    rng = random.Random(RANDOM_SEED)

    with app.app_context():
        anchor = choose_anchor(args.anchor_email)
        target_total = args.female + args.male
        print(
            f"[seed-demo-users] anchor={escape(anchor.address_label)} "
            f"lat={anchor.latitude:.5f} lon={anchor.longitude:.5f} "
            f"target={target_total} dry_run={args.dry_run}"
        )

        preview_names = build_name_pool("femmina", args.female, rng)[:2] + build_name_pool("maschio", args.male, rng)[:2]
        if args.dry_run:
            for idx, (first_name, surname) in enumerate(preview_names, start=1):
                print(f"  preview {idx}: {first_name} {surname}")
            print(f"Password demo condivisa: {PASSWORD_FOR_ALL}")
            return 0

        female_pool = build_name_pool("femmina", args.female, rng)
        male_pool = build_name_pool("maschio", args.male, rng)
        created_users: list[User] = []
        skipped = 0

        for index, (first_name, surname) in enumerate(female_pool, start=1):
            created = create_demo_user(
                gender="femmina",
                index=index,
                name=first_name,
                surname=surname,
                anchor=anchor,
                radius_km=args.radius_km,
                rng=rng,
            )
            if created is None:
                skipped += 1
            else:
                created_users.append(created)

        for offset, (first_name, surname) in enumerate(male_pool, start=1):
            absolute_index = args.female + offset
            created = create_demo_user(
                gender="maschio",
                index=absolute_index,
                name=first_name,
                surname=surname,
                anchor=anchor,
                radius_km=args.radius_km,
                rng=rng,
            )
            if created is None:
                skipped += 1
            else:
                created_users.append(created)

        follower_links = attach_follow_graph(created_users, rng)
        db.session.commit()

        print(
            f"[seed-demo-users] creati={len(created_users)} skipped={skipped} "
            f"followers={follower_links}"
        )
        print(f"[seed-demo-users] password demo condivisa: {PASSWORD_FOR_ALL}")
        print(f"[seed-demo-users] email dominio demo: *@{EMAIL_DOMAIN}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
