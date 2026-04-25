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

  Future<void> _openReviewHistorySheet(PublicProfile profile) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.48,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Material(
              color: AppTheme.cream,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recensioni ricevute',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Text(
                          '${profile.reviews.length}',
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: profile.reviews.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final review = profile.reviews[index];
                        final previewText = review.comment.trim().isNotEmpty
                            ? review.comment.trim()
                            : 'Nessun commento scritto per questa recensione.';
                        return _CompactPublicReviewTile(
                          review: review,
                          title: review.reviewer?.nome ?? 'Utente',
                          previewText: previewText,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openReviewDetailSheet(profile, review);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openReviewDetailSheet(
    PublicProfile profile,
    UserReview review,
  ) async {
    final offer = review.offer;
    final reviewDateText = review.createdAt != null
        ? DateFormat("dd/MM/yyyy 'alle' HH:mm", 'it_IT').format(
            review.createdAt!.toLocal(),
          )
        : '';
    final eventDateText = offer?.dateTime != null
        ? DateFormat("EEEE d MMMM 'alle' HH:mm", 'it_IT').format(
            offer!.dateTime!.toLocal(),
          )
        : '';

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Material(
            color: AppTheme.cream,
            borderRadius: BorderRadius.circular(28),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    review.reviewer?.nome ?? 'Utente',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ha lasciato questa recensione',
                    style: TextStyle(
                      color: AppTheme.brown.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < review.rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: AppTheme.gold,
                        size: 22,
                      ),
                    ),
                  ),
                  if (offer != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppTheme.softAccentGradient,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.cardBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: AppTheme.shadow,
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _reviewOfferLabel(offer),
                            style: const TextStyle(
                              color: AppTheme.espresso,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (eventDateText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              eventDateText,
                              style: TextStyle(
                                color: AppTheme.brown.withValues(alpha: 0.76),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (review.comment.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      review.comment,
                      style: const TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (reviewDateText.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Scritta il $reviewDateText',
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (review.viewerCanEdit) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _openReviewEditor(profile, review);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifica recensione'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _reviewOfferLabel(ReviewedOfferSummary? offer) {
    if (offer == null) {
      return 'Evento';
    }
    final meal = offer.mealType.trim();
    final locale = offer.localeName.trim();
    if (meal.isEmpty && locale.isEmpty) {
      return 'Evento';
    }
    if (meal.isEmpty) {
      return locale;
    }
    if (locale.isEmpty) {
      return meal;
    }
    return '$meal - $locale';
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

  Future<void> _openReviewEditor(
    PublicProfile profile,
    UserReview review,
  ) async {
    final offer = review.offer;
    if (offer == null) {
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final commentController = TextEditingController(text: review.comment);
        var selectedRating = review.rating;
        var isSubmitting = false;
        final whenText = offer.dateTime != null
            ? DateFormat(
                "EEEE d MMMM 'alle' HH:mm",
                'it_IT',
              ).format(offer.dateTime!.toLocal())
            : '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSubmitting) {
                return;
              }
              setSheetState(() => isSubmitting = true);
              try {
                final message = await widget.apiClient.submitReview(
                  offerId: offer.id,
                  reviewedId: profile.user.id,
                  rating: selectedRating,
                  comment: commentController.text.trim(),
                );
                if (!sheetContext.mounted) {
                  return;
                }
                Navigator.of(sheetContext).pop(message);
              } on ApiException catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
                setSheetState(() => isSubmitting = false);
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Non riesco a salvare la recensione adesso.',
                    ),
                  ),
                );
                setSheetState(() => isSubmitting = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: Material(
                color: AppTheme.cream,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBorder,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Modifica la tua recensione',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Puoi aggiornarla quando vuoi.',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.85),
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: AppTheme.surfaceGradient,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.cardBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: AppTheme.shadow,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${offer.mealType} - ${offer.localeName}',
                              style: const TextStyle(
                                color: AppTheme.espresso,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (offer.address.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                offer.address,
                                style: TextStyle(
                                  color: AppTheme.brown.withValues(alpha: 0.82),
                                  height: 1.35,
                                ),
                              ),
                            ],
                            if (whenText.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                whenText,
                                style: TextStyle(
                                  color: AppTheme.brown.withValues(alpha: 0.74),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Wrap(
                          spacing: 8,
                          children: List.generate(5, (index) {
                            final rating = index + 1;
                            return IconButton(
                              onPressed: () =>
                                  setSheetState(() => selectedRating = rating),
                              icon: Icon(
                                rating <= selectedRating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: const Color(0xFFD49B00),
                                size: 30,
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: commentController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Commento facoltativo',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSubmitting ? null : submit,
                          child: Text(
                            isSubmitting
                                ? 'Invio in corso...'
                                : 'Salva modifiche',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result)),
    );
    await _reload();
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

  Future<void> _openLinkedPublicProfile(int userId) async {
    if (userId == widget.userId) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(
          apiClient: widget.apiClient,
          userId: userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(height: 44, alignment: Alignment.center),
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
          final totalPhotos = _galleryUrls(profile.user).length;

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProfileHeader(
                  user: profile.user,
                  apiClient: widget.apiClient,
                  onOpenGallery: () => _openGallery(profile.user),
                  totalPhotos: totalPhotos,
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
                  'Follower',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (profile.followers.isEmpty)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: AppTheme.surfaceGradient,
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Text(
                          'Per ora questo profilo non ha ancora follower.'),
                    ),
                  )
                else
                  ...profile.followers.map(
                    (follower) {
                      final imageUrl = follower.photoFilename.isNotEmpty
                          ? widget.apiClient.buildUploadUrl(
                              follower.photoFilename,
                            )
                          : null;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: AppTheme.surfaceGradient,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: imageUrl != null
                                  ? NetworkImage(imageUrl)
                                  : null,
                              child: imageUrl == null
                                  ? const Icon(Icons.person_outline)
                                  : null,
                            ),
                            title: Text(follower.nome),
                            subtitle: Text(
                              '${follower.etaDisplay} anni - ${follower.cityLabel}',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openLinkedPublicProfile(follower.id),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 20),
                _CompactReviewSectionCard(
                  title: 'Recensioni ricevute',
                  icon: Icons.reviews_rounded,
                  count: profile.reviews.length,
                  emptyText: 'Per ora non ci sono ancora recensioni.',
                  actionLabel: 'Apri recensioni',
                  onTap: profile.reviews.isEmpty
                      ? null
                      : () => _openReviewHistorySheet(profile),
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
    required this.totalPhotos,
  });

  final UserPreview user;
  final ApiClient apiClient;
  final VoidCallback onOpenGallery;
  final int totalPhotos;

  @override
  Widget build(BuildContext context) {
    final extraBadgeBackground =
        AppTheme.useMusicAiPalette ? AppTheme.orange : AppTheme.espresso;
    final extraBadgeTextColor =
        AppTheme.useMusicAiPalette ? Colors.white : Colors.white;
    final imageUrl = user.photoFilename.isNotEmpty
        ? apiClient.buildUploadUrl(user.photoFilename)
        : null;
    final extraPhotoCount = totalPhotos > 0 ? totalPhotos - 1 : 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppTheme.cardBorder.withValues(alpha: 0.74),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.shadow,
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: totalPhotos > 0 ? onOpenGallery : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.paper.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.cardBorder.withValues(alpha: 0.72),
                    ),
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
                if (extraPhotoCount > 0)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: extraBadgeBackground,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.paper,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        '+$extraPhotoCount',
                        style: TextStyle(
                          color: extraBadgeTextColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (totalPhotos > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: AppTheme.useMusicAiPalette
                      ? AppTheme.orange
                      : AppTheme.espresso,
                ),
                const SizedBox(width: 6),
                Text(
                  'Tocca la foto per vedere l’album',
                  style: TextStyle(
                    color: AppTheme.espresso.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
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
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.surfaceGradient,
        ),
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
      ),
    );
  }
}

class _CompactReviewSectionCard extends StatelessWidget {
  const _CompactReviewSectionCard({
    required this.title,
    required this.icon,
    required this.count,
    required this.emptyText,
    required this.actionLabel,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final int count;
  final String emptyText;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.surfaceGradient,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.mist,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Icon(icon, color: AppTheme.orange),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        count == 0 ? emptyText : '$count recensioni',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.76),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0) ...[
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: AppTheme.orange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.orange),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactPublicReviewTile extends StatelessWidget {
  const _CompactPublicReviewTile({
    required this.review,
    required this.title,
    required this.previewText,
    required this.onTap,
  });

  final UserReview review;
  final String title;
  final String previewText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.surfaceGradient,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ha lasciato una recensione',
                            style: TextStyle(
                              color: AppTheme.brown.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.star_rounded,
                      color: AppTheme.gold,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${review.rating}/5',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.orange),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  previewText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.espresso,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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
