#!/usr/bin/env python3
"""
Script per correggere la query dell'host per mostrare eventi archiviati.
"""

def fix_host_query():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    old_code = '''    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Offer.user_id == current_user.id,
            Offer.stato.in_(["attiva", "completata"]),
        )
        if archived:
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
            )'''
    
    new_code = '''    if scope == "owned":
        offers_query = Offer.query.options(
            selectinload(Offer.autore).selectinload(User.photos),
            selectinload(Offer.claims).selectinload(Claim.utente).selectinload(User.photos),
        ).filter(
            Offer.user_id == current_user.id,
        )
        if archived:
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
                Offer.stato.in_(["attiva", "completata", "archiviata"]),
                Offer.data_ora > threshold,
            )'''
    
    if old_code in content:
        content = content.replace(old_code, new_code)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print("✓ Query host aggiornata - ora mostra eventi archiviati")
        return True
    else:
        print("⚠ Codice non trovato - potrebbe essere già aggiornato")
        return True

if __name__ == "__main__":
    print("=" * 50)
    print("Fix query host per eventi archiviati")
    print("=" * 50)
    fix_host_query()
