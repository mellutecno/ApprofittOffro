import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/offer.dart';
import 'auth_controller.dart';
import 'login_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.authController,
    this.autoOpenLogin = false,
  });

  final AuthController authController;
  final bool autoOpenLogin;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late Future<List<Offer>> _offersFuture;
  bool _didAutoOpenLogin = false;

  @override
  void initState() {
    super.initState();
    _offersFuture = widget.authController.apiClient.fetchOffers(limit: 20);
    _scheduleAutoLoginIfNeeded();
  }

  @override
  void didUpdateWidget(covariant LandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoOpenLogin && !oldWidget.autoOpenLogin) {
      _didAutoOpenLogin = false;
      _scheduleAutoLoginIfNeeded();
    }
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

  void _scheduleAutoLoginIfNeeded() {
    if (!widget.autoOpenLogin || _didAutoOpenLogin) {
      return;
    }
    _didAutoOpenLogin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _openLogin();
    });
  }

  Future<void> _reloadOffers() async {
    final future = widget.authController.apiClient.fetchOffers(limit: 20);
    setState(() {
      _offersFuture = future;
    });
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: AppTheme.brown.withValues(alpha: 0.84),
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _openLogin,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.82),
                                ),
                                child: const Text('Accedi / Iscriviti'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _LandingInfoCard(
                          title: 'ApprofittOffro Card',
                          body:
                              'Presto avrai la possibilità di aderire alla Community Card e con la tessera socio avrai diritto a sconti esclusivi nei locali che preferisci.',
                          highlighted: true,
                        ),
                        const SizedBox(height: 24),
                        const _LandingSectionHeading(
                          eyebrow: 'COME FUNZIONA',
                          title: 'Come funziona la community',
                        ),
                        const SizedBox(height: 12),
                        const _LandingStepCard(
                          title: 'Scopri chi c\'è in giro',
                          body:
                              'Apri Approfitta e guarda colazioni, pranzi e cene pubblicati dalla community.',
                        ),
                        const _LandingStepCard(
                          title: 'Entra nei profili veri',
                          body:
                              'Da Community puoi vedere foto, età, città e scegliere chi seguire davvero.',
                        ),
                        const _LandingStepCard(
                          title: 'Iscriviti per partecipare',
                          body:
                              'Se un evento ti piace, crei il tuo account, entri nella community e poi approfitti davvero.',
                        ),
                        const SizedBox(height: 24),
                        const _LandingSectionHeading(
                          eyebrow: 'EVENTI APERTI',
                          title: 'Eventi aperti della community',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cosa aspetti, approfitta.',
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
                              return const _LandingNoticeCard(
                                message:
                                    'Non riesco a caricare gli eventi aperti in questo momento.',
                              );
                            }

                            final offers = (snapshot.data ?? const <Offer>[])
                                .where(
                                  (offer) =>
                                      offer.claimStatus == 'open' &&
                                      offer.canClaim,
                                )
                                .take(4)
                                .toList();
                            if (offers.isEmpty) {
                              return const _LandingNoticeCard(
                                message:
                                    'Per ora non vedo ancora eventi pubblici aperti.',
                              );
                            }

                            return Column(
                              children: offers
                                  .map(
                                    (offer) => _PublicOfferCard(
                                      offer: offer,
                                      apiClient:
                                          widget.authController.apiClient,
                                      onTap: _openLogin,
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const _LandingSectionHeading(
                          eyebrow: 'VISIONE',
                          title: 'Perché nasce ApprofittOffro',
                        ),
                        const SizedBox(height: 12),
                        const _LandingInfoCard(
                          title: 'Più community, meno rumore',
                          body:
                              'L\'idea non è collezionare prenotazioni: è creare un giro di persone che si riconoscono e tornano.',
                        ),
                        const _LandingInfoCard(
                          title: 'Profili, follower e fiducia',
                          body:
                              'Segui le persone che ti piacciono, guarda i loro profili e tieni vivi i contatti migliori.',
                        ),
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

class _LandingSectionHeading extends StatelessWidget {
  const _LandingSectionHeading({
    required this.eyebrow,
    required this.title,
  });

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.brown,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppTheme.brown,
              ),
        ),
      ],
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
                child: const _FloatingPhotoCard(
                  assetPath: 'assets/landing/hero-brunch.jpg',
                  width: 108,
                  height: 156,
                  angle: -0.08,
                ),
              ),
              Positioned(
                right: 10,
                top: 10 + math.sin(progress + 1.7) * 12,
                child: const _FloatingPhotoCard(
                  assetPath: 'assets/landing/hero-dinner.jpg',
                  width: 138,
                  height: 182,
                  angle: 0.07,
                ),
              ),
              Positioned(
                left: 88,
                bottom: 8 + math.sin(progress + 3.2) * 10,
                child: const _FloatingPhotoCard(
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.82),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LandingInfoCard extends StatelessWidget {
  const _LandingInfoCard({
    required this.title,
    required this.body,
    this.highlighted = false,
  });

  final String title;
  final String body;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: highlighted
              ? const [Color(0xFFFFF7E9), Color(0xFFF9E3BF)]
              : const [Color(0xFFFFFCF7), Color(0xFFF7EFE3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: highlighted ? const Color(0xFFE0BB74) : AppTheme.cardBorder,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x1A7A4A00),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: highlighted ? 22 : 18,
                  fontWeight: highlighted ? FontWeight.w900 : FontWeight.w800,
                  color: highlighted ? AppTheme.espresso : AppTheme.brown,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  fontSize: highlighted ? 16.5 : null,
                  fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
                  color: highlighted ? AppTheme.espresso : AppTheme.brown,
                ),
          ),
        ],
      ),
    );
  }
}

class _LandingNoticeCard extends StatelessWidget {
  const _LandingNoticeCard({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage: authorPhotoUrl != null
                      ? NetworkImage(authorPhotoUrl)
                      : null,
                  child: authorPhotoUrl == null
                      ? const Icon(Icons.person, size: 30)
                      : null,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.mist,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                offer.indirizzo,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.espresso,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              child: const Text('Cosa aspetti, approfitta'),
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
