import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/app_user.dart';
import '../../models/offer.dart';
import '../auth/auth_controller.dart';
import '../create_offer/create_offer_page.dart';
import '../offers/offer_card.dart';
import 'profile_edit_page.dart';
import 'profile_gallery_viewer_page.dart';
import 'public_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<List<Offer>> _myOffersFuture;

  @override
  void initState() {
    super.initState();
    _myOffersFuture = _loadMyOffers();
  }

  Future<List<Offer>> _loadMyOffers() async {
    final offers = await widget.authController.apiClient.fetchOffers();
    final myOffers = offers.where((offer) => offer.isOwn).toList()
      ..sort((a, b) => b.dataOra.compareTo(a.dataOra));
    return myOffers;
  }

  Future<void> _refreshAll() async {
    await widget.authController.refreshCurrentUser();
    final future = _loadMyOffers();
    if (mounted) {
      setState(() {
        _myOffersFuture = future;
      });
    }
    await future;
  }

  Future<void> _handlePendingClaimDecision(
    PendingClaimRequest request, {
    required bool accept,
  }) async {
    try {
      final message = accept
          ? await widget.authController.apiClient.acceptClaimRequest(
              request.claimId,
            )
          : await widget.authController.apiClient.rejectClaimRequest(
              request.claimId,
            );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      await _refreshAll();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _openEditOffer(Offer offer) async {
    final result =
        await Navigator.of(context).push<CreateOfferPageResult>(
      MaterialPageRoute<CreateOfferPageResult>(
        builder: (_) => CreateOfferPage(
          authController: widget.authController,
          initialOffer: offer,
        ),
      ),
    );
    if (result?.changed == true) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (mounted) {
        await _refreshAll();
      }
    }
  }

  List<String> _galleryUrls() {
    final user = widget.authController.currentUser;
    if (user == null) {
      return const <String>[];
    }

    final filenames = <String>[];
    if (user.photoFilename.isNotEmpty) {
      filenames.add(user.photoFilename);
    }
    for (final filename in user.galleryFilenames) {
      if (filename.isNotEmpty && !filenames.contains(filename)) {
        filenames.add(filename);
      }
    }
    return filenames
        .map(widget.authController.apiClient.buildUploadUrl)
        .toList();
  }

  void _openGallery({int initialIndex = 0}) {
    final user = widget.authController.currentUser;
    final urls = _galleryUrls();
    if (user == null || urls.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileGalleryViewerPage(
          imageUrls: urls,
          initialIndex: initialIndex.clamp(0, urls.length - 1),
          title: 'Le tue foto',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final user = widget.authController.currentUser;
        final apiClient = widget.authController.apiClient;
        final photoUrl = user != null && user.photoFilename.isNotEmpty
            ? apiClient.buildUploadUrl(user.photoFilename)
            : null;

        return Scaffold(
          appBar: AppBar(
            title: const BrandWordmark(height: 24, alignment: Alignment.center),
          ),
          body: user == null
              ? const Center(child: Text('Utente non disponibile.'))
              : RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: AppTheme.heroGradient,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 24,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _openGallery,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: CircleAvatar(
                                  radius: 56,
                                  backgroundImage: photoUrl != null
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl == null
                                      ? const Icon(Icons.person, size: 48)
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              user.nome,
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${user.etaDisplay} anni - ${user.city}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: AppTheme.gold,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${user.ratingAverage.toStringAsFixed(1)} su ${user.ratingCount} recensioni',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (user.galleryFilenames.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Le tue foto',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 148,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _galleryUrls().length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final imageUrl = _galleryUrls()[index];
                              return GestureDetector(
                                onTap: () => _openGallery(initialIndex: index),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: AspectRatio(
                                    aspectRatio: 0.92,
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (user.pendingClaimRequests.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Richieste in attesa',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        ...user.pendingClaimRequests.map(
                          (request) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _PendingClaimCard(
                              request: request,
                              apiClient: apiClient,
                              onAccept: () =>
                                  _handlePendingClaimDecision(
                                    request,
                                    accept: true,
                                  ),
                              onReject: () =>
                                  _handlePendingClaimDecision(
                                    request,
                                    accept: false,
                                  ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Le mie offerte',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<List<Offer>>(
                        future: _myOffersFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: Text(
                                  'Non riesco a caricare le tue offerte adesso.',
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
                                  'Non hai ancora offerte attive. Quando pubblichi il prossimo invito, lo trovi qui.',
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: offers
                                .map(
                                  (offer) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: OfferCard(
                                      offer: offer,
                                      apiClient: apiClient,
                                      onEditOwn: () => _openEditOffer(offer),
                                      allowProfileOpen: false,
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Dati personali',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _InfoCard(title: 'Email', value: user.email),
                      _InfoCard(
                        title: 'Numero di telefono',
                        value: user.phoneNumber.isNotEmpty
                            ? user.phoneNumber
                            : 'Non indicato',
                      ),
                      if (user.bio.isNotEmpty)
                        _InfoCard(title: 'Bio', value: user.bio),
                      _InfoCard(
                        title: 'Cibi preferiti',
                        value: user.preferredFoods.isNotEmpty
                            ? user.preferredFoods
                            : 'Non ancora indicati',
                      ),
                      _InfoCard(
                        title: 'Intolleranze',
                        value: user.intolerances.isNotEmpty
                            ? user.intolerances
                            : 'Nessuna indicata',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Chi ti segue',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      if (user.followers.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('Per ora non hai ancora follower.'),
                          ),
                        )
                      else
                        ...user.followers.map(
                          (follower) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    follower.photoFilename.isNotEmpty
                                        ? NetworkImage(
                                            apiClient.buildUploadUrl(
                                              follower.photoFilename,
                                            ),
                                          )
                                        : null,
                                child: follower.photoFilename.isEmpty
                                    ? const Icon(Icons.person_outline)
                                    : null,
                              ),
                              title: Text(follower.nome),
                              subtitle: Text(
                                '${follower.etaDisplay} anni - ${follower.cityLabel}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PublicProfilePage(
                                      apiClient: apiClient,
                                      userId: follower.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final updated =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => ProfileEditPage(
                                authController: widget.authController,
                              ),
                            ),
                          );
                          if (updated == true) {
                            await _refreshAll();
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Modifica profilo'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PendingClaimCard extends StatelessWidget {
  const _PendingClaimCard({
    required this.request,
    required this.apiClient,
    required this.onAccept,
    required this.onReject,
  });

  final PendingClaimRequest request;
  final ApiClient apiClient;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final requester = request.requester;
    final requesterPhotoUrl = requester.photoFilename.isNotEmpty
        ? apiClient.buildUploadUrl(requester.photoFilename)
        : null;
    final whenText = request.offerDateTime != null
        ? DateFormat(
            "EEEE d MMMM 'alle' HH:mm",
            'it_IT',
          ).format(request.offerDateTime!.toLocal())
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: requesterPhotoUrl != null
                      ? NetworkImage(requesterPhotoUrl)
                      : null,
                  child: requesterPhotoUrl == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requester.nome,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${request.offerMealType} · ${request.offerLocaleName}',
                        style: const TextStyle(
                          color: AppTheme.brown,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (request.offerAddress.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                request.offerAddress,
                style: const TextStyle(
                  color: AppTheme.espresso,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (whenText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                whenText,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8A4336),
                      side: const BorderSide(color: Color(0xFFD7B4AC)),
                    ),
                    child: const Text('Rifiuta'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    child: const Text('Accetta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

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
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
