#!/usr/bin/env bash
# Sends a test silent push ({"type": "sync"}) through the APNs *sandbox*, the same
# way the future push server will. The .p8 key never leaves this machine.
#
#   tool/send_test_push.sh ~/secrets/AuthKey_A78SGLKGT5.p8             # booted simulator, else paired device
#   tool/send_test_push.sh ~/secrets/AuthKey_A78SGLKGT5.p8 --device    # iPhone connected by cable
#   tool/send_test_push.sh ~/secrets/AuthKey_A78SGLKGT5.p8 <hex-token>   # explicit device token
#
# The token is stored by the app once "Уведомления об успеваемости" are enabled in the profile.
# Simulators receive sandbox pushes on Apple silicon Macs (Xcode 14+).
set -euo pipefail

KEY_FILE=${1:?"usage: $0 <AuthKey_XXXX.p8> [device-token]"}
KEY_ID=${APNS_KEY_ID:-A78SGLKGT5}
TEAM_ID=${APNS_TEAM_ID:-F72A8BN5CB}
BUNDLE_ID=ru.bmstu.neo
HOST=${APNS_HOST:-api.sandbox.push.apple.com}

PREFS_PATH="Library/Preferences/$BUNDLE_ID.plist"

# The app's push token from a copied preferences plist. Not `plutil -extract`: it
# treats the dot in "flutter.push_token_v1" as a key path separator.
read_token() {
  plutil -convert json -o - "$1" 2>/dev/null |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("flutter.push_token_v1") or "")' 2>/dev/null || true
}

# Token saved by the app in the booted simulator, or nothing
token_from_simulator() {
  local container
  container=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null) || return 0
  read_token "$container/$PREFS_PATH"
}

# Token saved by the app on a paired iPhone/iPad (development builds only), or nothing
token_from_device() {
  local list device copy
  list=$(mktemp)
  xcrun devicectl list devices --quiet --json-output "$list" >/dev/null 2>&1 || true
  device=$(python3 -I -c '
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("reality") == "physical"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
# copy works with the hardware UDID, not with the CoreDevice identifier
print((phones[0].get("hardwareProperties", {}).get("udid") or phones[0]["identifier"]) if phones else "")' "$list")
  rm -f "$list"
  [[ -n "$device" ]] || return 0
  copy=$(mktemp -d)
  xcrun devicectl device copy from --quiet --device "$device" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" --source "$PREFS_PATH" --destination "$copy/prefs.plist" >/dev/null 2>&1 || true
  read_token "$copy/prefs.plist"
  rm -f "$copy/prefs.plist"
  rmdir "$copy"
}

TOKEN=${2:-}
case "$TOKEN" in
  --device) TOKEN=$(token_from_device); SOURCE="device" ;;
  --simulator) TOKEN=$(token_from_simulator); SOURCE="simulator" ;;
  "")
    TOKEN=$(token_from_simulator); SOURCE="simulator"
    if [[ -z "$TOKEN" ]]; then TOKEN=$(token_from_device); SOURCE="device"; fi
    ;;
  *) SOURCE="argument" ;;
esac

if [[ -z "$TOKEN" ]]; then
  cat >&2 <<'EOF'
No push token found, neither in a booted simulator nor on a paired iPhone/iPad.
- Install the app from this Mac (flutter run) and turn on "Уведомления об успеваемости" in the profile.
- A device must be paired with this Mac (Xcode → Devices and Simulators) and unlocked.
EOF
  exit 1
fi
echo "Token from $SOURCE"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# ES256 JWT. openssl emits a DER signature; JWS wants raw r||s, 32 bytes each.
der_to_raw() {
  openssl asn1parse -inform DER | awk -F: '/INTEGER/ {print $NF}' | while read -r hex; do
    hex=${hex#00}
    printf '%64s' "$hex" | tr ' ' 0
  done | xxd -r -p
}

header=$(printf '{"alg":"ES256","kid":"%s"}' "$KEY_ID" | b64url)
claims=$(printf '{"iss":"%s","iat":%d}' "$TEAM_ID" "$(date +%s)" | b64url)
signature=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$KEY_FILE" | der_to_raw | b64url)
jwt="$header.$claims.$signature"

echo "Sending silent push to ${TOKEN:0:8}… via $HOST"
curl --http2 --silent --show-error --write-out 'HTTP %{http_code}\n' \
  --header "authorization: bearer $jwt" \
  --header "apns-topic: $BUNDLE_ID" \
  --header "apns-push-type: background" \
  --header "apns-priority: 5" \
  --data '{"aps":{"content-available":1},"type":"sync"}' \
  "https://$HOST/3/device/$TOKEN"
