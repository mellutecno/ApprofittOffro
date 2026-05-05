import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';
import 'brand_wordmark.dart';

Future<bool> showLegalAcceptanceSheet({
  required BuildContext context,
  required ApiClient apiClient,
  LegalStatus? initialStatus,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _LegalAcceptanceSheet(
      apiClient: apiClient,
      initialStatus: initialStatus,
    ),
  );
  return result == true;
}

class _LegalAcceptanceSheet extends StatefulWidget {
  const _LegalAcceptanceSheet({
    required this.apiClient,
    this.initialStatus,
  });

  final ApiClient apiClient;
  final LegalStatus? initialStatus;

  @override
  State<_LegalAcceptanceSheet> createState() => _LegalAcceptanceSheetState();
}

class _LegalAcceptanceSheetState extends State<_LegalAcceptanceSheet> {
  late Future<LegalStatus> _statusFuture;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _adultConfirm = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStatus;
    _statusFuture = initial != null
        ? Future<LegalStatus>.value(initial)
        : widget.apiClient.fetchLegalStatus();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _accept() async {
    if (!(_acceptedTerms && _acceptedPrivacy && _adultConfirm) || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.apiClient.acceptLegalDocuments();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      setState(() => _isSaving = false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non riesco a salvare l\'accettazione adesso.'),
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.72,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Material(
            color: AppTheme.cream,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: FutureBuilder<LegalStatus>(
              future: _statusFuture,
              builder: (context, snapshot) {
                final status = snapshot.data;
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBorder,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const BrandWordmark(height: 54),
                      const SizedBox(height: 18),
                      Text(
                        'Prima di continuare',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.espresso,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Per usare ApprofittOffro in produzione devi accettare Termini e Condizioni, Regolamento Community e confermare di aver letto l\'Informativa privacy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.brown.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _LegalLinkTile(
                        icon: Icons.gavel_rounded,
                        title: 'Termini e Condizioni',
                        subtitle:
                            'Regole d\'uso, responsabilita e limiti del servizio.',
                        onTap: status == null
                            ? null
                            : () => _openLink(status.termsUrl),
                      ),
                      _LegalLinkTile(
                        icon: Icons.groups_2_rounded,
                        title: 'Regolamento Community',
                        subtitle:
                            'Comportamenti vietati, segnalazioni e moderazione.',
                        onTap: status == null
                            ? null
                            : () => _openLink(status.communityRulesUrl),
                      ),
                      _LegalLinkTile(
                        icon: Icons.privacy_tip_rounded,
                        title: 'Informativa privacy',
                        subtitle:
                            'Dati trattati, finalita, notifiche e moderazione.',
                        onTap: status == null
                            ? null
                            : () => _openLink(status.privacyUrl),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _acceptedTerms,
                        onChanged: (value) =>
                            setState(() => _acceptedTerms = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.vividViolet,
                        title: const Text(
                          'Accetto Termini e Condizioni e Regolamento Community',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      CheckboxListTile(
                        value: _acceptedPrivacy,
                        onChanged: (value) =>
                            setState(() => _acceptedPrivacy = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.vividViolet,
                        title: const Text(
                          'Confermo di aver letto l\'Informativa privacy',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      CheckboxListTile(
                        value: _adultConfirm,
                        onChanged: (value) =>
                            setState(() => _adultConfirm = value ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppTheme.vividViolet,
                        title: const Text(
                          'Confermo di avere almeno 18 anni',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _acceptedTerms &&
                                _acceptedPrivacy &&
                                _adultConfirm &&
                                !_isSaving
                            ? _accept
                            : null,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(_isSaving
                            ? 'Salvataggio...'
                            : 'Accetto e continuo'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LegalLinkTile extends StatelessWidget {
  const _LegalLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.vividViolet),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new_rounded),
      ),
    );
  }
}
