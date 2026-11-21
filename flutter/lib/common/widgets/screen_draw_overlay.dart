import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

class _DrawStroke {
  final Color color;
  final double width;
  final List<Offset> points;

  _DrawStroke({
    required this.color,
    required this.width,
    required this.points,
  });
}

class ScreenDrawOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const ScreenDrawOverlay({Key? key, required this.onClose}) : super(key: key);

  @override
  State<ScreenDrawOverlay> createState() => _ScreenDrawOverlayState();
}

class _ScreenDrawOverlayState extends State<ScreenDrawOverlay> {
  final List<_DrawStroke> _strokes = [];
  _DrawStroke? _activeStroke;
  Color _selectedColor = const Color(0xFFFF6B1A);
  double _strokeWidth = 3.5;

  static const _palette = [
    Color(0xFFFF6B1A),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFFFACC15),
    Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              setState(() {
                _activeStroke = _DrawStroke(
                  color: _selectedColor,
                  width: _strokeWidth,
                  points: [details.localPosition],
                );
                _strokes.add(_activeStroke!);
              });
            },
            onPanUpdate: (details) {
              if (_activeStroke == null) return;
              setState(() {
                _activeStroke!.points.add(details.localPosition);
              });
            },
            onPanEnd: (_) {
              _activeStroke = null;
            },
            child: CustomPaint(
              painter: _ScreenDrawPainter(_strokes),
            ),
          ),
        ),
        Positioned(
          top: 56,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: const Color(0xE6181B22),
              borderRadius: BorderRadius.circular(24),
              elevation: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() {
                        _strokeWidth = _strokeWidth < 5.0 ? 6.5 : 3.5;
                      }),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Icon(
                          Icons.line_weight,
                          size: 18,
                          color: _strokeWidth > 5.0
                              ? const Color(0xFFFF6B1A)
                              : Colors.white70,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.undo,
                          size: 18, color: Colors.white70),
                      tooltip: translate('Undo'),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: _strokes.isEmpty
                          ? null
                          : () => setState(() => _strokes.removeLast()),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.white70),
                      tooltip: translate('Clear'),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: _strokes.isEmpty
                          ? null
                          : () => setState(() => _strokes.clear()),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B1A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          translate('Exit draw'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreenDrawPainter extends CustomPainter {
  final List<_DrawStroke> strokes;
  _ScreenDrawPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawPoints(
            ui.PointMode.points, s.points, paint..strokeWidth = s.width * 1.2);
      } else {
        final path = Path()..moveTo(s.points[0].dx, s.points[0].dy);
        for (var i = 1; i < s.points.length; i++) {
          path.lineTo(s.points[i].dx, s.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenDrawPainter oldDelegate) => true;
}
