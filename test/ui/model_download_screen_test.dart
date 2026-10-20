import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/downloads/download_preflight.dart';
import 'package:loud_caption/speech/sense_voice_model_download.dart';
import 'package:loud_caption/ui/caption_theme.dart';
import 'package:loud_caption/ui/model_download_screen.dart';

final _theme = ThemeData.dark().copyWith(
  extensions: const [CaptionColors.dark],
);

Future<DownloadPreflight> _wifi({required int requiredBytes}) async =>
    const DownloadPreflight(isWifi: true);

void main() {
  testWidgets('shows download progress as events arrive', (tester) async {
    final controller = StreamController<ModelDownloadEvent>();
    var onReadyCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: ModelDownloadScreen(
          onReady: () => onReadyCalls++,
          downloadModel: () => controller.stream,
          preflightCheck: _wifi,
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
        totalBytes: 239549735,
      ),
    );
    await tester.pump();
    expect(find.text('解压模型中…'), findsOneWidget);
    expect(find.textContaining('正在解压约 240 MB'), findsOneWidget);
    expect(find.textContaining('0.0 MB'), findsNothing);

    controller.add(
      const ModelDownloadEvent(
        phase: ModelDownloadPhase.extracting,
        receivedBytes: 100 * 1024 * 1024,
        totalBytes: 239549735,
      ),
    );
    await tester.pump();
    expect(find.text('100.0 MB / 228.5 MB'), findsOneWidget);

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
        theme: _theme,
        home: ModelDownloadScreen(
          onReady: () => onReadyCalls++,
          preflightCheck: _wifi,
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
    await tester.pump();

    expect(attempts, 2);
    expect(onReadyCalls, 1);
    expect(find.textContaining('下载失败'), findsNothing);
  });

  testWidgets(
    'a blocked preflight check shows the reason and never starts the download',
    (tester) async {
      var downloadCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: ModelDownloadScreen(
            onReady: () {},
            preflightCheck: ({required requiredBytes}) async =>
                const DownloadPreflight(
                  isWifi: true,
                  blockReason: '存储空间不足：需要约 450 MB，仅剩 100 MB。请清理空间后重试。',
                ),
            downloadModel: () {
              downloadCalls++;
              return const Stream<ModelDownloadEvent>.empty();
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('存储空间不足'), findsOneWidget);
      expect(downloadCalls, 0);
    },
  );

  testWidgets(
    'a non-Wi-Fi connection asks before downloading and continues on confirm',
    (tester) async {
      var downloadCalls = 0;
      final controller = StreamController<ModelDownloadEvent>();

      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: ModelDownloadScreen(
            onReady: () {},
            preflightCheck: ({required requiredBytes}) async =>
                const DownloadPreflight(isWifi: false),
            downloadModel: () {
              downloadCalls++;
              return controller.stream;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('使用移动数据下载模型？'), findsOneWidget);
      expect(find.textContaining('当前未连接 Wi-Fi'), findsOneWidget);
      expect(downloadCalls, 0);

      await tester.tap(find.text('继续下载'));
      await tester.pump();

      expect(downloadCalls, 1);
      expect(find.text('下载语音识别模型中…'), findsOneWidget);

      await controller.close();
      await tester.pump();
    },
  );

  testWidgets('cancelling the mobile-data prompt leaves a retry option', (
    tester,
  ) async {
    var downloadCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: ModelDownloadScreen(
          onReady: () {},
          preflightCheck: ({required requiredBytes}) async =>
              const DownloadPreflight(isWifi: false),
          downloadModel: () {
            downloadCalls++;
            return const Stream<ModelDownloadEvent>.empty();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(downloadCalls, 0);
    expect(find.text('已取消下载'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('使用移动数据下载模型？'), findsOneWidget);
    expect(downloadCalls, 0);
  });
}
