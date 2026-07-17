import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/ble/ble_constants.dart';
import '../../shared/ble/ble_service.dart';
import '../../state/ble_providers.dart';
import 'dot_matrix_painter.dart';

/// Full-screen remote control surface. The user can swipe / tap anywhere on
/// the dark gesture area to drive the connected PDF reader via BLE
/// [input_event] commands. The bottom bar hosts the only way out: an "exit"
/// button that pops back to [RemotePage]. The system back button is
/// intercepted and translated into an InputEvent::Back so it never leaves the
/// page — only the explicit exit button (or BLE disconnect / command failure)
/// actually leaves remote mode.
class RemoteModePage extends ConsumerStatefulWidget {
  const RemoteModePage({super.key});

  @override
  ConsumerState<RemoteModePage> createState() => _RemoteModePageState();
}

class _RemoteModePageState extends ConsumerState<RemoteModePage> {
  // Gesture state (single-pointer; multi-touch is ignored beyond the first).
  Offset? _downPos;
  Offset? _latestPos;
  DateTime? _downAt;
  bool _resolved = false;
  Timer? _longPressTimer;

  // Pending BLE round-trip: while true, the loading overlay is shown and new
  // gestures are dropped.
  bool _busy = false;

  // Lifecycle / navigation guards.
  bool _disposed = false;
  bool _exiting = false;

  // Thresholds (kept as static consts for easy tuning).
  static const double _swipeThreshold = 24.0;
  static const Duration _longPressDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    // Immersive sticky so the gesture area gets the full screen. Restored on
    // dispose — wrapping in try/catch since some Android OEM ROMs throw.
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on Object {
      // best effort
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _longPressTimer?.cancel();
    try {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    } on Object {
      // best effort
    }
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_busy) return;
    _downPos = event.position;
    _latestPos = event.position;
    _downAt = DateTime.now();
    _resolved = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDelay, _onLongPressFire);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_busy || _resolved || _downPos == null) return;
    _latestPos = event.position;
    final Offset delta = event.position - _downPos!;
    if (delta.distance >= _swipeThreshold) {
      _longPressTimer?.cancel();
      _resolveSwipe(delta);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _longPressTimer?.cancel();
    if (_busy || _resolved || _downPos == null || _downAt == null) {
      _resetGesture();
      return;
    }
    final Duration dt = DateTime.now().difference(_downAt!);
    final double moved = (event.position - _downPos!).distance;
    if (dt < _longPressDelay && moved < _swipeThreshold) {
      _emit(BleConstants.inputEventEnter);
    }
    _resetGesture();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _resetGesture();
  }

  void _onLongPressFire() {
    if (_busy || _resolved || _downPos == null || _latestPos == null) return;
    final double moved = (_latestPos! - _downPos!).distance;
    if (moved < _swipeThreshold) {
      _resolved = true;
      _emit(BleConstants.inputEventBack);
    }
  }

  void _resolveSwipe(Offset delta) {
    _resolved = true;
    final double dx = delta.dx;
    final double dy = delta.dy;
    if (dx.abs() >= dy.abs()) {
      // Horizontal: left → next, right → prev.
      _emit(dx < 0
          ? BleConstants.inputEventDownRight
          : BleConstants.inputEventUpLeft);
    } else {
      // Vertical: up → next, down → prev.
      _emit(dy < 0
          ? BleConstants.inputEventDownRight
          : BleConstants.inputEventUpLeft);
    }
  }

  void _resetGesture() {
    _downPos = null;
    _latestPos = null;
    _downAt = null;
    _resolved = false;
  }

  Future<void> _emit(String event) async {
    if (_busy) return;
    final conn = ref.read(activeConnectionProvider).valueOrNull?.connection;
    if (conn == null) {
      _exit(reason: '设备连接已断开');
      return;
    }
    // _busy gates new gestures silently — no setState, no visual cue. The
    // spec requires loading to be imperceptible; we just drop inputs that
    // arrive while a round-trip is in flight.
    _busy = true;
    try {
      await ref.read(bleServiceProvider).sendInputEvent(
            connection: conn,
            event: event,
          );
      if (_disposed || !mounted) return;
      _busy = false;
      _resetGesture();
    } on RemoteInputException catch (e) {
      if (_disposed || !mounted) return;
      _busy = false;
      _exit(reason: e.message);
    } on Object catch (e) {
      if (_disposed || !mounted) return;
      _busy = false;
      _exit(reason: '遥控指令失败：$e');
    }
  }

  void _exit({required String reason}) {
    if (_disposed || _exiting || !mounted) return;
    _exiting = true;
    _longPressTimer?.cancel();
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Go (not pop) so the destination is re-resolved to /remote regardless of
    // how we got here. The PopScope's canPop=false does not block go_router's
    // imperative navigation APIs.
    context.go('/remote');
    messenger?.showSnackBar(
      SnackBar(
        content: Text(reason),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onSystemBack() {
    // Translate the system back button into a Back input event. Stay on the
    // page; the only way out is the explicit exit button or an error.
    if (_busy || _exiting) return;
    _emit(BleConstants.inputEventBack);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ActiveConnection>>(activeConnectionProvider,
        (AsyncValue<ActiveConnection>? prev,
            AsyncValue<ActiveConnection> next) {
      if (_exiting || _disposed) return;
      final ActiveConnection? c = next.valueOrNull;
      final bool lost =
          c?.connection == null || c?.isOffline == true;
      if (lost) {
        _exit(reason: '设备连接已断开');
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _onSystemBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            // Layer 1: dot matrix pattern fills the whole screen.
            Positioned.fill(
              child: CustomPaint(
                painter: const DotMatrixPainter(
                  color: Color(0xCCFFFFFF),
                ),
              ),
            ),
            // Layer 2: gesture area (everything except the bottom button strip).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 96,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
              ),
            ),
            // Layer 3: subtle static hint at top.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: Text(
                      '滑动翻页 · 点按确认 · 长按返回',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Layer 4: exit button anchored to the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Center(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: () => _exit(reason: '已退出遥控模式'),
                      child: const Text('退出遥控模式'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
