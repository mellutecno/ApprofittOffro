import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../models/offer.dart';

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.apiClient,
    this.onClaim,
  });

  final Offer offer;
  final ApiClient apiClient;
  final Future<void> Function()? onClaim;

  @override
  Widget build(BuildContext context) {
    final mealColor = _mealColor(offer.tipoPasto);
    final localeImageUrl = offer.fotoLocale.isNotEmpty && offer.fotoLocale != 'nessuna.jpg'
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
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: authorPhotoUrl != null ? NetworkImage(authorPhotoUrl) : null,
                  child: authorPhotoUrl == null ? const Icon(Icons.person) : null,
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
                      Text('${offer.autoreEta} anni • ${offer.autoreRatingAverage.toStringAsFixed(1)} ★'),
                      const SizedBox(height: 6),
                      Text(
                        'Visualizza profilo',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _CenteredChip(
              label: offer.tipoPasto.toUpperCase(),
              backgroundColor: mealColor.withOpacity(0.16),
              foregroundColor: mealColor,
            ),
            const SizedBox(height: 10),
            _CenteredChip(
              label: _formatWhenLabel(offer.dataOra),
              backgroundColor: mealColor.withOpacity(0.10),
              foregroundColor: mealColor,
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'Partecipanti',
                style: TextStyle(fontWeight: FontWeight.w700),
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
                      'Per ora nessuno si e` ancora aggiunto.',
                      textAlign: TextAlign.center,
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 12,
                      children: offer.participants.map((participant) {
                        final photoUrl = participant.photoFilename.isNotEmpty
                            ? apiClient.buildUploadUrl(participant.photoFilename)
                            : null;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                              child: photoUrl == null ? const Icon(Icons.person_outline) : null,
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
                          ],
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
                color: const Color(0xFFFFF8EE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.indirizzo),
                  const SizedBox(height: 6),
                  Text('Circa ${offer.distanceKm.toStringAsFixed(1)} km'),
                ],
              ),
            ),
            if (offer.descrizione.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                offer.descrizione,
                style: const TextStyle(height: 1.4),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onClaim == null ? null : () => onClaim!.call(),
              child: Text(_ctaLabel()),
            ),
          ],
        ),
      ),
    );
  }

  String _ctaLabel() {
    if (offer.isOwn) {
      return 'La tua offerta';
    }
    if (offer.alreadyClaimed) {
      return 'Sei gia` dentro';
    }
    if (offer.bookingClosed) {
      return 'Prenotazioni chiuse';
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
    return DateFormat('dd/MM • HH:mm').format(local).toUpperCase();
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
