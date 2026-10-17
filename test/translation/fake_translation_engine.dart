import 'dart:async';

import 'package:loud_caption/translation/translation_engine.dart';

/// A controllable [TranslationEngine] double for tests, in the same spirit
/// as `FakeSpeechEngine`: nothing resolves until the test tells it to, and
/// every call is recorded for inspection.
class FakeTranslationEngine implements TranslationEngine {
  bool _loaded = false;
  final List<FakeTranslationCall> calls = [];

  @override
  bool get isLoaded => _loaded;

  /// Lets a test control whether [ensureLoaded] appears to have already
  /// finished, without going through a real load.
  set isLoaded(bool value) => _loaded = value;

  @override
  Future<void> ensureLoaded() async => _loaded = true;

  @override
  TranslationRequest translate({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) {
    final request = FakeTranslationRequest();
    calls.add(
      FakeTranslationCall(
        text: text,
        sourceLang: sourceLang,
        targetLang: targetLang,
        request: request,
      ),
    );
    return request;
  }

  @override
  Future<void> dispose() async {}
}

class FakeTranslationCall {
  FakeTranslationCall({
    required this.text,
    required this.sourceLang,
    required this.targetLang,
    required this.request,
  });

  final String text;
  final String sourceLang;
  final String targetLang;
  final FakeTranslationRequest request;
}

/// A single in-flight fake translation: the test drives it with [emit] /
/// [complete] / [fail], and can observe whether the caller [cancel]ed it.
class FakeTranslationRequest implements TranslationRequest {
  final _controller = StreamController<String>();
  bool cancelled = false;

  @override
  Stream<String> get output => _controller.stream;

  @override
  void cancel() {
    cancelled = true;
    unawaited(_controller.close());
  }

  void emit(String token) => _controller.add(token);

  void complete() => _controller.close();

  void fail(Object error) {
    _controller.addError(error);
    unawaited(_controller.close());
  }
}
