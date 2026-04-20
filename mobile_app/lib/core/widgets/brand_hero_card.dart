import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandHeroCard extends StatelessWidget {
  const BrandHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.footer,
    this.eyebrow,
    this.padding,
    this.centered = false,
  });

  final String title;
  final String subtitle;
  final Widget? footer;
  final String? eyebrow;
  final EdgeInsetsGeometry? padding;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppTheme.cardBorder.withValues(alpha: 0.76),
        ),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.shadow,
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Align(
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.paper.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.cardBorder.withValues(alpha: 0.58),
                  ),
                ),
                child: Text(
                  eyebrow!,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: const TextStyle(
                    color: AppTheme.brown,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.brown.withValues(alpha: 0.84),
                  height: 1.45,
                ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 18),
            footer!,
          ],
        ],
      ),
    );
  }
}
