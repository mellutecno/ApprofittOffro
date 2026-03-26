import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
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
    final user = authController.currentUser;

    return AnimatedBuilder(
      animation: Listenable.merge([authController, offersController]),
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: offersController.loadOffers,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                title: const Text('Approfitta'),
                actions: [
                  IconButton(
                    onPressed: authController.isBusy ? null : authController.logout,
                    icon: const Icon(Icons.logout),
                    tooltip: 'Esci',
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Benvenuto a tavola',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user == null
                            ? 'Scopri chi sta cucinando qualcosa di buono.'
                            : 'Scopri chi ti sta cucinando qualcosa di buono vicino a ${user.city.isNotEmpty ? user.city : "te"}.',
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MealChip(
                            label: 'Colazioni',
                            value: 'colazione',
                            selected: offersController.selectedMealType == 'colazione',
                            onTap: offersController.toggleMealType,
                          ),
                          _MealChip(
                            label: 'Pranzi',
                            value: 'pranzo',
                            selected: offersController.selectedMealType == 'pranzo',
                            onTap: offersController.toggleMealType,
                          ),
                          _MealChip(
                            label: 'Cene',
                            value: 'cena',
                            selected: offersController.selectedMealType == 'cena',
                            onTap: offersController.toggleMealType,
                          ),
                        ],
                      ),
                    ],
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
                      child: Text(offersController.errorMessage!, textAlign: TextAlign.center),
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
                        'Per ora non ci sono eventi disponibili in questa vista. Appena ne arriva uno, lo vedrai qui.',
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
                      onClaim: offer.isOwn || offer.alreadyClaimed || offer.bookingClosed
                          ? null
                          : () async {
                              final message = await offersController.claimOffer(offer);
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
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(value),
      selectedColor: _colorForValue(value).withOpacity(0.22),
      side: BorderSide(color: _colorForValue(value).withOpacity(0.4)),
      labelStyle: TextStyle(
        color: selected ? _colorForValue(value) : null,
        fontWeight: FontWeight.w700,
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
