import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../community/community_controller.dart';
import '../community/community_page.dart';
import '../create_offer/create_offer_page.dart';
import '../offers/offers_controller.dart';
import '../offers/offers_page.dart';
import '../profile/profile_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.authController});

  final AuthController authController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  late final OffersController _offersController;
  late final CommunityController _communityController;

  @override
  void initState() {
    super.initState();
    _offersController = OffersController(widget.authController.apiClient)
      ..loadOffers();
    _communityController = CommunityController(widget.authController.apiClient)
      ..loadPeople();
  }

  @override
  void dispose() {
    _offersController.dispose();
    _communityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OffersPage(
        authController: widget.authController,
        offersController: _offersController,
      ),
      CommunityPage(
        authController: widget.authController,
        communityController: _communityController,
      ),
      CreateOfferPage(
        authController: widget.authController,
        onOfferCreated: () async {
          await _offersController.loadOffers();
          if (!mounted) {
            return;
          }
          setState(() => _selectedIndex = 0);
        },
      ),
      ProfilePage(authController: widget.authController),
    ];

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedIndex),
            child: pages[_selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu_rounded),
            label: 'Approfitta',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_rounded),
            selectedIcon: Icon(Icons.groups),
            label: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Offri',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Su di me',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}
