import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/widgets/native_touch_region.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestCanvasModel extends Fake implements CanvasModel {
  @override
  int get rotationTurns => 0;

  @override
  bool get locked => false;

  double lastScaleFactor = 1.0;
  double panDx = 0.0;
  double panDy = 0.0;

  @override
  void updateScale(double v, [Offset? focal]) {
    lastScaleFactor *= v;
  }

  @override
  void panX(double d) {
    panDx += d;
  }

  @override
  void panY(double d) {
    panDy += d;
  }
}

class _TestCursorModel extends Fake implements CursorModel {
  @override
  bool shouldBlock(double x, double y) => false;

  @override
  Offset? getRemotePosInRect(Offset offset) =>
      Offset(offset.dx * 2, offset.dy * 2);
}

class _TestInputModel extends Fake implements InputModel {
  final List<List<Map<String, dynamic>>> sentBatches = [];

  @override
  Future<void> sendNativeTouchContacts(
      List<Map<String, dynamic>> contacts) async {
    sentBatches.add(contacts);
  }
}

class _TestFFI extends Fake implements FFI {
  _TestFFI(this.canvasModel, this.cursorModel, this.inputModel);

  @override
  final _TestCanvasModel canvasModel;

  @override
  final _TestCursorModel cursorModel;

  @override
  final _TestInputModel inputModel;
}

void main() {
  testWidgets(
      'NativeTouchRegion inside Positioned.fill covers full viewport and dispatches touch contacts',
      (tester) async {
    final canvas = _TestCanvasModel();
    final cursor = _TestCursorModel();
    final input = _TestInputModel();
    final ffi = _TestFFI(canvas, cursor, input);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: Stack(
              children: [
                Positioned.fill(
                  child: NativeTouchRegion(
                    ffi: ffi,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: null),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(NativeTouchRegion));
    expect(box.size, const Size(800, 400));

    final g1 = await tester.createGesture(kind: PointerDeviceKind.touch);
    await g1.down(const Offset(250, 150));
    await tester.pump();
    await g1.up();
    await tester.pump();

    expect(input.sentBatches.length, 2);
    expect(input.sentBatches[0][0]['phase'], 'down');
    expect(input.sentBatches[0][0]['x'], 500);
    expect(input.sentBatches[0][0]['y'], 300);
    expect(input.sentBatches[1][0]['phase'], 'up');
  });

  testWidgets(
      'Two fingers cancel finger 1 and trigger local pinch scale when zoom unlocked',
      (tester) async {
    final canvas = _TestCanvasModel();
    final cursor = _TestCursorModel();
    final input = _TestInputModel();
    final ffi = _TestFFI(canvas, cursor, input);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: NativeTouchRegion(
              ffi: ffi,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final g1 = await tester.createGesture(kind: PointerDeviceKind.touch);
    final g2 = await tester.createGesture(kind: PointerDeviceKind.touch);
    await g1.down(const Offset(300, 200));
    await g2.down(const Offset(400, 200));
    await g2.moveTo(const Offset(500, 200));
    await tester.pump();

    expect(input.sentBatches.any((b) => b.any((c) => c['phase'] == 'cancel')),
        isTrue);
    expect(canvas.lastScaleFactor, greaterThan(1.0));
  });
}
