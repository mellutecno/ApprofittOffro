# ApprofittOffro - Fase 1 su Render + Postgres + R2

Questa fase porta l'app online su un'infrastruttura seria senza cambiare ancora dominio o branding finale.

## Obiettivo della fase 1

- Flask app su Render
- PostgreSQL gestito da Render
- immagini e upload su Cloudflare R2
- deploy ripetibile dal repository Git

## Prerequisiti

Hai già preparato:

- un database Render Postgres chiamato `approfittoffro-db`
- un bucket R2 chiamato `approfittoffro-uploads`
- chiavi R2 per accesso `Object Read & Write`

Importante:

- se le chiavi R2 sono finite in screenshot o chat, rigenerale prima del deploy finale

## File aggiunti in questa fase

- `render.yaml`: blueprint Render del web service
- `execution/migrate_sqlite_to_postgres.py`: migra i dati dall'attuale SQLite a Postgres
- `execution/migrate_uploads_to_r2.py`: carica gli upload locali su R2

## Variabili ambiente Render da impostare

Il blueprint imposta da solo:

- `DATABASE_URL` dal database Render
- `SECRET_KEY`
- `APP_TIMEZONE=Europe/Rome`
- `APP_STORAGE_BACKEND=r2`
- `APP_UPLOAD_FOLDER=/tmp/approfittoffro-uploads`

Devi aggiungere manualmente nel web service:

- `MAIL_USERNAME`
- `MAIL_PASSWORD`
- `MAIL_DEFAULT_SENDER`
- `EMAIL_PROVIDER`
- `RESEND_API_KEY`
- `RESEND_REPLY_TO`
- `ADMIN_EMAIL`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET_NAME=approfittoffro-uploads`

Opzionale:

- `R2_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com`

Se non la imposti, l'app la ricava da `R2_ACCOUNT_ID`.

Per le email:

- su PythonAnywhere puoi continuare con `EMAIL_PROVIDER=smtp`
- su Render conviene usare `EMAIL_PROVIDER=resend`
- con Resend, `MAIL_DEFAULT_SENDER` deve essere un mittente valido del dominio verificato
- `RESEND_REPLY_TO` e` opzionale, ma consigliato

Importante per il database:

- il `DATABASE_URL` del blueprint e` marcato `sync: false`
- se web service e database stanno in region diverse, devi incollare manualmente l'`External Database URL`
- se in futuro li allinei nella stessa region, puoi anche usare l'URL interno

## Come creare il web service

1. Collega il repository GitHub a Render.
2. Crea il servizio dal file `render.yaml` oppure crea manualmente un `Web Service`.
3. Se lo crei manualmente, usa:
   - Build command: `pip install -r requirements.txt`
   - Start command: `cd execution && gunicorn app:app --bind 0.0.0.0:$PORT --workers 2 --threads 4 --timeout 120`
4. Inserisci le variabili ambiente mancanti.
5. Esegui il primo deploy.

## Migrazione database

Una volta che il web service è pronto e le env vars sono impostate, dal tuo ambiente locale puoi migrare i dati così:

```bash
cd execution
python migrate_sqlite_to_postgres.py --source "..\\approfittoffro.db"
```

In alternativa puoi usare una sorgente diversa:

```bash
cd execution
python migrate_sqlite_to_postgres.py --source "C:\\percorso\\database.sqlite"
```

Lo script:

- crea le tabelle se mancano
- copia utenti, offerte, claim, recensioni, foto profilo e follow
- riallinea le sequence di Postgres dopo l'import

## Migrazione upload

Dopo aver configurato R2 nelle env vars, carica gli upload esistenti:

```bash
cd execution
python migrate_uploads_to_r2.py --source "..\\uploads"
```

Lo script:

- legge i file dalla cartella locale
- li carica nel bucket R2
- salta directory vuote o file mancanti

## Smoke test finale

Dopo migrazione dati e upload, controlla:

- registrazione
- login
- apertura profili
- upload foto profilo
- creazione offerta con foto
- dashboard offerte
- notifiche email
- area admin
- WhatsApp host/partecipanti

## Note operative

- in locale, senza `APP_STORAGE_BACKEND=r2`, l'app continua a usare la cartella `uploads/`
- in produzione, con `APP_STORAGE_BACKEND=r2`, la route `/uploads/<filename>` continua a funzionare ma legge i file da R2
- il database SQLite resta solo fallback locale / storico
