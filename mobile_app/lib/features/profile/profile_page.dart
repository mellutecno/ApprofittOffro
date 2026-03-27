import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
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

  Future<void> _openEditOffer(Offer offer) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CreateOfferPage(
          authController: widget.authController,
          initialOffer: offer,
        ),
      ),
    );
    if (updated == true) {
      await _refreshAll();
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
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Offerte',
                              value: user.offersCount.toString(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'Recuperi',
                              value: user.claimsCount.toString(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              label: 'Follower',
                              value: user.followersCount.toString(),
                            ),
                          ),
                        ],
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center),
        ],
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
