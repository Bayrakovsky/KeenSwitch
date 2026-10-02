#!/usr/bin/env bash
# Локальная сборка релиза (как в GitHub Actions).
# Использование: ./Scripts/package-release.sh 1.1.0
#
# Тулчейн: по умолчанию /Applications/Xcode.app (Xcode 27 / SDK 27). Переопределяется
# переменной DEVELOPER_DIR. Релиз обязан собираться SDK 27 — от линкованного SDK
# зависят второгодние правки Liquid Glass.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>, e.g. 1.1.0" >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_MAJOR="${SDK_VERSION%%.*}"
if (( SDK_MAJOR < 27 )); then
  echo "Нужен macOS SDK 27 или новее, найден $SDK_VERSION" >&2
  echo "Проверьте DEVELOPER_DIR (сейчас: $DEVELOPER_DIR) или выполните:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

echo "→ Toolchain: $(xcodebuild -version | head -1), macOS SDK $SDK_VERSION"

TAG="v${VERSION}"
ARCHIVE="KeenSwitch-${TAG}-macOS.zip"
DERIVED="DerivedData"

echo "→ Build Release KeenSwitch $VERSION"
# Подписываем ad-hoc прямо в сборке — как в release.yml, без отдельного codesign.
# (`codesign --deep` для подписи Apple не рекомендует.)
xcodebuild \
  -project KeenSwitch.xcodeproj \
  -scheme KeenSwitch \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$DERIVED/Build/Products/Release/KeenSwitch.app"

echo "→ Verify"
codesign --verify --deep --strict "$APP"
echo "   archs:      $(lipo -archs "$APP/Contents/MacOS/KeenSwitch")"
echo "   linked SDK: $(/usr/libexec/PlistBuddy -c 'Print :DTSDKName' "$APP/Contents/Info.plist")"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE"

echo "→ Готово: $ROOT/$ARCHIVE"
echo "→ Тег для GitHub: git tag $TAG && git push origin $TAG"
