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
  String? _lastProfileAlertSignature;

  @override
  void initState() {
    super.initState();
    _offersController = OffersController(widget.authController.apiClient)
      ..loadOffers();
    _communityController = CommunityController(widget.authController.apiClient)
      ..loadPeople();
    widget.authController.addListener(_handleAuthStateChanged);
    _offersController.addListener(_handleOffersStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenMandatoryProfileSetup());
      _applyLaunchTargetIfNeeded();
      _maybeShowProfileManagementAlert();
    });
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.launchTarget != widget.launchTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyLaunchTargetIfNeeded();
        _maybeShowProfileManagementAlert(forceProfileTab: true);
      });
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_handleAuthStateChanged);
    _offersController.removeListener(_handleOffersStateChanged);
    _offersController.dispose();
    _communityController.dispose();
    super.dispose();
  }

  void _handleOffersStateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowProfileManagementAlert();
    });
  }

  void _handleAuthStateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeOpenMandatoryProfileSetup());
      unawaited(_offersController.loadOffers());
      unawaited(_communityController.loadPeople());
      _applyLaunchTargetIfNeeded();
      _maybeShowProfileManagementAlert();
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

  bool _hasOffersToManage() {
    final user = widget.authController.currentUser;
    if (user == null) {
      return false;
    }
    return user.pendingClaimRequests.isNotEmpty ||
        user.manageableOffersCount > 0 ||
        _offersController.hiddenOwnOffersCount > 0;
  }

  bool _hasReviewsToManage() {
    final user = widget.authController.currentUser;
    if (user == null) {
      return false;
    }
    return user.pendingReviewReminders.isNotEmpty;
  }

  void _maybeShowProfileManagementAlert({bool forceProfileTab = false}) {
    if (!mounted) {
      return;
    }

    final user = widget.authController.currentUser;
    if (user == null) {
      _lastProfileAlertSignature = null;
      return;
    }

    final hasOffersToManage = _hasOffersToManage();
    final hasReviewsToManage = _hasReviewsToManage();
    if (!hasOffersToManage && !hasReviewsToManage) {
      _lastProfileAlertSignature = null;
      return;
    }

    final signature =
        '${user.id}:${hasOffersToManage ? 1 : 0}:${hasReviewsToManage ? 1 : 0}';
    if (_lastProfileAlertSignature == signature && !forceProfileTab) {
      return;
    }
    _lastProfileAlertSignature = signature;

    if (forceProfileTab && _selectedIndex != 3) {
      setState(() => _selectedIndex = 3);
    }

    final String message;
    if (hasOffersToManage && hasReviewsToManage) {
      message = 'Hai delle offerte e delle recensioni da gestire nel profilo.';
    } else if (hasOffersToManage) {
      message = 'Hai delle offerte da gestire nel profilo.';
    } else {
      message = 'Hai delle recensioni da gestire nel profilo.';
    }

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
        destinations: [
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
            icon: _ProfileTabIcon(
              selected: false,
              hasAlert: _hasOffersToManage() || _hasReviewsToManage(),
            ),
            selectedIcon: _ProfileTabIcon(
              selected: true,
              hasAlert: _hasOffersToManage() || _hasReviewsToManage(),
            ),
            label: 'Profilo',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class _ProfileTabIcon extends StatelessWidget {
  const _ProfileTabIcon({
    required this.selected,
    required this.hasAlert,
  });

  final bool selected;
  final bool hasAlert;

  @override
  Widget build(BuildContext context) {
    final icon = selected ? Icons.person : Icons.person_outline;
    return SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: Alignment.center,
            child: Icon(icon),
          ),
          if (hasAlert)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
