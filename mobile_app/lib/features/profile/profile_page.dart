import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/app_user.dart';
import '../../models/offer.dart';
import '../../models/public_profile.dart';
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
  static const int _profileEventHistoryHours = 24;
  static const int _profileArchiveLookbackDays = 30;
  bool _archiveExpanded = false;
  int _socialTabIndex = 0;
  late Future<List<Offer>> _myOffersFuture;
  late Future<List<Offer>> _myClaimsFuture;
  late Future<ReviewHistoryBundle> _reviewHistoryFuture;

  @override
  void initState() {
    super.initState();
    _myOffersFuture = _loadMyOffers();
    _myClaimsFuture = _loadMyClaims();
    _reviewHistoryFuture = _loadReviewHistory();
    unawaited(widget.authController.refreshCurrentUser());
  }

  Future<List<Offer>> _loadMyOffers() async {
    final offers = await widget.authController.apiClient.fetchMyProfileOffers(
      claimed: false,
    );
    return offers..sort((a, b) => b.dataOra.compareTo(a.dataOra));
  }

  Future<List<Offer>> _loadMyClaims() async {
    final claims = await widget.authController.apiClient.fetchMyProfileOffers(
      claimed: true,
    );
    return claims..sort((a, b) => b.dataOra.compareTo(a.dataOra));
  }

  Future<List<Offer>> _loadArchivedOffers({required bool claimed}) async {
    final offers = await widget.authController.apiClient.fetchMyProfileOffers(
      claimed: claimed,
      archived: true,
    );
    return offers..sort((a, b) => b.dataOra.compareTo(a.dataOra));
  }

  Future<ReviewHistoryBundle> _loadReviewHistory() {
    return widget.authController.apiClient.fetchMyReviewHistory();
  }

  Future<void> _openArchivedOffersSheet({
    required bool claimed,
  }) async {
    final title = claimed ? 'Eventi guest' : 'Eventi host';
    final emptyText = claimed
        ? 'Non ci sono eventi guest archiviati nell’ultimo mese.'
        : 'Non ci sono eventi host archiviati nell’ultimo mese.';

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
              child: FutureBuilder<List<Offer>>(
                future: _loadArchivedOffers(claimed: claimed),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Non riesco a caricare l’archivio adesso.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    );
                  }

                  final offers = snapshot.data ?? const <Offer>[];
                  return Column(
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
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            Text(
                              '${offers.length}',
                              style: TextStyle(
                                color: AppTheme.brown.withValues(alpha: 0.78),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Text(
                          'Qui trovi gli eventi conclusi tra 24 ore e $_profileArchiveLookbackDays giorni fa, finché non vengono rimossi dall’amministratore.',
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.76),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: offers.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    emptyText,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: offers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final offer = offers[index];
                                  return _OwnOfferPreviewCard(
                                    offer: offer,
                                    apiClient: widget.authController.apiClient,
                                    buttonLabel: 'Apri evento',
                                    onOpen: () {
                                      Navigator.of(sheetContext).pop();
                                      _openOwnOfferDetails(offer);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openReviewHistorySheet({
    required String title,
    required List<UserReview> reviews,
    required bool isReceived,
  }) async {
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
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Text(
                          '${reviews.length}',
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
                      itemCount: reviews.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final review = reviews[index];
                        return _ReviewHistoryTile(
                          review: review,
                          title: isReceived
                              ? (review.reviewer?.nome.isNotEmpty == true
                                  ? review.reviewer!.nome
                                  : 'Utente')
                              : (review.reviewed?.nome.isNotEmpty == true
                                  ? review.reviewed!.nome
                                  : 'Utente'),
                          subtitle: isReceived
                              ? 'Ti ha lasciato una recensione'
                              : 'Hai lasciato una recensione',
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openReviewDetailSheet(
                              review: review,
                              title: isReceived
                                  ? (review.reviewer?.nome.isNotEmpty == true
                                      ? review.reviewer!.nome
                                      : 'Utente')
                                  : (review.reviewed?.nome.isNotEmpty == true
                                      ? review.reviewed!.nome
                                      : 'Utente'),
                              subtitle: isReceived
                                  ? 'Ti ha lasciato questa recensione'
                                  : 'Hai lasciato questa recensione',
                            );
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

  Future<void> _openReviewDetailSheet({
    required UserReview review,
    required String title,
    required String subtitle,
  }) async {
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
      builder: (context) {
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
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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
                        color: AppTheme.mist,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.cardBorder),
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
                  if (review.viewerCanEdit &&
                      review.offer != null &&
                      review.reviewed != null) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openWrittenReviewEditor(review);
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

  Future<void> _openWrittenReviewEditor(UserReview review) async {
    final offer = review.offer;
    final reviewedUser = review.reviewed;
    if (offer == null || reviewedUser == null) {
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
                final message =
                    await widget.authController.apiClient.submitReview(
                  offerId: offer.id,
                  reviewedId: reviewedUser.id,
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
                    content: Text('Non riesco a salvare la recensione adesso.'),
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
                        'Puoi aggiornarla quando vuoi: la ritrovi sempre qui nel tuo profilo.',
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
                          color: AppTheme.paper,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.cardBorder),
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

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    await widget.authController.refreshCurrentUser();
    final offersFuture = _loadMyOffers();
    final claimsFuture = _loadMyClaims();
    final reviewHistoryFuture = _loadReviewHistory();
    if (mounted) {
      setState(() {
        _myOffersFuture = offersFuture;
        _myClaimsFuture = claimsFuture;
        _reviewHistoryFuture = reviewHistoryFuture;
      });
    }
    await Future.wait([offersFuture, claimsFuture, reviewHistoryFuture]);
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
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSubmitting) {
                return;
              }
              setSheetState(() => isSubmitting = true);
              try {
                final message =
                    await widget.authController.apiClient.submitReview(
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
                                  if (reminder.offerAddress
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      reminder.offerAddress,
                                      style: TextStyle(
                                        color: AppTheme.brown
                                            .withValues(alpha: 0.82),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  if (whenText.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      whenText,
                                      style: TextStyle(
                                        color: AppTheme.brown
                                            .withValues(alpha: 0.74),
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
                                  ? 'Scrivila adesso: poi la ritroverai sempre nel tuo profilo.'
                                  : 'Puoi aggiornarla quando vuoi dal tuo profilo.',
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

  bool _canCancelClaimFromProfile(Offer offer) {
    if (offer.isOwn || offer.claimId <= 0) {
      return false;
    }
    if (offer.dataOra.toLocal().isBefore(DateTime.now())) {
      return false;
    }
    return offer.claimStatus == 'pending' || offer.claimStatus == 'claimed';
  }

  String _cancelClaimLabel(Offer offer) {
    return offer.claimStatus == 'pending'
        ? 'Annulla richiesta'
        : 'Annulla partecipazione';
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
                      offer.isOwn ? 'La tua offerta' : 'Il tuo approfitto',
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
                      showAddressLeadIcon: false,
                      onEditOwn: offer.isOwn
                          ? () {
                              Navigator.of(sheetContext).pop();
                              unawaited(_openEditOffer(offer));
                            }
                          : null,
                      onArchive: offer.isOwn
                          ? () async {
                              try {
                                await widget.authController.apiClient
                                    .archiveOffer(offer.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Offerta archiviata')),
                                );
                                Navigator.of(sheetContext).pop();
                                await _refreshAll();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Errore: $e')),
                                );
                              }
                            }
                          : null,
                    ),
                    if (_canCancelClaimFromProfile(offer)) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: sheetContext,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(_cancelClaimLabel(offer)),
                              content: Text(
                                offer.claimStatus == 'pending'
                                    ? 'Vuoi davvero annullare la richiesta per ${offer.nomeLocale}?'
                                    : 'Vuoi davvero annullare la partecipazione a ${offer.nomeLocale}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('No'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  child: const Text('Si'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !context.mounted) {
                            return;
                          }
                          final message = await widget.authController.apiClient
                              .cancelClaim(offer.claimId);
                          if (!sheetContext.mounted) {
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)),
                          );
                          await _refreshAll();
                        },
                        icon: const Icon(Icons.event_busy_outlined),
                        label: Text(_cancelClaimLabel(offer)),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminare il profilo?'),
          content: const Text(
            'Se confermi, il tuo account verra eliminato definitivamente dalla community insieme a offerte, partecipazioni e dati collegati.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A4336),
              ),
              child: const Text('Elimina account'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final message = await widget.authController.deleteAccount();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non riesco a eliminare il tuo account adesso.'),
        ),
      );
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
        final galleryUrls = _galleryUrls();
        final totalPhotos = galleryUrls.length;
        final extraPhotoCount = totalPhotos > 0 ? totalPhotos - 1 : 0;
        final photoUrl = user != null && user.photoFilename.isNotEmpty
            ? apiClient.buildUploadUrl(user.photoFilename)
            : null;

        if (user == null) {
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: kToolbarHeight,
              leading: const SizedBox.shrink(),
              leadingWidth: kToolbarHeight,
              centerTitle: true,
              title: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: BrandWordmark(
                  height: 42,
                  alignment: Alignment.center,
                ),
              ),
              actions: const [
                SizedBox(width: kToolbarHeight),
              ],
            ),
            body: const Center(child: Text('Utente non disponibile.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: kToolbarHeight,
            leading: const SizedBox.shrink(),
            leadingWidth: kToolbarHeight,
            centerTitle: true,
            title: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: BrandWordmark(height: 42, alignment: Alignment.center),
            ),
            actions: const [
              SizedBox(width: kToolbarHeight),
            ],
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
                        onTap: totalPhotos > 0 ? _openGallery : null,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
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
                                    color: AppTheme.espresso,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    '+$extraPhotoCount',
                                    style: const TextStyle(
                                      color: Colors.white,
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
                            const Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                              color: AppTheme.espresso,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tocca la foto per vedere l’album',
                              style: TextStyle(
                                color:
                                    AppTheme.espresso.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
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
                FutureBuilder<ReviewHistoryBundle>(
                  future: _reviewHistoryFuture,
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState != ConnectionState.done;
                    final hasError = snapshot.hasError;
                    final reviewsReceived =
                        snapshot.data?.received ?? const <UserReview>[];
                    final reviewsGiven =
                        snapshot.data?.given ?? const <UserReview>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        const Text(
                          'Cosa dicono di te',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ReviewHistorySectionCard(
                          title: '',
                          icon: Icons.reviews_rounded,
                          count: reviewsReceived.length,
                          isLoading: isLoading,
                          hasError: hasError,
                          emptyText:
                              'Qui troverai cosa scrive la community di te.',
                          actionLabel: 'Apri recensioni',
                          onTap:
                              reviewsReceived.isEmpty || isLoading || hasError
                                  ? null
                                  : () => _openReviewHistorySheet(
                                        title: 'Cosa dicono di te',
                                        reviews: reviewsReceived,
                                        isReceived: true,
                                      ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Cosa dici degli altri',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ReviewHistorySectionCard(
                          title: '',
                          icon: Icons.edit_note_rounded,
                          count: reviewsGiven.length,
                          isLoading: isLoading,
                          hasError: hasError,
                          emptyText:
                              'Qui troverai le recensioni che lasci agli altri utenti.',
                          actionLabel: 'Apri recensioni',
                          onTap: reviewsGiven.isEmpty || isLoading || hasError
                              ? null
                              : () => _openReviewHistorySheet(
                                    title: 'Cosa dici degli altri',
                                    reviews: reviewsGiven,
                                    isReceived: false,
                                  ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Le mie offerte',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
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
                      return Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'Qui trovi le offerte attive e quelle concluse nelle ultime $_profileEventHistoryHours ore.',
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
                  'I miei approfitti',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Offer>>(
                  future: _myClaimsFuture,
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
                            'Non riesco a caricare i tuoi approfitti adesso.',
                          ),
                        ),
                      );
                    }

                    final claims = snapshot.data ?? const <Offer>[];
                    if (claims.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'Qui trovi gli eventi a cui hai approfittato o partecipato nelle ultime $_profileEventHistoryHours ore.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: claims
                          .map(
                            (offer) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _OwnOfferPreviewCard(
                                offer: offer,
                                apiClient: apiClient,
                                buttonLabel: 'Apri evento',
                                onOpen: () => _openOwnOfferDetails(offer),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            setState(() {
                              _archiveExpanded = !_archiveExpanded;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.history_toggle_off_rounded,
                                  color: AppTheme.espresso,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Archivio ultimo mese',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Icon(
                                  _archiveExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  color: AppTheme.espresso,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_archiveExpanded) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Dopo $_profileEventHistoryHours ore l’evento viene archiviato automaticamente.',
                            style: TextStyle(
                              color: AppTheme.espresso.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _openArchivedOffersSheet(
                                  claimed: false,
                                ),
                                icon:
                                    const Icon(Icons.event_available_outlined),
                                label: const Text('Eventi host'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openArchivedOffersSheet(
                                  claimed: true,
                                ),
                                icon: const Icon(Icons.groups_2_outlined),
                                label: const Text('Eventi guest'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'La tua community',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                _ProfileSocialTabsCard(
                  selectedIndex: _socialTabIndex,
                  onTabChanged: (index) {
                    setState(() => _socialTabIndex = index);
                  },
                  followers: user.followers,
                  following: user.following,
                  apiClient: apiClient,
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
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.authController.isBusy
                      ? null
                      : widget.authController.logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Esci da questo dispositivo'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.authController.isBusy
                      ? null
                      : _confirmDeleteAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8A4336),
                    side: const BorderSide(color: Color(0xFFD7B4AC)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Cancella il tuo account'),
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
            const SizedBox(height: 16),
            Text(
              existingReview == null
                  ? 'Scrivila adesso: poi la ritroverai sempre nel tuo profilo.'
                  : 'Puoi aggiornarla quando vuoi dal tuo profilo.',
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

class _ReviewHistorySectionCard extends StatelessWidget {
  const _ReviewHistorySectionCard({
    required this.title,
    required this.icon,
    required this.count,
    required this.isLoading,
    required this.hasError,
    required this.emptyText,
    required this.actionLabel,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final int count;
  final bool isLoading;
  final bool hasError;
  final String emptyText;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (title.isNotEmpty) ...[
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                    ],
                    if (isLoading)
                      Text(
                        'Sto caricando...',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.76),
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (hasError)
                      Text(
                        'Non riesco a caricarle adesso.',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.76),
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (count == 0)
                      Text(
                        emptyText,
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.76),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$count',
                            style: TextStyle(
                              color: AppTheme.brown.withValues(alpha: 0.76),
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            actionLabel,
                            style: TextStyle(
                              color: AppTheme.orange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewHistoryTile extends StatelessWidget {
  const _ReviewHistoryTile({
    required this.review,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final UserReview review;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offer = review.offer;
    final eventDateText = offer?.dateTime != null
        ? DateFormat("EEEE d MMMM 'alle' HH:mm", 'it_IT').format(
            offer!.dateTime!.toLocal(),
          )
        : '';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
                          subtitle,
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.star_rounded,
                      color: AppTheme.gold, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${review.rating}/5',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.orange,
                  ),
                ],
              ),
              if (offer != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${offer.mealType} - ${offer.localeName}',
                  style: const TextStyle(
                    color: AppTheme.espresso,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (eventDateText.isNotEmpty) ...[
                const SizedBox(height: 4),
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
      ),
    );
  }
}

class _ProfileSocialTabsCard extends StatelessWidget {
  const _ProfileSocialTabsCard({
    required this.selectedIndex,
    required this.onTabChanged,
    required this.followers,
    required this.following,
    required this.apiClient,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final List<UserPreview> followers;
  final List<UserPreview> following;
  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    final showingFollowers = selectedIndex == 0;
    final people = showingFollowers ? followers : following;
    final emptyText = showingFollowers
        ? 'Per ora non hai ancora follower.'
        : 'Per ora non segui ancora nessuno.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: Text('Chi ti segue (${followers.length})'),
                  selected: showingFollowers,
                  onSelected: (_) => onTabChanged(0),
                ),
                ChoiceChip(
                  label: Text('I tuoi seguiti (${following.length})'),
                  selected: !showingFollowers,
                  onSelected: (_) => onTabChanged(1),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  emptyText,
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.76),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ...people.map(
                (person) => _ProfileConnectionTile(
                  person: person,
                  apiClient: apiClient,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileConnectionTile extends StatelessWidget {
  const _ProfileConnectionTile({
    required this.person,
    required this.apiClient,
  });

  final UserPreview person;
  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: person.photoFilename.isNotEmpty
              ? NetworkImage(apiClient.buildUploadUrl(person.photoFilename))
              : null,
          child: person.photoFilename.isEmpty
              ? const Icon(Icons.person_outline)
              : null,
        ),
        title: Text(person.nome),
        subtitle: Text('${person.etaDisplay} anni - ${person.cityLabel}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PublicProfilePage(
                apiClient: apiClient,
                userId: person.id,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OwnOfferPreviewCard extends StatelessWidget {
  const _OwnOfferPreviewCard({
    required this.offer,
    required this.apiClient,
    required this.onOpen,
    this.buttonLabel = 'Apri offerta',
  });

  final Offer offer;
  final ApiClient apiClient;
  final VoidCallback onOpen;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final mealColor = _mealColor(offer.tipoPasto);
    final occupiedSeats = (offer.postiTotali - offer.postiDisponibili)
        .clamp(0, offer.postiTotali);
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
                backgroundImage: authorPhotoUrl != null
                    ? NetworkImage(authorPhotoUrl)
                    : null,
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
          if (offer.stato == 'archiviata')
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  const Text(
                    'Evento archiviato',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.espresso,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nell\'archivio tra 24 ore',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.brown.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else if (offer.isOwn &&
              offer.dataOra.isBefore(DateTime.now()) &&
              offer.dataOra
                  .isAfter(DateTime.now().subtract(const Duration(hours: 3))))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Text(
                'In corso',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF3D8B5A),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            )
          else
            OutlinedButton(
              onPressed: onOpen,
              child: Text(buttonLabel),
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
