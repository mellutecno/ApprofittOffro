import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat/chat_presence_tracker.dart';
import '../../core/navigation/app_launch_target.dart';
import '../../core/theme/app_theme.dart';
import '../admin/admin_page.dart';
import '../auth/auth_controller.dart';
import '../chat/chat_inbox_page.dart';
import '../community/community_controller.dart';
import '../community/community_page.dart';
import '../chat/chat_page.dart';
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
  int _profileRefreshVersion = 0;
  late final OffersController _offersController;
  late final CommunityController _communityController;
  bool _mandatoryProfileFlowOpen = false;
  bool _managementAlertInFlight = false;
  bool _launchRefreshInFlight = false;
  bool _chatLaunchInFlight = false;
  bool _reviewAlertVisible = false;
  String? _lastReviewsAlertSignature;

  bool get _isAdminUser => widget.authController.currentUser?.isAdmin == true;
  int get _profileTabIndex => _isAdminUser ? 0 : 4;
  int? get _adminTabIndex => _isAdminUser ? 0 : null;

  @override
  void initState() {
    super.initState();
    if (_isAdminUser) {
      _selectedIndex = _adminTabIndex ?? 0;
    }
    _offersController = OffersController(widget.authController.apiClient)
      ..loadOffers();
    _communityController = CommunityController(widget.authController.apiClient);
    if (!_isAdminUser) {
      unawaited(_communityController.loadPeople());
    }
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
      if (!_isAdminUser) {
        unawaited(_communityController.loadPeople());
      }
      if (_isAdminUser && mounted) {
        setState(() => _selectedIndex = _adminTabIndex ?? 0);
      }
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

    if (!_isAdminUser) {
      if (target.isChat) {
        unawaited(_openChatFromLaunchTarget(target));
      } else if (target == AppLaunchTarget.pendingRequests ||
          target == AppLaunchTarget.profile) {
        if (_selectedIndex != _profileTabIndex) {
          setState(() => _selectedIndex = _profileTabIndex);
        }
      } else if (target == AppLaunchTarget.offers && _selectedIndex != 0) {
        setState(() => _selectedIndex = 0);
      }
    }

    widget.onLaunchTargetHandled?.call();
    unawaited(_refreshAfterNotificationOpen());
  }

  Future<void> _openChatFromLaunchTarget(AppLaunchTarget target) async {
    if (!mounted || _chatLaunchInFlight) {
      return;
    }

    final offerId = target.offerId;
    final otherUserId = target.otherUserId;
    if (offerId == null ||
        offerId <= 0 ||
        otherUserId == null ||
        otherUserId <= 0) {
      return;
    }

    if (ChatPresenceTracker.isViewingConversation(
      offerId: offerId,
      otherUserId: otherUserId,
    )) {
      return;
    }

    final currentUser = widget.authController.currentUser;
    if (currentUser == null) {
      return;
    }

    _chatLaunchInFlight = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(
            apiClient: widget.authController.apiClient,
            offerId: offerId.toString(),
            currentUserId: currentUser.id.toString(),
            currentUserName: currentUser.nome,
            currentUserPhotoFilename: currentUser.photoFilename,
            otherUserId: otherUserId.toString(),
            otherUserName: target.otherUserName ?? 'Utente',
            otherUserPhotoFilename: target.otherUserPhotoFilename ?? '',
          ),
        ),
      );
      if (mounted) {
        setState(() => _selectedIndex = 2);
      }
    } finally {
      _chatLaunchInFlight = false;
    }
  }

  Future<void> _refreshAfterNotificationOpen() async {
    if (_launchRefreshInFlight || !mounted) {
      return;
    }

    _launchRefreshInFlight = true;
    try {
      await widget.authController.refreshCurrentUser();
      await _offersController.loadOffers();
      if (!_isAdminUser) {
        await _communityController.loadPeople();
      }
      if (mounted && !_isAdminUser) {
        setState(() {
          _profileRefreshVersion++;
        });
      }
    } finally {
      _launchRefreshInFlight = false;
    }
  }

  bool _hasReviewsToManage() {
    final user = widget.authController.currentUser;
    if (user == null) {
      return false;
    }
    return user.pendingReviewReminders.isNotEmpty ||
        user.pendingClaimRequests.isNotEmpty;
  }

  void _maybeShowProfileManagementAlert({bool forceProfileTab = false}) {
    if (!mounted) {
      return;
    }

    final user = widget.authController.currentUser;
    if (user == null) {
      _lastReviewsAlertSignature = null;
      return;
    }

    if (user.isAdmin) {
      _lastReviewsAlertSignature = null;
      return;
    }

    final hasReviewsToManage = _hasReviewsToManage();
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (!hasReviewsToManage && _reviewAlertVisible) {
      messenger?.hideCurrentSnackBar();
      _reviewAlertVisible = false;
    }

    if (!hasReviewsToManage) {
      _lastReviewsAlertSignature = null;
    }

    if (!hasReviewsToManage) {
      return;
    }

    final hasPendingClaims = user.pendingClaimRequests.isNotEmpty;
    final hasPendingReviews = user.pendingReviewReminders.isNotEmpty;
    final signature = hasReviewsToManage
        ? '${user.id}:${user.pendingReviewReminders.length}:${user.pendingClaimRequests.length}'
        : null;
    final shouldShowReviews =
        signature != null && _lastReviewsAlertSignature != signature;

    if (!shouldShowReviews) {
      return;
    }

    _lastReviewsAlertSignature = signature;
    if (_managementAlertInFlight) {
      return;
    }

    _managementAlertInFlight = true;
    unawaited(
      _runManagementAlertSequence(
        showReviewAlert: shouldShowReviews,
        restoreReviewAlert: hasReviewsToManage,
        forceProfileTab: forceProfileTab,
        hasPendingClaims: hasPendingClaims,
        hasPendingReviews: hasPendingReviews,
      ),
    );
  }

  Future<void> _runManagementAlertSequence({
    required bool showReviewAlert,
    required bool restoreReviewAlert,
    required bool forceProfileTab,
    required bool hasPendingClaims,
    required bool hasPendingReviews,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _managementAlertInFlight = false;
      return;
    }

    try {
      if ((showReviewAlert || restoreReviewAlert) &&
          mounted &&
          _hasReviewsToManage()) {
        messenger.hideCurrentSnackBar();
        _reviewAlertVisible = true;
        final claimWord = hasPendingClaims ? 'richieste da gestire' : '';
        final reviewWord = hasPendingReviews ? 'recensioni da gestire' : '';
        final parts =
            [claimWord, reviewWord].where((p) => p.isNotEmpty).toList();
        final message = parts.length == 2
            ? 'Hai ${parts[0]} e ${parts[1]} nel profilo.'
            : 'Hai ${parts.first} nel profilo.';
        unawaited(
          messenger
              .showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(message,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                  backgroundColor: const Color(0xFFE07800),
                  duration: const Duration(days: 1),
                  action: SnackBarAction(
                    label: 'Apri',
                    textColor: Colors.white,
                    onPressed: () {
                      if (!mounted) {
                        return;
                      }
                      setState(() => _selectedIndex = _profileTabIndex);
                    },
                  ),
                ),
              )
              .closed
              .then((_) {
            _reviewAlertVisible = false;
          }),
        );
      }
    } finally {
      _managementAlertInFlight = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeShowProfileManagementAlert(forceProfileTab: forceProfileTab);
        });
      }
    }
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
    if (!_isAdminUser) {
      await _communityController.loadPeople();
    }
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
    final pages = _isAdminUser
        ? <Widget>[
            AdminPage(authController: widget.authController),
          ]
        : <Widget>[
            OffersPage(
              authController: widget.authController,
              offersController: _offersController,
              onGoToProfile: () =>
                  setState(() => _selectedIndex = _profileTabIndex),
              onGoToChat: () => setState(() => _selectedIndex = 2),
            ),
            CommunityPage(
              authController: widget.authController,
              communityController: _communityController,
            ),
            ChatInboxPage(
              authController: widget.authController,
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
            ProfilePage(
              key: ValueKey<int>(_profileRefreshVersion),
              authController: widget.authController,
              onGoToChat: () => setState(() => _selectedIndex = 2),
            ),
          ];
    final selectedIndex = _selectedIndex.clamp(0, pages.length - 1);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: AppTheme.vividViolet.withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          height: 72,
          indicatorColor: AppTheme.vividViolet.withValues(alpha: 0.30),
          shadowColor: AppTheme.vividViolet.withValues(alpha: 0.62),
          selectedIndex: selectedIndex,
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              color: selected
                  ? AppTheme.vividViolet
                  : AppTheme.brown.withValues(alpha: 0.86),
              height: 1.05,
            );
          }),
          destinations: _isAdminUser
              ? const [
                  NavigationDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings_rounded),
                    label: 'Admin',
                  ),
                ]
              : [
                  const NavigationDestination(
                    icon: Icon(Icons.restaurant_menu_outlined),
                    selectedIcon: Icon(Icons.restaurant_menu_rounded),
                    label: 'Approfitta',
                  ),
                  const NavigationDestination(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.groups_rounded),
                    ),
                    selectedIcon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.groups),
                    ),
                    label: 'Community',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.forum_outlined),
                    selectedIcon: Icon(Icons.forum_rounded),
                    label: 'Chat',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.add_circle_outline),
                    selectedIcon: Icon(Icons.add_circle),
                    label: 'Offri',
                  ),
                  NavigationDestination(
                    icon: _ProfileTabIcon(
                      selected: false,
                      hasAlert: _hasReviewsToManage(),
                    ),
                    selectedIcon: _ProfileTabIcon(
                      selected: true,
                      hasAlert: _hasReviewsToManage(),
                    ),
                    label: 'Io',
                  ),
                ],
          onDestinationSelected: (index) {
            if (index == _selectedIndex) {
              if (!_isAdminUser && index == 0) {
                unawaited(_offersController.loadOffers());
              }
              return;
            }
            setState(() => _selectedIndex = index);
          },
        ),
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
                  color: AppTheme.orange,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.paper, width: 1.2),
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
