#!/usr/bin/env python3
"""
Script per aggiornare le query dell'archivio per includere lo stato 'archiviata'.
Eseguire questo script nella Bash console di PythonAnywhere.
"""

import re

def fix_archive_states():
    filepath = "execution/app.py"
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Sostituisci gli stati per includere 'archiviata'
    replacements = [
        ('Offer.stato.in_(["attiva", "completata"])', 'Offer.stato.in_(["attiva", "completata", "archiviata"])'),
    ]
    
    changes = 0
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            changes += 1
            print(f"✓ Sostituito: {old}")
    
    if changes == 0:
        print("⚠ Nessuna modifica necessaria - 'archiviata' già incluso")
        return True
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✓ {changes} modifica/e applicata/e!")
    return True

if __name__ == "__main__":
    print("=" * 50)
    print("Fix: include stato 'archiviata' nelle query")
    print("=" * 50)
    fix_archive_states()
