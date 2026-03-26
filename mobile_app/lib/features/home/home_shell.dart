import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _offersController = OffersController(widget.authController.apiClient)
      ..loadOffers();
  }

  @override
  void dispose() {
    _offersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OffersPage(
        authController: widget.authController,
        offersController: _offersController,
      ),
      const CommunityPage(),
      const CreateOfferPage(),
      ProfilePage(authController: widget.authController),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Approfitta'),
          NavigationDestination(icon: Icon(Icons.groups_rounded), label: 'Community'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Offri'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Su di me'),
        ],
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}
