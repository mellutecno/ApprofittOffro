import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PremiumBadge extends StatelessWidget {
  const PremiumBadge({
    super.key,
    this.compact = false,
    this.centered = false,
  });

  final bool compact;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2A145F),
            AppTheme.vividViolet,
            Color(0xFF123EBA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFD34D).withValues(alpha: 0.82),
          width: compact ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.vividViolet.withValues(alpha: 0.26),
            blurRadius: compact ? 10 : 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 12,
          vertical: compact ? 5 : 7,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              color: const Color(0xFFFFD34D),
              size: compact ? 15 : 18,
            ),
            SizedBox(width: compact ? 5 : 7),
            Text(
              'Premium',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 12 : 13.5,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );

    if (!centered) {
      return badge;
    }
    return Center(child: badge);
  }
}
