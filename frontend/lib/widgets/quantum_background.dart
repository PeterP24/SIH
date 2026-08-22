import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subtle animated "entanglement network": drifting nodes joined by faint
/// links, used as the background of every screen.
class QuantumBackground extends StatefulWidget {
  const QuantumBackground({super.key, required this.child, this.nodeCount = 28});

  final Widget child;
  final int nodeCount;

  @override
  State<QuantumBackground> createState() => _QuantumBackgroundState();
}

class _QuantumBackgroundState extends State<QuantumBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  late final List<_Node> _nodes = List.generate(widget.nodeCount, (i) {
    final random = Random(i * 7919);
    return _Node(
      origin: Offset(random.nextDouble(), random.nextDouble()),
      radius: 0.02 + random.nextDouble() * 0.05,
      speed: 0.4 + random.nextDouble(),
      phase: random.nextDouble() * 2 * pi,
      size: 1.2 + random.nextDouble() * 2.2,
    );
  });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _NetworkPainter(_nodes, _controller.value),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.72),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Node {
  _Node({
    required this.origin,
    required this.radius,
    required this.speed,
    required this.phase,
    required this.size,
  });

  final Offset origin;
  final double radius;
  final double speed;
  final double phase;
  final double size;

  Offset positionAt(double t, Size canvas) {
    final angle = phase + t * 2 * pi * speed;
    return Offset(
      (origin.dx + radius * cos(angle)) * canvas.width,
      (origin.dy + radius * sin(angle)) * canvas.height,
    );
  }
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter(this.nodes, this.t);

  final List<_Node> nodes;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final points = nodes.map((n) => n.positionAt(t, size)).toList();
    final linkPaint = Paint()..strokeWidth = 0.7;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final distance = (points[i] - points[j]).distance;
        if (distance < size.shortestSide * 0.22) {
          linkPaint.color = AppTheme.accentCyan
              .withValues(alpha: 0.16 * (1 - distance / (size.shortestSide * 0.22)));
          canvas.drawLine(points[i], points[j], linkPaint);
        }
      }
    }
    final dotPaint = Paint()..color = AppTheme.accentCyan.withValues(alpha: 0.5);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], nodes[i].size, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) => oldDelegate.t != t;
}
