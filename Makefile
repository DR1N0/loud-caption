# Loud Caption developer Makefile.
#
# A JDK 17 trusted by your network's TLS setup is required for the Gradle
# targets below. It defaults to JAVA_HOME; override JAVA17_HOME to point at a
# specific installation.
JAVA17_HOME ?= $(JAVA_HOME)

.PHONY: pub-get analyze test apk-debug apk-release apk \
        install-debug install-release clean check

## Fetch Dart/Flutter package dependencies.
pub-get:
	flutter pub get

## Run the Dart static analyzer.
analyze:
	flutter analyze

## Run the Flutter unit/widget test suite.
test:
	flutter test

## Build the debug APK (signed with the same committed key as release — see
## android/app/build.gradle.kts — so switching between the two never needs an
## uninstall first).
apk-debug:
	cd android && env JAVA_HOME=$(JAVA17_HOME) PATH="$(JAVA17_HOME)/bin:$$PATH" \
		./gradlew --no-daemon -Dorg.gradle.java.home=$(JAVA17_HOME) :app:assembleDebug

## Build the release APK (arm64-v8a only; what gets attached to a GitHub
## Release). Plain `ndk.abiFilters` doesn't work here: Flutter's Gradle
## plugin (3.35+) pre-populates abiFilters with every supported ABI before
## build.gradle.kts runs, so --target-platform/--split-per-abi is the only
## reliable way to drop the unused armeabi-v7a/x86_64 native libs.
apk-release:
	env JAVA_HOME=$(JAVA17_HOME) PATH="$(JAVA17_HOME)/bin:$$PATH" \
		flutter build apk --release --target-platform android-arm64 --split-per-abi
	cp build/app/outputs/apk/release/app-arm64-v8a-release.apk \
		build/app/outputs/apk/release/app-release.apk

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

## Full pre-release gate: deps, static analysis, and the test suite.
check: pub-get analyze test
