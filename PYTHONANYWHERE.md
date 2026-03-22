# PythonAnywhere + GitHub

Questa guida collega il deploy PythonAnywhere direttamente alla repo GitHub, evitando copie manuali in `~/mysite`.

## Obiettivo

- Codice sorgente: repo GitHub clonata in `/home/mellucci/ApprofittOffro`
- Dati persistenti: continuano a vivere in `/home/mellucci`
- Web app PythonAnywhere: importa `execution/app.py` dalla repo
- Static files: serviti dalla cartella `execution/static` della repo

## 1. Clona o aggiorna la repo su PythonAnywhere

```bash
cd ~
git clone https://github.com/mellutecno/ApprofittOffro.git
cd ~/ApprofittOffro
git pull --ff-only origin main
```

## 2. Mantieni i dati fuori repo

Il codice ora supporta queste variabili ambiente:

- `APP_ENV_FILE`
- `APP_DATA_DIR`
- `APP_DB_PATH`
- `APP_UPLOAD_FOLDER`
- `DATABASE_URL`

Per mantenere compatibili i dati attuali su PythonAnywhere, usa:

- `APP_ENV_FILE=/home/mellucci/.env`
- `APP_DATA_DIR=/home/mellucci`

Con questa configurazione:

- il database resta `/home/mellucci/approfittoffro.db`
- gli upload restano `/home/mellucci/uploads`

## 3. WSGI file consigliato

Nel file WSGI di PythonAnywhere usa questo contenuto:

```python
import os
import sys

repo_root = "/home/mellucci/ApprofittOffro"
execution_path = os.path.join(repo_root, "execution")

os.environ.setdefault("APP_ENV_FILE", "/home/mellucci/.env")
os.environ.setdefault("APP_DATA_DIR", "/home/mellucci")

if execution_path not in sys.path:
    sys.path.insert(0, execution_path)

from app import app as application
```

## 4. Static files mapping

Nel tab `Web` di PythonAnywhere imposta:

- URL: `/static/`
- Path: `/home/mellucci/ApprofittOffro/execution/static`

Se vuoi servire gli upload direttamente via web server, puoi anche aggiungere:

- URL: `/uploads/`
- Path: `/home/mellucci/uploads`

## 5. Deploy delle modifiche future

Workflow consigliato:

1. Modifica il codice in locale
2. `git push` su GitHub
3. Su PythonAnywhere:

```bash
cd ~/ApprofittOffro
git pull --ff-only origin main
touch /var/www/mellucci_pythonanywhere_com_wsgi.py
```

PythonAnywhere conferma che le web app devono essere ricaricate dopo modifiche al codice:
- https://help.pythonanywhere.com/pages/ReloadWebApp/

Per i file statici, PythonAnywhere consiglia una static files mapping dal path assoluto della cartella:
- https://help.pythonanywhere.com/pages/StaticFiles/

Per app Flask importate manualmente, PythonAnywhere usa un WSGI file che punta alla directory del progetto:
- https://help.pythonanywhere.com/pages/Flask

## 6. Importante

Non usare `~/mysite` come copia manuale del codice se vuoi che GitHub sia la sorgente unica. Tieni `~/mysite` solo come backup temporaneo finché il nuovo WSGI non è verificato.

## 7. Deploy automatico con `git push` (opzionale)

Se vuoi che un `git push` dal tuo PC aggiorni subito PythonAnywhere senza fare `git pull` a mano, PythonAnywhere documenta un flusso con bare repo + hook `post-receive`.

Nota: PythonAnywhere indica che questo workflow richiede accesso SSH, quindi in pratica serve un account a pagamento.

### Sul server PythonAnywhere

```bash
mkdir -p ~/bare-repos/approfittoffro.git
cd ~/bare-repos/approfittoffro.git
git init --bare
```

Crea `~/bare-repos/approfittoffro.git/hooks/post-receive` con questo contenuto:

```bash
#!/bin/bash
set -e

TARGET=/home/mellucci/ApprofittOffro
GIT_WORK_TREE="$TARGET" git checkout -f
touch /var/www/mellucci_pythonanywhere_com_wsgi.py
```

Poi rendilo eseguibile:

```bash
chmod +x ~/bare-repos/approfittoffro.git/hooks/post-receive
```

### Nel repo locale

```bash
git remote add pythonanywhere mellucci@ssh.pythonanywhere.com:/home/mellucci/bare-repos/approfittoffro.git
git push -u pythonanywhere main
```

Da quel momento:

1. `git push origin main` aggiorna GitHub
2. `git push pythonanywhere main` aggiorna PythonAnywhere e ricarica il sito

Riferimento ufficiale PythonAnywhere:
- https://blog.pythonanywhere.com/87/
