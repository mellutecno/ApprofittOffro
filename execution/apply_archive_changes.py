#!/usr/bin/env python3
"""
Script storico per aggiungere le modifiche dell'archivio al backend.
"""

def add_archive_modifications():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    changes = 0
    
    # 1. Aggiungi endpoint archive dopo api_edit_offer
    archive_endpoint = '''

@app.route("/api/offers/<int:offer_id>/archive", methods=["POST"])
@login_required
def api_archive_offer(offer_id):
    """Archivia un'offerta passata da parte dell'host."""
    offer = Offer.query.get_or_404(offer_id)
    if not can_manage_offer(offer, current_user):
        return jsonify({"success": False, "error": "Non autorizzato."}), 403
    
    if offer.stato == "archiviata":
        return jsonify({"success": False, "error": "Offerta già archiviata."}), 400
    
    offer.stato = "archiviata"
    offer.posti_disponibili = 0
    db.session.commit()
    return jsonify({"success": True, "message": "Offerta archiviata.", "offer_id": offer.id})

'''
    
    # Trova il punto di inserimento prima di @app.route("/api/offers", methods=["POST"])
    if 'def api_archive_offer' not in content:
        if '@app.route("/api/offers", methods=["POST"])' in content:
            content = content.replace(
                '@app.route("/api/offers", methods=["POST"])',
                archive_endpoint + '@app.route("/api/offers", methods=["POST"])'
            )
            changes += 1
            print("✓ Endpoint archive aggiunto")
        else:
            print("⚠ Punto di inserimento endpoint non trovato")
    
    # 2. Modifica query owned - lista host (non archivio)
    old_owned_filter = '''    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Offer.user_id == current_user.id,
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
            offers_query = offers_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(Offer.data_ora > threshold)'''
    
    new_owned_filter = '''    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Offer.user_id == current_user.id,
        )
        if archived:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora > threshold,
            )'''
    
    if old_owned_filter in content:
        content = content.replace(old_owned_filter, new_owned_filter)
        changes += 1
        print("✓ Query owned aggiornata")
    
    # 3. Modifica query claimed - lista guest (non archivio)
    old_claimed_filter = '''    elif scope == "claimed":
        claims_query = Claim.query.join(Offer, Claim.offer_id == Offer.id).options(
            selectinload(Claim.utente).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Claim.user_id == current_user.id,
            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
            claims_query = claims_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(Offer.data_ora > threshold)'''
    
    new_claimed_filter = '''    elif scope == "claimed":
        claims_query = Claim.query.join(Offer, Claim.offer_id == Offer.id).options(
            selectinload(Claim.utente).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Claim.user_id == current_user.id,
            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
        )
        if archived:
            from sqlalchemy import or_
            claims_query = claims_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora > threshold,
            )'''
    
    if old_claimed_filter in content:
        content = content.replace(old_claimed_filter, new_claimed_filter)
        changes += 1
        print("✓ Query claimed aggiornata")
    
    if changes == 0:
        print("⚠ Nessuna modifica necessaria")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✓ {changes} modifica/e applicata/e!")
    return True

if __name__ == "__main__":
    print("=" * 50)
    print("Modifiche archivio")
    print("=" * 50)
    add_archive_modifications()
