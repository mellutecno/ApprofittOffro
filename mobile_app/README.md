# ApprofittOffro Mobile

Frontend Flutter dedicato agli utenti mobili di ApprofittOffro.

## Obiettivo

- mantenere il backend Python/Flask esistente
- mantenere l'admin lato web
- rifare in Flutter solo l'esperienza utenti

## Stato attuale

Questa prima base copre:

- bootstrap app Flutter
- login via API `/api/login`
- sessione persistita via cookie Flask
- recupero utente corrente via `/api/user/me`
- dashboard offerte via `/api/offers`
- filtro `Colazioni / Pranzi / Cene`
- azione `Approfitta`
- shell pronta per `Community`, `Offri`, `Su di me`

## API backend usate

- `POST /api/login`
- `POST /api/logout`
- `GET /api/user/me`
- `GET /api/offers`
- `POST /api/offers/<id>/claim`
- `GET /uploads/<filename>`

## Installazione Flutter

Su questo PC il comando `flutter` non e` ancora installato. Quando lo installerai:

1. apri questa cartella
2. genera i file piattaforma mancanti:

```bash
flutter create . --platforms=android
```

3. scarica le dipendenze:

```bash
flutter pub get
```

4. avvia l'app puntando al backend che vuoi usare:

```bash
flutter run --dart-define=API_BASE_URL=https://mellucci.pythonanywhere.com
```

Oppure, per test su Render:

```bash
flutter run --dart-define=API_BASE_URL=https://approfittoffro.onrender.com
```

## Prossimi step consigliati

1. Registrazione utente con upload foto
2. Community con filtro eta`
3. Profilo completo con galleria
4. Creazione offerta in Flutter
5. Google Maps / Places al posto di OpenStreetMap
6. build Android (`AAB` / `APK`)
