# Only Social GPS — Engine protocol (v1)

Transport: newline-delimited JSON (NDJSON), UTF-8, exactly one JSON object per line. The app writes requests to the hub's **stdin**; the hub writes replies and events to **stdout**. The hub's **stderr** is human logs only. Every stdout line MUST be valid JSON. Unknown fields must be ignored by both sides (forward compatibility).

## Requests (app → hub)
Every request: `{"id": <int|string>, "cmd": "<name>", ...params}`. Every request gets exactly one reply:
`{"id": <same>, "ok": true, "result": {...}}` or `{"id": <same>, "ok": false, "error": {"code": "<snake_case>", "message": "<human text>"}}`.

| cmd | params | result |
|---|---|---|
| `hello` | `{"app_version": "1.0"}` | `{"engine_version": "1.0", "python": "3.14.6", "pymobiledevice3": "10.7.3", "pid": 123, "capabilities": ["userspace_tunnel", "go_ios_rsd_fallback"]}` |
| `list_devices` | — | `{"devices": [Device…]}` (also pushed as a `devices` event) |
| `set_desired` | `{"udid": "…", "target": {"lat": 51.5, "lon": -0.12} \| null}` | `{"accepted": true}` — `null` target = release to real GPS. The hub spawns a worker if needed and forwards; progress arrives as `device_state` events. |
| `set_all` | `{"targets": {"<udid>": {"lat":…, "lon":…} \| null, …}}` | `{"accepted": ["udid", …]}` — bulk form used at app launch. Replaces the whole desired map. |
| `release` | `{"udid": "…"}` | `{"accepted": true}` — same as `set_desired` with `null` |
| `release_all` | — | `{"accepted": ["udid", …]}` |
| `parse_proxy` | `{"proxy": "<string>"}` | `Proxy` (below) or error `parse_error` |
| `geolocate_proxy` | `{"proxy": "<string>"}` | `GeoResult` (below). Errors: `parse_error`, `proxy_unreachable` (error object also carries `"fallback": GeoResult|null` for the gateway-IP lookup), `geo_failed`. May take up to ~25 s; the hub emits `geo_progress` events meanwhile. Several may run concurrently. |
| `my_location` | — | `GeoResult` for the Mac's own public IP (cached 10 min) |
| `worker_restart` | `{"udid": "…"}` | `{"accepted": true}` |
| `worker_status` | — | `{"workers": {"<udid>": WorkerStatus}}` |
| `shutdown` | — | `{"accepted": true}` then the hub releases every phone (workers clear + quit) and exits 0. |

## Events (hub → app), unsolicited
| event | payload |
|---|---|
| `hello` | `{"event":"hello", "engine_version": "1.0", "pid": 123}` — first line on stdout, always |
| `devices` | `{"event":"devices", "devices": [Device…]}` — full list whenever it changes and right after `hello` |
| `device_state` | `{"event":"device_state", "udid": "…", "state": State, "target": {"lat","lon"}\|null, "applied": {"lat","lon","at": <unix seconds>}\|null, "message": "<optional human text>", "attempt": <int, optional>, "retry_in": <seconds, optional>}` |
| `geo_progress` | `{"event":"geo_progress", "id": <request id>, "stage": "connecting" \| "querying ip-api.com" \| "querying ipwho.is" \| "querying ipinfo.io" \| "fallback_gateway"}` |
| `log` | `{"event":"log", "level": "debug"\|"info"\|"warn"\|"error", "udid": "<optional>", "message": "…"}` |

`State` ∈ `idle` (connected, no target), `connecting` (worker starting / tunnel opening), `tunnel_up` (tunnel open, applying), `simulating` (target applied and held), `reconnecting` (lost the tunnel, retrying; `attempt` and `retry_in` present), `error` (gave up for now; `message` present; the hub still retries every 60 s), `released` (cleared on request; worker exiting), `disconnected` (phone not on USB; target remembered).

## Objects
```
Device = {
  "udid": "00008020-000A283934E9002E",
  "name": "iPhone",                 // DeviceName
  "product_type": "iPhone11,8",
  "model_name": "iPhone XR",        // marketing name from the table in BRIEF.md
  "ios": "18.7.9",
  "build": "22H355",
  "connection": "USB",
  "developer_mode": true | false | null,
  "ddi_mounted": true | false | null,
  "paired": true | false,
  "serial": "DX3ZVSDPKXKN" | null,
  "timezone": "America/Halifax" | null,
  "first_seen": <unix seconds>, "last_seen": <unix seconds>
}
Proxy = { "scheme": "socks5h" | "socks5" | "http" | "https", "host": "…", "port": 1080,
          "username": "…" | null, "password": "…" | null,
          "normalized": "socks5h://user:***@host:port", "curl_args": ["--socks5-hostname", "host:port", "--proxy-user", "user:pass"] }
GeoResult = { "ip": "1.2.3.4", "lat": 51.5074, "lon": -0.1278,
              "city": "London", "region": "England", "country": "United Kingdom", "country_code": "GB",
              "isp": "Virgin Media", "org": "…", "asn": "AS5089", "timezone": "Europe/London",
              "provider": "ip-api.com", "via_proxy": true, "note": null | "gateway IP — may differ from exit IP",
              "checked_at": <unix seconds>, "elapsed_ms": 1234 }
WorkerStatus = { "pid": 123 | null, "state": State, "target": {...}|null, "applied": {...}|null,
                 "restarts": 0, "last_error": "…" | null, "last_heartbeat": <unix seconds> | null }
```

## Worker protocol (hub ↔ worker, also NDJSON on stdin/stdout)
Hub → worker: `{"cmd": "set", "lat": 51.5, "lon": -0.12}`, `{"cmd": "clear"}`, `{"cmd": "quit"}`.
Worker → hub: `{"event": "state", "state": State, "target": …, "applied": …, "message": …, "attempt": …, "retry_in": …}`, `{"event": "heartbeat", "ts": <unix seconds>}` every 5 s, `{"event": "log", "level": …, "message": …}`.
Worker is launched as `python3 osgps_engine.py --worker <UDID>`; it exits 0 after `quit`, and on SIGTERM it clears (best effort, ≤3 s) then exits.

## Mock engine
`mock_engine.py` implements the hub side of this protocol with fake phones. `--devices <file.json>` overrides the fake fleet; `--scenario <name>` picks scripted behaviours (`normal`, `empty`, `flaky`, `no_pymobiledevice3` is simulated by the app itself). Geolocation answers are deterministic per proxy string (hash → one of ~8 cities) and take ~1.5 s, so the UI's loading states can be seen.
