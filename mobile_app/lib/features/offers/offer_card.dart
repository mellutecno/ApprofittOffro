import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/offer.dart';
import '../profile/public_profile_page.dart';

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.apiClient,
    this.onClaim,
    this.onEditOwn,
    this.onArchive,
    this.allowProfileOpen = true,
    this.showAddressLeadIcon = true,
  });

  final Offer offer;
  final ApiClient apiClient;
  final Future<void> Function()? onClaim;
  final VoidCallback? onEditOwn;
  final Future<void> Function()? onArchive;
  final bool allowProfileOpen;
  final bool showAddressLeadIcon;

  bool get _isPast => offer.dataOra.toLocal().isBefore(DateTime.now());

  bool get _isOngoing =>
      _isPast &&
      offer.dataOra
          .toLocal()
          .isAfter(DateTime.now().subtract(const Duration(hours: 3)));

  bool get _canArchive =>
      offer.isOwn &&
      offer.dataOra
          .toLocal()
          .isBefore(DateTime.now().subtract(const Duration(hours: 3)));

  @override
  Widget build(BuildContext context) {
    final mealColor = _mealColor(offer.tipoPasto);
    final canNavigateToOffer = offer.isOwn || offer.claimStatus == 'claimed';
    final canAddToCalendar =
        offer.isOwn || offer.alreadyClaimed || offer.claimStatus == 'claimed';
    final occupiedSeats = (offer.postiTotali - offer.postiDisponibili)
        .clamp(0, offer.postiTotali);
    final localeImageUrl =
        offer.fotoLocale.isNotEmpty && offer.fotoLocale != 'nessuna.jpg'
            ? apiClient.buildUploadUrl(offer.fotoLocale)
            : null;
    final authorPhotoUrl = offer.autoreFoto.isNotEmpty
        ? apiClient.buildUploadUrl(offer.autoreFoto)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: allowProfileOpen
                    ? () => _openProfile(context, offer.autoreId)
                    : null,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: authorPhotoUrl != null
                          ? NetworkImage(authorPhotoUrl)
                          : null,
                      child: authorPhotoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.autoreNome,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('${offer.autoreEta} anni'),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: Color(0xFFD49B00),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                  offer.autoreRatingAverage.toStringAsFixed(1)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (allowProfileOpen)
                            Text(
                              'Visualizza profilo',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (offer.hostWhatsAppLink.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _WhatsAppAction(
                                compact: true,
                                onTap: () => _handleWhatsAppTap(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (allowProfileOpen)
                      const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CenteredChip(
              label: offer.tipoPasto.toUpperCase(),
              backgroundColor: mealColor.withValues(alpha: 0.16),
              foregroundColor: mealColor,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _CenteredChip(
                    label: _formatWhenLabel(offer.dataOra),
                    backgroundColor: mealColor.withValues(alpha: 0.10),
                    foregroundColor: mealColor,
                  ),
                ),
                if (canAddToCalendar) ...[
                  const SizedBox(width: 10),
                  _ReminderButton(
                    offer: offer,
                    apiClient: apiClient,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Partecipanti  $occupiedSeats di ${offer.postiTotali}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: offer.participants.isEmpty
                  ? const Text(
                      'Per ora nessuno si e\' ancora aggiunto.',
                      textAlign: TextAlign.center,
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 12,
                      children: offer.participants.map((participant) {
                        final photoUrl = participant.photoFilename.isNotEmpty
                            ? apiClient
                                .buildUploadUrl(participant.photoFilename)
                            : null;
                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _openProfile(context, participant.id),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundImage: photoUrl != null
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null
                                    ? const Icon(Icons.person_outline)
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  participant.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (participant.whatsAppLink.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _WhatsAppAction(
                                  onTap: () => _handleParticipantWhatsAppTap(
                                    context,
                                    participant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              offer.nomeLocale,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (localeImageUrl != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(
                    localeImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => Container(
                      color: const Color(0xFFF6EEE2),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showAddressLeadIcon) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.peach.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.indirizzo,
                          style: const TextStyle(
                            color: AppTheme.espresso,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Circa ${offer.distanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canNavigateToOffer) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () =>
                            _openExternalLink(_googleMapsDirectionsUrl()),
                        child: Ink(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.peach.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Icon(
                            Icons.near_me_rounded,
                            color: AppTheme.orange,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (offer.descrizione.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                offer.descrizione,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  height: 1.45,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.espresso,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (offer.stato == 'archiviata')
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Text(
                  'Evento archiviato',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.espresso,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else if (_isOngoing && offer.isOwn)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Text(
                  'In corso',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF3D8B5A),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              )
            else if (_canArchive && onArchive != null)
              FilledButton(
                onPressed: () => onArchive?.call(),
                child: const Text('Archivia'),
              )
            else if (offer.isOwn && offer.telefonoLocale.trim().isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: onEditOwn,
                      child: const Text('Modifica la tua offerta'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _callLocalPhone,
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Vuoi prenotare?'),
                    ),
                  ),
                ],
              )
            else
              FilledButton(
                onPressed: offer.isOwn
                    ? onEditOwn
                    : (!offer.canClaim || onClaim == null
                        ? null
                        : () => onClaim!.call()),
                child: Text(_ctaLabel()),
              ),
          ],
        ),
      ),
    );
  }

  String _ctaLabel() {
    if (offer.stato == 'archiviata') {
      return 'Evento archiviato';
    }
    if (_isOngoing && offer.isOwn) {
      return 'In corso';
    }
    if (_canArchive) {
      return 'Archivia';
    }
    if (offer.isOwn) {
      return 'Modifica la tua offerta';
    }
    if (offer.claimStatus == 'pending') {
      return 'Richiesta inviata';
    }
    if (offer.claimStatus == 'rejected') {
      return 'Richiesta non accettata';
    }
    if (offer.claimStatus == 'started') {
      return 'In corso';
    }
    if (offer.alreadyClaimed || offer.claimStatus == 'claimed') {
      return 'Hai approfittato';
    }
    if (offer.claimStatus == 'full') {
      return 'Completa · non piu\' prenotabile';
    }
    if (offer.claimStatus == 'booking_closed' ||
        offer.claimStatus == 'started') {
      return 'Non piu\' prenotabile';
    }
    return 'Approfitta';
  }

  Color _mealColor(String type) {
    switch (type) {
      case 'colazione':
        return const Color(0xFFD49B00);
      case 'pranzo':
        return const Color(0xFF3D8B5A);
      case 'cena':
        return const Color(0xFF7A4EC7);
      case 'ape':
        return const Color(0xFFE05533);
      default:
        return const Color(0xFFE86E35);
    }
  }

  String _formatWhenLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(local.year, local.month, local.day);
    final time = DateFormat('HH:mm').format(local);

    if (eventDay == today) {
      return 'OGGI ALLE $time';
    }
    if (eventDay == today.add(const Duration(days: 1))) {
      return 'DOMANI ALLE $time';
    }
    return DateFormat('dd/MM - HH:mm').format(local).toUpperCase();
  }

  void _openProfile(BuildContext context, int userId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(
          apiClient: apiClient,
          userId: userId,
        ),
      ),
    );
  }

  Future<void> _openExternalLink(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleWhatsAppTap(BuildContext context) async {
    final isOwn = offer.isOwn;

    if (!offer.hostChatEnabled) {
      if (!isOwn) {
        try {
          await apiClient.requestChatNotification(offerId: offer.id);
        } catch (_) {}
      }

      if (!context.mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (bottomContext) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppTheme.cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: Color(0xFF25D366),
              ),
              const SizedBox(height: 16),
              const Text(
                'Chat non attiva',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.espresso,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isOwn
                    ? 'Devi attivare la chat WhatsApp nelle impostazioni del tuo profilo per permettere agli altri di chattare con te.'
                    : '${offer.autoreNome} non ha ancora attivato la chat WhatsApp. Abbiamo inviato una notifica per avvisarlo.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.brown,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(bottomContext).pop(),
                  child: const Text('Chiudi'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } else {
      await _openExternalLink(offer.hostWhatsAppLink);
    }
  }

  Future<void> _handleParticipantWhatsAppTap(
    BuildContext context,
    Participant participant,
  ) async {
    if (!participant.chatEnabled) {
      try {
        await apiClient.requestChatNotification(toUserId: participant.id);
      } catch (_) {}

      if (!context.mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (bottomContext) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppTheme.cream,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: Color(0xFF25D366),
              ),
              const SizedBox(height: 16),
              const Text(
                'Chat non attiva',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.espresso,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${participant.name} non ha ancora attivato la chat WhatsApp. Abbiamo inviato una notifica per avvisarlo.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.brown,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(bottomContext).pop(),
                  child: const Text('Chiudi'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } else {
      await _openExternalLink(participant.whatsAppLink);
    }
  }

  Future<void> _callLocalPhone() async {
    final digits = offer.telefonoLocale.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) {
      return;
    }
    final uri = Uri.tryParse('tel:$digits');
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _googleMapsDirectionsUrl() {
    return 'https://www.google.com/maps/dir/?api=1&destination=${offer.latitude},${offer.longitude}';
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
    return '${value.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
  }
}

class _CenteredChip extends StatelessWidget {
  const _CenteredChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WhatsAppAction extends StatelessWidget {
  const _WhatsAppAction({
    required this.onTap,
    this.compact = false,
  });

  final Future<void> Function() onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0x2538C172),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0x8838C172),
            ),
          ),
          child: Icon(
            FontAwesomeIcons.whatsapp,
            size: iconSize,
            color: const Color(0xFF138A45),
          ),
        ),
      ),
    );
  }
}

class _ReminderButton extends StatefulWidget {
  const _ReminderButton({
    required this.offer,
    required this.apiClient,
  });

  final Offer offer;
  final ApiClient apiClient;

  @override
  State<_ReminderButton> createState() => _ReminderButtonState();
}

class _ReminderButtonState extends State<_ReminderButton> {
  List<int> _reminderMinutes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    try {
      final minutes = await widget.apiClient.fetchOfferReminders(widget.offer.id);
      if (mounted) {
        setState(() {
          _reminderMinutes = minutes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveReminders(List<int> minutes) async {
    try {
      await widget.apiClient.saveOfferReminders(widget.offer.id, minutes);
      if (mounted) {
        setState(() => _reminderMinutes = minutes);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nel salvataggio dei promemoria.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasReminders = _reminderMinutes.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _openReminderDialog(context),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: hasReminders
                ? const Color(0xFFFFD54F).withValues(alpha: 0.85)
                : AppTheme.peach.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          child: Icon(
            hasReminders
                ? Icons.notifications_active
                : Icons.notifications_none,
            color: hasReminders ? const Color(0xFF8D6E00) : AppTheme.orange,
            size: 20,
          ),
        ),
      ),
    );
  }

  Future<void> _openReminderDialog(BuildContext context) async {
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) => _ReminderDialog(
        offer: widget.offer,
        currentReminders: _reminderMinutes,
      ),
    );
    if (result != null) {
      await _saveReminders(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isEmpty
                  ? 'Promemoria disattivati'
                  : 'Promemoria impostati a ${result.join(', ')} min prima',
            ),
          ),
        );
      }
    }
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    required this.offer,
    required this.currentReminders,
  });

  final Offer offer;
  final List<int> currentReminders;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late List<int> _selectedMinutes;

  final List<int> _options = [15, 30, 60, 120, 180];

  @override
  void initState() {
    super.initState();
    _selectedMinutes = List.from(widget.currentReminders);
  }

  void _toggleOption(int minutes) {
    setState(() {
      if (_selectedMinutes.contains(minutes)) {
        _selectedMinutes.remove(minutes);
      } else if (_selectedMinutes.length < 2) {
        _selectedMinutes.add(minutes);
        _selectedMinutes.sort();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Imposta promemoria'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scegli fino a 2 promemoria per "${widget.offer.nomeLocale}":',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _options.map((minutes) {
              final isSelected = _selectedMinutes.contains(minutes);
              return FilterChip(
                label: Text('$minutes min'),
                selected: isSelected,
                onSelected: (_) => _toggleOption(minutes),
                selectedColor: const Color(0xFFFFD54F),
              );
            }).toList(),
          ),
          if (_selectedMinutes.length >= 2) ...[
            const SizedBox(height: 12),
            Text(
              'Massimo 2 promemoria selezionati.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.orange,
                  ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop([]),
          child: const Text('Rimuovi tutti'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedMinutes),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
