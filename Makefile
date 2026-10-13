# Loud Caption developer Makefile.
#
# A JDK 17 trusted by your network's TLS setup is required for the Gradle
# targets below; override JAVA17_HOME if Zulu isn't installed at this path.
JAVA17_HOME ?= /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home

.PHONY: models pub-get analyze test jvm-test apk-debug apk-release apk \
        install-debug install-release clean check

## Download and checksum-verify the two bundled Vosk model archives.
models:
	python3 scripts/fetch_models.py
	python3 -m unittest discover -s test -p 'model_sources_test.py'

## Fetch Dart/Flutter package dependencies.
pub-get:
	flutter pub get

## Run the Dart static analyzer.
analyze:
	flutter analyze

## Run the Flutter unit/widget test suite.
test:
	flutter test

## Run the Android (Kotlin/JVM) unit test suite.
jvm-test:
	cd android && env JAVA_HOME=$(JAVA17_HOME) PATH="$(JAVA17_HOME)/bin:$$PATH" \
		./gradlew --no-daemon -Dorg.gradle.java.home=$(JAVA17_HOME) :app:testDebugUnitTest

## Build the debug APK (includes the debug-only INTERNET permission).
apk-debug:
	cd android && env JAVA_HOME=$(JAVA17_HOME) PATH="$(JAVA17_HOME)/bin:$$PATH" \
		./gradlew --no-daemon -Dorg.gradle.java.home=$(JAVA17_HOME) :app:assembleDebug

## Build the release APK (what gets attached to a GitHub Release).
apk-release:
	cd android && env JAVA_HOME=$(JAVA17_HOME) PATH="$(JAVA17_HOME)/bin:$$PATH" \
		./gradlew --no-daemon -Dorg.gradle.java.home=$(JAVA17_HOME) :app:assembleRelease

## Alias for apk-release.
apk: apk-release

## Install the debug/release APK on a connected device via adb.
install-debug: apk-debug
	adb install -r build/app/outputs/apk/debug/app-debug.apk

install-release: apk-release
	adb install -r build/app/outputs/apk/release/app-release.apk

## Remove all build output.
clean:
	flutter clean

## Full pre-release gate: models, deps, static analysis, and both test suites.
check: models pub-get analyze test jvm-test
