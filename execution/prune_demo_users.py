"""
Riduce in blocco i profili demo lasciando solo un sottoinsieme minimo.

Uso tipico:
    python execution/prune_demo_users.py

Comportamento predefinito:
- conserva le prime 10 demo femminili (demo-f01..demo-f10)
- elimina tutte le altre demo femminili
- elimina tutte le demo maschili
- pulisce follower, claims, recensioni, offerte, token push e foto collegate
- non invia email o notifiche durante la pulizia
"""

from __future__ import annotations

import argparse
import os

from sqlalchemy import or_

HOME_DIR = os.path.expanduser("~")
os.environ.setdefault("APP_ENV_FILE", os.path.join(HOME_DIR, ".env"))
if os.name != "nt" and "APP_DATA_DIR" not in os.environ:
    # Su PythonAnywhere il database live e gli upload stanno nella home utente.
    os.environ["APP_DATA_DIR"] = HOME_DIR

from app import SQLITE_PATH, UPLOAD_FOLDER, app, db, delete_upload_files, local_now
from models import Claim, DevicePushToken, Offer, Review, User, UserFollow, UserPhoto


EMAIL_DOMAIN = "demo.approfittoffro.local"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Elimina in blocco i profili demo lasciando solo un numero limitato di demo femminili.",
    )
    parser.add_argument(
        "--keep-female",
        type=int,
        default=10,
        help="Numero di demo femminili da conservare (ordinate per email).",
    )
    parser.add_argument(
        "--email-domain",
        default=EMAIL_DOMAIN,
        help="Dominio email usato per riconoscere i profili demo.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Non elimina nulla: mostra solo cosa verrebbe conservato e cancellato.",
    )
    return parser


def demo_users_query(email_domain: str):
    return User.query.filter(
        User.email.like(f"%@{email_domain}"),
        User.is_admin.is_(False),
    )


def pick_users_to_keep(email_domain: str, keep_female: int) -> tuple[list[User], list[User]]:
    demo_users = demo_users_query(email_domain).order_by(User.email.asc()).all()
    female_demo = [user for user in demo_users if (user.sesso or "").lower() == "femmina"]
    users_to_keep = female_demo[: max(0, keep_female)]
    keep_ids = {user.id for user in users_to_keep}
    users_to_delete = [user for user in demo_users if user.id not in keep_ids]
    return users_to_keep, users_to_delete


def prune_demo_users(*, email_domain: str, keep_female: int, dry_run: bool) -> int:
    users_to_keep, users_to_delete = pick_users_to_keep(email_domain, keep_female)

    print(f"[prune-demo-users] db={SQLITE_PATH} uploads={UPLOAD_FOLDER}")
    print(
        f"[prune-demo-users] dominio={email_domain} keep_female={keep_female} "
        f"keep={len(users_to_keep)} delete={len(users_to_delete)} dry_run={dry_run}"
    )

    if users_to_keep:
        print("[prune-demo-users] demo conservate:")
        for user in users_to_keep:
            print(f"  KEEP  {user.id:>4}  {user.email}  {user.nome}")

    if users_to_delete:
        print("[prune-demo-users] demo da eliminare:")
        for user in users_to_delete:
            print(f"  DROP  {user.id:>4}  {user.email}  {user.nome}")

    if dry_run or not users_to_delete:
        return 0

    delete_ids = [user.id for user in users_to_delete]
    now = local_now()

    gallery_files = [
        photo.filename
        for photo in UserPhoto.query.filter(UserPhoto.user_id.in_(delete_ids)).all()
        if getattr(photo, "filename", None)
    ]

    owned_offers = Offer.query.filter(Offer.user_id.in_(delete_ids)).all()
    owned_offer_ids = [offer.id for offer in owned_offers]
    offer_photo_files = [
        offer.foto_locale
        for offer in owned_offers
        if getattr(offer, "foto_locale", None)
    ]

    claims_on_other_offers_query = Claim.query.filter(Claim.user_id.in_(delete_ids))
    if owned_offer_ids:
        claims_on_other_offers_query = claims_on_other_offers_query.filter(
            ~Claim.offer_id.in_(owned_offer_ids),
        )
    claims_on_other_offers = claims_on_other_offers_query.all()

    for claim in claims_on_other_offers:
        offer = claim.offerta
        if offer:
            offer.posti_disponibili = min(
                offer.posti_totali,
                (offer.posti_disponibili or 0) + 1,
            )
            if offer.data_ora and offer.data_ora > now and offer.stato == "completata":
                offer.stato = "attiva"

    if owned_offer_ids:
        Review.query.filter(Review.offer_id.in_(owned_offer_ids)).delete(synchronize_session=False)
        Claim.query.filter(Claim.offer_id.in_(owned_offer_ids)).delete(synchronize_session=False)

    Claim.query.filter(Claim.user_id.in_(delete_ids)).delete(synchronize_session=False)
    Review.query.filter(
        or_(Review.reviewer_id.in_(delete_ids), Review.reviewed_id.in_(delete_ids))
    ).delete(synchronize_session=False)
    UserFollow.query.filter(
        or_(UserFollow.follower_id.in_(delete_ids), UserFollow.followed_id.in_(delete_ids))
    ).delete(synchronize_session=False)
    DevicePushToken.query.filter(DevicePushToken.user_id.in_(delete_ids)).delete(
        synchronize_session=False,
    )
    UserPhoto.query.filter(UserPhoto.user_id.in_(delete_ids)).delete(synchronize_session=False)
    Offer.query.filter(Offer.user_id.in_(delete_ids)).delete(synchronize_session=False)
    User.query.filter(User.id.in_(delete_ids)).delete(synchronize_session=False)
    db.session.commit()

    delete_upload_files(gallery_files + offer_photo_files)

    print(
        f"[prune-demo-users] eliminati={len(delete_ids)} "
        f"foto_profilo={len(gallery_files)} foto_offerte={len(offer_photo_files)}"
    )
    return 0


def main() -> int:
    args = build_parser().parse_args()
    with app.app_context():
        return prune_demo_users(
            email_domain=args.email_domain.strip(),
            keep_female=args.keep_female,
            dry_run=args.dry_run,
        )


if __name__ == "__main__":
    raise SystemExit(main())
