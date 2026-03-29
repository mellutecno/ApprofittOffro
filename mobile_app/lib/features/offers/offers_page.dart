import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/offer.dart';
import '../auth/auth_controller.dart';
import 'offer_card.dart';
import 'offers_controller.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({
    super.key,
    required this.authController,
    required this.offersController,
  });

  final AuthController authController;
  final OffersController offersController;

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  static const int _minDistanceKm = 5;
  static const int _maxDistanceKm = 500;

  double? _distancePreferenceDraft;
  bool _isSavingDistance = false;
  bool _isDistanceCardExpanded = false;

  int _normalizeDistanceForUi(int rawValue) {
    if (rawValue >= 999) {
      return _maxDistanceKm;
    }
    return rawValue.clamp(_minDistanceKm, _maxDistanceKm);
  }

  String _distanceLabelText(int valueKm) {
    return '$valueKm km';
  }

  Future<void> _openOfferDetails(
    BuildContext context,
    Offer offer,
  ) async {
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
                      'Evento aperto',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 14),
                    OfferCard(
                      offer: offer,
                      apiClient: widget.authController.apiClient,
                      allowProfileOpen: true,
                      onEditOwn: null,
                      onClaim: offer.isOwn || !offer.canClaim
                          ? null
                          : () async {
                              final navigator = Navigator.of(sheetContext);
                              final messenger = ScaffoldMessenger.of(context);
                              final message =
                                  await widget.offersController.claimOffer(
                                offer,
                              );
                              if (!context.mounted || message == null) {
                                return;
                              }
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(content: Text(message)),
                              );
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

  Future<void> _saveDistancePreference() async {
    final user = widget.authController.currentUser;
    if (user == null) {
      return;
    }

    final selectedKm =
        (_distancePreferenceDraft ??
                _normalizeDistanceForUi(user.actionRadiusKm).toDouble())
            .round()
            .clamp(_minDistanceKm, _maxDistanceKm);
    final currentKm = _normalizeDistanceForUi(user.actionRadiusKm);
    if (selectedKm == currentKm) {
      return;
    }

    setState(() => _isSavingDistance = true);
    try {
      await widget.authController.apiClient.updateProfile(
        nome: user.nome,
        email: user.email,
        eta: user.etaDisplay,
        gender: user.gender,
        actionRadiusKm: selectedKm,
        numeroTelefono: user.phoneNumber,
        citta: user.city,
        latitude: user.latitude?.toString() ?? '',
        longitude: user.longitude?.toString() ?? '',
        preferredFoods: user.preferredFoods,
        intolerances: user.intolerances,
        bio: user.bio,
        existingGalleryFilenames: user.galleryFilenames,
      );
      await widget.authController.refreshCurrentUser();
      await widget.offersController.loadOffers();
      if (!mounted) {
        return;
      }
      setState(() {
        _distancePreferenceDraft = selectedKm.toDouble();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Da ora vedrai eventi entro $selectedKm km.'),
        ),
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
          content: Text(
            'Non riesco ad aggiornare la distanza adesso.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingDistance = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.authController,
        widget.offersController,
      ]),
      builder: (context, _) {
        final rawActionRadius =
            widget.authController.currentUser?.actionRadiusKm ?? 15;
        final currentActionRadius = _normalizeDistanceForUi(rawActionRadius);
        final distanceDraft =
            _distancePreferenceDraft ?? currentActionRadius.toDouble();

        return RefreshIndicator(
          onRefresh: widget.offersController.loadOffers,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: const BrandWordmark(
                  height: 24,
                  alignment: Alignment.center,
                ),
                actions: [
                  IconButton(
                    onPressed:
                        widget.authController.isBusy
                            ? null
                            : widget.authController.logout,
                    icon: const Icon(Icons.logout),
                    tooltip: 'Esci',
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: BrandHeroCard(
                    eyebrow: 'APPROFITTA',
                    title: 'Eventi aperti della community',
                    subtitle:
                        'Scegli colazione, pranzo o cena e apri gli eventi che ti interessano.',
                    centered: true,
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MealChip(
                                label: 'Colazioni',
                                value: 'colazione',
                                selected:
                                    widget.offersController.selectedMealType ==
                                    'colazione',
                                onTap: widget.offersController.toggleMealType,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MealChip(
                                label: 'Pranzi',
                                value: 'pranzo',
                                selected:
                                    widget.offersController.selectedMealType ==
                                    'pranzo',
                                onTap: widget.offersController.toggleMealType,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MealChip(
                                label: 'Cene',
                                value: 'cena',
                                selected: widget
                                        .offersController.selectedMealType ==
                                    'cena',
                                onTap: widget.offersController.toggleMealType,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _DistancePreferenceControl(
                          valueKm: _normalizeDistanceForUi(
                            distanceDraft.round(),
                          ),
                          isSaving: _isSavingDistance,
                          isExpanded: _isDistanceCardExpanded,
                          distanceLabel: _distanceLabelText(
                            _normalizeDistanceForUi(
                              distanceDraft.round(),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() => _distancePreferenceDraft = value);
                          },
                          onToggle: () {
                            setState(
                              () => _isDistanceCardExpanded =
                                  !_isDistanceCardExpanded,
                            );
                          },
                          onSave: _saveDistancePreference,
                          isDirty:
                              _normalizeDistanceForUi(
                                distanceDraft.round(),
                              ) !=
                              currentActionRadius,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.offersController.hiddenOwnOffersCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.peach.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppTheme.orange.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.manage_accounts_rounded,
                              color: AppTheme.espresso,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                              'Se vedi questo banner hai delle offerte!!! Gestiscile del tuo profilo.',
                              style: const TextStyle(
                                color: AppTheme.espresso,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Tutti gli eventi aperti',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brown,
                    ),
                  ),
                ),
              ),
              if (widget.offersController.isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (widget.offersController.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.offersController.errorMessage!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (widget.offersController.offers.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Per questa selezione non vedo ancora eventi aperti. Appena arriva un nuovo tavolo, lo troverai qui.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: widget.offersController.offers.length,
                  itemBuilder: (context, index) {
                    final offer = widget.offersController.offers[index];
                    return _OfferPreviewCard(
                      offer: offer,
                      apiClient: widget.authController.apiClient,
                      onOpen: () => _openOfferDetails(context, offer),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

class _OfferPreviewCard extends StatelessWidget {
  const _OfferPreviewCard({
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
    final authorPhotoUrl = offer.autoreFoto.isNotEmpty
        ? apiClient.buildUploadUrl(offer.autoreFoto)
        : null;
    final occupiedSeats = (offer.postiTotali - offer.postiDisponibili)
        .clamp(0, offer.postiTotali);
    final canAddToCalendar =
        offer.alreadyClaimed || offer.claimStatus == 'claimed';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
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
                  child:
                      authorPhotoUrl == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.autoreNome,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  child: Row(
                    children: [
                      Expanded(
                        child: _CompactInfoChip(
                          label: _formatWhenLabel(context, offer.dataOra),
                          backgroundColor: AppTheme.mist,
                          foregroundColor: AppTheme.brown,
                        ),
                      ),
                      if (canAddToCalendar) ...[
                        const SizedBox(width: 6),
                        _CompactCalendarButton(
                          onTap: _openCalendar,
                        ),
                      ],
                    ],
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
              child: const Text('Apri evento'),
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

  Future<void> _openCalendar() async {
    final uri = Uri.tryParse(_googleCalendarUrl());
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _googleCalendarUrl() {
    final startDate = offer.dataOra.toUtc();
    final endDate = startDate.add(const Duration(hours: 2));
    final summary =
        '${offer.tipoPasto.toUpperCase()} presso ${offer.nomeLocale}';
    final description =
        'Condividi un pasto con ${offer.autoreNome}. Per favore arriva puntuale.';
    final location =
        offer.indirizzo.isNotEmpty ? offer.indirizzo : offer.nomeLocale;
    final dates =
        '${_formatCalendarTimestamp(startDate)}/${_formatCalendarTimestamp(endDate)}';

    final uri = Uri.https(
      'calendar.google.com',
      '/calendar/render',
      {
        'action': 'TEMPLATE',
        'text': summary,
        'dates': dates,
        'details': description,
        'location': location,
      },
    );
    return uri.toString();
  }

  String _formatCalendarTimestamp(DateTime value) {
    return value
            .toIso8601String()
            .replaceAll('-', '')
            .replaceAll(':', '')
            .split('.')
            .first +
        'Z';
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

class _CompactCalendarButton extends StatelessWidget {
  const _CompactCalendarButton({
    required this.onTap,
  });

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.peach.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: const Icon(
            Icons.event_available_rounded,
            color: AppTheme.orange,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final Future<void> Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilterChip(
        selected: selected,
        label: SizedBox(
          width: double.infinity,
          child: Text(label, textAlign: TextAlign.center),
        ),
        onSelected: (_) => onTap(value),
        backgroundColor: Colors.white.withValues(alpha: 0.72),
        selectedColor: _colorForValue(value).withValues(alpha: 0.18),
        side: BorderSide(color: _colorForValue(value).withValues(alpha: 0.34)),
        labelStyle: TextStyle(
          color: selected ? _colorForValue(value) : null,
          fontWeight: FontWeight.w700,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Color _colorForValue(String input) {
    switch (input) {
      case 'colazione':
        return const Color(0xFFD49B00);
      case 'pranzo':
        return const Color(0xFF3D8B5A);
      case 'cena':
        return const Color(0xFF7A4EC7);
      default:
        return Colors.grey;
    }
  }
}

class _DistancePreferenceControl extends StatelessWidget {
  const _DistancePreferenceControl({
    required this.valueKm,
    required this.isSaving,
    required this.isExpanded,
    required this.distanceLabel,
    required this.onChanged,
    required this.onToggle,
    required this.onSave,
    required this.isDirty,
  });

  final int valueKm;
  final bool isSaving;
  final bool isExpanded;
  final String distanceLabel;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggle;
  final Future<void> Function() onSave;
  final bool isDirty;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.radar_rounded,
                    color: AppTheme.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stai vedendo eventi entro $distanceLabel',
                      style: const TextStyle(
                        color: AppTheme.espresso,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.brown,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.orange,
                inactiveTrackColor: AppTheme.cardBorder,
                thumbColor: AppTheme.orange,
                overlayColor: AppTheme.orange.withValues(alpha: 0.14),
                valueIndicatorColor: AppTheme.orange,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Slider(
                min: _OffersPageState._minDistanceKm.toDouble(),
                max: _OffersPageState._maxDistanceKm.toDouble(),
                divisions:
                    ((_OffersPageState._maxDistanceKm -
                                _OffersPageState._minDistanceKm) ~/
                            5),
                value: valueKm
                    .clamp(
                      _OffersPageState._minDistanceKm,
                      _OffersPageState._maxDistanceKm,
                    )
                    .toDouble(),
                label: '$valueKm km',
                onChanged: isSaving ? null : onChanged,
              ),
            ),
            Row(
              children: [
                Text(
                  '${_OffersPageState._minDistanceKm} km',
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_OffersPageState._maxDistanceKm} km',
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: isSaving || !isDirty ? null : onSave,
              child: Text(
                isSaving
                    ? 'Salvataggio...'
                    : (isDirty ? 'Salva distanza' : 'Distanza aggiornata'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

