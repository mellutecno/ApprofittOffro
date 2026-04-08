"""
Invia reminder push schedulati per ApprofittOffro.

Uso consigliato:
    python execution/send_scheduled_push_reminders.py --dry-run
    python execution/send_scheduled_push_reminders.py

Il job invia, una sola volta per destinatario:
- reminder evento imminente (default: entro 2 ore)
- reminder recensione da lasciare (default: da 3 ore dopo l'evento, guardando 72 ore indietro)
"""

import argparse
import os

HOME_DIR = os.path.expanduser("~")
os.environ.setdefault("APP_ENV_FILE", os.path.join(HOME_DIR, ".env"))
if os.name != "nt" and "APP_DATA_DIR" not in os.environ:
    # Su PythonAnywhere il database live e gli upload stanno nella home utente.
    os.environ["APP_DATA_DIR"] = HOME_DIR

from app import (
    SQLITE_PATH,
    Offer,
    app,
    local_now,
    send_pending_review_reminders,
    send_upcoming_event_reminders,
)


def build_parser():
    parser = argparse.ArgumentParser(
        description="Invia reminder push schedulati (eventi imminenti e recensioni)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Mostra quanti reminder verrebbero inviati senza inviare nulla.",
    )
    parser.add_argument(
        "--upcoming-hours",
        type=int,
        default=2,
        help="Finestra in ore per considerare un evento imminente (default: 2).",
    )
    parser.add_argument(
        "--review-delay-hours",
        type=int,
        default=3,
        help="Ore da attendere dopo l'evento prima di ricordare la recensione (default: 3).",
    )
    parser.add_argument(
        "--review-lookback-hours",
        type=int,
        default=72,
        help="Quante ore indietro considerare per cercare recensioni mancanti (default: 72).",
    )
    parser.add_argument(
        "--skip-upcoming",
        action="store_true",
        help="Salta i reminder evento imminente.",
    )
    parser.add_argument(
        "--skip-review",
        action="store_true",
        help="Salta i reminder recensione da lasciare.",
    )
    parser.add_argument(
        "--debug-offers",
        action="store_true",
        help="Mostra i prossimi eventi visti dal server per diagnosticare il reminder.",
    )
    return parser


def main():
    args = build_parser().parse_args()

    with app.app_context():
        now = local_now()
        print(
            f"[REMINDER_JOB] now={now.isoformat()} dry_run={args.dry_run} db={SQLITE_PATH}"
        )

        if args.debug_offers:
            debug_upper_bound = now + timedelta(hours=max(args.upcoming_hours, 12))
            debug_offers = (
                Offer.query.filter(
                    Offer.stato == "attiva",
                    Offer.data_ora > now,
                    Offer.data_ora <= debug_upper_bound,
                )
                .order_by(Offer.data_ora.asc())
                .all()
            )
            print(
                "[REMINDER_DEBUG_OFFERS] "
                f"count={len(debug_offers)} "
                f"window_end={debug_upper_bound.isoformat()}"
            )
            for offer in debug_offers[:20]:
                print(
                    "[REMINDER_DEBUG_OFFER] "
                    f"id={offer.id} "
                    f"meal={offer.tipo_pasto} "
                    f"starts_at={offer.data_ora.isoformat()} "
                    f"status={offer.stato} "
                    f"host_id={offer.user_id} "
                    f"locale={offer.nome_locale}"
                )

        if not args.skip_upcoming:
            upcoming_stats = send_upcoming_event_reminders(
                now=now,
                hours_ahead=args.upcoming_hours,
                dry_run=args.dry_run,
            )
            print(
                "[REMINDER_UPCOMING] "
                f"offers={upcoming_stats['offers_considered']} "
                f"host={upcoming_stats['sent']['host']} "
                f"participants={upcoming_stats['sent']['participants']} "
                f"skipped={upcoming_stats['skipped']} "
                f"window_end={upcoming_stats['window_end']}"
            )

        if not args.skip_review:
            review_stats = send_pending_review_reminders(
                now=now,
                delay_hours=args.review_delay_hours,
                lookback_hours=args.review_lookback_hours,
                dry_run=args.dry_run,
            )
            print(
                "[REMINDER_REVIEW] "
                f"offers={review_stats['offers_considered']} "
                f"sent={review_stats['sent']} "
                f"skipped={review_stats['skipped']} "
                f"threshold={review_stats['threshold']}"
            )


if __name__ == "__main__":
    main()
