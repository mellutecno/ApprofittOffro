class AppGuideContent {
  const AppGuideContent({
    required this.version,
    required this.title,
    required this.subtitle,
    required this.highlights,
    required this.premiumIntro,
    required this.premiumNote,
    required this.premiumFeatures,
    required this.sections,
  });

  final int version;
  final String title;
  final String subtitle;
  final List<AppGuideHighlight> highlights;
  final String premiumIntro;
  final String premiumNote;
  final List<AppGuidePremiumFeature> premiumFeatures;
  final List<AppGuideSection> sections;

  factory AppGuideContent.fromJson(Map<String, dynamic> json) {
    return AppGuideContent(
      version: json['version'] as int? ?? fallback.version,
      title: (json['title'] ?? fallback.title).toString(),
      subtitle: (json['subtitle'] ?? fallback.subtitle).toString(),
      highlights: (json['highlights'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AppGuideHighlight.fromJson)
          .toList(),
      premiumIntro: (json['premium_intro'] ?? fallback.premiumIntro).toString(),
      premiumNote: (json['premium_note'] ?? fallback.premiumNote).toString(),
      premiumFeatures: (json['premium_features'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AppGuidePremiumFeature.fromJson)
          .toList(),
      sections: (json['sections'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(AppGuideSection.fromJson)
          .toList(),
    ).withFallbackLists();
  }

  AppGuideContent withFallbackLists() {
    return AppGuideContent(
      version: version,
      title: title.trim().isEmpty ? fallback.title : title,
      subtitle: subtitle.trim().isEmpty ? fallback.subtitle : subtitle,
      highlights: highlights.isEmpty ? fallback.highlights : highlights,
      premiumIntro:
          premiumIntro.trim().isEmpty ? fallback.premiumIntro : premiumIntro,
      premiumNote:
          premiumNote.trim().isEmpty ? fallback.premiumNote : premiumNote,
      premiumFeatures:
          premiumFeatures.isEmpty ? fallback.premiumFeatures : premiumFeatures,
      sections: sections.isEmpty ? fallback.sections : sections,
    );
  }

  static const fallback = AppGuideContent(
    version: 3,
    title: 'Benvenuto in ApprofittOffro',
    subtitle:
        'Qui trovi le funzioni principali dell\'app, le novita e i punti da ricordare per usarla meglio.',
    highlights: [
      AppGuideHighlight(
        icon: 'workspace_premium',
        text: 'Le funzioni Premium sono riconoscibili dal lucchetto dedicato.',
      ),
      AppGuideHighlight(
        icon: 'notifications',
        text: 'Le notifiche restano nel centro notifiche per 24 ore.',
      ),
      AppGuideHighlight(
        icon: 'bug_report',
        text: 'Le segnalazioni bug utili possono ricevere punti.',
      ),
      AppGuideHighlight(
        icon: 'admin_panel',
        text: 'La moderazione protegge profili, offerte, chat e segnalazioni.',
      ),
    ],
    premiumIntro:
        'Alcune funzioni avanzate sono riservate agli utenti Premium. Per ora abbiamo inserito questa prima voce, poi la tabella crescera con le prossime novita.',
    premiumNote:
        'Premium richiede un abbonamento attivo. Gli ApprofittOffro Points potranno permettere di ottenere mesi Premium gratuiti quando saranno disponibili.',
    premiumFeatures: [
      AppGuidePremiumFeature(
        feature: 'Locali preferiti',
        status: 'Attivo',
        details:
            'Salvi i locali che ti interessano e ricevi notifiche dedicate quando viene creato un evento in quel locale.',
      ),
    ],
    sections: [
      AppGuideSection(
        icon: 'local_fire',
        title: 'Approfitta',
        bullets: [
          'Trovi gli eventi aperti nella tua zona e puoi filtrarli per chilometraggio.',
          'I tuoi eventi restano sempre evidenziati con il badge dedicato.',
          'La campanella ti permette di inserire un promemoria prima dell\'evento.',
        ],
      ),
      AppGuideSection(
        icon: 'add_location',
        title: 'Offri',
        bullets: [
          'Crei colazioni, aperitivi, pranzi o cene e scegli il locale dalla mappa.',
          'La posizione puo partire dal GPS o dall\'indirizzo salvato nel profilo.',
          'Se inserisci il telefono del locale, dalla scheda evento puoi chiamarlo rapidamente.',
          'Titolo, descrizione e foto evento possono essere controllati prima della pubblicazione.',
        ],
      ),
      AppGuideSection(
        icon: 'groups',
        title: 'Community',
        bullets: [
          'Vedi profili reali della tua zona e puoi aprire le schede pubbliche.',
          'Gli utenti in revisione non vengono mostrati finche l\'admin non li approva.',
          'Dalla scheda profilo puoi bloccare o segnalare un utente se qualcosa non va.',
          'Le recensioni aiutano a capire con chi stai organizzando un incontro.',
        ],
      ),
      AppGuideSection(
        icon: 'chat',
        title: 'Chat',
        bullets: [
          'Le conversazioni partono dagli eventi e restano disponibili nella sezione Chat.',
          'Le chat si cancellano automaticamente dopo 30 giorni.',
          'Messaggi e immagini sospette possono essere bloccati e mandati in revisione.',
          'Se un profilo entra in revisione, la chat viene bloccata finche la verifica non finisce.',
        ],
      ),
      AppGuideSection(
        icon: 'person',
        title: 'Io',
        bullets: [
          'Gestisci le tue offerte, i tuoi approfitti, la community e le recensioni.',
          'In Strumenti profilo trovi modifica profilo, centro notifiche, guida, aggiornamenti e locali preferiti.',
          'Archivio eventi tiene separati gli eventi passati come host e come guest.',
          'Gli ApprofittOffro Points compariranno nel profilo quando l\'admin valida le segnalazioni utili.',
        ],
      ),
      AppGuideSection(
        icon: 'settings',
        title: 'Impostazioni',
        bullets: [
          'Da qui apri privacy, sicurezza, documenti legali e gestione account.',
          'Termini e Condizioni e Regolamento Community restano sempre disponibili.',
          'Puoi accettare i documenti dell\'app prima di usare segnalazioni e funzioni sensibili.',
          'Se hai accesso admin, puoi entrare nel pannello senza uscire dal tuo utente.',
        ],
      ),
      AppGuideSection(
        icon: 'workspace_premium',
        title: 'Premium',
        bullets: [
          'Le funzioni Premium sono indicate con il lucchetto e la scritta Premium.',
          'I locali preferiti sono la prima funzione Premium attiva: salvi un locale e ricevi avvisi quando nasce un evento li.',
          'L\'abbonamento Premium abilita le funzioni riservate agli abbonati.',
          'Gli ApprofittOffro Points potranno permettere di ottenere mesi Premium gratuiti.',
        ],
      ),
      AppGuideSection(
        icon: 'bug_report',
        title: 'Segnala bug',
        bullets: [
          'La linguetta laterale apre il modulo di segnalazione bug.',
          'Puoi allegare uno screenshot per far capire meglio il problema.',
          'Testo e screenshot vengono controllati per evitare abusi nelle segnalazioni.',
          'Le segnalazioni vere vengono validate dall\'admin e possono dare ApprofittOffro Points.',
        ],
      ),
      AppGuideSection(
        icon: 'verified_user',
        title: 'Sicurezza',
        bullets: [
          'Profili, offerte, chat, recensioni, foto, screenshot e segnalazioni possono essere controllati con moderazione automatica e revisione admin.',
          'I profili sospetti vengono temporaneamente nascosti e i contenuti rischiosi possono essere bloccati.',
          'Le notifiche importanti restano leggibili anche dopo il tap sulla push.',
        ],
      ),
    ],
  );
}

class AppGuideHighlight {
  const AppGuideHighlight({
    required this.icon,
    required this.text,
  });

  final String icon;
  final String text;

  factory AppGuideHighlight.fromJson(Map<String, dynamic> json) {
    return AppGuideHighlight(
      icon: (json['icon'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
    );
  }
}

class AppGuidePremiumFeature {
  const AppGuidePremiumFeature({
    required this.feature,
    required this.status,
    required this.details,
  });

  final String feature;
  final String status;
  final String details;

  factory AppGuidePremiumFeature.fromJson(Map<String, dynamic> json) {
    return AppGuidePremiumFeature(
      feature: (json['feature'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      details: (json['details'] ?? '').toString(),
    );
  }
}

class AppGuideSection {
  const AppGuideSection({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  final String icon;
  final String title;
  final List<String> bullets;

  factory AppGuideSection.fromJson(Map<String, dynamic> json) {
    return AppGuideSection(
      icon: (json['icon'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      bullets: (json['bullets'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }
}
