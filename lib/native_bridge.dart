import 'package:flutter/services.dart';

class DesktopBridge {
  static const _channel = MethodChannel('dev.anyusagepin/desktop');
  Future<void> Function(String event)? onEvent;

  DesktopBridge() {
    _channel.setMethodCallHandler((call) async {
      await onEvent?.call(call.method);
    });
  }

  Future<void> ready({required bool open}) =>
      _channel.invokeMethod<void>('desktop.ready', {'open': open});

  Future<void> updatePins(List<Map<String, Object?>> pins) =>
      _channel.invokeMethod<void>('menu.update', {'pins': pins});

  Future<void> updatePanel(Map<String, Object?> panel) =>
      _channel.invokeMethod<void>('panel.update', panel);
  Future<void> quit() => _channel.invokeMethod<void>('app.quit');
}
