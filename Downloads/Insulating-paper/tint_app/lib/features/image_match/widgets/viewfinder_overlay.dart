import 'package:flutter/material.dart';

const double _kHandleSize = 32.0; // 觸控熱區
const double _kHandleVis = 14.0;  // 可見圓點大小
const double _kMinFrame = 80.0;   // 最小框尺寸

/// 可調整大小的取景框。
/// 四個角落有拖曳把手，拖動後透過 [frameNotifier] 回報目前框的座標（螢幕 dp）。
class ResizableViewfinderOverlay extends StatefulWidget {
  final ValueNotifier<Rect?> frameNotifier;
  const ResizableViewfinderOverlay({super.key, required this.frameNotifier});

  @override
  State<ResizableViewfinderOverlay> createState() =>
      _ResizableViewfinderOverlayState();
}

class _ResizableViewfinderOverlayState
    extends State<ResizableViewfinderOverlay> {
  Rect? _frame;

  Rect _defaultFrame(Size size) {
    final w = size.width * 0.82;
    final h = w * 0.5; // 預設 2:1 寬高比
    final l = (size.width - w) / 2;
    final t = (size.height - h) / 2 - size.height * 0.05;
    return Rect.fromLTWH(l, t, w, h);
  }

  void _updateFrame(Rect r, Size size) {
    final l = r.left.clamp(0.0, size.width - _kMinFrame);
    final t = r.top.clamp(0.0, size.height - _kMinFrame);
    final ri = r.right.clamp(l + _kMinFrame, size.width);
    final bo = r.bottom.clamp(t + _kMinFrame, size.height);
    setState(() {
      _frame = Rect.fromLTRB(l, t, ri, bo);
      widget.frameNotifier.value = _frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (_frame == null) {
        _frame = _defaultFrame(size);
        widget.frameNotifier.value = _frame;
      }
      final f = _frame!;

      return Stack(children: [
        // 遮罩 + 框線 + 角標
        CustomPaint(
          painter: _ViewfinderPainter(frame: f),
          child: const SizedBox.expand(),
        ),

        // 四角拖曳把手
        _handle(f.topLeft, (d) {
          _updateFrame(
              Rect.fromLTRB(f.left + d.dx, f.top + d.dy, f.right, f.bottom),
              size);
        }),
        _handle(f.topRight, (d) {
          _updateFrame(
              Rect.fromLTRB(f.left, f.top + d.dy, f.right + d.dx, f.bottom),
              size);
        }),
        _handle(f.bottomLeft, (d) {
          _updateFrame(
              Rect.fromLTRB(f.left + d.dx, f.top, f.right, f.bottom + d.dy),
              size);
        }),
        _handle(f.bottomRight, (d) {
          _updateFrame(
              Rect.fromLTRB(f.left, f.top, f.right + d.dx, f.bottom + d.dy),
              size);
        }),
      ]);
    });
  }

  Widget _handle(Offset corner, void Function(Offset) onDrag) {
    return Positioned(
      left: corner.dx - _kHandleSize / 2,
      top: corner.dy - _kHandleSize / 2,
      width: _kHandleSize,
      height: _kHandleSize,
      child: GestureDetector(
        onPanUpdate: (d) => onDrag(d.delta),
        child: Center(
          child: Container(
            width: _kHandleVis,
            height: _kHandleVis,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final Rect frame;
  const _ViewfinderPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    // 框外半透明遮罩
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // 框線
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(frame, borderPaint);

    // 四角 L 型標記
    const cornerLen = 24.0;
    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawCorner(double cx, double cy, double dx, double dy) {
      canvas.drawLine(
          Offset(cx, cy + dy * cornerLen), Offset(cx, cy), cornerPaint);
      canvas.drawLine(
          Offset(cx, cy), Offset(cx + dx * cornerLen, cy), cornerPaint);
    }

    drawCorner(frame.left, frame.top, 1, 1);
    drawCorner(frame.right, frame.top, -1, 1);
    drawCorner(frame.left, frame.bottom, 1, -1);
    drawCorner(frame.right, frame.bottom, -1, -1);
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.frame != frame;
}
