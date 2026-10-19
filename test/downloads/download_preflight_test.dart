import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/downloads/download_preflight.dart';

void main() {
  test('insufficient disk space blocks regardless of Wi-Fi', () async {
    final reason = await downloadBlockReason(
      requiredBytes: 1000,
      wifiOnly: false,
      isWifiConnected: () async => true,
      availableDiskSpace: () async => 500,
    );

    expect(reason, contains('存储空间不足'));
  });

  test('Wi-Fi required but absent blocks when space is sufficient', () async {
    final reason = await downloadBlockReason(
      requiredBytes: 1000,
      wifiOnly: true,
      isWifiConnected: () async => false,
      availableDiskSpace: () async => 5000,
    );

    expect(reason, contains('Wi-Fi'));
  });

  test('not Wi-Fi-only does not check connection type at all', () async {
    final reason = await downloadBlockReason(
      requiredBytes: 1000,
      wifiOnly: false,
      isWifiConnected: () async => false,
      availableDiskSpace: () async => 5000,
    );

    expect(reason, isNull);
  });

  test('clear to proceed when space is sufficient and Wi-Fi is connected', () async {
    final reason = await downloadBlockReason(
      requiredBytes: 1000,
      wifiOnly: true,
      isWifiConnected: () async => true,
      availableDiskSpace: () async => 5000,
    );

    expect(reason, isNull);
  });
}
