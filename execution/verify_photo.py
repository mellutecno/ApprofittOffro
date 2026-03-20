"""
Verifica foto utente per ApprofittOffro.
Controlla che l'immagine contenga almeno un volto umano
usando OpenCV Haar Cascades (nessuna dipendenza pesante).
"""

import cv2
import numpy as np
import os
import sys


def verifica_volto(image_path: str) -> dict:
    """
    Verifica che un'immagine contenga almeno un volto umano.
    
    Args:
        image_path: Percorso assoluto all'immagine da verificare.
        
    Returns:
        dict con:
            - valida (bool): True se contiene almeno un volto
            - num_volti (int): Numero di volti trovati
            - errore (str|None): Messaggio di errore se presente
    """
    # Controlla che il file esista
    if not os.path.exists(image_path):
        return {"valida": False, "num_volti": 0, "errore": "File non trovato"}

    # Carica l'immagine
    img = cv2.imread(image_path)
    if img is None:
        return {"valida": False, "num_volti": 0, "errore": "Impossibile leggere l'immagine"}

    # Converti in scala di grigi
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Carica il classificatore Haar per i volti (incluso in OpenCV)
    cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    face_cascade = cv2.CascadeClassifier(cascade_path)

    if face_cascade.empty():
        return {"valida": False, "num_volti": 0, "errore": "Classificatore non caricato"}

    # Rileva i volti
    faces = face_cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(80, 80),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )

    num_volti = len(faces)

    if num_volti == 0:
        return {
            "valida": False,
            "num_volti": 0,
            "errore": "Nessun volto rilevato nell'immagine. Carica una foto del tuo viso.",
        }

    return {"valida": True, "num_volti": num_volti, "errore": None}


if __name__ == "__main__":
    # Uso da riga di comando per test
    if len(sys.argv) < 2:
        print("Uso: python verify_photo.py <percorso_immagine>")
        sys.exit(1)

    risultato = verifica_volto(sys.argv[1])
    print(f"Risultato: {risultato}")
    sys.exit(0 if risultato["valida"] else 1)
