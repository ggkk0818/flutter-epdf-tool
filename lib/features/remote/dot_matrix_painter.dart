import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Static white dot-matrix background used by the remote-mode gesture area.
///
/// Dots are laid out on a square grid of [spacing] pixels. The dot at the
/// center of the screen has [maxRadius]; dots near the edges fade down to
/// [minRadius] over [edgeFadeRatio] of the smaller screen dimension. The
/// fade is symmetric on both axes so the corners get the smallest dots and
/// the center stays crisp.
class DotMatrixPainter extends CustomPainter {
  const DotMatrixPainter({
    this.spacing = 28,
    this.maxRadius = 2.4,
    this.minRadius = 0.4,
    this.edgeFadeRatio = 0.42,
    this.color = const Color(0xFFFFFFFF),
  });

  final double spacing;
  final double maxRadius;
  final double minRadius;
  final double edgeFadeRatio;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;

    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    // Distance from center past which dots reach their minimum radius.
    final double fadeLimit =
        math.min(size.width, size.height) * 0.5 * edgeFadeRatio.clamp(0.05, 0.9);
    final double fadeSpan =
        math.min(size.width, size.height) * 0.5 - fadeLimit;

    // Walk the grid from the top-left, snapping the first row/column to a
    // half-cell margin so the pattern is symmetric around the center.
    final int cols = (size.width / spacing).floor();
    final int rows = (size.height / spacing).floor();
    final double startX = (size.width - cols * spacing) / 2 + spacing / 2;
    final double startY = (size.height - rows * spacing) / 2 + spacing / 2;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final double dx = startX + c * spacing - centerX;
        final double dy = startY + r * spacing - centerY;
        final double dist = math.sqrt(dx * dx + dy * dy);
        final double t = ((dist - fadeLimit) / fadeSpan).clamp(0.0, 1.0);
        // Ease the fade so the transition is gentler than linear.
        final double eased = t * t;
        final double radius = maxRadius - (maxRadius - minRadius) * eased;
        if (radius <= 0) continue;
        canvas.drawCircle(Offset(centerX + dx, centerY + dy), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotMatrixPainter oldDelegate) =>
      oldDelegate.spacing != spacing ||
      oldDelegate.maxRadius != maxRadius ||
      oldDelegate.minRadius != minRadius ||
      oldDelegate.edgeFadeRatio != edgeFadeRatio ||
      oldDelegate.color != color;
}
