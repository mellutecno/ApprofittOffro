# Direttiva: Applicazione ApprofittOffro

## Obiettivo
Applicazione web dove utenti registrati possono offrire o approfittare di colazioni, pranzi e cene in locali nella propria zona.

## Flussi Principali

### 1. Registrazione
- Input: nome, email, password, foto (con volto), fascia d'età, posizione su mappa
- Verifica: `execution/verify_photo.py` controlla presenza volto
- Output: utente salvato nel database, redirect a login

### 2. Login
- Input: email + password
- Output: sessione autenticata, redirect a dashboard

### 3. Crea Offerta
- Input: tipo pasto, nome locale, indirizzo, posizione mappa, numero posti, data/ora, descrizione
- Output: offerta salvata, visibile ad altri utenti nella zona

### 4. Approfitta di un'Offerta
- Input: click su "Approfitta"
- Regola: posti_disponibili -= 1. Se posti_disponibili == 0 → offerta non più disponibile
- Vincolo: un utente non può approfittare della propria offerta

### 5. Dashboard
- Mostra mappa con offerte nella zona
- Lista offerte filtrabile per tipo pasto
- Profilo utente

## Strumenti (execution/)
- `app.py` — Server Flask principale
- `models.py` — Modelli database
- `verify_photo.py` — Verifica foto con rilevamento volto

## Fasce d'Età
18-25, 26-35, 36-45, 46-55, 56-65, 65+

## Casi Limite
- Foto senza volto → registrazione rifiutata
- Posti esauriti → bottone "Approfitta" disabilitato
- Utente tenta di approfittare della propria offerta → bloccato
- Offerta scaduta (data passata) → non mostrata
