#!/usr/bin/env python3
"""
Script storico per aggiungere l'endpoint di archiviazione offerte al backend.
Eseguire questo script solo su una copia locale del progetto o su un deploy controllato.

Uso: python3 add_archive_endpoint.py
"""

import re
import sys

ARCHIVE_ENDPOINT = '''

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

def add_archive_endpoint_to_app():
    """Aggiunge l'endpoint di archiviazione a app.py"""
    filepath = "app.py"
    
    # Leggi il file
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Controlla se l'endpoint esiste già
    if 'def api_archive_offer' in content:
        print("✓ L'endpoint api_archive_offer esiste già in app.py")
        return True
    
    # Trova il punto di inserimento: prima di @app.route("/api/offers", methods=["POST"])
    pattern = r'(@app\.route\("/api/offers", methods\["POST"\])'
    match = re.search(pattern, content)
    
    if not match:
        print("✗ Non trovo @app.route('/api/offers', methods=['POST']) in app.py")
        return False
    
    # Inserisci l'endpoint prima di /api/offers POST
    position = match.start()
    new_content = content[:position] + ARCHIVE_ENDPOINT + '\n\n' + content[position:]
    
    # Scrivi il file
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print("✓ Endpoint api_archive_offer aggiunto a app.py")
    return True

def update_models():
    """Aggiorna models.py per supportare lo stato 'archiviata'"""
    filepath = "models.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Controlla se già aggiornato
    if 'archiviata' in content and 'stato = db.Column' in content:
        # Sostituisci il commento per includere archiviata
        old_pattern = r'(stato = db\.Column\(db\.String\(20\), default="attiva"\))  #.*'
        new_text = r'\1  # attiva, completata, annullata, archiviata'
        new_content = re.sub(old_pattern, new_text, content)
        
        if new_content != content:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print("✓ models.py aggiornato per supportare 'archiviata'")
        else:
            print("✓ models.py già configurato per 'archiviata'")
        return True
    
    print("⚠ models.py non necessita modifiche (usa validazione runtime)")
    return True

def main():
    print("=" * 50)
    print("Aggiunta endpoint archiviazione offerte")
    print("=" * 50)
    
    success = True
    
    # Aggiungi endpoint
    if not add_archive_endpoint_to_app():
        success = False
    
    # Aggiorna models
    if not update_models():
        success = False
    
    print("=" * 50)
    if success:
        print("✓ Completato! Ora ricarica l'app WSGI.")
        print("  Vai su: Web → il tuo sito → Reload")
    else:
        print("✗ Errore! Controlla i messaggi sopra.")
        sys.exit(1)

if __name__ == "__main__":
    main()
