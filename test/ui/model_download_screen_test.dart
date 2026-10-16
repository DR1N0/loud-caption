import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/speech/sense_voice_model_download.dart';
import 'package:loud_caption/ui/model_download_screen.dart';

void main() {
  testWidgets('shows download progress as events arrive', (tester) async {
    final controller = StreamController<ModelDownloadEvent>();
    var onReadyCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ModelDownloadScreen(
          onReady: () => onReadyCalls++,
          downloadModel: () => controller.stream,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('下载语音识别模型中…'), findsOneWidget);

    controller.add(
      ModelDownloadEvent(
        phase: ModelDownloadPhase.downloadingAsr,
        receivedBytes: 50 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
      ),
    );
    await tester.pump();
    expect(find.text('50.0 MB / 100.0 MB'), findsOneWidget);

    controller.add(
      const ModelDownloadEvent(
        phase: ModelDownloadPhase.extracting,
        receivedBytes: 0,
      ),
    );
    await tester.pump();
    expect(find.text('解压模型中…'), findsOneWidget);

    controller.add(
      const ModelDownloadEvent(
        phase: ModelDownloadPhase.downloadingVad,
        receivedBytes: 10,
        totalBytes: 20,
      ),
    );
    await tester.pump();
    expect(find.text('下载降噪模型中…'), findsOneWidget);

    expect(onReadyCalls, 0);
    await controller.close();
    await tester.pump();
    expect(onReadyCalls, 1);
  });

  testWidgets('shows an error with a retry button that restarts the download', (
    tester,
  ) async {
    var attempts = 0;
    var onReadyCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ModelDownloadScreen(
          onReady: () => onReadyCalls++,
          downloadModel: () {
            attempts++;
            if (attempts == 1) {
              return Stream<ModelDownloadEvent>.error(StateError('boom'));
            }
            return const Stream<ModelDownloadEvent>.empty();
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('下载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(onReadyCalls, 0);

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(attempts, 2);
    expect(onReadyCalls, 1);
    expect(find.textContaining('下载失败'), findsNothing);
  });
}
