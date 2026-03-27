import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/offer.dart';
import 'auth_controller.dart';
import 'login_page.dart';
import 'register_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late Future<List<Offer>> _offersFuture;

  @override
  void initState() {
    super.initState();
    _offersFuture = widget.authController.apiClient.fetchOffers();
  }

  void _openLogin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginPage(
          authController: widget.authController,
        ),
      ),
    );
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisterPage(
          authController: widget.authController,
        ),
      ),
    );
  }

  Future<void> _reloadOffers() async {
    final future = widget.authController.apiClient.fetchOffers();
    setState(() => _offersFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _reloadOffers,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: BrandWordmark(
                            height: 42,
                            alignment: Alignment.center,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _LandingPhotoCluster(),
                        const SizedBox(height: 22),
                        Text(
                          'Nuove persone, tavoli veri, pasti condivisi davvero.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontSize: 30,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ApprofittOffro mette insieme chi offre un pasto e chi vuole viverlo con leggerezza, dal telefono e con profili reali.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppTheme.brown.withValues(alpha: 0.84),
                                    height: 1.45,
                                  ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _openLogin,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.68),
                                ),
                                child: const Text('Accedi'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _openRegister,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.68),
                                ),
                                child: const Text('Crea account'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Come funziona la community',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const _LandingStepCard(
                          title: 'Scopri chi c e in giro',
                          body:
                              'Apri Approfitta e guarda colazioni, pranzi e cene pubblicati dalla community.',
                        ),
                        const _LandingStepCard(
                          title: 'Entra nei profili veri',
                          body:
                              'Da Community puoi vedere foto, eta, citta e scegliere chi seguire davvero.',
                        ),
                        const _LandingStepCard(
                          title: 'Iscriviti per partecipare',
                          body:
                              'Se un evento ti piace, crei il tuo account, entri nella community e poi approfitti davvero.',
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Eventi aperti della community',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.brown,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Iscriviti per partecipare agli eventi aperti adesso.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        FutureBuilder<List<Offer>>(
                          future: _offersFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    'Non riesco a caricare gli eventi aperti in questo momento.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            final offers = snapshot.data ?? const <Offer>[];
                            if (offers.isEmpty) {
                              return const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(18),
                                  child: Text(
                                    'Per ora non vedo ancora eventi pubblici aperti.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            return Column(
                              children: offers
                                  .take(4)
                                  .map(
                                    (offer) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _PublicOfferCard(
                                        offer: offer,
                                        apiClient:
                                            widget.authController.apiClient,
                                        onTap: _openLogin,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Perche nasce ApprofittOffro',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const _LandingInfoCard(
                          title: 'Piu community, meno rumore',
                          body:
                              'L idea non e collezionare prenotazioni: e creare un giro di persone che si riconoscono e tornano.',
                        ),
                        const _LandingInfoCard(
                          title: 'Profili, follower e fiducia',
                          body:
                              'Segui le persone che ti piacciono, guarda i loro profili e tieni vivi i contatti migliori.',
                        ),
                        const _LandingInfoCard(
                          title: 'Versione mobile pensata per crescere',
                          body:
                              'Questa app Android e il primo passo verso una community piu diretta, piu bella e piu semplice da usare.',
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
      ),
    );
  }
}

class _LandingPhotoCluster extends StatefulWidget {
  const _LandingPhotoCluster();

  @override
  State<_LandingPhotoCluster> createState() => _LandingPhotoClusterState();
}

class _LandingPhotoClusterState extends State<_LandingPhotoCluster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value * 2 * math.pi;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 12,
                top: 36 + math.sin(progress) * 10,
                child: _FloatingPhotoCard(
                  assetPath: 'assets/landing/hero-brunch.jpg',
                  width: 108,
                  height: 156,
                  angle: -0.08,
                ),
              ),
              Positioned(
                right: 10,
                top: 10 + math.sin(progress + 1.7) * 12,
                child: _FloatingPhotoCard(
                  assetPath: 'assets/landing/hero-dinner.jpg',
                  width: 138,
                  height: 182,
                  angle: 0.07,
                ),
              ),
              Positioned(
                left: 88,
                bottom: 8 + math.sin(progress + 3.2) * 10,
                child: _FloatingPhotoCard(
                  assetPath: 'assets/landing/hero-friends.jpg',
                  width: 118,
                  height: 154,
                  angle: -0.03,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingPhotoCard extends StatelessWidget {
  const _FloatingPhotoCard({
    required this.assetPath,
    required this.width,
    required this.height,
    required this.angle,
  });

  final String assetPath;
  final double width;
  final double height;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            assetPath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _LandingStepCard extends StatelessWidget {
  const _LandingStepCard({
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicOfferCard extends StatelessWidget {
  const _PublicOfferCard({
    required this.offer,
    required this.apiClient,
    required this.onTap,
  });

  final Offer offer;
  final ApiClient apiClient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mealColor = _mealColor(offer.tipoPasto);
    final authorPhotoUrl = offer.autoreFoto.isNotEmpty
        ? apiClient.buildUploadUrl(offer.autoreFoto)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: mealColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  offer.tipoPasto.toUpperCase(),
                  style: TextStyle(
                    color: mealColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              offer.nomeLocale,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _formatWhenLabel(offer.dataOra),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.brown,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      authorPhotoUrl != null ? NetworkImage(authorPhotoUrl) : null,
                  child:
                      authorPhotoUrl == null ? const Icon(Icons.person, size: 22) : null,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.brown,
                            height: 1.35,
                          ),
                      children: [
                        const TextSpan(text: 'Offerto da '),
                        TextSpan(
                          text: offer.autoreNome,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              offer.indirizzo,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              child: const Text('Iscriviti o accedi per partecipare'),
            ),
          ],
        ),
      ),
    );
  }

  Color _mealColor(String type) {
    switch (type) {
      case 'colazione':
        return const Color(0xFFD49B00);
      case 'pranzo':
        return const Color(0xFF3D8B5A);
      case 'cena':
        return const Color(0xFF7A4EC7);
      default:
        return const Color(0xFFE86E35);
    }
  }

  String _formatWhenLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(local.year, local.month, local.day);
    final time = DateFormat('HH:mm').format(local);

    if (eventDay == today) {
      return 'Oggi alle $time';
    }
    if (eventDay == today.add(const Duration(days: 1))) {
      return 'Domani alle $time';
    }
    return DateFormat('dd/MM - HH:mm').format(local);
  }
}
