import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand_wordmark.dart';

class BrandHeroCard extends StatelessWidget {
  const BrandHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.footer,
    this.eyebrow,
    this.padding,
  });

  final String title;
  final String subtitle;
  final Widget? footer;
  final String? eyebrow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              _BrandIcon(),
              SizedBox(width: 12),
              Expanded(child: BrandWordmark(height: 28)),
            ],
          ),
          if (eyebrow != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                eyebrow!,
                style: const TextStyle(
                  color: AppTheme.brown,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 28,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.brown.withOpacity(0.84),
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

class _BrandIcon extends StatelessWidget {
  const _BrandIcon();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
