import 'package:flutter/services.dart';

typedef SetOrientations = Future<void> Function(List<DeviceOrientation>);

/// Applies the user's persistent orientation preference to the platform.
class OrientationManager {
  OrientationManager({SetOrientations? setOrientations})
    : _setOrientations =
          setOrientations ?? SystemChrome.setPreferredOrientations;

  final SetOrientations _setOrientations;

  Future<void> apply(bool landscape) => _setOrientations(
    landscape
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [DeviceOrientation.portraitUp],
  );
}
