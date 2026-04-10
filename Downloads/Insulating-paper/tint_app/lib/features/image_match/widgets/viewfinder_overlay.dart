import 'package:flutter/material.dart';

/// 相機取景框 overlay：四角定位標記 + 半透明遮罩
class ViewfinderOverlay extends StatelessWidget {
  const ViewfinderOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ViewfinderPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameW = size.width * 0.82;
    final frameH = frameW * (1 / 2); // 2:1 寬高比
    final frameLeft = (size.width - frameW) / 2;
    final frameTop = (size.height - frameH) / 2 - size.height * 0.05;
    final frameRect = Rect.fromLTWH(frameLeft, frameTop, frameW, frameH);

    // 半透明遮罩（框外區域）
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frameRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // 框線
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(frameRect, borderPaint);

    // 四角定位標記
    const cornerLen = 24.0;
    const cornerWidth = 3.5;
    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawCorner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(
        Offset(cx, cy + dy * cornerLen),
        Offset(cx, cy),
        cornerPaint,
      );
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + dx * cornerLen, cy),
        cornerPaint,
      );
    }

    drawCorner(frameLeft, frameTop, 1, 1);
    drawCorner(frameLeft + frameW, frameTop, -1, 1);
    drawCorner(frameLeft, frameTop + frameH, 1, -1);
    drawCorner(frameLeft + frameW, frameTop + frameH, -1, -1);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) => false;
}
