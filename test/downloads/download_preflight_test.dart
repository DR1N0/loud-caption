import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/downloads/download_preflight.dart';

void main() {
  test('insufficient disk space blocks before checking the network', () async {
    var wifiChecks = 0;
    final result = await checkDownloadPreflight(
      requiredBytes: 1000,
      isWifiConnected: () async {
        wifiChecks++;
        return true;
      },
      availableDiskSpace: () async => 500,
    );

    expect(result.blockReason, contains('存储空间不足'));
    expect(result.canStart, isFalse);
    expect(result.isWifi, isFalse);
    expect(wifiChecks, 0);
  });

  test('sufficient space and Wi-Fi is clear to proceed', () async {
    final result = await checkDownloadPreflight(
      requiredBytes: 1000,
      isWifiConnected: () async => true,
      availableDiskSpace: () async => 5000,
    );

    expect(result.blockReason, isNull);
    expect(result.canStart, isTrue);
    expect(result.isWifi, isTrue);
  });

  test(
    'a mobile connection is reported for confirmation, not blocked',
    () async {
      final result = await checkDownloadPreflight(
        requiredBytes: 1000,
        isWifiConnected: () async => false,
        availableDiskSpace: () async => 5000,
      );

      expect(result.blockReason, isNull);
      expect(result.canStart, isTrue);
      expect(result.isWifi, isFalse);
    },
  );
}
