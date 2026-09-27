#!/opt/homebrew/bin/python3
"""Only Social GPS engine.

    python3 osgps_engine.py                 # hub: NDJSON on stdin/stdout, see PROTOCOL.md
    python3 osgps_engine.py --worker UDID   # worker: one userspace tunnel + DVT LocationSimulation

The hub discovers USB phones (usbmux poll every 2 s), keeps the desired-target map, runs one
worker subprocess per phone that has a target, forwards commands, aggregates state, and does
proxy geolocation through curl. Workers hold the DVT LocationSimulation channel open (the spoof
lives only while that channel is open), reconnect with backoff, and re-apply the target.

stdout is protocol only (every line is JSON). Logs go to stderr and
~/Library/Logs/OnlySocialGPS/engine.log. Standard library + pymobiledevice3 only.

Environment knobs (all optional):
    OSGPS_DEBUG=1          debug-level logging (including pymobiledevice3 internals)
    OSGPS_NO_USB=1         hub: skip USB discovery entirely (used by the hardware-free tests)
    OSGPS_RSD_FALLBACK=0   disable the go-ios `ios tunnel ls` RSD fallback (default: on when `ios` exists)
    OSGPS_FORCE_GO_IOS=1   worker: skip the userspace tunnel and use the go-ios fallback (test hook)
    OSGPS_SKIP_DDI=1       worker: skip the developer-disk-image / Developer Mode pre-check
    OSGPS_KEEPALIVE=30     worker: seconds between re-asserting the pin (liveness probe)
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import logging
import os
import platform
import shutil
import signal
import sys
import threading
import time
from logging.handlers import RotatingFileHandler
from typing import Any, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import proxy_geo  # noqa: E402

ENGINE_VERSION = "1.0"
LOG_DIR = os.path.expanduser("~/Library/Logs/OnlySocialGPS")
LOG_FILE = os.path.join(LOG_DIR, "engine.log")
DEBUG = os.environ.get("OSGPS_DEBUG") == "1"

USB_POLL_INTERVAL = 2.0
HEARTBEAT_INTERVAL = 5.0
HEARTBEAT_MISSES = 3
WORKER_BACKOFF = [1, 2, 5, 10, 20, 30]
ERROR_RETRY = 60
KEEPALIVE_INTERVAL = float(os.environ.get("OSGPS_KEEPALIVE", "30"))  # worker re-asserts the target this often (liveness probe)
FARM_NAMES_FILE = "/Users/james/Desktop/iphone-bot copy/.devicenames.json"  # read-only, optional

GO_IOS = shutil.which("ios") or ("/opt/homebrew/bin/ios" if os.path.exists("/opt/homebrew/bin/ios") else None)

MARKETING_NAMES = {
    "iPhone11,8": "iPhone XR", "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
    "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
    "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone12,8": "iPhone SE (2nd gen)",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
    "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro",
    "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3rd gen)",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e",
    "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17",
    "iPhone18,4": "iPhone Air",
}


def marketing_name(product_type: Optional[str]) -> Optional[str]:
    if not product_type:
        return None
    if product_type in MARKETING_NAMES:
        return MARKETING_NAMES[product_type]
    if product_type.startswith("iPhone18,"):
        return "iPhone 17 family"
    return product_type


# ======================================================================================
# Logging (stderr + rotating file; passwords redacted everywhere)
# ======================================================================================
class RedactFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:
            msg = str(record.msg)
        record.msg = proxy_geo.redact(msg)
        record.args = ()
        return True


def setup_logging(role: str, udid: Optional[str] = None) -> None:
    root = logging.getLogger()
    root.setLevel(logging.DEBUG if DEBUG else logging.INFO)
    tag = f"{role}" + (f" {udid[-6:]}" if udid else "")
    fmt = logging.Formatter(f"%(asctime)s [{tag}] %(levelname)s %(name)s: %(message)s")
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(fmt)
    sh.addFilter(RedactFilter())
    root.addHandler(sh)
    if role == "hub":
        try:
            os.makedirs(LOG_DIR, exist_ok=True)
            fh = RotatingFileHandler(LOG_FILE, maxBytes=2 * 1024 * 1024, backupCount=3, encoding="utf-8")
            fh.setFormatter(fmt)
            fh.addFilter(RedactFilter())
            root.addHandler(fh)
        except Exception as e:  # pragma: no cover
            root.warning("cannot open log file %s: %s", LOG_FILE, e)
    for noisy in ("pymobiledevice3", "pmd_pytcp", "asyncio", "hpack", "httpx", "h2", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.DEBUG if DEBUG else logging.WARNING)


log = logging.getLogger("osgps")


# ======================================================================================
# Protocol output: keep the real stdout private, point fd 1 at stderr for stray prints
# ======================================================================================
class ProtoOut:
    def __init__(self) -> None:
        fd = os.dup(1)
        self._f = os.fdopen(fd, "wb", buffering=0)
        try:
            os.dup2(2, 1)
        except OSError:
            pass
        self.broken = False
        self.on_broken: Optional[Any] = None

    def send(self, obj: dict) -> None:
        if self.broken:
            return
        try:
            data = json.dumps(obj, separators=(",", ":"), ensure_ascii=False, default=str).encode("utf-8")
            self._f.write(data + b"\n")
        except (BrokenPipeError, OSError):
            self.broken = True
            if self.on_broken:
                self.on_broken()

    def flush(self) -> None:
        with contextlib.suppress(Exception):
            self._f.flush()


async def read_ndjson_lines(fd: int):
    """Yield stripped non-empty lines from fd until EOF.

    A daemon reader thread feeds an asyncio queue, so this works identically for pipes, TTYs,
    regular files and /dev/null (kqueue never reports /dev/null readable, so connect_read_pipe
    would hang there).
    """
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
        except Exception as e:  # pragma: no cover
            with contextlib.suppress(Exception):
                log.warning("stdin read error: %s", e)
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


def pmd3_version() -> Optional[str]:
    try:
        import importlib.metadata as md
        return md.version("pymobiledevice3")
    except Exception:
        return None


def farm_handles() -> dict[str, str]:
    try:
        with open(FARM_NAMES_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return {str(k): str(v) for k, v in data.items()} if isinstance(data, dict) else {}
    except Exception:
        return {}


def describe_exc(e: BaseException) -> str:
    text = proxy_geo.redact(str(e)).strip()
    return f"{type(e).__name__}: {text}" if text else type(e).__name__


def valid_target(t: Any) -> Optional[dict]:
    if t is None:
        return None
    if not isinstance(t, dict):
        raise ValueError("target must be an object with lat/lon or null")
    try:
        lat = float(t["lat"])
        lon = float(t["lon"])
    except (KeyError, TypeError, ValueError):
        raise ValueError("target needs numeric lat and lon") from None
    if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
        raise ValueError("lat must be within ±90 and lon within ±180")
    return {"lat": lat, "lon": lon}


# ======================================================================================
# HUB
# ======================================================================================
class ProtocolError(Exception):
    def __init__(self, code: str, message: str, **extra: Any):
        super().__init__(message)
        self.code = code
        self.extra = extra


class WorkerHandle:
    def __init__(self, udid: str):
        self.udid = udid
        self.proc: Optional[asyncio.subprocess.Process] = None
        self.state = "connecting"
        self.target: Optional[dict] = None
        self.applied: Optional[dict] = None
        self.message: Optional[str] = None
        self.restarts = 0
        self.last_error: Optional[str] = None
        self.last_heartbeat: Optional[float] = None
        self.started_at = 0.0
        self.stop_requested = False
        self.release_requested = False
        self.consecutive_failures = 0
        self.tasks: list[asyncio.Task] = []
        self.exited = asyncio.Event()

    @property
    def pid(self) -> Optional[int]:
        return self.proc.pid if self.proc is not None and self.proc.returncode is None else None

    @property
    def alive(self) -> bool:
        return self.proc is not None and self.proc.returncode is None

    def status(self) -> dict:
        return {
            "pid": self.pid, "state": self.state, "target": self.target, "applied": self.applied,
            "restarts": self.restarts, "last_error": self.last_error,
            "last_heartbeat": int(self.last_heartbeat) if self.last_heartbeat else None,
        }


class EventLogHandler(logging.Handler):
    """Forward the hub's own INFO+ log records to the app as `log` events."""

    def __init__(self, hub: "Hub"):
        super().__init__(logging.INFO)
        self.hub = hub

    def emit(self, record: logging.LogRecord) -> None:
        if not record.name.startswith("osgps"):
            return
        if record.name.startswith("osgps.worker.") and record.levelno < logging.WARNING:
            return
        level = {logging.DEBUG: "debug", logging.INFO: "info", logging.WARNING: "warn"}.get(record.levelno, "error")
        ev = {"event": "log", "level": level, "message": proxy_geo.redact(record.getMessage())}
        udid = getattr(record, "udid", None)
        if udid:
            ev["udid"] = udid
        self.hub.out.send(ev)


class Hub:
    def __init__(self, out: ProtoOut):
        self.out = out
        self.devices: dict[str, dict] = {}
        self.desired: dict[str, Optional[dict]] = {}
        self.workers: dict[str, WorkerHandle] = {}
        self.locks: dict[str, asyncio.Lock] = {}
        self.respawn_tasks: dict[str, asyncio.Task] = {}
        self.pending_tasks: set[asyncio.Task] = set()
        self.inflight: dict[asyncio.Task, Any] = {}   # handle() task -> request id, replied on shutdown
        self.first_scan = asyncio.Event()
        self.shutting_down = False
        self.shutdown_done = asyncio.Event()
        self.exit_code = 0
        self.usb_disabled = os.environ.get("OSGPS_NO_USB") == "1"
        self.rsd_fallback = os.environ.get("OSGPS_RSD_FALLBACK", "1") != "0" and GO_IOS is not None
        self.my_loc: Optional[dict] = None
        self.my_loc_task: Optional[asyncio.Task] = None
        self.handles: dict[str, str] = {}
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        # The farm's name file lives on the Desktop. When the hub is a child of an app launched by
        # LaunchServices, the first open(2) there blocks on macOS's "access your Desktop folder"
        # consent dialog — so it is read on a daemon thread and never holds up hello / discovery.
        threading.Thread(target=self._load_farm_handles, name="farm-handles", daemon=True).start()
        self._usb_error_logged = 0.0
        out.on_broken = lambda: self.spawn(self.shutdown("stdout closed"))

    # ------------------------------------------------------------------ plumbing
    def _load_farm_handles(self) -> None:
        names = farm_handles()
        if not names:
            return

        def apply() -> None:
            self.handles = names
            changed = False
            for udid, d in self.devices.items():
                if udid in names and d.get("farm_handle") != names[udid]:
                    d["farm_handle"] = names[udid]
                    changed = True
            if changed and not self.shutting_down:
                self.emit_devices()

        loop = self.loop
        if loop is not None and not loop.is_closed():
            with contextlib.suppress(RuntimeError):
                loop.call_soon_threadsafe(apply)
        else:
            self.handles = names  # loop not up yet: no devices exist, plain assignment is enough

    def emit(self, obj: dict) -> None:
        self.out.send(obj)

    def spawn(self, coro) -> asyncio.Task:
        t = asyncio.get_running_loop().create_task(coro)
        self.pending_tasks.add(t)
        t.add_done_callback(self.pending_tasks.discard)
        return t

    def lock(self, udid: str) -> asyncio.Lock:
        return self.locks.setdefault(udid, asyncio.Lock())

    def reply(self, req_id: Any, result: dict) -> None:
        self.emit({"id": req_id, "ok": True, "result": result})

    def reply_error(self, req_id: Any, code: str, message: str, **extra: Any) -> None:
        err = {"code": code, "message": proxy_geo.redact(message)}
        err.update(extra)
        self.emit({"id": req_id, "ok": False, "error": err})

    def emit_state(self, udid: str, state: str, **fields: Any) -> None:
        ev = {"event": "device_state", "udid": udid, "state": state,
              "target": fields.pop("target", self.desired.get(udid)),
              "applied": fields.pop("applied", None)}
        for k, v in fields.items():
            if v is not None:
                ev[k] = v
        self.emit(ev)

    def emit_devices(self) -> None:
        self.emit({"event": "devices", "devices": self.device_list()})

    def device_list(self) -> list[dict]:
        return [dict(d) for d in self.devices.values()]

    # ------------------------------------------------------------------ main loop
    async def run(self) -> int:
        loop = asyncio.get_running_loop()
        self.loop = loop
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with contextlib.suppress(Exception):
                loop.add_signal_handler(sig, lambda s=sig: self.spawn(self.shutdown(f"signal {s.name}")))
        self.emit({"event": "hello", "engine_version": ENGINE_VERSION, "pid": os.getpid()})
        log.info("hub started pid=%s python=%s pymobiledevice3=%s go-ios=%s", os.getpid(),
                 platform.python_version(), pmd3_version(), GO_IOS)
        self.spawn(self.discovery_loop())
        self.spawn(self.watchdog_loop())
        stdin_task = self.spawn(self.stdin_loop())
        await self.shutdown_done.wait()
        stdin_task.cancel()
        return self.exit_code

    async def stdin_loop(self) -> None:
        try:
            async for line in read_ndjson_lines(0):
                if self.shutting_down:
                    break
                try:
                    req = json.loads(line)
                except ValueError:
                    log.error("stdin: not JSON: %r", line[:200])
                    continue
                if not isinstance(req, dict):
                    log.error("stdin: not an object: %r", line[:200])
                    continue
                self.spawn(self.handle(req))
        finally:
            if not self.shutting_down:
                self.spawn(self.shutdown("stdin EOF"))

    async def handle(self, req: dict) -> None:
        req_id = req.get("id")
        cmd = req.get("cmd")
        handler = getattr(self, f"cmd_{cmd}", None) if isinstance(cmd, str) else None
        if handler is None:
            self.reply_error(req_id, "unknown_command", f"unknown cmd {cmd!r}")
            return
        task = asyncio.current_task()
        if task is not None:
            self.inflight[task] = req_id
        try:
            result = await handler(req)
            if result is not None:
                self.reply(req_id, result)
        except ProtocolError as e:
            self.reply_error(req_id, e.code, str(e), **e.extra)
        except Exception as e:
            log.exception("command %s failed", cmd)
            self.reply_error(req_id, "internal_error", f"{type(e).__name__}: {e}")
        finally:
            if task is not None:
                self.inflight.pop(task, None)

    # ------------------------------------------------------------------ commands
    async def cmd_hello(self, req: dict) -> dict:
        caps = []
        if pmd3_version():
            caps.append("userspace_tunnel")
        if self.rsd_fallback:
            caps.append("go_ios_rsd_fallback")
        log.info("hello from app_version=%s", req.get("app_version"))
        return {"engine_version": ENGINE_VERSION, "python": platform.python_version(),
                "pymobiledevice3": pmd3_version(), "pid": os.getpid(), "capabilities": caps}

    async def cmd_list_devices(self, req: dict) -> dict:
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(self.first_scan.wait(), timeout=12)
        return {"devices": self.device_list()}

    async def cmd_set_desired(self, req: dict) -> dict:
        udid = req.get("udid")
        if not isinstance(udid, str) or not udid:
            raise ProtocolError("bad_request", "udid required")
        try:
            target = valid_target(req.get("target"))
        except ValueError as e:
            raise ProtocolError("bad_request", str(e)) from None
        await self.apply_desired(udid, target)
        return {"accepted": True}

    async def cmd_set_all(self, req: dict) -> dict:
        targets = req.get("targets")
        if not isinstance(targets, dict):
            raise ProtocolError("bad_request", "targets must be an object")
        parsed: dict[str, Optional[dict]] = {}
        for udid, t in targets.items():
            try:
                parsed[str(udid)] = valid_target(t)
            except ValueError as e:
                raise ProtocolError("bad_request", f"{udid}: {e}") from None
        accepted = []
        for udid in list(self.desired):
            if udid not in parsed and self.desired[udid] is not None:
                await self.apply_desired(udid, None)
        for udid, t in parsed.items():
            await self.apply_desired(udid, t)
            accepted.append(udid)
        return {"accepted": accepted}

    async def cmd_release(self, req: dict) -> dict:
        udid = req.get("udid")
        if not isinstance(udid, str) or not udid:
            raise ProtocolError("bad_request", "udid required")
        await self.apply_desired(udid, None)
        return {"accepted": True}

    async def cmd_release_all(self, req: dict) -> dict:
        accepted = []
        for udid in list(set(self.desired) | set(self.workers)):
            if self.desired.get(udid) is not None or udid in self.workers:
                await self.apply_desired(udid, None)
                accepted.append(udid)
        return {"accepted": accepted}

    async def cmd_parse_proxy(self, req: dict) -> dict:
        try:
            return proxy_geo.parse_proxy(str(req.get("proxy", "")))
        except proxy_geo.ProxyParseError as e:
            raise ProtocolError("parse_error", str(e)) from None

    async def cmd_geolocate_proxy(self, req: dict) -> dict:
        req_id = req.get("id")
        try:
            proxy = proxy_geo.parse_proxy(str(req.get("proxy", "")))
        except proxy_geo.ProxyParseError as e:
            raise ProtocolError("parse_error", str(e)) from None

        def progress(stage: str) -> None:
            self.emit({"event": "geo_progress", "id": req_id, "stage": stage})

        log.info("geolocate %s", proxy["normalized"])
        try:
            result = await proxy_geo.geolocate_via_proxy(proxy, progress)
        except proxy_geo.ProxyUnreachable as e:
            extra: dict[str, Any] = {"fallback": e.fallback}
            if e.fallback_error:
                extra["fallback_error"] = e.fallback_error
            raise ProtocolError("proxy_unreachable", f"could not connect through {proxy['normalized']}: {e}",
                                **extra) from None
        except proxy_geo.GeoFailed as e:
            raise ProtocolError("geo_failed", str(e)) from None
        log.info("geolocate %s -> %s, %s (%s) via %s", proxy["normalized"], result.get("city"),
                 result.get("country"), result.get("ip"), result.get("provider"))
        return result

    async def cmd_my_location(self, req: dict) -> dict:
        now = time.time()
        if self.my_loc and now - self.my_loc["checked_at"] < 600:
            return self.my_loc
        if self.my_loc_task is None or self.my_loc_task.done():
            self.my_loc_task = self.spawn(proxy_geo.geolocate_ip(None))
        try:
            self.my_loc = await asyncio.shield(self.my_loc_task)
        except proxy_geo.GeoFailed as e:
            raise ProtocolError("geo_failed", str(e)) from None
        return self.my_loc

    async def cmd_worker_restart(self, req: dict) -> dict:
        udid = req.get("udid")
        if not isinstance(udid, str) or not udid:
            raise ProtocolError("bad_request", "udid required")
        w = self.workers.get(udid)
        if w is not None:
            await self.stop_worker(udid, reason="restart requested", keep_handle=True)
            w.consecutive_failures = 0
            w.last_error = None
        self.cancel_respawn(udid)
        if self.desired.get(udid) is not None:
            await self.ensure_worker(udid, restart=True)
        elif self.workers.get(udid) is w:
            self.workers.pop(udid, None)
        return {"accepted": True}

    async def cmd_worker_status(self, req: dict) -> dict:
        out: dict[str, dict] = {}
        for udid in set(self.workers) | {u for u, t in self.desired.items() if t is not None}:
            w = self.workers.get(udid)
            if w is not None:
                out[udid] = w.status()
            else:
                out[udid] = {"pid": None, "state": "disconnected" if udid not in self.devices else "idle",
                             "target": self.desired.get(udid), "applied": None, "restarts": 0,
                             "last_error": None, "last_heartbeat": None}
        return {"workers": out}

    async def cmd_shutdown(self, req: dict) -> None:
        self.reply(req.get("id"), {"accepted": True})
        await self.shutdown("shutdown command")

    async def cmd_ping(self, req: dict) -> dict:
        return {"pong": True, "ts": time.time()}

    # ------------------------------------------------------------------ desired state
    async def apply_desired(self, udid: str, target: Optional[dict]) -> None:
        if target is None:
            had = self.desired.get(udid) is not None or udid in self.workers
            self.desired[udid] = None
            self.cancel_respawn(udid)
            w = self.workers.get(udid)
            if w is not None and w.alive:
                w.release_requested = True
                w.stop_requested = True
                w.target = None
                log.info("release: clearing simulation", extra={"udid": udid})
                await self.send_worker(w, {"cmd": "clear"})
                await self.send_worker(w, {"cmd": "quit"})
                self.spawn(self.enforce_exit(w, grace=8))
            elif had:
                self.emit_state(udid, "idle" if udid in self.devices else "disconnected", target=None)
            return

        self.desired[udid] = target
        if not self.first_scan.is_set():
            # set_all at app launch usually beats the first USB scan; don't call the phone unplugged yet
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(self.first_scan.wait(), timeout=8)
            if self.desired.get(udid) is not target:
                return  # superseded meanwhile
        w = self.workers.get(udid)
        if udid not in self.devices:
            log.info("target set for unplugged phone; will apply when it returns", extra={"udid": udid})
            self.emit_state(udid, "disconnected", target=target, message="phone not on USB; will apply when it returns")
            return
        if w is not None and w.alive and not w.stop_requested:
            w.target = target
            await self.send_worker(w, {"cmd": "set", "lat": target["lat"], "lon": target["lon"]})
            return
        await self.ensure_worker(udid)

    # ------------------------------------------------------------------ workers
    async def ensure_worker(self, udid: str, restart: bool = False) -> None:
        async with self.lock(udid):
            target = self.desired.get(udid)
            if target is None or udid not in self.devices or self.shutting_down:
                return
            w = self.workers.get(udid)
            if w is not None and w.alive and not w.stop_requested:
                w.target = target
                await self.send_worker(w, {"cmd": "set", "lat": target["lat"], "lon": target["lon"]})
                return
            if w is not None and w.alive:
                await self.enforce_exit(w, grace=3)
            prev = w
            w = WorkerHandle(udid)
            if prev is not None:
                w.restarts = prev.restarts + (1 if restart or not prev.release_requested else 0)
                w.consecutive_failures = prev.consecutive_failures
            w.target = target
            env = dict(os.environ)
            env["PYTHONUNBUFFERED"] = "1"
            env["OSGPS_RSD_FALLBACK"] = "1" if self.rsd_fallback else "0"
            try:
                w.proc = await asyncio.create_subprocess_exec(
                    sys.executable, os.path.abspath(__file__), "--worker", udid,
                    stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE, env=env,
                )
            except Exception as e:
                log.error("cannot spawn worker: %s", e, extra={"udid": udid})
                w.last_error = f"spawn failed: {e}"
                self.workers[udid] = w
                self.emit_state(udid, "error", target=target, message=w.last_error, retry_in=ERROR_RETRY)
                self.schedule_respawn(udid, ERROR_RETRY)
                return
            w.started_at = time.time()
            w.state = "connecting"
            self.workers[udid] = w
            log.info("worker spawned pid=%s restarts=%s", w.proc.pid, w.restarts, extra={"udid": udid})
            self.emit_state(udid, "connecting", target=target, attempt=1)
            w.tasks.append(self.spawn(self.pump_worker_stdout(w)))
            w.tasks.append(self.spawn(self.pump_worker_stderr(w)))
            w.tasks.append(self.spawn(self.wait_worker(w)))
            await self.send_worker(w, {"cmd": "set", "lat": target["lat"], "lon": target["lon"]})

    async def send_worker(self, w: WorkerHandle, obj: dict) -> None:
        if not w.alive or w.proc is None or w.proc.stdin is None:
            return
        try:
            w.proc.stdin.write(json.dumps(obj, separators=(",", ":")).encode() + b"\n")
            await w.proc.stdin.drain()
        except (BrokenPipeError, ConnectionResetError, OSError) as e:
            log.warning("cannot write to worker pid=%s: %s", w.pid, e, extra={"udid": w.udid})

    async def pump_worker_stdout(self, w: WorkerHandle) -> None:
        assert w.proc is not None and w.proc.stdout is not None
        udid = w.udid
        while True:
            try:
                line = await w.proc.stdout.readline()
            except (ValueError, asyncio.LimitOverrunError):
                continue
            except Exception:
                return
            if not line:
                return
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                log.warning("worker stdout not JSON: %r", line[:200], extra={"udid": udid})
                continue
            kind = ev.get("event")
            if kind == "heartbeat":
                w.last_heartbeat = time.time()
            elif kind == "state":
                w.last_heartbeat = time.time()
                w.state = ev.get("state", w.state)
                # the hub's desired map is the authority for `target` (the worker's first events may
                # predate its `set` command)
                w.target = self.desired.get(udid) if w.state != "released" else None
                w.applied = ev.get("applied")
                w.message = ev.get("message")
                if w.state == "simulating":
                    w.consecutive_failures = 0
                    w.last_error = None
                elif w.state in ("reconnecting", "error") and ev.get("message"):
                    w.last_error = ev.get("message")
                if self.workers.get(udid) is w:
                    fields = {k: ev.get(k) for k in ("message", "attempt", "retry_in") if ev.get(k) is not None}
                    self.emit_state(udid, w.state, target=w.target, applied=w.applied, **fields)
            elif kind == "log":
                lvl = {"debug": logging.DEBUG, "info": logging.INFO, "warn": logging.WARNING}.get(
                    ev.get("level"), logging.ERROR)
                log.log(lvl, "%s", ev.get("message"), extra={"udid": udid})

    async def pump_worker_stderr(self, w: WorkerHandle) -> None:
        assert w.proc is not None and w.proc.stderr is not None
        wlog = logging.getLogger(f"osgps.worker.{w.udid[-6:]}")
        while True:
            try:
                line = await w.proc.stderr.readline()
            except (ValueError, asyncio.LimitOverrunError):
                continue
            except Exception:
                return
            if not line:
                return
            text = line.decode("utf-8", "replace").rstrip()
            if text:
                level = logging.WARNING if (" ERROR " in text or " CRITICAL " in text or "Traceback" in text) else logging.INFO
                wlog.log(level, "%s", text, extra={"udid": w.udid})

    async def wait_worker(self, w: WorkerHandle) -> None:
        assert w.proc is not None
        rc = await w.proc.wait()  # reaps the child
        w.exited.set()
        udid = w.udid
        uptime = time.time() - w.started_at
        log.info("worker pid=%s exited rc=%s after %.1fs (stop_requested=%s)", w.proc.pid, rc, uptime,
                 w.stop_requested, extra={"udid": udid})
        if self.workers.get(udid) is not w:
            return
        if w.stop_requested:
            if w.release_requested:
                del self.workers[udid]
                if not self.shutting_down:
                    self.emit_state(udid, "idle" if udid in self.devices else "disconnected", target=None)
            return
        # unexpected exit
        w.last_error = w.last_error or f"worker exited with code {rc}"
        if uptime > 120:
            w.consecutive_failures = 0
        w.consecutive_failures += 1
        if self.shutting_down or self.desired.get(udid) is None or udid not in self.devices:
            return
        n = w.consecutive_failures
        if n <= len(WORKER_BACKOFF):
            delay = WORKER_BACKOFF[n - 1]
            self.emit_state(udid, "reconnecting", target=self.desired.get(udid), message=w.last_error,
                            attempt=n, retry_in=delay)
        else:
            delay = ERROR_RETRY
            self.emit_state(udid, "error", target=self.desired.get(udid), message=w.last_error,
                            attempt=n, retry_in=delay)
        log.warning("worker died (%s); respawn in %ss (failure %s)", w.last_error, delay, n, extra={"udid": udid})
        self.schedule_respawn(udid, delay)

    def schedule_respawn(self, udid: str, delay: float) -> None:
        self.cancel_respawn(udid)

        async def later() -> None:
            await asyncio.sleep(delay)
            self.respawn_tasks.pop(udid, None)
            await self.ensure_worker(udid, restart=True)

        self.respawn_tasks[udid] = self.spawn(later())

    def cancel_respawn(self, udid: str) -> None:
        t = self.respawn_tasks.pop(udid, None)
        if t is not None:
            t.cancel()

    async def enforce_exit(self, w: WorkerHandle, grace: float) -> None:
        """Wait `grace` s for a worker to exit on its own, then SIGTERM (3 s), then SIGKILL."""
        if not w.alive:
            return
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(w.exited.wait(), timeout=grace)
        if w.alive:
            log.warning("worker pid=%s did not exit in %ss; SIGTERM", w.pid, grace, extra={"udid": w.udid})
            with contextlib.suppress(ProcessLookupError):
                w.proc.terminate()
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(w.exited.wait(), timeout=3)
        if w.alive:
            log.warning("worker pid=%s ignored SIGTERM; SIGKILL", w.pid, extra={"udid": w.udid})
            with contextlib.suppress(ProcessLookupError):
                w.proc.kill()
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(w.exited.wait(), timeout=3)

    async def stop_worker(self, udid: str, reason: str, grace: float = 8, keep_handle: bool = False) -> None:
        w = self.workers.get(udid)
        if w is None:
            return
        w.stop_requested = True
        self.cancel_respawn(udid)
        if w.alive:
            log.info("stopping worker pid=%s (%s)", w.pid, reason, extra={"udid": udid})
            await self.send_worker(w, {"cmd": "quit"})
            await self.enforce_exit(w, grace=grace)
        if self.workers.get(udid) is w and not keep_handle:
            del self.workers[udid]

    async def watchdog_loop(self) -> None:
        while not self.shutting_down:
            await asyncio.sleep(HEARTBEAT_INTERVAL)
            now = time.time()
            for udid, w in list(self.workers.items()):
                if not w.alive or w.stop_requested:
                    continue
                last = w.last_heartbeat or w.started_at
                if now - last > HEARTBEAT_INTERVAL * HEARTBEAT_MISSES + 2:
                    log.warning("worker pid=%s missed %d heartbeats (%.0fs); killing", w.pid, HEARTBEAT_MISSES,
                                now - last, extra={"udid": udid})
                    w.last_error = f"hung: missed {HEARTBEAT_MISSES} heartbeats"
                    with contextlib.suppress(ProcessLookupError):
                        w.proc.kill()

    # ------------------------------------------------------------------ discovery
    async def discovery_loop(self) -> None:
        if self.usb_disabled:
            self.first_scan.set()
            self.emit_devices()
            return
        try:
            from pymobiledevice3 import usbmux
        except Exception as e:
            log.error("pymobiledevice3 unavailable: %s", e)
            self.first_scan.set()
            self.emit_devices()
            return
        while not self.shutting_down:
            try:
                devs = await asyncio.wait_for(usbmux.list_devices(), timeout=5)
            except Exception as e:
                if time.time() - self._usb_error_logged > 60:
                    log.warning("usbmux list_devices failed: %s", e)
                    self._usb_error_logged = time.time()
                devs = []
            present = {d.serial: d for d in devs if getattr(d, "is_usb", False)}
            now = time.time()
            changed = False
            for udid in list(self.devices):
                if udid not in present:
                    await self.on_device_gone(udid)
                    changed = True
            new = [u for u in present if u not in self.devices]
            if new:
                results = await asyncio.gather(*(self.fetch_details(u) for u in new), return_exceptions=True)
                for udid, det in zip(new, results):
                    if isinstance(det, BaseException):
                        det = self.blank_device(udid)
                        det["error"] = f"{type(det).__name__}"
                    if udid in present:
                        self.devices[udid] = det
                        changed = True
            for udid in present:
                if udid in self.devices:
                    d = self.devices[udid]
                    d["last_seen"] = max(int(now), d.get("first_seen") or 0)
            if changed or not self.first_scan.is_set():
                self.emit_devices()
                self.first_scan.set()
            for udid in new:
                if udid in self.devices:
                    await self.on_device_new(udid)
            await asyncio.sleep(USB_POLL_INTERVAL)

    def blank_device(self, udid: str) -> dict:
        now = int(time.time())
        return {
            "udid": udid, "name": None, "product_type": None, "model_name": None, "ios": None, "build": None,
            "connection": "USB", "developer_mode": None, "ddi_mounted": None, "paired": False, "serial": None,
            "timezone": None, "first_seen": now, "last_seen": now, "farm_handle": self.handles.get(udid),
        }

    async def fetch_details(self, udid: str) -> dict:
        det = self.blank_device(udid)
        try:
            from pymobiledevice3.exceptions import NotPairedError, NotTrustedError, PasswordRequiredError
            from pymobiledevice3.lockdown import create_using_usbmux
        except Exception as e:
            det["error"] = f"pymobiledevice3 import failed: {e}"
            return det
        try:
            ld = await asyncio.wait_for(create_using_usbmux(serial=udid, autopair=False), timeout=10)
        except (NotPairedError, NotTrustedError, PasswordRequiredError) as e:
            det["paired"] = False
            det["error"] = f"{type(e).__name__}"
            return det
        except Exception as e:
            det["error"] = f"{type(e).__name__}: {e}"
            log.warning("lockdown details failed: %s", det["error"], extra={"udid": udid})
            return det
        try:
            av = ld.all_values or {}
            det.update({
                "name": av.get("DeviceName"), "product_type": av.get("ProductType"),
                "model_name": marketing_name(av.get("ProductType")), "ios": av.get("ProductVersion"),
                "build": av.get("BuildVersion"), "serial": av.get("SerialNumber"), "timezone": av.get("TimeZone"),
                "paired": bool(getattr(ld, "paired", False)),
            })
            if det["paired"]:
                try:
                    det["developer_mode"] = bool(await asyncio.wait_for(ld.get_developer_mode_status(), timeout=5))
                except Exception as e:
                    log.debug("developer mode query failed: %s", e, extra={"udid": udid})
                try:
                    det["ddi_mounted"] = await asyncio.wait_for(ddi_mounted(ld, det["ios"]), timeout=8)
                except Exception as e:
                    log.debug("DDI query failed: %s", e, extra={"udid": udid})
        finally:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(ld.close(), timeout=3)
        return det

    async def on_device_new(self, udid: str) -> None:
        d = self.devices[udid]
        log.info("phone connected: %s %s iOS %s ddi=%s devmode=%s", d.get("name"), d.get("model_name"),
                 d.get("ios"), d.get("ddi_mounted"), d.get("developer_mode"), extra={"udid": udid})
        if self.desired.get(udid) is not None:
            await self.ensure_worker(udid)
        else:
            self.emit_state(udid, "idle", target=None)

    async def on_device_gone(self, udid: str) -> None:
        log.info("phone unplugged", extra={"udid": udid})
        self.devices.pop(udid, None)
        self.cancel_respawn(udid)
        w = self.workers.get(udid)
        if w is not None:
            w.stop_requested = True
            if w.alive:
                await self.send_worker(w, {"cmd": "quit"})
                self.spawn(self.enforce_exit(w, grace=3))
            if self.workers.get(udid) is w:
                del self.workers[udid]
        self.emit_state(udid, "disconnected", target=self.desired.get(udid),
                        message="phone not on USB; will re-apply when it returns"
                        if self.desired.get(udid) else None)

    # ------------------------------------------------------------------ shutdown
    async def shutdown(self, reason: str) -> None:
        if self.shutting_down:
            return
        self.shutting_down = True
        log.info("shutting down (%s): releasing %d worker(s)", reason, len(self.workers))
        for t in list(self.respawn_tasks.values()):
            t.cancel()
        self.respawn_tasks.clear()
        workers = list(self.workers.values())
        for w in workers:
            w.stop_requested = True
            if w.alive:
                await self.send_worker(w, {"cmd": "quit"})
        if workers:
            await asyncio.gather(*(self.enforce_exit(w, grace=8) for w in workers), return_exceptions=True)
        for w in workers:
            if w.proc is not None and w.proc.returncode is None:
                with contextlib.suppress(Exception):
                    w.proc.kill()
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(w.proc.wait(), timeout=2)
        self.workers.clear()
        missing = object()
        for t in list(self.pending_tasks):
            if t is not asyncio.current_task():
                # PROTOCOL.md: every request gets exactly one reply — a request still waiting
                # (list_devices before the first USB scan, a slow geolocate_proxy) is answered, not dropped.
                rid = self.inflight.pop(t, missing)
                if rid is not missing:
                    self.reply_error(rid, "shutting_down", "hub is shutting down")
                t.cancel()
        log.info("hub exiting")
        self.shutdown_done.set()


async def ddi_mounted(ld: Any, ios: Optional[str]) -> Optional[bool]:
    from pymobiledevice3.services.mobile_image_mounter import MobileImageMounterService
    major = 0
    try:
        major = int(str(ios or "0").split(".")[0])
    except ValueError:
        pass
    image_type = "Personalized" if major >= 17 else "Developer"
    m = MobileImageMounterService(lockdown=ld)
    async with m:
        return bool(await m.is_image_mounted(image_type))


def main_hub() -> int:
    out = ProtoOut()
    setup_logging("hub")
    hub = Hub(out)
    logging.getLogger().addHandler(EventLogHandler(hub))

    async def runner() -> int:
        return await hub.run()

    try:
        code = asyncio.run(runner())
    except KeyboardInterrupt:
        code = 0
    out.flush()
    logging.shutdown()
    return code


# ======================================================================================
# WORKER
# ======================================================================================
class QuitRequested(Exception):
    pass


class Session:
    """One open path to the phone: tunnel (userspace or go-ios RSD) + DVT + LocationSimulation."""

    def __init__(self, tunnel: Any, rsd: Any, dvt: Any, sim: Any, kind: str):
        self.tunnel = tunnel
        self.rsd = rsd
        self.dvt = dvt
        self.sim = sim
        self.kind = kind

    async def close(self) -> None:
        with contextlib.suppress(Exception):
            await asyncio.wait_for(self.dvt.close(), timeout=5)
        if self.tunnel is not None:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(self.tunnel.aclose(), timeout=8)
        else:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(self.rsd.close(), timeout=5)


class Worker:
    def __init__(self, udid: str, out: ProtoOut):
        self.udid = udid
        self.out = out
        self.target: Optional[dict] = None
        self.applied: Optional[dict] = None
        self.pending = False
        self.quit = False
        self.quit_event = asyncio.Event()
        self.wake = asyncio.Event()
        self.state = "connecting"
        self.rsd_fallback = os.environ.get("OSGPS_RSD_FALLBACK", "1") != "0" and GO_IOS is not None
        self.log = logging.getLogger("osgps.worker")

    # ------------------------------------------------------------------ io
    def emit(self, obj: dict) -> None:
        self.out.send(obj)

    def emit_state(self, state: str, message: Optional[str] = None, attempt: Optional[int] = None,
                   retry_in: Optional[float] = None) -> None:
        self.state = state
        ev: dict[str, Any] = {"event": "state", "state": state, "target": self.target, "applied": self.applied}
        if message is not None:
            ev["message"] = proxy_geo.redact(message)
        if attempt is not None:
            ev["attempt"] = attempt
        if retry_in is not None:
            ev["retry_in"] = retry_in
        self.emit(ev)
        self.log.info("state=%s%s", state, f" ({message})" if message else "")

    def request_quit(self, why: str) -> None:
        if not self.quit:
            self.log.info("quit requested (%s)", why)
        self.quit = True
        self.quit_event.set()
        self.wake.set()

    async def read_commands(self) -> None:
        async for line in read_ndjson_lines(0):
            try:
                cmd = json.loads(line)
            except ValueError:
                self.log.error("bad command line %r", line[:100])
                continue
            name = cmd.get("cmd")
            if name == "set":
                try:
                    self.target = valid_target({"lat": cmd.get("lat"), "lon": cmd.get("lon")})
                except ValueError as e:
                    self.log.error("bad set: %s", e)
                    continue
                self.pending = True
                self.wake.set()
            elif name == "clear":
                self.target = None
                self.pending = True
                self.wake.set()
            elif name == "quit":
                self.request_quit("quit command")
                return
            else:
                self.log.warning("unknown worker command %r", name)
        self.request_quit("hub closed stdin")

    async def heartbeat_loop(self) -> None:
        while not self.quit:
            self.emit({"event": "heartbeat", "ts": time.time()})
            await asyncio.sleep(HEARTBEAT_INTERVAL)

    # ------------------------------------------------------------------ session
    async def ensure_ddi(self) -> None:
        if os.environ.get("OSGPS_SKIP_DDI") == "1":
            return
        from pymobiledevice3.lockdown import create_using_usbmux
        from pymobiledevice3.services.mobile_image_mounter import auto_mount
        ld = await asyncio.wait_for(create_using_usbmux(serial=self.udid, autopair=False), timeout=15)
        try:
            ios = (ld.all_values or {}).get("ProductVersion")
            try:
                devmode = await asyncio.wait_for(ld.get_developer_mode_status(), timeout=5)
            except Exception:
                devmode = None
            if devmode is False:
                raise RuntimeError("Developer Mode is off on this phone (Settings > Privacy & Security > Developer Mode)")
            mounted = await asyncio.wait_for(ddi_mounted(ld, ios), timeout=10)
            if mounted:
                return
            self.log.warning("developer disk image not mounted; auto-mounting (needs internet or Xcode)")
            self.emit_state("connecting", message="mounting developer disk image")
            await asyncio.wait_for(auto_mount(ld), timeout=240)
            self.log.info("developer disk image mounted")
        finally:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(ld.close(), timeout=3)

    async def open_go_ios_rsd(self) -> Any:
        """Cheap fallback: reuse the farm's root go-ios tunnel (`ios tunnel ls`) as a plain RSD."""
        from pymobiledevice3.remote.remote_service_discovery import RemoteServiceDiscoveryService
        proc = await asyncio.create_subprocess_exec(
            GO_IOS, "tunnel", "ls", "--udid", self.udid,
            stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
        except asyncio.TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                proc.kill()
            raise RuntimeError("ios tunnel ls timed out")
        entry = None
        for line in out.decode("utf-8", "replace").splitlines():
            line = line.strip()
            if not line.startswith("["):
                continue
            with contextlib.suppress(ValueError):
                for item in json.loads(line):
                    if isinstance(item, dict) and item.get("udid") == self.udid:
                        entry = item
        if not entry:
            raise RuntimeError("go-ios has no tunnel for this phone")
        rsd = RemoteServiceDiscoveryService((entry["address"], int(entry["rsdPort"])))
        await asyncio.wait_for(rsd.connect(), timeout=20)
        return rsd

    async def _open_session_inner(self) -> Session:
        from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
        from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
        from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

        try:
            await self.ensure_ddi()
        except RuntimeError:
            raise
        except Exception as e:
            self.log.warning("DDI/developer-mode pre-check skipped: %s", describe_exc(e))

        tunnel: Any = UserspaceRsdTunnel(serial=self.udid)
        rsd = None
        kind = "userspace"
        t0 = time.monotonic()
        try:
            if os.environ.get("OSGPS_FORCE_GO_IOS") == "1":  # test hook for the fallback path
                raise RuntimeError("userspace tunnel disabled by OSGPS_FORCE_GO_IOS")
            rsd = await asyncio.wait_for(tunnel.aopen(), timeout=90)
        except BaseException as e:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(tunnel.aclose(), timeout=5)
            if isinstance(e, asyncio.CancelledError) or not self.rsd_fallback:
                raise
            primary = describe_exc(e)
            self.log.warning("userspace tunnel failed (%s); trying go-ios RSD fallback", primary)
            tunnel = None
            try:
                rsd = await self.open_go_ios_rsd()
            except asyncio.CancelledError:
                raise
            except Exception as fe:
                raise RuntimeError(f"userspace tunnel: {primary}; go-ios fallback: {describe_exc(fe)}") from None
            kind = "go-ios"
        self.log.info("%s RSD up in %.1fs", kind, time.monotonic() - t0)
        dvt = DvtProvider(rsd)
        try:
            await asyncio.wait_for(dvt.connect(), timeout=30)
            sim = LocationSimulation(dvt)
            await asyncio.wait_for(sim.connect(), timeout=30)
        except BaseException:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(dvt.close(), timeout=5)
            if tunnel is not None:
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(tunnel.aclose(), timeout=8)
            else:
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(rsd.close(), timeout=5)
            raise
        return Session(tunnel, rsd, dvt, sim, kind)

    async def open_session(self) -> Session:
        """Open a session, abandoning it promptly if quit is requested meanwhile."""
        task = asyncio.ensure_future(self._open_session_inner())
        quit_task = asyncio.ensure_future(self.quit_event.wait())
        try:
            done, _ = await asyncio.wait({task, quit_task}, return_when=asyncio.FIRST_COMPLETED)
        finally:
            quit_task.cancel()
        if task in done:
            return task.result()
        task.cancel()
        with contextlib.suppress(BaseException):
            await asyncio.wait_for(task, timeout=5)
        raise QuitRequested()

    async def serve(self, session: Session) -> None:
        """Hold the channel open; apply commands; return on quit; raise on drop."""
        sim = session.sim
        disconnected = asyncio.ensure_future(session.dvt.dtx.wait_disconnected())
        try:
            while True:
                if self.quit:
                    if self.applied is not None:
                        try:
                            await asyncio.wait_for(sim.clear(), timeout=3)
                            self.log.info("simulation cleared on quit")
                        except Exception as e:
                            self.log.warning("clear on quit failed: %s", e)
                        self.applied = None
                        self.emit_state("released")
                    return
                if self.pending:
                    self.pending = False
                    if self.target is not None:
                        t = self.target
                        await asyncio.wait_for(sim.set(t["lat"], t["lon"]), timeout=20)
                        self.applied = {"lat": t["lat"], "lon": t["lon"], "at": int(time.time())}
                        self.emit_state("simulating")
                    else:
                        await asyncio.wait_for(sim.clear(), timeout=10)
                        self.applied = None
                        self.emit_state("released")
                    continue
                wake_task = asyncio.ensure_future(self.wake.wait())
                try:
                    done, _ = await asyncio.wait({wake_task, disconnected}, timeout=KEEPALIVE_INTERVAL,
                                                 return_when=asyncio.FIRST_COMPLETED)
                finally:
                    wake_task.cancel()
                if wake_task in done:
                    self.wake.clear()
                if disconnected in done:
                    raise RuntimeError("DTX connection dropped")
                if not done and self.target is not None and self.applied is not None:
                    # keepalive: re-assert the pin; a dead tunnel raises here and triggers reconnect
                    t = self.target
                    await asyncio.wait_for(sim.set(t["lat"], t["lon"]), timeout=20)
                    self.applied["at"] = int(time.time())
                    self.log.info("keepalive re-applied %s,%s", t["lat"], t["lon"])
        finally:
            disconnected.cancel()

    async def sleep_or_quit(self, seconds: float) -> None:
        with contextlib.suppress(asyncio.TimeoutError):
            await asyncio.wait_for(self.quit_event.wait(), timeout=seconds)

    async def connection_loop(self) -> None:
        failures = 0
        first = True
        while not self.quit:
            if first:
                self.emit_state("connecting", attempt=1)
                first = False
            session: Optional[Session] = None
            try:
                session = await self.open_session()
                self.emit_state("tunnel_up", message=f"{session.kind} tunnel")
                failures = 0
                self.pending = self.target is not None
                await self.serve(session)
            except QuitRequested:
                pass
            except BaseException as e:
                if isinstance(e, asyncio.CancelledError) and self.quit:
                    pass
                else:
                    failures += 1
                    msg = describe_exc(e)
                    self.applied = None
                    if session is not None:
                        await session.close()
                        session = None
                    if self.quit:
                        break
                    if failures <= len(WORKER_BACKOFF):
                        delay = WORKER_BACKOFF[failures - 1]
                        self.emit_state("reconnecting", message=msg, attempt=failures, retry_in=delay)
                    else:
                        delay = ERROR_RETRY
                        self.emit_state("error", message=msg, attempt=failures, retry_in=delay)
                    self.log.warning("session failed (%s); retry in %ss", msg, delay)
                    await self.sleep_or_quit(delay)
                    continue
            if session is not None:
                await session.close()
            break

    async def run(self) -> int:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with contextlib.suppress(Exception):
                loop.add_signal_handler(sig, lambda s=sig: self.request_quit(f"signal {s.name}"))
        reader = loop.create_task(self.read_commands())
        hb = loop.create_task(self.heartbeat_loop())
        self.log.info("worker started pid=%s", os.getpid())
        try:
            await self.connection_loop()
        finally:
            for t in (reader, hb):
                t.cancel()
        self.log.info("worker exiting")
        return 0


def main_worker(udid: str) -> int:
    out = ProtoOut()
    setup_logging("worker", udid)
    worker = Worker(udid, out)
    out.on_broken = lambda: worker.request_quit("hub gone (stdout closed)")
    try:
        code = asyncio.run(worker.run())
    except KeyboardInterrupt:
        code = 0
    except Exception as e:
        logging.getLogger("osgps.worker").exception("fatal: %s", e)
        code = 1
    out.flush()
    logging.shutdown()
    with contextlib.suppress(Exception):
        sys.stderr.flush()
    os._exit(code)  # skip GC noise from the userspace stack's leftover loop tasks


# ======================================================================================
def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Only Social GPS engine (hub, or --worker UDID)")
    ap.add_argument("--worker", metavar="UDID", help="run as the per-phone worker")
    args = ap.parse_args(argv)
    if args.worker:
        return main_worker(args.worker)
    return main_hub()


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(code)
