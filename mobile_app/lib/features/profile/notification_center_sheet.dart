import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_notification.dart';

class NotificationCenterSheet extends StatefulWidget {
  const NotificationCenterSheet({
    super.key,
    required this.apiClient,
  });

  final ApiClient apiClient;

  @override
  State<NotificationCenterSheet> createState() =>
      _NotificationCenterSheetState();
}

class _NotificationCenterSheetState extends State<NotificationCenterSheet> {
  late Future<AppNotificationBundle> _future;
  List<AppNotification>? _notifications;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AppNotificationBundle> _load() async {
    final bundle = await widget.apiClient.fetchNotifications();
    if (bundle.unreadCount > 0) {
      await widget.apiClient.markAllNotificationsRead();
    }
    if (mounted) {
      setState(() => _notifications = bundle.notifications);
    }
    return bundle;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _closeNotification(AppNotification notification) async {
    await widget.apiClient.deleteNotification(notification.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _notifications = (_notifications ?? const <AppNotification>[])
          .where((item) => item.id != notification.id)
          .toList();
    });
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    return DateFormat("d MMM HH:mm", 'it_IT').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppTheme.cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: FutureBuilder<AppNotificationBundle>(
              future: _future,
              builder: (context, snapshot) {
                final notifications =
                    _notifications ?? snapshot.data?.notifications;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBorder,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(
                            Icons.notifications_active_rounded,
                            color: AppTheme.vividViolet,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Centro notifiche',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Chiudi',
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Qui trovi gli avvisi dell\'app delle ultime 24 ore. Dopo 24 ore si cancellano da soli.',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (snapshot.connectionState != ConnectionState.done &&
                          notifications == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError && notifications == null)
                        _NotificationEmptyState(
                          icon: Icons.wifi_off_rounded,
                          title: 'Non riesco a caricare gli avvisi',
                          subtitle: snapshot.error.toString(),
                        )
                      else if ((notifications ?? const <AppNotification>[])
                          .isEmpty)
                        const _NotificationEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Nessuna notifica recente',
                          subtitle:
                              'Quando arriva un avviso dell\'app lo ritrovi qui per 24 ore.',
                        )
                      else
                        ...(notifications ?? const <AppNotification>[]).map(
                          (notification) => _NotificationCard(
                            notification: notification,
                            createdAtLabel: _formatDate(notification.createdAt),
                            expiresAtLabel: _formatDate(notification.expiresAt),
                            onClose: () => _closeNotification(notification),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.createdAtLabel,
    required this.expiresAtLabel,
    required this.onClose,
  });

  final AppNotification notification;
  final String createdAtLabel;
  final String expiresAtLabel;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.surfaceGradient,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.vividViolet.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.notifications_rounded,
                      color: AppTheme.vividViolet,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title,
                          style: const TextStyle(
                            color: AppTheme.brown,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        if (createdAtLabel.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            createdAtLabel,
                            style: TextStyle(
                              color: AppTheme.brown.withValues(alpha: 0.58),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                notification.body,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.82),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      expiresAtLabel.isEmpty
                          ? 'Si cancella automaticamente.'
                          : 'Si cancella il $expiresAtLabel',
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.58),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Chiudi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppTheme.vividViolet),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.brown.withValues(alpha: 0.68),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
