#!/usr/bin/env python3
"""
Script per aggiornare app.py per mostrare offerte archiviate nell'archivio profilo.
Eseguire questo script nella Bash console di PythonAnywhere.

Uso: python3 fix_archive_query.py
"""

import re

FIX_CODE = '''    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        )
        if archived:
            # Include offerte attive, completate O archiviate dall'utente
            offers_query = offers_query.filter(
                Offer.user_id == current_user.id,
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.user_id == current_user.id,
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()
        result = [
            serialize_mobile_offer(offer, viewer=current_user, now=now)
            for offer in offers
        ]
    elif scope == "claimed":
        claims_query = Claim.query.join(Offer, Claim.offer_id == Offer.id).options(
            selectinload(Claim.utente).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Claim.offerta).selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        )
        if archived:
            # Include offerte attive, completate O archiviate dove l'utente ha partecipato
            claims_query = claims_query.filter(
                Claim.user_id == current_user.id,
                Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Claim.user_id == current_user.id,
                Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )'''

def fix_archive_query():
    """Aggiorna la query archivio per includere offerte con stato archiviata"""
    filepath = "app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Controlla se già applicata la fix
    if 'Offer.stato.in_(["attiva", "completata", "archiviata"])' in content:
        print("✓ La fix è già applicata!")
        return True
    
    # Cerca e sostituisce il blocco scope == "owned"
    old_owned = r'''    if scope == "owned":
        offers_query = Offer\.query\.options\(
            selectinload\(Offer\.autore\)\.selectinload\(User\.photos\),
            selectinload\(Offer\.claims\)\.selectinload\(Claim\.utente\)\.selectinload\(User\.photos\),
        \)\.filter\(
            Offer\.user_id == current_user\.id,
            Offer\.stato\.in_\(\["attiva", "completata"\]\),
        \)
        if archived:
            offers_query = offers_query\.filter\(
                Offer\.data_ora <= threshold,
                Offer\.data_ora >= archive_start,
            \)
        else:
            offers_query = offers_query\.filter\(Offer\.data_ora > threshold\)
        offers = offers_query\.order_by\(Offer\.data_ora\.desc\(\)\)\.all\(\)
        result = \[
            serialize_mobile_offer\(offer, viewer=current_user, now=now\)
            for offer in offers
        \]
    elif scope == "claimed":
        claims_query = Claim\.query\.join\(Offer, Claim\.offer_id == Offer\.id\)\.options\(
            selectinload\(Claim\.utente\)\.selectinload\(User\.photos\),
            selectinload\(Claim\.offerta\)\.selectinload\(Offer\.autore\)\.selectinload\(User\.photos\),
            selectinload\(Claim\.offerta\)\.selectinload\(Offer\.claims\)\.selectinload\(Claim\.utente\)\.selectinload\(User\.photos\),
        \)\.filter\(
            Claim\.user_id == current_user\.id,
            Claim\.status\.in_\(\[CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED\]\),
            Offer\.stato\.in_\(\["attiva", "completata"\]\),
        \)
        if archived:
            claims_query = claims_query\.filter\(
                Offer\.data_ora <= threshold,
                Offer\.data_ora >= archive_start,
            \)
        else:
            claims_query = claims_query\.filter\(Offer\.data_ora > threshold\)'''
    
    # Semplifica: cerca e sostituisci sezioni specifiche
    # Prima sezione: owned query
    old_owned_block = '''        if archived:
            offers_query = offers_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(Offer.data_ora > threshold)
        offers = offers_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_owned_block = '''        if archived:
            offers_query = offers_query.filter(
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()'''
    
    # Seconda sezione: claimed query
    old_claimed_block = '''        if archived:
            claims_query = claims_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(Offer.data_ora > threshold)
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_claimed_block = '''        if archived:
            claims_query = claims_query.filter(
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    modified = False
    
    if old_owned_block in content and new_owned_block not in content:
        content = content.replace(old_owned_block, new_owned_block)
        modified = True
        print("✓ Sezione 'owned' aggiornata")
    
    if old_claimed_block in content and new_claimed_block not in content:
        content = content.replace(old_claimed_block, new_claimed_block)
        modified = True
        print("✓ Sezione 'claimed' aggiornata")
    
    if not modified:
        print("⚠ Nessuna modifica necessaria o già applicata")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ File app.py aggiornato!")
    return True

def main():
    print("=" * 50)
    print("Fix archivio profilo - mostra offerte archiviate")
    print("=" * 50)
    
    success = fix_archive_query()
    
    print("=" * 50)
    if success:
        print("✓ Completato! Ricarica l'app WSGI.")
    else:
        print("✗ Errore!")
    
if __name__ == "__main__":
    main()
