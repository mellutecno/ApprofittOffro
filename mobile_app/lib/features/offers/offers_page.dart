import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../auth/auth_controller.dart';
import '../create_offer/create_offer_page.dart';
import 'offer_card.dart';
import 'offers_controller.dart';

class OffersPage extends StatelessWidget {
  const OffersPage({
    super.key,
    required this.authController,
    required this.offersController,
  });

  final AuthController authController;
  final OffersController offersController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([authController, offersController]),
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: offersController.loadOffers,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: const BrandWordmark(
                    height: 24, alignment: Alignment.center),
                actions: [
                  IconButton(
                    onPressed:
                        authController.isBusy ? null : authController.logout,
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
                        'Scopri chi sta condividendo una colazione, un pranzo o una cena e scegli dove entrare.',
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
                                selected: offersController.selectedMealType ==
                                    'colazione',
                                onTap: offersController.toggleMealType,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MealChip(
                                label: 'Pranzi',
                                value: 'pranzo',
                                selected:
                                    offersController.selectedMealType == 'pranzo',
                                onTap: offersController.toggleMealType,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MealChip(
                                label: 'Cene',
                                value: 'cena',
                                selected:
                                    offersController.selectedMealType == 'cena',
                                onTap: offersController.toggleMealType,
                              ),
                            ),
                          ],
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
              if (offersController.isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (offersController.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(offersController.errorMessage!,
                          textAlign: TextAlign.center),
                    ),
                  ),
                )
              else if (offersController.offers.isEmpty)
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
                  itemCount: offersController.offers.length,
                  itemBuilder: (context, index) {
                    final offer = offersController.offers[index];
                    return OfferCard(
                      offer: offer,
                      apiClient: authController.apiClient,
                      onEditOwn: offer.isOwn
                          ? () async {
                              final result = await Navigator.of(context)
                                  .push<CreateOfferPageResult>(
                                MaterialPageRoute<CreateOfferPageResult>(
                                  builder: (_) => CreateOfferPage(
                                    authController: authController,
                                    initialOffer: offer,
                                    onOfferCreated: () async {
                                      await offersController.loadOffers();
                                      await authController.refreshCurrentUser();
                                    },
                                  ),
                                ),
                              );
                              if (result?.changed == true) {
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 30),
                                );
                                await offersController.loadOffers();
                                await authController.refreshCurrentUser();
                              }
                            }
                          : null,
                      onClaim: offer.isOwn ||
                              offer.alreadyClaimed ||
                              offer.bookingClosed
                          ? null
                          : () async {
                              final message =
                                  await offersController.claimOffer(offer);
                              if (!context.mounted || message == null) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(message)),
                              );
                            },
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
