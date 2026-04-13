#!/usr/bin/env python3
"""
Script per applicare le modifiche archivio al backend PythonAnywhere.
Esegui questo script da ~/ApprofittOffro/
"""

import re

APP_PATH = "app.py"

def read_file():
    with open(APP_PATH, "r", encoding="utf-8") as f:
        return f.read()

def write_file(content):
    with open(APP_PATH, "w", encoding="utf-8") as f:
        f.write(content)

def has_endpoint():
    content = read_file()
    return "def api_archive_offer" in content

def add_archive_endpoint():
    """Aggiunge l'endpoint /api/offers/<id>/archive"""
    content = read_file()
    
    if has_endpoint():
        print("✓ Endpoint archive gia presente")
        return
    
    archive_endpoint = '''
@app.route("/api/offers/<int:offer_id>/archive", methods=["POST"])
@login_required
def api_archive_offer(offer_id):
    """Archivia un'offerta (solo l'host puo farlo)"""
    offer = Offer.query.get_or_404(offer_id)
    
    if offer.host_id != current_user.id:
        abort(403)
    
    offer.archived = True
    db.session.commit()
    
    return jsonify({"success": True, "archived": True})
'''
    
    content = content.replace(
        '@app.route("/api/offers", methods=["POST"])',
        archive_endpoint + '\n@app.route("/api/offers", methods=["POST"])'
    )
    
    write_file(content)
    print("✓ Endpoint archive aggiunto")

def fix_owned_query():
    """Modifica la query owned per includere eventi archiviati"""
    content = read_file()
    
    old_owned = '''        if owned:
            query = query.filter(
                Offer.host_id == current_user.id
            )
            if archived:
                query = query.filter(
                    Offer.data_ora >= archive_start,
                )'''
    
    new_owned = '''        if owned:
            query = query.filter(
                Offer.host_id == current_user.id
            )
            if not archived:
                query = query.filter(Offer.archived == False)
            else:
                query = query.filter(
                    db.or_(
                        db.and_(
                            Offer.archived == True,
                            Offer.data_ora >= archive_start
                        ),
                        Offer.archived == False
                    )
                )'''
    
    if old_owned in content and 'if not archived:' not in content:
        content = content.replace(old_owned, new_owned)
        write_file(content)
        print("✓ Query owned aggiornata")
    else:
        print("✓ Query owned gia corretta")

def fix_claimed_query():
    """Modifica la query claimed per mostrare eventi archiviati dall'host"""
    content = read_file()
    
    old_claimed = '''        if claimed:
            query = query.join(Claim)
            query = query.filter(Claim.user_id == current_user.id)
            if archived:
                query = query.filter(
                    Offer.data_ora >= archive_start,
                )'''
    
    new_claimed = '''        if claimed:
            query = query.join(Claim)
            query = query.filter(Claim.user_id == current_user.id)
            if not archived:
                query = query.filter(
                    db.or_(
                        Offer.host_id != current_user.id,
                        Offer.archived == False
                    )
                )
            else:
                query = query.filter(
                    db.or_(
                        Offer.host_id == current_user.id,
                        db.and_(
                            Offer.archived == True,
                            Offer.data_ora >= archive_start
                        )
                    )
                )'''
    
    if old_claimed in content and 'if not archived:' not in content:
        content = content.replace(old_claimed, new_claimed)
        write_file(content)
        print("✓ Query claimed aggiornata")
    else:
        print("✓ Query claimed gia corretta")

def main():
    print("Applicazione modifiche archivio a PythonAnywhere...")
    print("=" * 50)
    
    add_archive_endpoint()
    fix_owned_query()
    fix_claimed_query()
    
    print("=" * 50)
    print("Fatto! Riavvia l'app su PythonAnywhere per applicare le modifiche.")

if __name__ == "__main__":
    main()
