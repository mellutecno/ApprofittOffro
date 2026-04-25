import 'package:flutter/material.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.height = 36,
    this.alignment = Alignment.center,
  });

  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Image.asset(
        'assets/branding/wordmark.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
