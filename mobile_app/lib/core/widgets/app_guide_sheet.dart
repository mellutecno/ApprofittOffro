import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand_wordmark.dart';

Future<bool> showAppGuideSheet(
  BuildContext context, {
  bool startupMode = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppGuideSheet(startupMode: startupMode),
  );
  return result ?? false;
}

class _AppGuideSheet extends StatefulWidget {
  const _AppGuideSheet({required this.startupMode});

  final bool startupMode;

  @override
  State<_AppGuideSheet> createState() => _AppGuideSheetState();
}

class _AppGuideSheetState extends State<_AppGuideSheet> {
  bool _hideAtStartup = false;

  static const _sections = <_GuideSectionData>[
    _GuideSectionData(
      icon: Icons.local_fire_department_rounded,
      title: 'Approfitta',
      bullets: [
        'Trovi gli eventi aperti nella tua zona e puoi filtrarli per chilometraggio.',
        'I tuoi eventi restano sempre evidenziati con il badge dedicato.',
        'La campanella ti permette di inserire un promemoria prima dell\'evento.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.add_location_alt_rounded,
      title: 'Offri',
      bullets: [
        'Crei colazioni, aperitivi, pranzi o cene e scegli il locale dalla mappa.',
        'La posizione puo partire dal GPS o dall\'indirizzo salvato nel profilo.',
        'Se inserisci il telefono del locale, dalla scheda evento puoi chiamarlo rapidamente.',
        'Titolo, descrizione e foto evento possono essere controllati prima della pubblicazione.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.groups_2_rounded,
      title: 'Community',
      bullets: [
        'Vedi profili reali della tua zona e puoi aprire le schede pubbliche.',
        'Gli utenti in revisione non vengono mostrati finche l\'admin non li approva.',
        'Dalla scheda profilo puoi bloccare o segnalare un utente se qualcosa non va.',
        'Le recensioni aiutano a capire con chi stai organizzando un incontro.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.chat_bubble_rounded,
      title: 'Chat',
      bullets: [
        'Le conversazioni partono dagli eventi e restano disponibili nella sezione Chat.',
        'Le chat si cancellano automaticamente dopo 30 giorni.',
        'Messaggi e immagini sospette possono essere bloccati e mandati in revisione.',
        'Se un profilo entra in revisione, la chat viene bloccata finche la verifica non finisce.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.person_rounded,
      title: 'Io',
      bullets: [
        'Gestisci le tue offerte, i tuoi approfitti, la community e le recensioni.',
        'In Strumenti profilo trovi modifica profilo, centro notifiche, guida, aggiornamenti e locali preferiti.',
        'Archivio eventi tiene separati gli eventi passati come host e come guest.',
        'Gli ApprofittOffro Points compariranno nel profilo quando l\'admin valida le segnalazioni utili.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.settings_rounded,
      title: 'Impostazioni',
      bullets: [
        'Da qui apri privacy, sicurezza, documenti legali e gestione account.',
        'Termini e Condizioni e Regolamento Community restano sempre disponibili.',
        'Puoi accettare i documenti dell\'app prima di usare segnalazioni e funzioni sensibili.',
        'Se hai accesso admin, puoi entrare nel pannello senza uscire dal tuo utente.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.workspace_premium_rounded,
      title: 'Premium',
      bullets: [
        'Le funzioni Premium sono indicate con il lucchetto e la scritta Premium.',
        'I locali preferiti sono la prima funzione Premium attiva: salvi un locale e ricevi avvisi quando nasce un evento li.',
        'Premium potra essere attivato con abbonamento da 0,99 euro al mese oppure con 1000 ApprofittOffro Points per 3 mesi.',
        'Chi non e Premium vede la funzione bloccata, ma puo capire cosa sblocchera.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.bug_report_rounded,
      title: 'Segnala bug',
      bullets: [
        'La linguetta laterale apre il modulo di segnalazione bug.',
        'Puoi allegare uno screenshot per far capire meglio il problema.',
        'Testo e screenshot vengono controllati per evitare abusi nelle segnalazioni.',
        'Le segnalazioni vere vengono validate dall\'admin e possono dare ApprofittOffro Points.',
      ],
    ),
    _GuideSectionData(
      icon: Icons.verified_user_rounded,
      title: 'Sicurezza',
      bullets: [
        'Profili, offerte, chat, recensioni, foto, screenshot e segnalazioni possono essere controllati con moderazione automatica e revisione admin.',
        'I profili sospetti vengono temporaneamente nascosti e i contenuti rischiosi possono essere bloccati.',
        'Le notifiche importanti restano leggibili anche dopo il tap sulla push.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: AppTheme.cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.brown.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const BrandWordmark(height: 54),
                const SizedBox(height: 18),
                Text(
                  widget.startupMode
                      ? 'Benvenuto in ApprofittOffro'
                      : 'Guida rapida',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Qui trovi le funzioni principali dell\'app, le novita e i punti da ricordare per usarla meglio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                const _GuideHighlightCard(),
                const SizedBox(height: 14),
                const _PremiumGuideCard(),
                const SizedBox(height: 14),
                ..._sections.map(
                  (section) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GuideSectionCard(section: section),
                  ),
                ),
                if (widget.startupMode) ...[
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: _hideAtStartup,
                    onChanged: (value) {
                      setState(() => _hideAtStartup = value ?? false);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppTheme.vividViolet,
                    title: const Text(
                      'Non mostrarla piu all\'avvio',
                      style: TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      'Potrai riaprirla quando vuoi da Io > Impostazioni > Guida all\'app.',
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.68),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_hideAtStartup),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(widget.startupMode ? 'Ho capito' : 'Chiudi'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuideHighlightCard extends StatelessWidget {
  const _GuideHighlightCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Da ricordare',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          _GuidePill(
            icon: Icons.workspace_premium_rounded,
            text:
                'Le funzioni Premium sono riconoscibili dal lucchetto dedicato.',
          ),
          _GuidePill(
            icon: Icons.notifications_active_rounded,
            text: 'Le notifiche restano nel centro notifiche per 24 ore.',
          ),
          _GuidePill(
            icon: Icons.bug_report_rounded,
            text: 'Le segnalazioni bug utili possono ricevere punti.',
          ),
          _GuidePill(
            icon: Icons.admin_panel_settings_rounded,
            text:
                'La moderazione protegge profili, offerte, chat e segnalazioni.',
          ),
        ],
      ),
    );
  }
}

class _GuidePill extends StatelessWidget {
  const _GuidePill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumGuideCard extends StatelessWidget {
  const _PremiumGuideCard();

  static const _rows = <_PremiumFeatureRow>[
    _PremiumFeatureRow(
      feature: 'Locali preferiti',
      status: 'Attivo',
      details:
          'Salvi i locali che ti interessano e ricevi notifiche dedicate quando viene creato un evento in quel locale.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A145F),
            Color(0xFF4C22B8),
            Color(0xFF123EBA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 22,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Funzioni Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Alcune funzioni avanzate saranno riservate agli abbonati Premium. Per ora abbiamo inserito questa prima voce, poi la tabella crescera con le prossime novita.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 14),
          ..._rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PremiumFeatureTile(row: row),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const Text(
              'Costo previsto: 0,99 euro al mese oppure 3 mesi Premium con 1000 ApprofittOffro Points.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  const _PremiumFeatureTile({required this.row});

  final _PremiumFeatureRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.feature,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD34D),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  row.status,
                  style: const TextStyle(
                    color: Color(0xFF251057),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            row.details,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumFeatureRow {
  const _PremiumFeatureRow({
    required this.feature,
    required this.status,
    required this.details,
  });

  final String feature;
  final String status;
  final String details;
}

class _GuideSectionCard extends StatelessWidget {
  const _GuideSectionCard({required this.section});

  final _GuideSectionData section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.vividViolet.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              section.icon,
              color: AppTheme.vividViolet,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: AppTheme.espresso,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...section.bullets.map(
                  (bullet) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _GuideBullet(text: bullet),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideBullet extends StatelessWidget {
  const _GuideBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: AppTheme.sage,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.brown.withValues(alpha: 0.80),
              fontWeight: FontWeight.w600,
              height: 1.28,
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideSectionData {
  const _GuideSectionData({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final List<String> bullets;
}
