import 'package:flutter/material.dart';

import '../../models/app_guide.dart';
import '../network/api_client.dart';
import '../theme/app_theme.dart';
import 'brand_wordmark.dart';

Future<bool> showAppGuideSheet(
  BuildContext context, {
  required ApiClient apiClient,
  bool startupMode = false,
  AppGuideContent? initialContent,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppGuideSheet(
      apiClient: apiClient,
      startupMode: startupMode,
      initialContent: initialContent,
    ),
  );
  return result ?? false;
}

class _AppGuideSheet extends StatefulWidget {
  const _AppGuideSheet({
    required this.apiClient,
    required this.startupMode,
    this.initialContent,
  });

  final ApiClient apiClient;
  final bool startupMode;
  final AppGuideContent? initialContent;

  @override
  State<_AppGuideSheet> createState() => _AppGuideSheetState();
}

class _AppGuideSheetState extends State<_AppGuideSheet> {
  bool _hideAtStartup = false;
  late final Future<AppGuideContent> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initialContent != null
        ? Future<AppGuideContent>.value(widget.initialContent)
        : _loadGuide();
  }

  Future<AppGuideContent> _loadGuide() async {
    try {
      return await widget.apiClient.fetchAppGuide();
    } catch (_) {
      return AppGuideContent.fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: AppTheme.cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: FutureBuilder<AppGuideContent>(
            future: _future,
            initialData: widget.initialContent,
            builder: (context, snapshot) {
              final content = snapshot.data ?? AppGuideContent.fallback;
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.brown.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const BrandWordmark(height: 54),
                    const SizedBox(height: 18),
                    Text(
                      widget.startupMode ? content.title : 'Guida rapida',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppTheme.espresso,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      content.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.brown.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GuideHighlightCard(highlights: content.highlights),
                    const SizedBox(height: 14),
                    _PremiumGuideCard(content: content),
                    const SizedBox(height: 14),
                    ...content.sections.map(
                      (section) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _GuideSectionCard(section: section),
                      ),
                    ),
                    if (widget.startupMode) ...[
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: _hideAtStartup,
                        onChanged: (value) {
                          setState(() => _hideAtStartup = value ?? false);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.vividViolet,
                        title: const Text(
                          'Non mostrarla piu all\'avvio',
                          style: TextStyle(
                            color: AppTheme.espresso,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          'Potrai riaprirla quando vuoi da Io > Strumenti profilo > Guida all\'app.',
                          style: TextStyle(
                            color: AppTheme.brown.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_hideAtStartup),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(widget.startupMode ? 'Ho capito' : 'Chiudi'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GuideHighlightCard extends StatelessWidget {
  const _GuideHighlightCard({required this.highlights});

  final List<AppGuideHighlight> highlights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Da ricordare',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...highlights.map(
            (item) => _GuidePill(
              icon: _guideIcon(item.icon),
              text: item.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidePill extends StatelessWidget {
  const _GuidePill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumGuideCard extends StatelessWidget {
  const _PremiumGuideCard({required this.content});

  final AppGuideContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A145F),
            Color(0xFF4C22B8),
            Color(0xFF123EBA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.30),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 22,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Funzioni Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content.premiumIntro,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 14),
          ...content.premiumFeatures.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PremiumFeatureTile(row: row),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Text(
              content.premiumNote,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  const _PremiumFeatureTile({required this.row});

  final AppGuidePremiumFeature row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.feature,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD34D),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  row.status,
                  style: const TextStyle(
                    color: Color(0xFF251057),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            row.details,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              height: 1.28,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSectionCard extends StatelessWidget {
  const _GuideSectionCard({required this.section});

  final AppGuideSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.vividViolet.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              _guideIcon(section.icon),
              color: AppTheme.vividViolet,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: AppTheme.espresso,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...section.bullets.map(
                  (bullet) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _GuideBullet(text: bullet),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideBullet extends StatelessWidget {
  const _GuideBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: AppTheme.sage,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.brown.withValues(alpha: 0.80),
              fontWeight: FontWeight.w600,
              height: 1.28,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _guideIcon(String key) {
  switch (key) {
    case 'add_location':
      return Icons.add_location_alt_rounded;
    case 'admin_panel':
      return Icons.admin_panel_settings_rounded;
    case 'bug_report':
      return Icons.bug_report_rounded;
    case 'chat':
      return Icons.chat_bubble_rounded;
    case 'groups':
      return Icons.groups_2_rounded;
    case 'local_fire':
      return Icons.local_fire_department_rounded;
    case 'notifications':
      return Icons.notifications_active_rounded;
    case 'person':
      return Icons.person_rounded;
    case 'settings':
      return Icons.settings_rounded;
    case 'verified_user':
      return Icons.verified_user_rounded;
    case 'workspace_premium':
      return Icons.workspace_premium_rounded;
    default:
      return Icons.info_outline_rounded;
  }
}
