#!/usr/bin/env bash
# Локальная сборка релиза (как в GitHub Actions).
# Использование: ./Scripts/package-release.sh 1.0.0

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>, e.g. 1.0.0" >&2
  exit 1
fi

TAG="v${VERSION}"
ARCHIVE="KeenSwitch-${TAG}-macOS.zip"
DERIVED="DerivedData"

echo "→ Build Release KeenSwitch $VERSION"
xcodebuild \
  -project KeenSwitch.xcodeproj \
  -scheme KeenSwitch \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED/Build/Products/Release/KeenSwitch.app"
codesign --force --deep --sign - "$APP"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE"

echo "→ Готово: $ROOT/$ARCHIVE"
echo "→ Тег для GitHub: git tag $TAG && git push origin $TAG"
