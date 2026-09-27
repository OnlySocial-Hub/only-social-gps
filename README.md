# Only Social GPS

A macOS menu-bar app that sets a connected iPhone's GPS to match the location of
its proxy. It geolocates each proxy's exit IP (through the proxy) and drives the
phone's location to that city. It pairs with **iPhone Bot**, which calls it over a
loopback HTTP bridge (`127.0.0.1:8765`) to set a phone's location once a proxy is
applied.

## Requirements
- **macOS 15+**
- **Xcode Command Line Tools** (for `swiftc`) — install with `xcode-select --install`
- **Python 3** (the bundled engine uses only the standard library — no `pip install`)

## Build & run
```bash
./build.sh --install
```
This compiles the Swift sources with `swiftc` (no Xcode project needed), bundles
the Python engine, copies **Only Social GPS.app** into `/Applications`, and
launches it. Plain `./build.sh` builds into `dist/` without installing.

## How it connects to iPhone Bot
The app runs a loopback HTTP bridge on `127.0.0.1:8765`. iPhone Bot's proxy page
calls it (`/osgps/ping`, `/osgps/set-from-proxy`, `/osgps/release`) — see
`PROTOCOL.md`. Nothing is exposed off the machine.

## Docs
- `BRIEF.md` — what it does and why
- `DESIGN.md` — architecture and UI
- `PROTOCOL.md` — the engine's NDJSON protocol + the HTTP bridge
