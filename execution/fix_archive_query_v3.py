#!/usr/bin/env python3
"""
Script per correggere la query dell'archivio su PythonAnywhere.
L'archivio mostra:
- Eventi > 24 ore (automatici)
- OPPURE eventi archiviati manualmente (stato = archiviata)
"""

def fix_archive_query():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    changes = 0
    
    # Fix 1: owned query
    old_owned = '''        if archived:
            offers_query = offers_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )'''
    
    new_owned = '''        if archived:
            from sqlalchemy import or_
            offers_query = offers_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
                Offer.data_ora >= archive_start,
            )'''
    
    if old_owned in content:
        content = content.replace(old_owned, new_owned)
        changes += 1
        print("✓ Sezione 'owned' corretta")
    
    # Fix 2: claimed query
    old_claimed = '''        if archived:
            claims_query = claims_query.filter(
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora <= threshold,
                Offer.data_ora >= archive_start,
            )'''
    
    new_claimed = '''        if archived:
            from sqlalchemy import or_
            claims_query = claims_query.filter(
                or_(
                    Offer.stato == "archiviata",
                    Offer.data_ora <= threshold,
                ),
                Offer.data_ora >= archive_start,
            )'''
    
    if old_claimed in content:
        content = content.replace(old_claimed, new_claimed)
        changes += 1
        print("✓ Sezione 'claimed' corretta")
    
    if changes == 0:
        print("⚠ Nessuna modifica necessaria")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✓ {changes} fix applicato!")
    return True

if __name__ == "__main__":
    print("=" * 50)
    print("Fix query archivio v3")
    print("=" * 50)
    fix_archive_query()
