#!/usr/bin/env python3
"""
Script per correggere definitivamente la query dell'archivio su PythonAnywhere.
"""

def fix_archive():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    changes = 0
    
    # Fix 1: owned query - versione attuale
    old_owned = '''        if archived:
            offers_query = offers_query.filter(
                Offer.data_ora >= archive_start,
            )
        else:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        offers = offers_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_owned = '''        if archived:
            from sqlalchemy import or_
            offers_query = offers_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
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
        print("✓ Sezione 'owned' corretta")
    
    # Fix 2: claimed query - versione attuale
    old_claimed = '''        if archived:
            claims_query = claims_query.filter(
                Offer.data_ora >= archive_start,
            )
        else:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    new_claimed = '''        if archived:
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
                Offer.stato.in_(["attiva", "completata"]),
                Offer.data_ora > threshold,
            )
        claims = claims_query.order_by(Offer.data_ora.desc()).all()'''
    
    if old_claimed in content:
        content = content.replace(old_claimed, new_claimed)
        changes += 1
        print("✓ Sezione 'claimed' corretta")
    
    if changes == 0:
        print("⚠ Nessuna modifica necessaria o struttura non riconosciuta")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✓ {changes} fix applicato!")
    return True

if __name__ == "__main__":
    print("=" * 50)
    print("Fix query archivio definitivo")
    print("=" * 50)
    fix_archive()
