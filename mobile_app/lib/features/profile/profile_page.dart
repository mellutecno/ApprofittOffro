import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/app_user.dart';
import '../../models/offer.dart';
import '../../models/user_preview.dart';
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
    final offers = await widget.authController.apiClient.fetchOffers(
      radiusKm: 999,
    );
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

  Future<void> _openReviewComposer(PendingReviewReminder reminder) async {
    final existingReview = reminder.existingReview;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final commentController = TextEditingController(
          text: existingReview?.comment ?? '',
        );
        var selectedRating = existingReview?.rating ?? 5;
        var isSubmitting = false;
        final offerLabel =
            '${reminder.offerMealType} - ${reminder.offerLocaleName}';
        final whenText = reminder.offerDateTime != null
            ? DateFormat(
                "EEEE d MMMM 'alle' HH:mm",
                'it_IT',
              ).format(reminder.offerDateTime!.toLocal())
            : '';
        final editableUntilText =
            existingReview?.editableUntil != null
                ? DateFormat(
                    "dd/MM 'alle' HH:mm",
                    'it_IT',
                  ).format(existingReview!.editableUntil!.toLocal())
                : '';

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSubmitting) {
                return;
              }
              setSheetState(() => isSubmitting = true);
              try {
                final message = await widget.authController.apiClient.submitReview(
                  offerId: reminder.offerId,
                  reviewedId: reminder.targetUser.id,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : MediaQuery.of(context).size.height * 0.82;
                  return Material(
                    color: AppTheme.cream,
                    borderRadius: BorderRadius.circular(28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
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
                              existingReview == null
                                  ? 'Lascia una recensione'
                                  : 'Modifica la tua recensione',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Come ti sei trovato con ${reminder.targetUser.nome}?',
                              style: TextStyle(
                                color: AppTheme.brown.withValues(alpha: 0.85),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.paper,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppTheme.cardBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    offerLabel,
                                    style: const TextStyle(
                                      color: AppTheme.espresso,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (reminder.offerAddress.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      reminder.offerAddress,
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
                            const SizedBox(height: 12),
                            Text(
                              existingReview == null
                                  ? 'Dopo la pubblicazione potrai modificare questa recensione per 24 ore.'
                                  : 'Puoi modificare questa recensione fino al $editableUntilText.',
                              style: TextStyle(
                                color: AppTheme.brown.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Center(
                              child: Wrap(
                                spacing: 8,
                                children: List.generate(5, (index) {
                                  final rating = index + 1;
                                  return IconButton(
                                    onPressed: () => setSheetState(
                                      () => selectedRating = rating,
                                    ),
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
                                      : existingReview == null
                                          ? 'Pubblica recensione'
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
    await _refreshAll();
  }

  Future<void> _openEditOffer(Offer offer) async {
    final result = await Navigator.of(context).push<CreateOfferPageResult>(
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

  Future<void> _openOwnOfferDetails(Offer offer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.84,
          minChildSize: 0.58,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: const BoxDecoration(
                color: AppTheme.cream,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 14),
                    Text(
                      'La tua offerta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 14),
                    OfferCard(
                      offer: offer,
                      apiClient: widget.authController.apiClient,
                      allowProfileOpen: false,
                      onEditOwn: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_openEditOffer(offer));
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

        if (user == null) {
          return Scaffold(
            appBar: AppBar(
              title: const BrandWordmark(
                height: 42,
                alignment: Alignment.center,
              ),
            ),
            body: const Center(child: Text('Utente non disponibile.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const BrandWordmark(height: 42, alignment: Alignment.center),
          ),
          body: RefreshIndicator(
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
                            backgroundImage:
                                photoUrl != null ? NetworkImage(photoUrl) : null,
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
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                        onOpenRequesterProfile: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PublicProfilePage(
                                apiClient: apiClient,
                                userId: request.requester.id,
                              ),
                            ),
                          );
                        },
                        onAccept: () => _handlePendingClaimDecision(
                          request,
                          accept: true,
                        ),
                        onReject: () => _handlePendingClaimDecision(
                          request,
                          accept: false,
                        ),
                      ),
                    ),
                  ),
                ],
                if (user.pendingReviewReminders.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Recensioni da lasciare',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  ...user.pendingReviewReminders.map(
                    (reminder) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PendingReviewCard(
                        reminder: reminder,
                        apiClient: apiClient,
                        onOpenProfile: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PublicProfilePage(
                                apiClient: apiClient,
                                userId: reminder.targetUser.id,
                              ),
                            ),
                          );
                        },
                        onReview: () => _openReviewComposer(reminder),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Persone incrociate',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (user.metUsers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Qui troverai le persone che hai incontrato nei pasti offerti o partecipati.',
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 206,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: user.metUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final metUser = user.metUsers[index];
                        final imageUrl = metUser.photoFilename.isNotEmpty
                            ? apiClient.buildUploadUrl(metUser.photoFilename)
                            : null;
                        return _MetUserSummaryCard(
                          user: metUser,
                          imageUrl: imageUrl,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PublicProfilePage(
                                  apiClient: apiClient,
                                  userId: metUser.id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Le mie offerte',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Offer>>(
                  future: _myOffersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
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
                              child: _OwnOfferPreviewCard(
                                offer: offer,
                                apiClient: apiClient,
                                onOpen: () => _openOwnOfferDetails(offer),
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
                  _InfoCard(
                    title: 'Bio',
                    value: user.bio,
                    emphasizedValue: true,
                  ),
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
                          backgroundImage: follower.photoFilename.isNotEmpty
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
                    final updated = await Navigator.of(context).push<bool>(
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
    required this.onOpenRequesterProfile,
    required this.onAccept,
    required this.onReject,
  });

  final PendingClaimRequest request;
  final ApiClient apiClient;
  final VoidCallback onOpenRequesterProfile;
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
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onOpenRequesterProfile,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
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
                            '${request.offerMealType} - ${request.offerLocaleName}',
                            style: const TextStyle(
                              color: AppTheme.brown,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.brown,
                    ),
                  ],
                ),
              ),
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

class _PendingReviewCard extends StatelessWidget {
  const _PendingReviewCard({
    required this.reminder,
    required this.apiClient,
    required this.onOpenProfile,
    required this.onReview,
  });

  final PendingReviewReminder reminder;
  final ApiClient apiClient;
  final VoidCallback onOpenProfile;
  final Future<void> Function() onReview;

  @override
  Widget build(BuildContext context) {
    final targetUser = reminder.targetUser;
    final targetPhotoUrl = targetUser.photoFilename.isNotEmpty
        ? apiClient.buildUploadUrl(targetUser.photoFilename)
        : null;
    final whenText = reminder.offerDateTime != null
        ? DateFormat(
            "EEEE d MMMM 'alle' HH:mm",
            'it_IT',
          ).format(reminder.offerDateTime!.toLocal())
        : '';
    final existingReview = reminder.existingReview;
    final editableUntilText =
        existingReview?.editableUntil != null
            ? DateFormat(
                "dd/MM 'alle' HH:mm",
                'it_IT',
              ).format(existingReview!.editableUntil!.toLocal())
            : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.reviews_rounded,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    existingReview == null
                        ? 'Recensisci ${targetUser.nome}'
                        : 'Recensione pronta per ${targetUser.nome}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onOpenProfile,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: targetPhotoUrl != null
                          ? NetworkImage(targetPhotoUrl)
                          : null,
                      child: targetPhotoUrl == null
                          ? const Icon(Icons.person_outline)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            targetUser.nome,
                            style: const TextStyle(
                              color: AppTheme.espresso,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reminder.roleLabel,
                            style: TextStyle(
                              color: AppTheme.brown.withValues(alpha: 0.78),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.brown,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${reminder.offerMealType} - ${reminder.offerLocaleName}',
              style: const TextStyle(
                color: AppTheme.espresso,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (reminder.offerAddress.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reminder.offerAddress,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.86),
                  height: 1.35,
                ),
              ),
            ],
            if (whenText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                whenText,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (existingReview != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.mist,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (index) => Icon(
                            index < existingReview.rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: const Color(0xFFD49B00),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${existingReview.rating}/5',
                          style: const TextStyle(
                            color: AppTheme.espresso,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (existingReview.comment.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        existingReview.comment,
                        style: const TextStyle(
                          color: AppTheme.espresso,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              existingReview == null
                  ? 'Dopo la pubblicazione potrai modificare questa recensione per 24 ore.'
                  : 'Modificabile fino al $editableUntilText.',
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_rounded),
                label: Text(
                  existingReview == null
                      ? 'Lascia recensione'
                      : 'Modifica recensione',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetUserSummaryCard extends StatelessWidget {
  const _MetUserSummaryCard({
    required this.user,
    required this.imageUrl,
    required this.onTap,
  });

  final UserPreview user;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage:
                      imageUrl != null ? NetworkImage(imageUrl!) : null,
                  child: imageUrl == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  user.nome,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.espresso,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${user.etaDisplay} anni',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    user.cityLabel.isNotEmpty ? user.cityLabel : user.city,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.brown.withValues(alpha: 0.72),
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

class _OwnOfferPreviewCard extends StatelessWidget {
  const _OwnOfferPreviewCard({
    required this.offer,
    required this.apiClient,
    required this.onOpen,
  });

  final Offer offer;
  final ApiClient apiClient;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final mealColor = _mealColor(offer.tipoPasto);
    final occupiedSeats =
        (offer.postiTotali - offer.postiDisponibili).clamp(0, offer.postiTotali);
    final authorPhotoUrl = offer.autoreFoto.isNotEmpty
        ? apiClient.buildUploadUrl(offer.autoreFoto)
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage:
                    authorPhotoUrl != null ? NetworkImage(authorPhotoUrl) : null,
                child: authorPhotoUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.autoreNome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.espresso,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer.nomeLocale,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brown,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CompactInfoChip(
                  label: offer.tipoPasto.toUpperCase(),
                  backgroundColor: mealColor.withValues(alpha: 0.14),
                  foregroundColor: mealColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactInfoChip(
                  label: _formatWhenLabel(context, offer.dataOra),
                  backgroundColor: AppTheme.mist,
                  foregroundColor: AppTheme.brown,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Partecipanti $occupiedSeats di ${offer.postiTotali}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.brown,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onOpen,
            child: const Text('Apri offerta'),
          ),
        ],
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
        return AppTheme.orange;
    }
  }

  String _formatWhenLabel(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(local.year, local.month, local.day);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );

    if (eventDay == today) {
      return 'Oggi alle $time';
    }
    if (eventDay == today.add(const Duration(days: 1))) {
      return 'Domani alle $time';
    }
    final dateLabel =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$dateLabel - $time';
  }
}

class _CompactInfoChip extends StatelessWidget {
  const _CompactInfoChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
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
              style: const TextStyle(
                color: AppTheme.espresso,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.92),
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
