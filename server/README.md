# BMSTU neo — push server

Registers app installations and wakes them with **silent pushes** (`{"type": "sync"}`) on a
schedule. Woken apps refresh progress from LKS with their own session and notify the student
locally. The server never sees LKS credentials, grades or names — only push tokens, the
platform and the group UUID. See `docs/PUSH_NOTIFICATIONS_PLAN.md` for the overall design.

## API

| Method | Path | Notes |
|---|---|---|
| `POST` | `/v1/devices` | `{installationId, secret, platform: apns\|fcm, token, groupUuid?}` → `201` created / `204` updated / `403` wrong secret |
| `DELETE` | `/v1/devices/{installationId}` | header `x-installation-secret`; idempotent |
| `GET` | `/healthz` | `{"ok": true, "devices": N}` |
| `POST` | `/internal/tick` | runs one scheduling pass now; `Authorization: Bearer $ADMIN_TOKEN`; 404 if no token is configured |

Limits: 8 KB bodies, 60 requests/min per IP. The installation secret is stored as SHA-256 only.

## Configuration (environment)

| Variable | Default | |
|---|---|---|
| `APNS_KEY_FILE` (or `APNS_KEY`) | — | `.p8` key from Apple Developer → Keys |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | — | `A78SGLKGT5` / `F72A8BN5CB` |
| `APNS_BUNDLE_ID` | `ru.bmstu.neo` | |
| `FCM_SERVICE_ACCOUNT_FILE` (or `FCM_SERVICE_ACCOUNT`) | — | Firebase → Project settings → Service accounts → private key JSON |
| `SYNC_INTERVAL_MINUTES` | `120` | how often each device is woken |
| `TICK_SECONDS` | `300` | how often the scheduler looks for due devices |
| `ADMIN_TOKEN` | — | enables `/internal/tick` |
| `DATA_DIR` | `data` | `devices.json` lives here — keep it on a persistent volume |
| `PORT` | `8080` | |

Without APNs or FCM credentials that platform is skipped (its devices are kept). Nights
22:00–08:00 Moscow time are quiet. Dead tokens (`Unregistered`, `UNREGISTERED`) are removed;
an iOS token is tried on production APNs first and on sandbox if Apple says `BadDeviceToken`
(Xcode builds), and the result is remembered per device.

## Run locally

```bash
cd server
APNS_KEY_FILE=~/secrets/AuthKey_A78SGLKGT5.p8 APNS_KEY_ID=A78SGLKGT5 APNS_TEAM_ID=F72A8BN5CB \
FCM_SERVICE_ACCOUNT_FILE=~/secrets/bmstuneo-firebase-adminsdk.json ADMIN_TOKEN=local-test \
~/flutter/flutter/bin/dart run bin/server.dart
```

Build the app against it: `flutter run --dart-define=PUSH_SERVER_URL=http://localhost:8080`
(for an Android phone on USB add `adb reverse tcp:8080 tcp:8080`; debug builds allow plain HTTP to
localhost only). Trigger a round without waiting:

```bash
curl -X POST -H 'Authorization: Bearer local-test' http://localhost:8080/internal/tick
```

## Deploy (any VPS with Docker)

```bash
docker build -t bmstu-neo-push server/
docker run -d --name push --restart unless-stopped -p 127.0.0.1:8080:8080 \
  -v push-data:/data -v /etc/bmstu-neo:/secrets:ro \
  -e APNS_KEY_FILE=/secrets/AuthKey.p8 -e APNS_KEY_ID=A78SGLKGT5 -e APNS_TEAM_ID=F72A8BN5CB \
  -e FCM_SERVICE_ACCOUNT_FILE=/secrets/fcm.json bmstu-neo-push
```

Put an HTTPS reverse proxy in front (e.g. Caddy: `push.example.ru { reverse_proxy 127.0.0.1:8080 }`)
— the app must use `https://`. Store the key files readable by root only. Keep one instance:
the JSON store is not shared between processes.

## Tests

```bash
cd server && ~/flutter/flutter/bin/dart test
```

Test keys in `test/fixtures/*.testkey` are throwaway and grant access to nothing.
