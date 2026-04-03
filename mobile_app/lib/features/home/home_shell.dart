import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/app_launch_target.dart';
import '../auth/auth_controller.dart';
import '../community/community_controller.dart';
import '../community/community_page.dart';
import '../create_offer/create_offer_page.dart';
import '../offers/offers_controller.dart';
import '../offers/offers_page.dart';
import '../profile/profile_page.dart';
import '../profile/profile_edit_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.authController,
    this.launchTarget,
    this.onLaunchTargetHandled,
  });

  final AuthController authController;
  final AppLaunchTarget? launchTarget;
  final VoidCallback? onLaunchTargetHandled;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  late final OffersController _offersController;
  late final CommunityController _communityController;
  bool _mandatoryProfileFlowOpen = false;
  String? _lastPendingAlertSignature;

  @override
  void initState() {
    super.initState();
    _offersController = OffersController(widget.authController.apiClient)
      ..loadOffers();
    _communityController = CommunityController(widget.authController.apiClient)
      ..loadPeople();
    widget.authController.addListener(_handleAuthStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenMandatoryProfileSetup());
      _applyLaunchTargetIfNeeded();
      _maybeShowPendingRequestsAlert();
    });
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launchTarget != widget.launchTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyLaunchTargetIfNeeded();
        _maybeShowPendingRequestsAlert(forceProfileTab: true);
      });
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_handleAuthStateChanged);
    _offersController.dispose();
    _communityController.dispose();
    super.dispose();
  }

  void _handleAuthStateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenMandatoryProfileSetup());
      unawaited(_offersController.loadOffers());
      unawaited(_communityController.loadPeople());
      _applyLaunchTargetIfNeeded();
      _maybeShowPendingRequestsAlert();
    });
  }

  void _applyLaunchTargetIfNeeded() {
    if (!mounted) {
      return;
    }

    final target = widget.launchTarget;
    if (target == null) {
      return;
    }

    if (target == AppLaunchTarget.pendingRequests && _selectedIndex != 3) {
      setState(() => _selectedIndex = 3);
    }

    widget.onLaunchTargetHandled?.call();
  }

  void _maybeShowPendingRequestsAlert({bool forceProfileTab = false}) {
    if (!mounted) {
      return;
    }

    final user = widget.authController.currentUser;
    if (user == null) {
      _lastPendingAlertSignature = null;
      return;
    }

    final pendingCount = user.pendingClaimRequests.length;
    if (pendingCount <= 0) {
      _lastPendingAlertSignature = null;
      return;
    }

    final signature = '${user.id}:$pendingCount';
    if (_lastPendingAlertSignature == signature && !forceProfileTab) {
      return;
    }
    _lastPendingAlertSignature = signature;

    if (forceProfileTab && _selectedIndex != 3) {
      setState(() => _selectedIndex = 3);
    }

    final message = pendingCount == 1
        ? 'Attenzione, hai una richiesta da evadere in Su di me.'
        : 'Attenzione, hai $pendingCount richieste da evadere in Su di me.';

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Apri',
          onPressed: () {
            if (!mounted) {
              return;
            }
            setState(() => _selectedIndex = 3);
          },
        ),
      ),
    );
  }

  Future<void> _maybeOpenMandatoryProfileSetup() async {
    if (!mounted || _mandatoryProfileFlowOpen) {
      return;
    }
    if (!widget.authController.isAuthenticated) {
      return;
    }
    if (!widget.authController.consumePendingProfileCompletion()) {
      return;
    }

    _mandatoryProfileFlowOpen = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileEditPage(
          authController: widget.authController,
          requireCompletion: true,
        ),
      ),
    );

    await widget.authController.refreshCurrentUser();
    await _offersController.loadOffers();
    await _communityController.loadPeople();
    _mandatoryProfileFlowOpen = false;

    if (!mounted) {
      return;
    }

    if (widget.authController.currentUser?.needsMandatoryProfileSetup ??
        false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeOpenMandatoryProfileSetup());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OffersPage(
        authController: widget.authController,
        offersController: _offersController,
        onManageOwnOffersTap: () {
          if (!mounted) {
            return;
          }
          setState(() => _selectedIndex = 3);
        },
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
