import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import 'auth_controller.dart';
import 'login_page.dart';
import 'register_page.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverAppBar(
                floating: true,
                snap: true,
                title: BrandWordmark(height: 26, alignment: Alignment.center),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BrandHeroCard(
                        eyebrow: 'COMMUNITY MOBILE',
                        title:
                            'Nuove persone, tavoli veri, pasti condivisi davvero.',
                        subtitle:
                            'ApprofittOffro mette insieme chi offre un pasto e chi vuole viverlo con leggerezza, dal telefono e con profili reali.',
                        footer: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _LandingBadge(text: 'Eventi aperti'),
                            SizedBox(height: 10),
                            _LandingBadge(text: 'Profili reali'),
                            SizedBox(height: 10),
                            _LandingBadge(text: 'Community attiva'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => LoginPage(
                                      authController: authController,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Accedi'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RegisterPage(
                                      authController: authController,
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Crea account'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Come funziona la community',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const _LandingStepCard(
                        step: '1',
                        title: 'Scopri chi c\'e in giro',
                        body:
                            'Apri Approfitta e guarda colazioni, pranzi e cene pubblicati dalla community.',
                      ),
                      const _LandingStepCard(
                        step: '2',
                        title: 'Entra nei profili veri',
                        body:
                            'Da Community puoi vedere foto, eta, citta e scegliere chi seguire davvero.',
                      ),
                      const _LandingStepCard(
                        step: '3',
                        title: 'Offri o approfitta',
                        body:
                            'Se vuoi partecipare, entri. Se vuoi organizzare, pubblichi tu il prossimo tavolo.',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Perche nasce ApprofittOffro',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const _LandingInfoCard(
                        title: 'Più community, meno rumore',
                        body:
                            'L\'idea non e collezionare prenotazioni: e creare un giro di persone che si riconoscono e tornano.',
                      ),
                      const _LandingInfoCard(
                        title: 'Profili, follower e fiducia',
                        body:
                            'Segui le persone che ti piacciono, guarda i loro profili e tieni vivi i contatti migliori.',
                      ),
                      const _LandingInfoCard(
                        title: 'Versione mobile pensata per crescere',
                        body:
                            'Questa app Android e il primo passo verso una community più diretta, più bella e più semplice da usare.',
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingBadge extends StatelessWidget {
  const _LandingBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppTheme.brown,
        ),
      ),
    );
  }
}

class _LandingStepCard extends StatelessWidget {
  const _LandingStepCard({
    required this.step,
    required this.title,
    required this.body,
  });

  final String step;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.sand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  step,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brown,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 18,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingInfoCard extends StatelessWidget {
  const _LandingInfoCard({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
