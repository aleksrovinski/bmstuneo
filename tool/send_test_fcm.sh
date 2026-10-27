#!/usr/bin/env bash
# Sends a test silent push ({"type": "sync"}) to Android through FCM HTTP v1, the
# same way the future push server will. The service account key never leaves
# this machine; it is only used to sign a short-lived OAuth token request.
#
#   tool/send_test_fcm.sh ~/secrets/bmstuneo-firebase-adminsdk-xxxx.json             # debug build on a connected device/emulator
#   tool/send_test_fcm.sh ~/secrets/bmstuneo-firebase-adminsdk-xxxx.json <fcm-token>
#
# The token is stored by the app once "Уведомления об успеваемости" are enabled in the profile.
set -euo pipefail

SA_FILE=${1:?"usage: $0 <service-account.json> [fcm-token]"}
PACKAGE=ru.bmstu.neo
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}

TOKEN=${2:-}
if [[ -z "$TOKEN" ]]; then
  # run-as only works for debuggable (debug) builds
  TOKEN=$("$ADB" shell run-as "$PACKAGE" cat shared_prefs/FlutterSharedPreferences.xml 2>/dev/null |
    python3 -I -c '
import re, sys
m = re.search(r"<string name=\"flutter\.push_token_v1\">([^<]+)</string>", sys.stdin.read())
print(m.group(1) if m else "")')
  [[ -n "$TOKEN" ]] || { echo "No FCM token on the device: install a debug build and enable notifications in the profile" >&2; exit 1; }
  echo "Token from device"
fi

field() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$SA_FILE" "$1"; }
CLIENT_EMAIL=$(field client_email)
PROJECT_ID=$(field project_id)

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# RS256 JWT signed with the service account key (openssl's RSA signature is already raw)
key=$(mktemp)
chmod 600 "$key"
field private_key > "$key"
now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
claims=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/firebase.messaging","aud":"https://oauth2.googleapis.com/token","iat":%d,"exp":%d}' \
  "$CLIENT_EMAIL" "$now" "$((now + 3600))" | b64url)
signature=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$key" | b64url)
rm -f "$key"

access=$(curl --silent --show-error \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$header.$claims.$signature" \
  https://oauth2.googleapis.com/token |
  python3 -I -c 'import json, sys; r = json.load(sys.stdin); print(r.get("access_token") or ""); sys.exit(0 if r.get("access_token") else "OAuth failed: " + json.dumps(r))')

echo "Sending silent push to ${TOKEN:0:8}… via FCM (project $PROJECT_ID)"
# Data-only + high priority: delivered to PushMessagingService even in the background
curl --silent --show-error --write-out '\nHTTP %{http_code}\n' \
  --header "authorization: Bearer $access" \
  --header 'content-type: application/json' \
  --data "{\"message\":{\"token\":\"$TOKEN\",\"data\":{\"type\":\"sync\"},\"android\":{\"priority\":\"high\"}}}" \
  "https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send"
