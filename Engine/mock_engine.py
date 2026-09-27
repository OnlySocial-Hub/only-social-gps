#!/usr/bin/env python3
"""Only Social GPS — mock engine.

Implements the hub side of PROTOCOL.md with fake phones so the app can be developed, run and
snapshotted without hardware. NDJSON on stdin/stdout; human logs on stderr.

    python3 mock_engine.py [--devices fleet.json] [--scenario normal|empty|flaky|snapshot]

Geolocation answers are deterministic per proxy string (hash -> one of eight cities) and take
~1.5 s so the UI's loading states are visible. Proxy hosts containing "bad" are unreachable
(with a gateway fallback), hosts containing "fail" make every provider fail.
"""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import hashlib
import json
import os
import re
import sys
import threading
import time
from typing import Any, Optional
from urllib.parse import unquote

ENGINE_VERSION = "1.0-mock"

# ----------------------------------------------------------------------------------- fleet
DEFAULT_FLEET = [
    {"udid": "00008020-000A283934E9002E", "name": "iPhone", "product_type": "iPhone11,8",
     "model_name": "iPhone XR", "ios": "18.7.9", "build": "22H355", "serial": "DX3ZVSDPKXKN",
     "timezone": "America/Halifax", "farm_handle": "@nat.hunterrr"},
    {"udid": "00008020-00092D843405002E", "name": "iPhone", "product_type": "iPhone11,8",
     "model_name": "iPhone XR", "ios": "18.7.9", "build": "22H355", "serial": "F71ZC2XKKXKN",
     "timezone": "America/Halifax", "farm_handle": "@onlyemspage"},
    {"udid": "00008020-001019503499002E", "name": "Work Phone", "product_type": "iPhone11,8",
     "model_name": "iPhone XR", "ios": "18.7.9", "build": "22H355", "serial": "DX3Z9Q7LKXKN",
     "timezone": "America/Halifax", "farm_handle": "@onlyglazertori"},
    {"udid": "00008030-0009193402B8402E", "name": "iPhone", "product_type": "iPhone12,1",
     "model_name": "iPhone 11", "ios": "18.7.8", "build": "22H354", "serial": "C39ZH0P3N72Q",
     "timezone": "America/Halifax", "farm_handle": "@ellybellywellyyy"},
]

CITIES = [
    {"city": "London", "region": "England", "country": "United Kingdom", "country_code": "GB",
     "lat": 51.5074, "lon": -0.1278, "timezone": "Europe/London", "isp": "Virgin Media",
     "org": "Virgin Media Limited", "asn": "AS5089", "ip_prefix": "82.12"},
    {"city": "Dallas", "region": "Texas", "country": "United States", "country_code": "US",
     "lat": 32.7767, "lon": -96.7970, "timezone": "America/Chicago", "isp": "AT&T Internet",
     "org": "AT&T Services, Inc.", "asn": "AS7018", "ip_prefix": "99.104"},
    {"city": "Berlin", "region": "Berlin", "country": "Germany", "country_code": "DE",
     "lat": 52.5200, "lon": 13.4050, "timezone": "Europe/Berlin", "isp": "Deutsche Telekom",
     "org": "Deutsche Telekom AG", "asn": "AS3320", "ip_prefix": "91.64"},
    {"city": "Paris", "region": "Île-de-France", "country": "France", "country_code": "FR",
     "lat": 48.8566, "lon": 2.3522, "timezone": "Europe/Paris", "isp": "Orange",
     "org": "Orange S.A.", "asn": "AS3215", "ip_prefix": "90.2"},
    {"city": "Amsterdam", "region": "North Holland", "country": "Netherlands", "country_code": "NL",
     "lat": 52.3676, "lon": 4.9041, "timezone": "Europe/Amsterdam", "isp": "KPN",
     "org": "KPN B.V.", "asn": "AS1136", "ip_prefix": "77.172"},
    {"city": "Toronto", "region": "Ontario", "country": "Canada", "country_code": "CA",
     "lat": 43.6532, "lon": -79.3832, "timezone": "America/Toronto", "isp": "Rogers",
     "org": "Rogers Communications", "asn": "AS812", "ip_prefix": "99.238"},
    {"city": "Los Angeles", "region": "California", "country": "United States", "country_code": "US",
     "lat": 34.0522, "lon": -118.2437, "timezone": "America/Los_Angeles", "isp": "Spectrum",
     "org": "Charter Communications", "asn": "AS20001", "ip_prefix": "47.156"},
    {"city": "Madrid", "region": "Madrid", "country": "Spain", "country_code": "ES",
     "lat": 40.4168, "lon": -3.7038, "timezone": "Europe/Madrid", "isp": "Movistar",
     "org": "Telefónica de España", "asn": "AS3352", "ip_prefix": "83.34"},
]

MAC_LOCATION = {
    "ip": "142.166.71.14", "lat": 44.6713, "lon": -63.5772, "city": "Dartmouth",
    "region": "Nova Scotia", "country": "Canada", "country_code": "CA", "isp": "Bell Canada",
    "org": "Bell Aliant", "asn": "AS855", "timezone": "America/Halifax", "provider": "ip-api.com",
    "via_proxy": False, "note": None, "flag": "🇨🇦",
}


def log(msg: str) -> None:
    sys.stderr.write(f"[mock {time.strftime('%H:%M:%S')}] {msg}\n")
    sys.stderr.flush()


def flag_emoji(cc: Optional[str]) -> Optional[str]:
    if not cc or len(cc) != 2 or not cc.isalpha():
        return None
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in cc.upper())


# ----------------------------------------------------------------------------------- proxy parser
class ProxyParseError(ValueError):
    pass


SCHEMES = ("socks5h", "socks5", "http", "https")


def _is_port(s: str) -> bool:
    return s.isdigit() and 0 < int(s) < 65536


def _split_hostport(hp: str) -> tuple[str, int]:
    hp = hp.strip()
    if hp.startswith("["):
        end = hp.find("]")
        if end < 0:
            raise ProxyParseError("unterminated IPv6 bracket")
        host, rest = hp[1:end], hp[end + 1:]
        if not rest.startswith(":") or not _is_port(rest[1:]):
            raise ProxyParseError("missing or bad port after IPv6 host")
        return host, int(rest[1:])
    if hp.count(":") != 1:
        raise ProxyParseError(f"expected host:port, got {hp!r}")
    host, port = hp.split(":")
    if not host:
        raise ProxyParseError("empty host")
    if not _is_port(port):
        raise ProxyParseError(f"bad port {port!r}")
    return host, int(port)


def parse_proxy(text: str) -> dict:
    s = text.strip().strip("'\"").strip()
    if s.endswith("/"):
        s = s.rstrip("/")
    if not s:
        raise ProxyParseError("empty proxy")
    scheme = "socks5h"
    user = pw = None
    m = re.match(r"^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$", s)
    if m:
        scheme = m.group(1).lower()
        if scheme == "socks5h":
            pass
        elif scheme in ("socks5", "socks"):
            scheme = "socks5"
        elif scheme in ("http", "https"):
            pass
        else:
            raise ProxyParseError(f"unsupported scheme {scheme!r}")
        s = m.group(2)
    if "@" in s:
        creds, hp = s.rsplit("@", 1)
        if ":" in creds:
            user, pw = creds.split(":", 1)
        else:
            user = creds
        user = unquote(user) or None
        pw = unquote(pw) if pw is not None else None
        host, port = _split_hostport(hp)
    else:
        if s.startswith("["):
            host, port = _split_hostport(s)
        else:
            parts = s.split(":")
            if len(parts) == 2:
                host, port = _split_hostport(s)
            elif len(parts) == 4:
                if _is_port(parts[1]):
                    host, port, user, pw = parts[0], int(parts[1]), parts[2], parts[3]
                elif _is_port(parts[3]):
                    user, pw, host, port = parts[0], parts[1], parts[2], int(parts[3])
                else:
                    raise ProxyParseError("4-field form needs a numeric port in field 2 or 4")
                if not host:
                    raise ProxyParseError("empty host")
            else:
                raise ProxyParseError(f"unrecognised proxy notation ({len(parts)} colon fields)")
    hp = (f"[{host}]" if ":" in host else host) + f":{port}"
    cred_mask = (f"{user}:***@" if pw else f"{user}@") if user else ""
    normalized = f"{scheme}://{cred_mask}{hp}"
    if scheme == "socks5h":
        curl_args = ["--socks5-hostname", hp]
    elif scheme == "socks5":
        curl_args = ["--socks5", hp]
    else:
        curl_args = ["--proxy", f"{scheme}://{hp}"]
    if user:
        curl_args += ["--proxy-user", f"{user}:{pw or ''}"]
    return {"scheme": scheme, "host": host, "port": port, "username": user, "password": pw,
            "normalized": normalized, "curl_args": curl_args}


try:  # prefer the real parser when it is next to us, so behaviour matches the hub exactly
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import proxy_geo as _pg  # type: ignore

    def parse_proxy_authoritative(text: str) -> dict:
        try:
            return _pg.parse_proxy(text)
        except _pg.ProxyParseError as e:  # type: ignore[attr-defined]
            raise ProxyParseError(str(e)) from None
except Exception:  # pragma: no cover
    parse_proxy_authoritative = parse_proxy


def geo_for_proxy(proxy_text: str, via_proxy: bool = True, note: Optional[str] = None,
                  provider: str = "ip-api.com") -> dict:
    h = hashlib.sha1(proxy_text.strip().encode("utf-8")).digest()
    city = CITIES[h[0] % len(CITIES)]
    ip = f"{city['ip_prefix']}.{h[1]}.{h[2] or 1}"
    jitter_lat = (h[3] - 128) / 128 * 0.01
    jitter_lon = (h[4] - 128) / 128 * 0.01
    r = {k: city[k] for k in ("city", "region", "country", "country_code", "timezone", "isp", "org", "asn")}
    r.update({"ip": ip, "lat": round(city["lat"] + jitter_lat, 4), "lon": round(city["lon"] + jitter_lon, 4),
              "provider": provider, "via_proxy": via_proxy, "note": note,
              "checked_at": int(time.time()), "elapsed_ms": 1200 + h[5] * 4,
              "flag": flag_emoji(city["country_code"])})
    return r


# ----------------------------------------------------------------------------------- output
class ProtoOut:
    def __init__(self) -> None:
        self._f = os.fdopen(os.dup(1), "wb", buffering=0)
        with contextlib.suppress(OSError):
            os.dup2(2, 1)
        self.broken = False

    def send(self, obj: dict) -> None:
        if self.broken:
            return
        try:
            self._f.write(json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode() + b"\n")
        except (BrokenPipeError, OSError):
            self.broken = True


async def read_lines(fd: int):
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue()

    def put(item: Optional[bytes]) -> None:
        with contextlib.suppress(RuntimeError):
            loop.call_soon_threadsafe(q.put_nowait, item)

    def pump() -> None:
        try:
            with os.fdopen(fd, "rb", closefd=False) as f:
                while True:
                    line = f.readline()
                    if not line:
                        break
                    put(line)
        finally:
            put(None)

    threading.Thread(target=pump, name="stdin-reader", daemon=True).start()
    while True:
        line = await q.get()
        if line is None:
            return
        line = line.strip()
        if line:
            yield line


# ----------------------------------------------------------------------------------- fake worker
class FakePhone:
    def __init__(self, hub: "MockHub", device: dict, index: int):
        self.hub = hub
        self.device = device
        self.index = index
        self.udid = device["udid"]
        self.connected = True
        self.target: Optional[dict] = None
        self.applied: Optional[dict] = None
        self.state = "idle"
        self.pid: Optional[int] = None
        self.restarts = 0
        self.last_error: Optional[str] = None
        self.task: Optional[asyncio.Task] = None
        self.flaky_task: Optional[asyncio.Task] = None

    def emit(self, state: str, **fields: Any) -> None:
        self.state = state
        ev = {"event": "device_state", "udid": self.udid, "state": state,
              "target": self.target, "applied": self.applied}
        ev.update({k: v for k, v in fields.items() if v is not None})
        self.hub.emit(ev)

    def cancel(self) -> None:
        for t in (self.task, self.flaky_task):
            if t and not t.done():
                t.cancel()
        self.task = self.flaky_task = None

    # ---- transitions
    async def _apply(self, fast: bool) -> None:
        s = self.hub.scenario
        if self.pid is None:
            self.pid = 40000 + self.index * 7 + self.restarts
            self.emit("connecting", message="opening userspace tunnel")
            await asyncio.sleep(0.15 if fast else 0.9)
            self.emit("tunnel_up", message="tunnel open, applying")
            await asyncio.sleep(0.15 if fast else 0.7)
        else:
            await asyncio.sleep(0.05 if fast else 0.3)
        if self.target is None:
            return
        self.applied = {"lat": self.target["lat"], "lon": self.target["lon"], "at": int(time.time())}
        self.emit("simulating")
        if s == "flaky" and self.flaky_task is None:
            self.flaky_task = asyncio.create_task(self._flaky_loop())

    async def _flaky_loop(self) -> None:
        # every ~18 s drop the tunnel; phone index 2 gives up into "error" once in a while
        n = 0
        while True:
            await asyncio.sleep(14 + self.index * 4)
            n += 1
            if self.target is None:
                return
            if self.index == 2 and n % 2 == 0:
                for attempt, wait in ((1, 1), (2, 2), (3, 5)):
                    self.emit("reconnecting", attempt=attempt, retry_in=wait, message="tunnel dropped")
                    await asyncio.sleep(wait)
                self.restarts += 1
                self.last_error = "UserspaceTunnelUnavailableError: RSD handshake timed out (3 attempts)"
                self.emit("error", message=self.last_error)
                await asyncio.sleep(20)
                self.pid = None
                self.task = asyncio.create_task(self._apply(False))
                await asyncio.sleep(3)
                continue
            for attempt, wait in ((1, 1), (2, 2)):
                self.emit("reconnecting", attempt=attempt, retry_in=wait, message="tunnel dropped")
                await asyncio.sleep(wait)
            self.applied = {"lat": self.target["lat"], "lon": self.target["lon"], "at": int(time.time())}
            self.emit("simulating")

    def set_target(self, target: Optional[dict]) -> None:
        self.target = target
        if not self.connected:
            self.emit("disconnected", message="phone not on USB; target remembered")
            return
        if target is None:
            self.cancel()
            if self.pid is not None:
                self.applied = None
                self.emit("released")
                self.pid = None
            self.applied = None
            self.emit("idle")
            return
        if self.task and not self.task.done():
            self.task.cancel()
        fast = self.hub.scenario == "snapshot"
        self.task = asyncio.create_task(self._apply(fast))

    def unplug(self) -> None:
        self.connected = False
        self.cancel()
        self.pid = None
        self.applied = None
        self.emit("disconnected", message="phone left USB")

    def plug(self) -> None:
        self.connected = True
        if self.target is not None:
            self.restarts += 1
            self.task = asyncio.create_task(self._apply(False))
        else:
            self.emit("idle")

    def status(self) -> dict:
        return {"pid": self.pid, "state": self.state, "target": self.target, "applied": self.applied,
                "restarts": self.restarts, "last_error": self.last_error,
                "last_heartbeat": int(time.time()) if self.pid else None}


# ----------------------------------------------------------------------------------- hub
class MockHub:
    def __init__(self, fleet: list[dict], scenario: str):
        self.out = ProtoOut()
        self.scenario = scenario
        now = int(time.time())
        self.phones: dict[str, FakePhone] = {}
        for i, d in enumerate(fleet):
            dev = {"udid": d["udid"], "name": d.get("name", "iPhone"), "product_type": d.get("product_type"),
                   "model_name": d.get("model_name"), "ios": d.get("ios"), "build": d.get("build"),
                   "connection": "USB", "developer_mode": True, "ddi_mounted": True, "paired": True,
                   "serial": d.get("serial"), "timezone": d.get("timezone"),
                   "first_seen": now - 3600 + i, "last_seen": now,
                   "farm_handle": d.get("farm_handle")}
            self.phones[dev["udid"]] = FakePhone(self, dev, i)
        if scenario == "empty":
            for p in self.phones.values():
                p.connected = False
        if scenario == "snapshot" and len(self.phones) >= 4:
            list(self.phones.values())[3].connected = False
        self.my_loc: Optional[dict] = None
        self.stop = asyncio.Event()
        self.exit_code = 0
        self.inflight: set[asyncio.Task] = set()

    def emit(self, obj: dict) -> None:
        self.out.send(obj)

    def reply(self, rid: Any, result: dict) -> None:
        self.emit({"id": rid, "ok": True, "result": result})

    def reply_error(self, rid: Any, code: str, message: str, **extra: Any) -> None:
        err = {"code": code, "message": message}
        err.update(extra)
        self.emit({"id": rid, "ok": False, "error": err})

    def device_list(self) -> list[dict]:
        out = []
        for p in self.phones.values():
            if p.connected:
                d = dict(p.device)
                d["last_seen"] = int(time.time())
                out.append(d)
        return out

    def emit_devices(self) -> None:
        self.emit({"event": "devices", "devices": self.device_list()})

    async def run(self) -> int:
        self.emit({"event": "hello", "engine_version": ENGINE_VERSION, "pid": os.getpid()})
        self.emit_devices()
        log(f"mock hub up: scenario={self.scenario}, {len(self.device_list())} phones")
        bg = []
        if self.scenario == "flaky":
            bg.append(asyncio.create_task(self.hotplug_loop()))
        try:
            async for line in read_lines(0):
                try:
                    req = json.loads(line)
                except json.JSONDecodeError:
                    self.emit({"event": "log", "level": "warn", "message": f"bad JSON on stdin: {line[:80]!r}"})
                    continue
                self.inflight.add(asyncio.create_task(self.handle(req)))
                self.inflight = {t for t in self.inflight if not t.done()}
                if self.stop.is_set():
                    break
            if not self.stop.is_set():
                log("stdin closed — draining in-flight requests, then exiting")
                pending = [t for t in self.inflight if not t.done()]
                if pending:
                    await asyncio.wait(pending, timeout=5)
        finally:
            for t in bg:
                t.cancel()
        return self.exit_code

    async def hotplug_loop(self) -> None:
        phones = list(self.phones.values())
        if len(phones) < 4:
            return
        p = phones[3]
        while True:
            await asyncio.sleep(25)
            p.unplug()
            self.emit_devices()
            self.emit({"event": "log", "level": "info", "udid": p.udid, "message": "device left usbmux"})
            await asyncio.sleep(20)
            p.plug()
            self.emit_devices()
            self.emit({"event": "log", "level": "info", "udid": p.udid, "message": "device back on usbmux"})

    async def handle(self, req: dict) -> None:
        rid = req.get("id")
        cmd = req.get("cmd")
        try:
            fn = getattr(self, f"cmd_{cmd}", None)
            if fn is None:
                self.reply_error(rid, "unknown_command", f"unknown command {cmd!r}")
                return
            result = await fn(req)
            if result is not None:
                self.reply(rid, result)
        except ProxyParseError as e:
            self.reply_error(rid, "parse_error", str(e))
        except Exception as e:  # pragma: no cover
            self.reply_error(rid, "internal_error", f"{type(e).__name__}: {e}")

    # ---- commands
    async def cmd_hello(self, req: dict) -> dict:
        return {"engine_version": ENGINE_VERSION, "python": ".".join(map(str, sys.version_info[:3])),
                "pymobiledevice3": "10.7.3 (mock)", "pid": os.getpid(),
                "capabilities": ["userspace_tunnel", "mock"]}

    async def cmd_ping(self, req: dict) -> dict:
        return {"pong": True, "ts": time.time()}

    async def cmd_list_devices(self, req: dict) -> dict:
        return {"devices": self.device_list()}

    def _target(self, t: Any) -> Optional[dict]:
        if t is None:
            return None
        if not isinstance(t, dict) or "lat" not in t or "lon" not in t:
            raise ValueError("target must be {lat, lon} or null")
        lat, lon = float(t["lat"]), float(t["lon"])
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("coordinates out of range")
        return {"lat": lat, "lon": lon}

    def _phone(self, udid: Any) -> FakePhone:
        if not isinstance(udid, str) or not udid:
            raise ValueError("udid required")
        p = self.phones.get(udid)
        if p is None:
            # unknown UDID: remember it as a never-connected phone
            dev = {"udid": udid, "name": "iPhone", "product_type": None, "model_name": None, "ios": None,
                   "build": None, "connection": "USB", "developer_mode": None, "ddi_mounted": None,
                   "paired": False, "serial": None, "timezone": None,
                   "first_seen": int(time.time()), "last_seen": int(time.time()), "farm_handle": None}
            p = FakePhone(self, dev, len(self.phones))
            p.connected = False
            self.phones[udid] = p
        return p

    async def cmd_set_desired(self, req: dict) -> dict:
        try:
            p = self._phone(req.get("udid"))
            t = self._target(req.get("target"))
        except ValueError as e:
            self.reply_error(req.get("id"), "bad_request", str(e))
            return None  # type: ignore[return-value]
        p.set_target(t)
        return {"accepted": True}

    async def cmd_set_all(self, req: dict) -> dict:
        targets = req.get("targets")
        if not isinstance(targets, dict):
            self.reply_error(req.get("id"), "bad_request", "targets must be an object")
            return None  # type: ignore[return-value]
        accepted = []
        for p in self.phones.values():
            if p.udid not in targets and p.target is not None:
                p.set_target(None)
        if self.scenario == "snapshot":
            await asyncio.sleep(0.2)
            phones = list(self.phones.values())
            for udid, t in targets.items():
                p = self._phone(udid)
                p.target = self._target(t)
                accepted.append(udid)
                if p.target is None:
                    continue
                if p in phones and phones.index(p) == 2:
                    p.pid = 40017
                    p.applied = {"lat": p.target["lat"], "lon": p.target["lon"], "at": int(time.time()) - 90}
                    p.emit("reconnecting", attempt=3, retry_in=5, message="tunnel dropped")
                elif not p.connected:
                    p.emit("disconnected", message="phone not on USB; target remembered")
                else:
                    p.pid = 40000 + p.index * 7
                    p.applied = {"lat": p.target["lat"], "lon": p.target["lon"], "at": int(time.time()) - 600}
                    p.emit("simulating")
            return {"accepted": accepted}
        for udid, t in targets.items():
            try:
                p = self._phone(udid)
                p.set_target(self._target(t))
                accepted.append(udid)
            except ValueError as e:
                self.reply_error(req.get("id"), "bad_request", f"{udid}: {e}")
                return None  # type: ignore[return-value]
        return {"accepted": accepted}

    async def cmd_release(self, req: dict) -> dict:
        p = self._phone(req.get("udid"))
        p.set_target(None)
        return {"accepted": True}

    async def cmd_release_all(self, req: dict) -> dict:
        accepted = []
        for p in self.phones.values():
            if p.target is not None or p.pid is not None:
                p.set_target(None)
                accepted.append(p.udid)
        return {"accepted": accepted}

    async def cmd_parse_proxy(self, req: dict) -> dict:
        return parse_proxy_authoritative(str(req.get("proxy", "")))

    async def cmd_geolocate_proxy(self, req: dict) -> dict:
        rid = req.get("id")
        text = str(req.get("proxy", ""))
        proxy = parse_proxy_authoritative(text)
        host = proxy["host"].lower()

        def progress(stage: str) -> None:
            self.emit({"event": "geo_progress", "id": rid, "stage": stage})

        progress("connecting")
        await asyncio.sleep(0.4)
        if "bad" in host or (self.scenario == "flaky" and hashlib.sha1(text.encode()).digest()[6] % 5 == 0):
            await asyncio.sleep(0.6)
            progress("fallback_gateway")
            await asyncio.sleep(0.5)
            fallback = geo_for_proxy(host, via_proxy=False, note="gateway IP — may differ from exit IP")
            self.reply_error(rid, "proxy_unreachable",
                             f"could not connect through {proxy['normalized']}: connection refused",
                             fallback=fallback)
            return None  # type: ignore[return-value]
        progress("querying ip-api.com")
        await asyncio.sleep(0.6)
        if "fail" in host:
            progress("querying ipwho.is")
            await asyncio.sleep(0.5)
            progress("querying ipinfo.io")
            await asyncio.sleep(0.5)
            self.reply_error(rid, "geo_failed", "all providers failed: ip-api.com timed out; ipwho.is HTTP 429; ipinfo.io timed out")
            return None  # type: ignore[return-value]
        await asyncio.sleep(0.5)
        return geo_for_proxy(text)

    async def cmd_my_location(self, req: dict) -> dict:
        if self.my_loc is None:
            await asyncio.sleep(0.3 if self.scenario != "snapshot" else 0.05)
            self.my_loc = dict(MAC_LOCATION, checked_at=int(time.time()), elapsed_ms=312)
        return self.my_loc

    async def cmd_worker_restart(self, req: dict) -> dict:
        p = self._phone(req.get("udid"))
        p.cancel()
        p.pid = None
        p.restarts += 1
        p.last_error = None
        if p.target is not None and p.connected:
            p.task = asyncio.create_task(p._apply(self.scenario == "snapshot"))
        return {"accepted": True}

    async def cmd_worker_status(self, req: dict) -> dict:
        return {"workers": {u: p.status() for u, p in self.phones.items() if p.target is not None or p.pid}}

    async def cmd_shutdown(self, req: dict) -> None:
        self.reply(req.get("id"), {"accepted": True})
        for p in self.phones.values():
            if p.pid is not None:
                p.cancel()
                p.applied = None
                p.emit("released")
        log("shutdown — bye")
        self.stop.set()
        await asyncio.sleep(0.05)
        os._exit(0)
        return None


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Only Social GPS mock engine")
    ap.add_argument("--devices", help="JSON file with a list of fake devices")
    ap.add_argument("--scenario", default=os.environ.get("OSGPS_MOCK_SCENARIO", "normal"),
                    choices=["normal", "empty", "flaky", "snapshot"])
    args = ap.parse_args(argv)
    fleet = DEFAULT_FLEET
    if args.devices:
        with open(args.devices, "r", encoding="utf-8") as f:
            data = json.load(f)
        fleet = data["devices"] if isinstance(data, dict) and "devices" in data else data
    hub = MockHub(fleet, args.scenario)
    try:
        return asyncio.run(hub.run())
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
