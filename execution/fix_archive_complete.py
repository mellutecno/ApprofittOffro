#!/usr/bin/env python3
"""
Script per aggiornare app.py per includere offerte archiviate nell'archivio profilo.
Eseguire questo script nella Bash console di PythonAnywhere.

Uso: python3 fix_archive_complete.py
"""

def fix_archive_complete():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    changes = 0
    
    # Fix 1: owned query - aggiungi archiviata agli stati
    old_owned = '''        )
        if archived:
            offers_query = offers_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(Offer.data_ora > threshold)
        offers = offers_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_owned = '''        )
        if archived:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()'''
    
    if old_owned in content:
        content = content.replace(old_owned, new_owned)
        changes += 1
        print("✓ Sezione 'owned' aggiornata")
    
    # Fix 2: claimed query - aggiungi archiviata agli stati
    old_claimed = '''            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
            claims_query = claims_query.filter(
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(Offer.data_ora > threshold)
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_claimed = '''            Claim.status.in_([CLAIM_STATUS_PENDING, CLAIM_STATUS_ACCEPTED]),
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    if old_claimed in content:
        content = content.replace(old_claimed, new_claimed)
        changes += 1
        print("✓ Sezione 'claimed' aggiornata")
    
    if changes == 0:
        print("⚠ Nessuna modifica necessaria")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✓ {changes} modifica/e applicata/e!")
    return True

if __name__ == "__main__":
    print("=" * 50)
    print("Fix completo archivio profilo")
    print("=" * 50)
    fix_archive_complete()
