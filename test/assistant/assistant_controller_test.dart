import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon/assistant/assistant_controller.dart';
import 'package:hackathon/assistant/assistant_models.dart';
import 'package:hackathon/openrouter/openrouter_service.dart';
import 'package:hackathon/services/speech_to_text_service.dart';
import 'package:hackathon/services/text_to_speech_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeData implements AssistantDataSource {
  AssistantAction? proposal;
  List<AssistantImage> images = const [];
  final Completer<AssistantToolResult>? delayed;
  int confirmed = 0;
  int saves = 0;
  FakeData({this.delayed});
  @override
  List<Map<String, Object?>> get tools => [
    {
      'type': 'function',
      'function': {
        'name': 'read',
        'description': 'read',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];
  @override
  Future<Map<String, Object?>> summary() async => {
    'dietary': ['vegan'],
  };
  @override
  Future<AssistantToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  ) async =>
      delayed?.future ??
      AssistantToolResult({'ok': true}, action: proposal, images: images);
  @override
  Future<Map<String, Object?>> confirm(AssistantAction action) async {
    confirmed++;
    return {'success': true};
  }

  @override
  Future<AssistantSettings> loadSettings() async =>
      const AssistantSettings(voiceEnabled: false);
  @override
  Future<void> saveSettings(AssistantSettings settings) async {
    saves++;
  }
}

class FakeSpeech extends SpeechToTextService {
  FakeSpeech({this.available = true, this.initialization});
  bool available;
  final Completer<bool>? initialization;
  int listens = 0;
  @override
  bool get isAvailable => available;
  @override
  Future<bool> initialize({void Function(String)? onError}) async =>
      initialization?.future ?? true;
  @override
  Future<bool> listen({
    required void Function(String, bool) onResult,
    void Function(String)? onStatus,
    String locale = 'en-GB',
  }) async {
    listens++;
    return true;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class DelayedSettingsData extends FakeData {
  final settingsLoaded = Completer<AssistantSettings>();
  @override
  Future<AssistantSettings> loadSettings() => settingsLoaded.future;
}

class FakeTts extends TextToSpeechService {
  int speaks = 0;
  Completer<void>? rateConfiguration;
  Completer<void>? rateStarted;
  Completer<void>? stopGate;
  @override
  Future<void> speak(String text, {String? locale}) async {
    speaks++;
  }

  @override
  Future<void> stop() async {
    await stopGate?.future;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    rateStarted?.complete();
    await rateConfiguration?.future;
  }

  @override
  Future<void> setVoice(String name, String locale) async {}
  @override
  Future<List<Map<String, String>>> getVoices() async => const [];
}

http.Response _json(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200);

void main() {
  test('clearing during settings load cancels the original send', () async {
    final data = DelayedSettingsData();
    var requests = 0;
    final ai = OpenRouterService(
      apiKey: 'test',
      client: MockClient((_) async {
        requests++;
        return _json({'choices': []});
      }),
    );
    final controller = AssistantController(
      data: data,
      ai: ai,
      speech: FakeSpeech(),
      tts: FakeTts(),
    );
    final sending = controller.send('This request is cancelled');
    expect(controller.busy, isTrue);
    await controller.clear();
    data.settingsLoaded.complete(const AssistantSettings(voiceEnabled: false));
    await sending;
    expect(controller.messages, isEmpty);
    expect(requests, 0);
    expect(controller.busy, isFalse);
    controller.dispose();
    ai.close();
  });

  test('tool-only assistant message is executed and then answered', () async {
    var requestNo = 0;
    final ai = OpenRouterService(
      apiKey: 'test',
      client: MockClient((request) async {
        requestNo++;
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        if (requestNo == 1) {
          expect(sent['messages'].last['content'], 'What is my diet?');
          return _json({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {'name': 'read', 'arguments': '{}'},
                    },
                  ],
                },
              },
            ],
          });
        }
        expect(sent['messages'].last['tool_call_id'], 'call_1');
        return _json({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Your diet is vegan.',
              },
            },
          ],
        });
      }),
    );
    final c = AssistantController(data: FakeData(), ai: ai);
    await c.initialize();
    await c.send('What is my diet?');
    expect(c.messages.last.text, 'Your diet is vegan.');
    expect(requestNo, 2);
    c.dispose();
    ai.close();
  });

  test('clear ignores a late tool result', () async {
    final delayed = Completer<AssistantToolResult>();
    final data = FakeData(delayed: delayed);
    final ai = OpenRouterService(
      apiKey: 'test',
      client: MockClient(
        (request) async => _json({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {'name': 'read', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        }),
      ),
    );
    final c = AssistantController(data: data, ai: ai);
    final turn = c.send('load');
    await Future<void>.delayed(Duration.zero);
    await c.clear();
    delayed.complete(const AssistantToolResult({'late': true}));
    await turn;
    expect(c.messages, isEmpty);
    c.dispose();
    ai.close();
  });

  test(
    'write proposal waits for confirmation and resumes with matching call id',
    () async {
      final action = AssistantAction(
        id: 'action-generated',
        toolName: 'write',
        arguments: const {},
        summary: 'Add Vegan?',
      );
      final data = FakeData()..proposal = action;
      var calls = 0;
      String? toolCallId;
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((request) async {
          calls++;
          final history =
              (jsonDecode(request.body) as Map<String, dynamic>)['messages']
                  as List;
          if (calls == 1) {
            return _json({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_write',
                        'type': 'function',
                        'function': {'name': 'write', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            });
          }
          toolCallId = history.last['tool_call_id'] as String?;
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Done.'},
              },
            ],
          });
        }),
      );
      final c = AssistantController(data: data, ai: ai);
      await c.initialize();
      await c.send('Make it vegan');
      expect(c.pendingAction, same(action));
      expect(data.confirmed, 0);
      await c.confirmAction();
      expect(data.confirmed, 1);
      expect(toolCallId, 'call_write');
      expect(c.messages.last.text, 'Done.');
      c.dispose();
      ai.close();
    },
  );

  test(
    'image tool results are attached to the visible assistant reply',
    () async {
      final image = AssistantImage(
        foodId: 'apple',
        name: 'Apple',
        url: 'https://example.test/apple.jpg',
      );
      final data = FakeData()..images = [image];
      var calls = 0;
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return _json({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'read_1',
                        'type': 'function',
                        'function': {'name': 'read', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            });
          }
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Try an apple.'},
              },
            ],
          });
        }),
      );
      final c = AssistantController(data: data, ai: ai);
      await c.initialize();
      await c.send('Suggest fruit');
      expect(c.messages.last.images.single, same(image));
      c.dispose();
      ai.close();
    },
  );

  test(
    'cancelled multi-tool proposal leaves a result for every call ID',
    () async {
      final action = AssistantAction(
        id: 'action-multi',
        toolName: 'write',
        arguments: const {},
        summary: 'Change preference?',
      );
      final data = FakeData()..proposal = action;
      var requests = 0;
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((request) async {
          requests++;
          final history =
              (jsonDecode(request.body) as Map<String, dynamic>)['messages']
                  as List;
          if (requests == 1) {
            return _json({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'write_1',
                        'type': 'function',
                        'function': {'name': 'write', 'arguments': '{}'},
                      },
                      {
                        'id': 'write_2',
                        'type': 'function',
                        'function': {'name': 'write', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            });
          }
          final toolResults = history
              .whereType<Map>()
              .where((item) => item['role'] == 'tool')
              .toList();
          expect(
            toolResults.map((r) => r['tool_call_id']).toSet(),
            containsAll(['write_1', 'write_2']),
          );
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Cancelled.'},
              },
            ],
          });
        }),
      );
      final c = AssistantController(data: data, ai: ai);
      await c.initialize();
      await c.send('Change this');
      await c.cancelAction();
      await c.send('Continue');
      expect(data.confirmed, 0);
      c.dispose();
      ai.close();
    },
  );

  test(
    'successful write stays visible when follow-up model request fails',
    () async {
      final action = AssistantAction(
        id: 'action-ok',
        toolName: 'write',
        arguments: const {},
        summary: 'Add Vegan',
      );
      final data = FakeData()..proposal = action;
      var calls = 0;
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            return _json({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'write_ok',
                        'type': 'function',
                        'function': {'name': 'write', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            });
          }
          return http.Response(
            '{"error":{"code":500,"message":"offline"}}',
            500,
          );
        }),
      );
      final c = AssistantController(data: data, ai: ai);
      await c.initialize();
      await c.send('Make me vegan');
      await c.confirmAction();
      expect(data.confirmed, 1);
      expect(c.pendingAction, isNull);
      expect(
        c.messages.any((m) => m.text.startsWith('Saved: Add Vegan')),
        isTrue,
      );
      expect(c.error, contains('Saved successfully'));
      c.dispose();
      ai.close();
    },
  );

  test('two immediate sends serialize to one user turn', () async {
    var calls = 0;
    final ai = OpenRouterService(
      apiKey: 'test',
      client: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'One answer.'},
            },
          ],
        });
      }),
    );
    final c = AssistantController(data: FakeData(), ai: ai);
    await Future.wait([c.send('first'), c.send('second')]);
    expect(c.messages.where((m) => m.role == 'user').length, 1);
    expect(calls, 1);
    c.dispose();
    ai.close();
  });

  test(
    'suspend during model request keeps reply text but prevents late speech',
    () async {
      final reply = Completer<http.Response>();
      final tts = FakeTts();
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((_) => reply.future),
      );
      final c = AssistantController(
        data: FakeData(),
        ai: ai,
        speech: FakeSpeech(),
        tts: tts,
      );
      final turn = c.send('Hello');
      await Future<void>.delayed(Duration.zero);
      await c.suspend();
      reply.complete(
        _json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Hello there.'},
            },
          ],
        }),
      );
      await turn;
      await Future<void>.delayed(Duration.zero);
      expect(c.messages.last.text, 'Hello there.');
      expect(tts.speaks, 0);
      c.dispose();
      ai.close();
    },
  );

  test(
    'preview has no tools and does not alter the transcript or save settings',
    () async {
      late Map<String, dynamic> requestBody;
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Sample voice.'},
              },
            ],
          });
        }),
      );
      final data = FakeData();
      final c = AssistantController(data: data, ai: ai);
      final sample = await c.previewSettings(
        const AssistantSettings(name: 'Luna'),
      );
      expect(sample, 'Sample voice.');
      expect(requestBody.containsKey('tools'), isFalse);
      expect(c.messages, isEmpty);
      expect(data.saves, 0);
      c.dispose();
      ai.close();
    },
  );

  test(
    'late microphone permission result after suspend never starts listening',
    () async {
      final permission = Completer<bool>();
      final speech = FakeSpeech(available: false, initialization: permission);
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient(
          (_) async => _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'unused'},
              },
            ],
          }),
        ),
      );
      final c = AssistantController(
        data: FakeData(),
        ai: ai,
        speech: speech,
        tts: FakeTts(),
      );
      final starting = c.startListening((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.requestingMicrophonePermission, isTrue);
      await c.suspend();
      permission.complete(true);
      await starting;
      expect(c.requestingMicrophonePermission, isFalse);
      expect(speech.listens, 0);
      expect(c.listening, isFalse);
      c.dispose();
      ai.close();
    },
  );

  test(
    'a new microphone turn cancels automatic announcement audio setup',
    () async {
      final speech = FakeSpeech();
      final tts = FakeTts()
        ..rateConfiguration = Completer<void>()
        ..rateStarted = Completer<void>();
      final c = AssistantController(data: FakeData(), speech: speech, tts: tts);
      final autoSpeech = c.speakAnnouncement(
        'Product summary',
        isCurrent: () => true,
      );
      await tts.rateStarted!.future;
      await c.startListening((_) {});
      tts.rateConfiguration!.complete();
      await autoSpeech;
      expect(speech.listens, 1);
      expect(tts.speaks, 0);
      c.dispose();
    },
  );

  test('cancel turn after history trimming removes only its complete current group', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final ai = OpenRouterService(
      apiKey: 'test',
      client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (calls <= 11) {
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Done $calls.'},
              },
            ],
          });
        }
        if (calls == 12) return pending.future;
        final history = body['messages'] as List;
        expect(
          history.any(
            (m) =>
                m is Map && m['role'] == 'user' && m['content'] == 'unfinished',
          ),
          isFalse,
        );
        return _json({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'After cancel.'},
            },
          ],
        });
      }),
    );
    final c = AssistantController(data: FakeData(), ai: ai);
    for (var i = 0; i < 11; i++) {
      await c.send('turn $i');
    }
    final turn = c.send('unfinished');
    await Future<void>.delayed(Duration.zero);
    await c.cancelTurn();
    pending.complete(
      _json({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'unused'},
          },
        ],
      }),
    );
    await turn;
    await c.send('continue');
    expect(
      c.messages.any((m) => m.role == 'user' && m.text == 'unfinished'),
      isFalse,
    );
    expect(c.messages.last.text, 'After cancel.');
    c.dispose();
    ai.close();
  });

  test(
    'cancel before the new user message is appended preserves prior history',
    () async {
      final tts = FakeTts();
      final ai = OpenRouterService(
        apiKey: 'test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final history = body['messages'] as List;
          if (history.any(
            (item) =>
                item is Map &&
                item['role'] == 'user' &&
                item['content'] == 'next',
          )) {
            expect(
              history.any(
                (item) =>
                    item is Map &&
                    item['role'] == 'user' &&
                    item['content'] == 'previous',
              ),
              isTrue,
            );
          }
          return _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Reply.'},
              },
            ],
          });
        }),
      );
      final c = AssistantController(data: FakeData(), ai: ai, tts: tts);
      await c.send('previous');
      tts.stopGate = Completer<void>();
      final cancelledSend = c.send('cancel before append');
      await Future<void>.delayed(Duration.zero);
      final cancelling = c.cancelTurn();
      tts.stopGate!.complete();
      await Future.wait([cancelledSend, cancelling]);
      expect(
        c.messages.any((m) => m.role == 'user' && m.text == 'previous'),
        isTrue,
      );
      expect(
        c.messages.any(
          (m) => m.role == 'user' && m.text == 'cancel before append',
        ),
        isFalse,
      );
      tts.stopGate = null;
      await c.send('next');
      c.dispose();
      ai.close();
    },
  );
}
