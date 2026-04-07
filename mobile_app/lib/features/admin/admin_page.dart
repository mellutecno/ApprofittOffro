import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_hero_card.dart';
import '../../core/widgets/brand_wordmark.dart';
import '../../models/admin_dashboard.dart';
import '../auth/auth_controller.dart';

enum _AdminSection {
  users('Utenti'),
  futureOffers('Eventi futuri'),
  pastOffers('Eventi passati');

  const _AdminSection(this.label);

  final String label;
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.authController});

  final AuthController authController;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late Future<AdminDashboardData> _dashboardFuture;
  _AdminSection _selectedSection = _AdminSection.users;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = widget.authController.apiClient.fetchAdminDashboard();
  }

  Future<void> _reloadDashboard() async {
    final future = widget.authController.apiClient.fetchAdminDashboard();
    setState(() => _dashboardFuture = future);
    await future;
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Data non disponibile';
    }
    return DateFormat("d MMM yyyy, HH:mm", 'it_IT').format(dateTime.toLocal());
  }

  Future<void> _confirmDeleteUser(AdminUserSummary user) async {
    final reasonController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Elimina account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stai per eliminare ${user.name}.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivazione',
                  hintText: 'Spiega chiaramente il motivo della rimozione.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    try {
      final message = await widget.authController.apiClient.deleteAdminUser(
        user.id,
        motivazione: reasonController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
      await _reloadDashboard();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _contactUser(AdminUserSummary user) async {
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Contatta utente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.email),
              const SizedBox(height: 12),
              TextField(
                controller: subjectController,
                decoration: const InputDecoration(
                  labelText: 'Oggetto',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Messaggio',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Invia'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      subjectController.dispose();
      messageController.dispose();
      return;
    }

    try {
      final result = await widget.authController.apiClient.sendAdminMessage(
        user.id,
        subject: subjectController.text.trim(),
        message: messageController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(result)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      subjectController.dispose();
      messageController.dispose();
    }
  }

  Future<void> _confirmDeleteOffer(AdminOfferSummary offer) async {
    final reasonController = TextEditingController(
      text: 'Evento rimosso dall’amministrazione.',
    );
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Elimina evento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${offer.localeName} • ${offer.author.name}'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivazione',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Elimina'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    try {
      final result = await widget.authController.apiClient.deleteOffer(
        offer.id,
        motivazione: reasonController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(result)));
      await _reloadDashboard();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      reasonController.dispose();
    }
  }

  Widget _buildAvatar({
    required String filename,
    required String fallback,
    double radius = 26,
  }) {
    final trimmed = filename.trim();
    final imageProvider = trimmed.isEmpty
        ? null
        : NetworkImage(widget.authController.apiClient.buildUploadUrl(trimmed));
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.peach,
      backgroundImage: imageProvider,
      child: imageProvider == null
          ? Text(
              fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: AppTheme.brown,
                fontWeight: FontWeight.w900,
                fontSize: radius * 0.78,
              ),
            )
          : null,
    );
  }

  Widget _buildStatsGrid(AdminDashboardStats stats) {
    final items = <({String label, int value})>[
      (label: 'Utenti', value: stats.users),
      (label: 'Admin', value: stats.admins),
      (label: 'Futuri', value: stats.futureOffers),
      (label: 'Passati', value: stats.pastOffers),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${item.value}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.brown,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildSectionItems(AdminDashboardData data) {
    switch (_selectedSection) {
      case _AdminSection.users:
        if (data.users.isEmpty) {
          return const [
            _AdminEmptyState(
              title: 'Nessun utente da mostrare',
              subtitle: 'Appena si iscrivono nuovi profili, li vedrai qui.',
            ),
          ];
        }
        return data.users.map(_buildUserCard).toList();
      case _AdminSection.futureOffers:
        if (data.futureOffers.isEmpty) {
          return const [
            _AdminEmptyState(
              title: 'Nessun evento futuro',
              subtitle: 'Al momento non ci sono tavoli ancora programmati.',
            ),
          ];
        }
        return data.futureOffers
            .map((offer) => _buildOfferCard(offer))
            .toList();
      case _AdminSection.pastOffers:
        if (data.pastOffers.isEmpty) {
          return const [
            _AdminEmptyState(
              title: 'Nessun evento passato',
              subtitle:
                  'Lo storico sarà visibile qui appena ci saranno eventi chiusi.',
            ),
          ];
        }
        return data.pastOffers.map((offer) => _buildOfferCard(offer)).toList();
    }
  }

  Widget _buildUserCard(AdminUserSummary user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(
                  filename: user.photoFilename,
                  fallback: user.name,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.brown,
                            ),
                          ),
                          _StatusPill(
                            label: user.isVerified
                                ? 'Verificato'
                                : 'Non verificato',
                            color: user.isVerified
                                ? const Color(0xFF0F9D75)
                                : const Color(0xFFF39C12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${user.ageDisplay} anni • ${user.cityLabel.isNotEmpty ? user.cityLabel : 'Città non definita'}',
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniStat(label: 'Offerte', value: user.offersCount),
                _MiniStat(label: 'Approfitti', value: user.claimsCount),
                _MiniStat(label: 'Recensioni', value: user.reviewsCount),
              ],
            ),
            if (user.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                user.bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.78),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _contactUser(user),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Contatta'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFBE3455),
                    ),
                    onPressed: () => _confirmDeleteUser(user),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Elimina'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCard(AdminOfferSummary offer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  label: offer.mealType.toUpperCase(),
                  color: offer.mealType == 'colazione'
                      ? const Color(0xFFDD4B82)
                      : offer.mealType == 'pranzo'
                          ? const Color(0xFF7640C8)
                          : const Color(0xFF2E8AD1),
                ),
                _StatusPill(
                  label: offer.status,
                  color: AppTheme.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              offer.localeName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppTheme.brown,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${offer.author.name} • ${offer.author.email}',
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.74),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDateTime(offer.startsAt),
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.74),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              offer.address,
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.74),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniStat(label: 'Posti', value: offer.totalSeats),
                _MiniStat(label: 'Disponibili', value: offer.availableSeats),
                _MiniStat(
                    label: 'Partecipanti', value: offer.participantsCount),
              ],
            ),
            if (offer.description.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                offer.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.brown.withValues(alpha: 0.78),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFBE3455),
                ),
                onPressed: () => _confirmDeleteOffer(offer),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Elimina evento'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting && data == null;
        final error = snapshot.hasError ? snapshot.error.toString() : null;

        if (isLoading) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 420,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }

        if (error != null && data == null) {
          return RefreshIndicator(
            onRefresh: _reloadDashboard,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 80),
                Text(
                  'Non riesco a caricare il pannello admin adesso.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.brown.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _reloadDashboard,
                  child: const Text('Riprova'),
                ),
              ],
            ),
          );
        }

        final dashboard = data!;
        final items = _buildSectionItems(dashboard);

        return RefreshIndicator(
          onRefresh: _reloadDashboard,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
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
                actions: [
                  IconButton(
                    onPressed: widget.authController.isBusy
                        ? null
                        : widget.authController.logout,
                    icon: const Icon(Icons.logout),
                    tooltip: 'Esci',
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: BrandHeroCard(
                    eyebrow: 'ADMIN',
                    title: 'Controllo completo della piattaforma',
                    subtitle:
                        'Gestisci utenti, monitora eventi futuri e passati, elimina account o tavoli problematici e contatta chi serve direttamente dal telefono.',
                    centered: true,
                    footer: Column(
                      children: [
                        _buildStatsGrid(dashboard.stats),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<_AdminSection>(
                            segments: _AdminSection.values
                                .map(
                                  (section) => ButtonSegment<_AdminSection>(
                                    value: section,
                                    label: Text(section.label),
                                  ),
                                )
                                .toList(),
                            selected: <_AdminSection>{_selectedSection},
                            onSelectionChanged: (selection) {
                              setState(
                                () => _selectedSection = selection.first,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    _selectedSection == _AdminSection.users
                        ? 'Utenti registrati'
                        : _selectedSection == _AdminSection.futureOffers
                            ? 'Eventi futuri'
                            : 'Eventi passati',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.brown,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: items
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: item,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.mist,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: AppTheme.brown,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.brown.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
