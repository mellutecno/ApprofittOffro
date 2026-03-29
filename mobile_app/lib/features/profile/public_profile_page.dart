import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/public_profile.dart';
import '../../models/user_preview.dart';
import 'profile_gallery_viewer_page.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({
    super.key,
    required this.apiClient,
    required this.userId,
  });

  final ApiClient apiClient;
  final int userId;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  late Future<PublicProfile> _future;
  bool _isTogglingFollow = false;

  @override
  void initState() {
    super.initState();
    _future = widget.apiClient.fetchPublicUser(widget.userId);
  }

  Future<void> _reload() async {
    final future = widget.apiClient.fetchPublicUser(widget.userId);
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _toggleFollow(PublicProfile profile) async {
    setState(() => _isTogglingFollow = true);
    try {
      final payload = profile.user.isFollowing
          ? await widget.apiClient.unfollowUser(profile.user.id)
          : await widget.apiClient.followUser(profile.user.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                payload['message']?.toString() ?? 'Operazione completata.')),
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isTogglingFollow = false);
      }
    }
  }

  List<String> _galleryUrls(UserPreview user) {
    final filenames = <String>[];
    if (user.photoFilename.isNotEmpty) {
      filenames.add(user.photoFilename);
    }
    for (final filename in user.galleryFilenames) {
      if (filename.isNotEmpty && !filenames.contains(filename)) {
        filenames.add(filename);
      }
    }
    return filenames.map(widget.apiClient.buildUploadUrl).toList();
  }

  void _openGallery(UserPreview user, {int initialIndex = 0}) {
    final urls = _galleryUrls(user);
    if (urls.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileGalleryViewerPage(
          imageUrls: urls,
          initialIndex: initialIndex.clamp(0, urls.length - 1),
          title: 'Foto di ${user.nome}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(height: 24, alignment: Alignment.center),
      ),
      body: FutureBuilder<PublicProfile>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Non riesco a caricare il profilo adesso.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Profilo non disponibile.'));
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProfileHeader(
                  user: profile.user,
                  apiClient: widget.apiClient,
                  onOpenGallery: () => _openGallery(profile.user),
                ),
                const SizedBox(height: 18),
                if (!profile.user.isSelf) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        _isTogglingFollow ? null : () => _toggleFollow(profile),
                    child: Text(
                        profile.user.isFollowing ? 'Non seguire piu' : 'Segui'),
                  ),
                ],
                if (profile.user.galleryFilenames.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Foto',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 148,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _galleryUrls(profile.user).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final url = _galleryUrls(profile.user)[index];
                        return GestureDetector(
                          onTap: () => _openGallery(
                            profile.user,
                            initialIndex: index,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AspectRatio(
                              aspectRatio: 0.92,
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (profile.user.bio.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _InfoCard(
                    title: 'Bio',
                    value: profile.user.bio,
                    emphasizedValue: true,
                  ),
                ],
                _InfoCard(
                  title: 'Cibi preferiti',
                  value: profile.user.preferredFoods.isNotEmpty
                      ? profile.user.preferredFoods
                      : 'Non indicati',
                ),
                _InfoCard(
                  title: 'Intolleranze',
                  value: profile.user.intolerances.isNotEmpty
                      ? profile.user.intolerances
                      : 'Nessuna indicata',
                ),
                const SizedBox(height: 20),
                Text(
                  'Recensioni',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (profile.reviews.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Per ora non ci sono ancora recensioni.'),
                    ),
                  )
                else
                  ...profile.reviews.map(
                    (review) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    review.reviewer?.nome ?? 'Utente',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFD49B00),
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text('${review.rating}'),
                              ],
                            ),
                            if (review.comment.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(review.comment),
                            ],
                            if (review.createdAt != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                DateFormat('dd/MM/yyyy')
                                    .format(review.createdAt!),
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.apiClient,
    required this.onOpenGallery,
  });

  final UserPreview user;
  final ApiClient apiClient;
  final VoidCallback onOpenGallery;

  @override
  Widget build(BuildContext context) {
    final imageUrl = user.photoFilename.isNotEmpty
        ? apiClient.buildUploadUrl(user.photoFilename)
        : null;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onOpenGallery,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: CircleAvatar(
                radius: 52,
                backgroundImage:
                    imageUrl != null ? NetworkImage(imageUrl) : null,
                child: imageUrl == null
                    ? const Icon(Icons.person, size: 44)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user.nome,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${user.etaDisplay} anni - ${user.cityLabel.isNotEmpty ? user.cityLabel : user.city}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFD49B00),
              ),
              const SizedBox(width: 6),
              Text(
                '${user.ratingAverage.toStringAsFixed(1)} su ${user.ratingCount} recensioni',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    this.emphasizedValue = false,
  });

  final String title;
  final String value;
  final bool emphasizedValue;

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
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: emphasizedValue ? 17 : null,
                fontWeight:
                    emphasizedValue ? FontWeight.w700 : FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
