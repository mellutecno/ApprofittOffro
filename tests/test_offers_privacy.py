"""Eventi senza login: niente età, gusti, intolleranze e galleria dell'host, niente ospiti."""
import app as app_module

# Quello che la pagina iniziale dell'app legge dagli eventi (landing_page.dart).
LANDING_FIELDS = {
    "id",
    "tipo_pasto",
    "nome_locale",
    "indirizzo",
    "data_ora",
    "foto_locale",
    "foto_locale_gallery",
    "autore",
    "autore_foto",
    "claim_status",
    "can_claim",
}


def _host(make_user):
    return make_user("Host", eta=41, cibi_preferiti="sushi", intolleranze="lattosio, glutine")


def _payload(response, offer_id):
    assert response.status_code == 200, response.get_json()
    return next(item for item in response.get_json()["offers"] if item["id"] == offer_id)


def test_anonymous_feed_hides_login_only_fields(make_user, make_offer, make_claim, anon_client):
    offer = make_offer(_host(make_user))
    guest = make_user("Giulia Ospite")
    guest_photo = guest.foto_filename
    make_claim(guest, offer)

    response = anon_client.get("/api/offers?limit=20")  # come la pagina iniziale
    payload = _payload(response, offer.id)

    for key in app_module.LOGIN_ONLY_OFFER_FIELDS:
        assert key not in payload
    body = response.get_data(as_text=True)
    for private_value in ("lattosio", "sushi", "Giulia Ospite", guest_photo):
        assert private_value not in body


def test_anonymous_feed_keeps_what_the_landing_page_shows(make_user, make_offer, anon_client):
    host = _host(make_user)
    offer = make_offer(host)

    payload = _payload(anon_client.get("/api/offers?limit=20"), offer.id)

    assert LANDING_FIELDS <= payload.keys()
    assert payload["autore"] == "Host"
    assert payload["autore_foto"] == host.foto_filename
    assert payload["claim_status"] == "open"
    assert payload["can_claim"] is True


def test_logged_in_feed_keeps_author_details_and_guests(make_user, make_offer, make_claim, client_for):
    viewer, host = make_user("Spettatore"), _host(make_user)
    offer = make_offer(host)
    guest = make_user("Giulia Ospite")
    make_claim(guest, offer)

    payload = _payload(client_for(viewer).get("/api/offers"), offer.id)

    assert payload["autore_eta"] == "41"
    assert payload["autore_cibi_preferiti"] == "sushi"
    assert payload["autore_intolleranze"] == "lattosio, glutine"
    assert payload["autore_foto_gallery"] == [host.foto_filename]
    assert [(p["id"], p["nome"]) for p in payload["partecipanti"]] == [(guest.id, "Giulia Ospite")]


def test_offer_serializer_without_viewer_hides_login_only_fields(make_user, make_offer, make_claim):
    offer = make_offer(_host(make_user))
    make_claim(make_user("Giulia Ospite"), offer)

    payload = app_module.serialize_mobile_offer(offer)

    for key in app_module.LOGIN_ONLY_OFFER_FIELDS:
        assert key not in payload
    assert payload["autore"] == "Host"
