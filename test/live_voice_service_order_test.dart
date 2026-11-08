import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/services/live_voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('sentinel/live_voice');
  const events = MethodChannel('sentinel/live_voice/events');
  test('stop during voice setup prevents a late speak dispatch', () async {
    final setting = Completer<void>();
    final entered = Completer<void>();
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call.method);
      if (call.method == 'setConversationMode') {
        entered.complete();
        await setting.future;
      }
      return null;
    });
    final voice = LiveVoiceService();
    final speaking = voice.speak('This must not play after stop.');
    await entered.future;
    await voice.stop();
    setting.complete();
    await speaking;
    expect(calls, isNot(contains('speak')));
    voice.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });
}
