import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';

class NativeTouchRegion extends StatefulWidget {
  final Widget child;
  final FFI ffi;

  const NativeTouchRegion({
    Key? key,
    required this.child,
    required this.ffi,
  }) : super(key: key);

  @override
  State<NativeTouchRegion> createState() => _NativeTouchRegionState();
}

class _TrackedPointer {
  Offset localPos;
  Offset? lastRemotePos;
  bool sentDown = false;
  bool canceled = false;

  _TrackedPointer({required this.localPos});
}

class _NativeTouchRegionState extends State<NativeTouchRegion> {
  final Map<int, _TrackedPointer> _pointers = {};
  bool _pinchMode = false;
  double? _lastPinchDistance;
  Offset? _lastPinchFocal;

  FFI get ffi => widget.ffi;

  bool _isTouchKind(PointerDeviceKind kind) =>
      kTouchBasedDeviceKinds.contains(kind);

  Offset? _mapToRemote(Offset localPos, Size widgetSize) {
    final turns = ffi.canvasModel.rotationTurns;
    Offset unrotated = localPos;
    if (turns != 0 && widgetSize.width > 0 && widgetSize.height > 0) {
      final w = widgetSize.width;
      final h = widgetSize.height;
      switch (turns % 4) {
        case 1: // 90 deg CW: (x, y) -> (y, w - x)
          unrotated = Offset(localPos.dy, w - localPos.dx);
          break;
        case 2: // 180 deg: (x, y) -> (w - x, h - y)
          unrotated = Offset(w - localPos.dx, h - localPos.dy);
          break;
        case 3: // 270 deg CW: (x, y) -> (h - y, x)
          unrotated = Offset(h - localPos.dy, localPos.dx);
          break;
      }
    }
    return ffi.cursorModel.getRemotePosInRect(unrotated);
  }

  Map<String, dynamic> _contactPayload(
    int id,
    String phase,
    Offset remotePos, {
    double radiusMajor = 8,
    double radiusMinor = 8,
    double pressure = 0.5,
  }) {
    final w = (radiusMajor * 2).round().clamp(8, 128);
    final h = (radiusMinor * 2).round().clamp(8, 128);
    final p = (pressure.clamp(0.0, 1.0) * 1024).round().clamp(1, 1024);
    return {
      'id': id & 0x7fffffff,
      'phase': phase,
      'x': remotePos.dx.round(),
      'y': remotePos.dy.round(),
      'w': w,
      'h': h,
      'p': p,
    };
  }

  void _cancelAllRemoteTouches() {
    final batch = <Map<String, dynamic>>[];
    for (final entry in _pointers.entries) {
      final ptr = entry.value;
      if (ptr.sentDown && !ptr.canceled && ptr.lastRemotePos != null) {
        batch.add(_contactPayload(entry.key, 'cancel', ptr.lastRemotePos!));
        ptr.canceled = true;
      }
    }
    if (batch.isNotEmpty) {
      ffi.inputModel.sendNativeTouchContacts(batch);
    }
  }

  void _updateTwoFingerPinch() {
    if (_pointers.length < 2) return;
    final pts = _pointers.values.take(2).map((e) => e.localPos).toList();
    final p0 = pts[0];
    final p1 = pts[1];
    final focal = Offset((p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
    final dist = (p0 - p1).distance;

    if (_lastPinchFocal != null && _lastPinchDistance != null && _lastPinchDistance! > 1.0) {
      final scaleFactor = dist / _lastPinchDistance!;
      if ((scaleFactor - 1.0).abs() > 0.001) {
        ffi.canvasModel.updateScale(scaleFactor, focal);
      }
      final delta = focal - _lastPinchFocal!;
      if (delta != Offset.zero) {
        ffi.canvasModel.panX(delta.dx);
        ffi.canvasModel.panY(delta.dy);
      }
    }
    _lastPinchFocal = focal;
    _lastPinchDistance = max(dist, 1.0);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_isTouchKind(event.kind)) return;
    if (ffi.cursorModel.shouldBlock(event.localPosition.dx, event.localPosition.dy)) {
      return;
    }

    final passMultiTouch = ffi.canvasModel.locked;
    final tracked = _TrackedPointer(localPos: event.localPosition);
    _pointers[event.pointer] = tracked;

    if (!passMultiTouch && _pointers.length >= 2) {
      if (!_pinchMode) {
        _pinchMode = true;
        _cancelAllRemoteTouches();
      }
      _lastPinchFocal = null;
      _lastPinchDistance = null;
      _updateTwoFingerPinch();
      return;
    }

    if (_pinchMode) return;
    if (_pointers.length > 10) return;

    final size = context.size ?? Size.zero;
    final remotePos = _mapToRemote(event.localPosition, size);
    if (remotePos == null) return;
    tracked.lastRemotePos = remotePos;
    tracked.sentDown = true;
    ffi.inputModel.sendNativeTouchContacts([
      _contactPayload(
        event.pointer,
        'down',
        remotePos,
        radiusMajor: event.radiusMajor,
        radiusMinor: event.radiusMinor,
        pressure: event.pressureMax > 0 ? event.pressure / event.pressureMax : 0.5,
      ),
    ]);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isTouchKind(event.kind)) return;
    final tracked = _pointers[event.pointer];
    if (tracked == null) return;
    tracked.localPos = event.localPosition;

    if (_pinchMode) {
      _updateTwoFingerPinch();
      return;
    }

    if (tracked.canceled) return;
    final size = context.size ?? Size.zero;
    final remotePos = _mapToRemote(event.localPosition, size);
    if (remotePos == null) return;
    if (!tracked.sentDown) {
      tracked.sentDown = true;
      tracked.lastRemotePos = remotePos;
      ffi.inputModel.sendNativeTouchContacts([
        _contactPayload(event.pointer, 'down', remotePos),
      ]);
      return;
    }
    tracked.lastRemotePos = remotePos;
    ffi.inputModel.sendNativeTouchContacts([
      _contactPayload(
        event.pointer,
        'move',
        remotePos,
        radiusMajor: event.radiusMajor,
        radiusMinor: event.radiusMinor,
        pressure: event.pressureMax > 0 ? event.pressure / event.pressureMax : 0.5,
      ),
    ]);
  }

  void _onPointerUpOrCancel(PointerEvent event, {required bool isCancel}) {
    if (!_isTouchKind(event.kind)) return;
    final tracked = _pointers.remove(event.pointer);
    if (tracked != null && !_pinchMode && tracked.sentDown && !tracked.canceled) {
      final size = context.size ?? Size.zero;
      final remotePos = _mapToRemote(event.localPosition, size) ?? tracked.lastRemotePos;
      if (remotePos != null) {
        ffi.inputModel.sendNativeTouchContacts([
          _contactPayload(
            event.pointer,
            isCancel ? 'cancel' : 'up',
            remotePos,
          ),
        ]);
      }
    }
    if (_pointers.isEmpty) {
      _pinchMode = false;
      _lastPinchDistance = null;
      _lastPinchFocal = null;
    } else if (_pinchMode && _pointers.length < 2) {
      _lastPinchDistance = null;
      _lastPinchFocal = null;
    }
  }

  @override
  void dispose() {
    _cancelAllRemoteTouches();
    _pointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (e) => _onPointerUpOrCancel(e, isCancel: false),
      onPointerCancel: (e) => _onPointerUpOrCancel(e, isCancel: true),
      child: widget.child,
    );
  }
}
