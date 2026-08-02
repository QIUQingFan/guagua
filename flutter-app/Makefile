.PHONY: dev staging prod pub get codegen analyze test clean run-android run-ios

pub:
	flutter pub get

codegen:
	dart run build_runner build --delete-conflicting-outputs

l10n:
	flutter gen-l10n

dev:
	flutter run \
	  --dart-define=API_BASE_URL=http://10.0.2.2:3001/api \
	  --dart-define=SOCKET_URL=http://10.0.2.2:3001 \
	  --dart-define=ENV=dev

staging:
	flutter run --dart-define=API_BASE_URL=https://staging-api.guagua.com/api \
	  --dart-define=SOCKET_URL=https://staging-api.guagua.com --dart-define=ENV=staging

prod:
	flutter run --dart-define=API_BASE_URL=https://api.guagua.com/api \
	  --dart-define=SOCKET_URL=https://api.guagua.com --dart-define=ENV=prod

analyze:
	flutter analyze

test:
	flutter test

test-coverage:
	flutter test --coverage

run-android:
	flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:3001/api --dart-define=SOCKET_URL=http://10.0.2.2:3001

run-ios:
	flutter run -d ios --dart-define=API_BASE_URL=http://localhost:3001/api --dart-define=SOCKET_URL=http://localhost:3001

clean:
	flutter clean
	rm -rf build/ .dart_tool/
