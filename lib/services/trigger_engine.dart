import 'package:flutter/material.dart';
import 'package:tapsense/services/bluetooth_service.dart';

/// TriggerEngine listens to wallet BT events and routes them to
/// the Confirm Log screen. Call start() once from HomeScreen.
class TriggerEngine {
  BuildContext? _context;

  void start(BuildContext context) {
    _context = context;
    walletBluetooth.events.listen(_onWalletEvent);
  }

  void _onWalletEvent(WalletEvent event) {
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    // Only act on meaningful events
    if (event.type == WalletEventType.cardRemoved ||
        event.type == WalletEventType.buttonPressed) {
      _openConfirmLog(ctx, event.type == WalletEventType.cardRemoved
          ? 'card_removed' : 'button_press');
    }
  }

  void _openConfirmLog(BuildContext ctx, String triggerType) {
    Navigator.of(ctx).pushNamed('/confirm-log', arguments: {
      'triggerType': triggerType,
      'merchantName': null,
      'merchantUen': null,
      'amount': null,
      'rawQr': null,
    });
  }

  /// Manually fire a mock event (for testing without hardware)
  void mockEvent(BuildContext context, String triggerType) {
    _context = context;
    _openConfirmLog(context, triggerType);
  }
}

final triggerEngine = TriggerEngine();