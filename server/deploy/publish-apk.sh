#!/usr/bin/env bash
# Publishes a release APK on the website and announces it to installed apps (version.json).
# Usage: server/deploy/publish-apk.sh root@HOST path/to/app-release.apk ["Что нового"]
set -euo pipefail

HOST=$1 APK=$2 NOTES=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
SITE_DIR=$(cd "$HERE/../../../website" && pwd)
AAPT=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt | tail -1)

BADGING=$("$AAPT" dump badging "$APK" | head -1)
CODE=$(sed -E "s/.*versionCode='([0-9]+)'.*/\1/" <<<"$BADGING")
NAME=$(sed -E "s/.*versionName='([^']+)'.*/\1/" <<<"$BADGING")
FILE="bmstu-neo-$NAME.apk"
SIZE=$(stat -f %z "$APK")
SHA=$(shasum -a 256 "$APK" | cut -d' ' -f1)

# Keep only the published version locally; old links stop working on purpose
find "$SITE_DIR/downloads" -name '*.apk' ! -name "$FILE" -delete
cp "$APK" "$SITE_DIR/downloads/$FILE"
NOTES="$NOTES" CODE="$CODE" NAME="$NAME" FILE="$FILE" SIZE="$SIZE" SHA="$SHA" python3 - "$SITE_DIR/version.json" <<'PY'
import json, os, sys
json.dump({
    "versionCode": int(os.environ["CODE"]),
    "versionName": os.environ["NAME"],
    "apk": "downloads/" + os.environ["FILE"],
    "size": int(os.environ["SIZE"]),
    "sha256": os.environ["SHA"],
    "notes": os.environ["NOTES"],
}, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY
sed -i '' -E "s#android: \"downloads/[^\"]*\"#android: \"downloads/$FILE\"#; s#androidSize: \"[^\"]*\"#androidSize: \"$(( (SIZE + 500000) / 1000000 )) МБ\"#" "$SITE_DIR/script.js"

rsync -az --delete --exclude .git --exclude .gitignore --exclude README.md "$SITE_DIR/" "$HOST:/var/www/bmstuneo/"
ssh "$HOST" 'chmod -R a+rX /var/www/bmstuneo'
echo "Published $NAME ($CODE): https://bmstuneo.xyz/downloads/$FILE"
