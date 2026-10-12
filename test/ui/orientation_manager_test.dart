import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loud_caption/ui/orientation_manager.dart';

void main() {
  test('apply uses portraitUp when landscape is disabled', () async {
    final calls = <List<DeviceOrientation>>[];
    final manager = OrientationManager(
      setOrientations: (orientations) async => calls.add(orientations),
    );

    await manager.apply(false);

    expect(calls, [
      const [DeviceOrientation.portraitUp],
    ]);
  });

  test(
    'apply enables both landscape directions when landscape is enabled',
    () async {
      final calls = <List<DeviceOrientation>>[];
      final manager = OrientationManager(
        setOrientations: (orientations) async => calls.add(orientations),
      );

      await manager.apply(true);

      expect(calls, [
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      ]);
    },
  );
}
