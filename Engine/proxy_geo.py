"""Proxy string parsing and exit-IP geolocation for Only Social GPS.

Standard library only. Network access goes through /usr/bin/curl subprocesses
(SOCKS5 support built in, no PySocks needed), each capped at 15 s per provider.

Public surface:
    parse_proxy(text) -> dict            (PROTOCOL.md "Proxy"; raises ProxyParseError)
    mask_proxy(text) -> str              (best-effort password masking for free text)
    redact(text) -> str                  (replace every password seen so far with ***)
    geolocate_via_proxy(proxy, progress) -> GeoResult   (async; raises ProxyUnreachable / GeoFailed)
    geolocate_ip(ip_or_None, progress)   -> GeoResult   (async; direct lookup, None = own public IP)
    geolocate_gateway(proxy, progress)   -> GeoResult   (async; degraded lookup of the proxy host)
    normalize_ip_api / normalize_ipwhois / normalize_ipinfo   (pure, unit-testable)
"""

from __future__ import annotations

import asyncio
import ipaddress
import json
import logging
import re
import socket
import time
from typing import Any, Awaitable, Callable, Optional
from urllib.parse import unquote

log = logging.getLogger("osgps.geo")

CURL = "/usr/bin/curl"
PROVIDER_TIMEOUT = 15  # seconds per provider (hard cap, enforced by curl --max-time and by us)
SCHEMES = ("socks5h", "socks5", "http", "https")

GATEWAY_NOTE = "gateway IP — may differ from exit IP"

ProgressCB = Optional[Callable[[str], Any]]


# --------------------------------------------------------------------------------------
# Errors
# --------------------------------------------------------------------------------------
class ProxyParseError(ValueError):
    """The proxy string could not be understood."""


class ProxyUnreachable(Exception):
    """curl could not connect/authenticate to the proxy itself."""

    def __init__(self, message: str, fallback: Optional[dict] = None, fallback_error: Optional[str] = None):
        super().__init__(message)
        self.fallback = fallback
        self.fallback_error = fallback_error


class GeoFailed(Exception):
    """The proxy works (or no proxy was used) but every geolocation provider failed."""


# --------------------------------------------------------------------------------------
# Secret handling
# --------------------------------------------------------------------------------------
_SECRETS: set[str] = set()


def remember_secret(secret: Optional[str]) -> None:
    if secret and len(secret) >= 2:
        _SECRETS.add(secret)


def redact(text: Any) -> str:
    """Replace every password this process has parsed with *** (longest first)."""
    s = str(text)
    for secret in sorted(_SECRETS, key=len, reverse=True):
        if secret in s:
            s = s.replace(secret, "***")
    return s


_MASK_URL_RE = re.compile(r"(://[^:/@\s]+:)([^@\s]+)(@)")
_MASK_AT_RE = re.compile(r"(?<![:/])\b([^:/@\s]+:)([^@\s]+)(@)")


def mask_proxy(text: str) -> str:
    """Best-effort masking of a password inside a free-form proxy string.

    Handles `scheme://user:pass@host:port`, `user:pass@host:port` and the colon forms.
    Never raises.
    """
    if not text:
        return text
    try:
        p = parse_proxy(text)
        return p["normalized"]
    except Exception:
        pass
    s = _MASK_URL_RE.sub(r"\1***\3", text)
    s = _MASK_AT_RE.sub(r"\1***\3", s)
    return s


# --------------------------------------------------------------------------------------
# Proxy parsing
# --------------------------------------------------------------------------------------
_PORT_RE = re.compile(r"^\d{1,5}$")


def _is_port(s: str) -> bool:
    return bool(_PORT_RE.match(s)) and 1 <= int(s) <= 65535


def _clean(text: str) -> str:
    s = text.strip()
    # strip one layer of matching quotes / stray quotes
    while len(s) >= 2 and s[0] in "\"'`" and s[-1] == s[0]:
        s = s[1:-1].strip()
    s = s.strip("\"'` \t\r\n")
    while s.endswith("/"):
        s = s[:-1]
    return s


def _split_hostport(hp: str) -> tuple[str, int]:
    """'host:port' or '[v6]:port' -> (host, port). Raises ProxyParseError."""
    hp = hp.strip()
    if not hp:
        raise ProxyParseError("missing host")
    if hp.startswith("["):
        end = hp.find("]")
        if end < 0:
            raise ProxyParseError("unterminated IPv6 bracket")
        host = hp[1:end]
        rest = hp[end + 1:]
        if not rest.startswith(":"):
            raise ProxyParseError("IPv6 host must be followed by :port")
        port_s = rest[1:]
        try:
            ipaddress.IPv6Address(host)
        except ValueError:
            raise ProxyParseError(f"invalid IPv6 address {host!r}") from None
    else:
        if hp.count(":") > 1:
            raise ProxyParseError("bare IPv6 addresses must be written in [brackets]")
        if ":" not in hp:
            raise ProxyParseError("missing port")
        host, port_s = hp.rsplit(":", 1)
    host = host.strip()
    port_s = port_s.strip()
    if not host or " " in host:
        raise ProxyParseError(f"invalid host {host!r}")
    if not _is_port(port_s):
        raise ProxyParseError(f"invalid port {port_s!r}")
    return host, int(port_s)


def _split_userpass(up: str) -> tuple[Optional[str], Optional[str]]:
    if up == "":
        return None, None
    if ":" in up:
        u, p = up.split(":", 1)
        return unquote(u) or None, unquote(p) if p != "" else None
    return unquote(up) or None, None


def _fmt_host(host: str) -> str:
    return f"[{host}]" if ":" in host else host


def build_proxy(scheme: str, host: str, port: int, username: Optional[str], password: Optional[str]) -> dict:
    scheme = scheme.lower()
    if scheme not in SCHEMES:
        raise ProxyParseError(f"unsupported scheme {scheme!r}")
    remember_secret(password)
    hp = f"{_fmt_host(host)}:{port}"
    if username:
        cred_mask = f"{username}:***@" if password else f"{username}@"
    else:
        cred_mask = ""
    normalized = f"{scheme}://{cred_mask}{hp}"
    if scheme == "socks5h":
        curl_args = ["--socks5-hostname", hp]
    elif scheme == "socks5":
        curl_args = ["--socks5", hp]
    else:
        curl_args = ["--proxy", f"{scheme}://{hp}"]
    if username:
        curl_args += ["--proxy-user", f"{username}:{password or ''}"]
    return {
        "scheme": scheme,
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "normalized": normalized,
        "curl_args": curl_args,
    }


def parse_proxy(text: str) -> dict:
    """Parse every common SOCKS5/HTTP proxy notation into the PROTOCOL.md Proxy object.

    Accepted: host:port:user:pass | user:pass:host:port | user:pass@host:port |
    host:port@user:pass | scheme://[user:pass@]host:port[/] | host:port | [v6]:port forms,
    with surrounding quotes/whitespace. Default scheme is socks5h (hostnames resolved by
    the proxy, which is what exit-IP geolocation wants).
    """
    if text is None:
        raise ProxyParseError("empty proxy string")
    s = _clean(str(text))
    if not s:
        raise ProxyParseError("empty proxy string")

    scheme = "socks5h"
    m = re.match(r"^([A-Za-z][A-Za-z0-9+.-]*)://(.*)$", s)
    if m:
        scheme = m.group(1).lower()
        if scheme in ("socks", "socks5a"):
            scheme = "socks5h"
        if scheme not in SCHEMES:
            raise ProxyParseError(f"unsupported scheme {m.group(1)!r} (use socks5, socks5h, http or https)")
        s = _clean(m.group(2))
        if not s:
            raise ProxyParseError("missing host")

    username = password = None

    if "@" in s:
        left, right = s.rsplit("@", 1)
        # normal: user:pass@host:port ; lenient: host:port@user:pass
        try:
            host, port = _split_hostport(right)
            username, password = _split_userpass(left)
        except ProxyParseError:
            host, port = _split_hostport(left)
            username, password = _split_userpass(right)
        return build_proxy(scheme, host, port, username, password)

    # bracketed IPv6 without '@': [v6]:port or [v6]:port:user:pass
    if s.startswith("["):
        end = s.find("]")
        if end < 0:
            raise ProxyParseError("unterminated IPv6 bracket")
        rest = s[end + 1:]
        parts = rest.split(":")
        # parts[0] == '' (before the port)
        if len(parts) < 2 or parts[0] != "":
            raise ProxyParseError("IPv6 host must be followed by :port")
        host, port = _split_hostport(s[: end + 1] + ":" + parts[1])
        if len(parts) == 2:
            return build_proxy(scheme, host, port, None, None)
        if len(parts) >= 4:
            username = unquote(parts[2]) or None
            password = unquote(":".join(parts[3:])) or None
            return build_proxy(scheme, host, port, username, password)
        raise ProxyParseError("could not understand IPv6 proxy notation")

    fields = s.split(":")
    if len(fields) > 2:
        # a bare IPv6 literal (with or without a trailing :port) is ambiguous in the colon forms
        for candidate in (s, ":".join(fields[:-1])):
            try:
                ipaddress.IPv6Address(candidate)
            except ValueError:
                continue
            raise ProxyParseError("bare IPv6 addresses must be written in [brackets], e.g. [2001:db8::1]:1080")
        if any(f == "" for f in fields):
            raise ProxyParseError("empty field in proxy string")
    if len(fields) == 2:
        host, port = _split_hostport(s)
        return build_proxy(scheme, host, port, None, None)
    if len(fields) == 1:
        raise ProxyParseError("missing port (expected host:port)")
    if len(fields) == 3:
        # host:port:user (no password) is the only sane reading
        if _is_port(fields[1]):
            host, port = _split_hostport(":".join(fields[:2]))
            return build_proxy(scheme, host, port, unquote(fields[2]) or None, None)
        raise ProxyParseError("ambiguous 3-field proxy; expected host:port:user:pass or user:pass@host:port")
    # 4+ fields: rule from BRIEF.md
    if _is_port(fields[1]):
        host, port = _split_hostport(":".join(fields[:2]))
        username = unquote(fields[2]) or None
        password = unquote(":".join(fields[3:])) or None
        return build_proxy(scheme, host, port, username, password)
    if _is_port(fields[-1]):
        host, port = _split_hostport(":".join(fields[-2:]))
        username = unquote(fields[0]) or None
        password = unquote(":".join(fields[1:-2])) or None
        return build_proxy(scheme, host, port, username, password)
    raise ProxyParseError("could not find a port; expected host:port:user:pass or user:pass:host:port")


# --------------------------------------------------------------------------------------
# Geo normalisation (pure functions)
# --------------------------------------------------------------------------------------
def _f(v: Any) -> Optional[float]:
    try:
        if v is None or v == "":
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def _s(v: Any) -> Optional[str]:
    if v is None:
        return None
    v = str(v).strip()
    return v or None


def _asn(v: Any) -> Optional[str]:
    """'AS855 Bell Canada' | 855 | 'AS855' -> 'AS855'."""
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return f"AS{int(v)}"
    s = str(v).strip()
    m = re.match(r"^(?:AS)?(\d+)", s, re.I)
    return f"AS{m.group(1)}" if m else s or None


def flag_emoji(country_code: Optional[str]) -> Optional[str]:
    if not country_code or len(country_code) != 2 or not country_code.isalpha():
        return None
    cc = country_code.upper()
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in cc)


def _base(provider: str) -> dict:
    return {
        "ip": None, "lat": None, "lon": None,
        "city": None, "region": None, "country": None, "country_code": None,
        "isp": None, "org": None, "asn": None, "timezone": None,
        "provider": provider, "via_proxy": False, "note": None,
        "checked_at": int(time.time()), "elapsed_ms": 0, "flag": None,
    }


def _finish(r: dict) -> dict:
    if r["lat"] is None or r["lon"] is None:
        raise GeoFailed(f"{r['provider']}: response has no coordinates")
    if r["country_code"]:
        r["country_code"] = r["country_code"].upper()
        r["flag"] = flag_emoji(r["country_code"])
        if not r["country"]:
            r["country"] = COUNTRY_NAMES.get(r["country_code"], r["country_code"])
    return r


def normalize_ip_api(data: dict) -> dict:
    if not isinstance(data, dict):
        raise GeoFailed("ip-api.com: malformed response")
    if data.get("status") != "success":
        raise GeoFailed(f"ip-api.com: {data.get('message') or 'lookup failed'}")
    r = _base("ip-api.com")
    r.update({
        "ip": _s(data.get("query")),
        "lat": _f(data.get("lat")), "lon": _f(data.get("lon")),
        "city": _s(data.get("city")), "region": _s(data.get("regionName")) or _s(data.get("region")),
        "country": _s(data.get("country")), "country_code": _s(data.get("countryCode")),
        "isp": _s(data.get("isp")), "org": _s(data.get("org")), "asn": _asn(data.get("as")),
        "timezone": _s(data.get("timezone")),
    })
    return _finish(r)


def normalize_ipwhois(data: dict) -> dict:
    if not isinstance(data, dict):
        raise GeoFailed("ipwho.is: malformed response")
    if data.get("success") is False:
        raise GeoFailed(f"ipwho.is: {data.get('message') or 'lookup failed'}")
    conn = data.get("connection") or {}
    tz = data.get("timezone")
    tz_id = tz.get("id") if isinstance(tz, dict) else tz
    r = _base("ipwho.is")
    r.update({
        "ip": _s(data.get("ip")),
        "lat": _f(data.get("latitude")), "lon": _f(data.get("longitude")),
        "city": _s(data.get("city")), "region": _s(data.get("region")),
        "country": _s(data.get("country")), "country_code": _s(data.get("country_code")),
        "isp": _s(conn.get("isp")) or _s(conn.get("org")), "org": _s(conn.get("org")),
        "asn": _asn(conn.get("asn")), "timezone": _s(tz_id),
    })
    return _finish(r)


def normalize_ipinfo(data: dict) -> dict:
    if not isinstance(data, dict):
        raise GeoFailed("ipinfo.io: malformed response")
    if data.get("error") or data.get("status") == 429:
        err = data.get("error")
        msg = err.get("message") if isinstance(err, dict) else err
        raise GeoFailed(f"ipinfo.io: {msg or 'lookup failed'}")
    if data.get("bogon"):
        raise GeoFailed("ipinfo.io: bogon/private address")
    lat = lon = None
    loc = _s(data.get("loc"))
    if loc and "," in loc:
        a, b = loc.split(",", 1)
        lat, lon = _f(a), _f(b)
    org_raw = _s(data.get("org"))
    isp = org_raw
    if org_raw:
        m = re.match(r"^AS\d+\s+(.*)$", org_raw)
        if m:
            isp = m.group(1).strip() or None
    r = _base("ipinfo.io")
    cc = _s(data.get("country"))
    r.update({
        "ip": _s(data.get("ip")), "lat": lat, "lon": lon,
        "city": _s(data.get("city")), "region": _s(data.get("region")),
        "country": COUNTRY_NAMES.get(cc.upper(), cc) if cc else None, "country_code": cc,
        "isp": isp, "org": isp, "asn": _asn(org_raw), "timezone": _s(data.get("timezone")),
    })
    return _finish(r)


IP_API_FIELDS = "status,message,country,countryCode,regionName,region,city,zip,lat,lon,timezone,isp,org,as,query"


def provider_chain(ip: Optional[str] = None) -> list[tuple[str, str, Callable[[dict], dict]]]:
    """(stage label, url, normaliser) for the three providers, optionally for a specific IP."""
    tail = ip or ""
    return [
        ("querying ip-api.com", f"http://ip-api.com/json/{tail}?fields={IP_API_FIELDS}", normalize_ip_api),
        ("querying ipwho.is", f"https://ipwho.is/{tail}", normalize_ipwhois),
        ("querying ipinfo.io", f"https://ipinfo.io/{tail + '/' if tail else ''}json", normalize_ipinfo),
    ]


# --------------------------------------------------------------------------------------
# curl plumbing
# --------------------------------------------------------------------------------------
_WRITE_OUT = "\n__OSGPS__ %{exitcode} %{http_code} %{time_connect} %{errormsg}"
PROXY_LEVEL_EXIT = {5, 7, 97}  # couldn't resolve proxy / couldn't connect / SOCKS (proxy) error


class CurlResult:
    __slots__ = ("exit_code", "http_code", "time_connect", "body", "errormsg", "elapsed_ms", "timed_out")

    def __init__(self) -> None:
        self.exit_code = -1
        self.http_code = 0
        self.time_connect = 0.0
        self.body = ""
        self.errormsg = ""
        self.elapsed_ms = 0
        self.timed_out = False

    @property
    def proxy_level_failure(self) -> bool:
        if self.exit_code in PROXY_LEVEL_EXIT:
            return True
        if self.exit_code == 28 and self.time_connect == 0:
            return True  # timed out before ever reaching the proxy
        if self.timed_out and self.time_connect == 0:
            return True
        return False


async def run_curl(url: str, proxy_args: list[str], timeout: int = PROVIDER_TIMEOUT) -> CurlResult:
    args = [
        CURL, "-sS", "--max-time", str(timeout), "--connect-timeout", str(min(10, timeout)),
        "-A", "OnlySocialGPS/1.0", "-H", "Accept: application/json",
        "--write-out", _WRITE_OUT, *proxy_args, url,
    ]
    res = CurlResult()
    t0 = time.monotonic()
    proc = await asyncio.create_subprocess_exec(
        *args, stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout + 3)
    except asyncio.TimeoutError:
        res.timed_out = True
        res.exit_code = 28
        res.errormsg = f"curl did not finish within {timeout + 3}s"
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        with _suppress():
            await asyncio.wait_for(proc.wait(), timeout=2)
        res.elapsed_ms = int((time.monotonic() - t0) * 1000)
        return res
    except asyncio.CancelledError:
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        raise
    res.elapsed_ms = int((time.monotonic() - t0) * 1000)
    text = out.decode("utf-8", "replace")
    body, sep, tail = text.rpartition("\n__OSGPS__ ")
    if sep:
        parts = tail.strip().split(" ", 3)
        try:
            res.exit_code = int(parts[0])
            res.http_code = int(parts[1])
            res.time_connect = float(parts[2])
        except (ValueError, IndexError):
            res.exit_code = proc.returncode if proc.returncode is not None else -1
        res.errormsg = parts[3] if len(parts) > 3 else ""
        res.body = body
    else:
        res.body = text
        res.exit_code = proc.returncode if proc.returncode is not None else -1
    if not res.errormsg:
        res.errormsg = err.decode("utf-8", "replace").strip()
    if res.exit_code == 0 and proc.returncode not in (0, None):
        res.exit_code = proc.returncode
    return res


class _suppress:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return True

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return True


def _describe(res: CurlResult, label: str) -> str:
    msg = redact(res.errormsg or f"curl exit {res.exit_code}")
    if res.http_code and res.exit_code == 0:
        return f"{label}: HTTP {res.http_code}"
    return f"{label}: {msg}"


async def _query_chain(
    proxy_args: list[str], ip: Optional[str], progress: ProgressCB, via_proxy: bool, note: Optional[str],
) -> dict:
    """Run the provider chain. Raises ProxyUnreachable (when via_proxy) or GeoFailed."""
    errors: list[str] = []
    t0 = time.monotonic()
    for stage, url, normalise in provider_chain(ip):
        if progress:
            progress(stage)
        res = await run_curl(url, proxy_args)
        if res.exit_code != 0:
            desc = _describe(res, stage.replace("querying ", ""))
            errors.append(desc)
            log.info("geo provider failed: %s (exit %s, connect %.2fs, %dms)", desc, res.exit_code,
                     res.time_connect, res.elapsed_ms)
            if via_proxy and res.proxy_level_failure:
                raise ProxyUnreachable(redact(res.errormsg or f"curl exit {res.exit_code}"))
            continue
        if res.http_code >= 400:
            errors.append(f"{stage.replace('querying ', '')}: HTTP {res.http_code}")
            continue
        try:
            data = json.loads(res.body)
            r = normalise(data)
        except (ValueError, GeoFailed) as e:
            errors.append(str(e) if isinstance(e, GeoFailed) else f"{stage.replace('querying ', '')}: bad JSON")
            continue
        r["via_proxy"] = via_proxy
        r["note"] = note
        r["elapsed_ms"] = int((time.monotonic() - t0) * 1000)
        r["checked_at"] = int(time.time())
        return r
    raise GeoFailed("; ".join(errors) if errors else "no provider answered")


# --------------------------------------------------------------------------------------
# Public async API
# --------------------------------------------------------------------------------------
async def geolocate_ip(ip: Optional[str] = None, progress: ProgressCB = None) -> dict:
    """Direct (no proxy) lookup. ip=None -> the Mac's own public IP."""
    return await _query_chain([], ip, progress, via_proxy=False, note=None)


async def resolve_host(host: str) -> Optional[str]:
    """Resolve a hostname to its first IP (prefers IPv4). Returns None on failure."""
    try:
        ipaddress.ip_address(host)
        return host
    except ValueError:
        pass
    loop = asyncio.get_running_loop()
    try:
        infos = await asyncio.wait_for(loop.getaddrinfo(host, None, type=socket.SOCK_STREAM), timeout=8)
    except Exception as e:
        log.info("resolve %s failed: %s", host, e)
        return None
    v4 = [i[4][0] for i in infos if i[0] == socket.AF_INET]
    v6 = [i[4][0] for i in infos if i[0] == socket.AF_INET6]
    return (v4 or v6 or [None])[0]


async def geolocate_gateway(proxy: dict, progress: ProgressCB = None) -> dict:
    """Degraded lookup: geolocate the proxy host itself, flagged as a gateway IP."""
    if progress:
        progress("fallback_gateway")
    ip = await resolve_host(proxy["host"])
    if ip is None:
        raise GeoFailed(f"could not resolve proxy host {proxy['host']!r}")
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        addr = None
    if addr is not None and (addr.is_private or addr.is_reserved or addr.is_loopback or addr.is_link_local):
        raise GeoFailed(f"proxy host {ip} is a private/reserved address; nothing to geolocate")
    return await _query_chain([], ip, progress, via_proxy=False, note=GATEWAY_NOTE)


async def geolocate_via_proxy(proxy: dict, progress: ProgressCB = None, with_fallback: bool = True) -> dict:
    """Geolocate the proxy's exit IP by connecting through it.

    Raises ProxyUnreachable (with .fallback = gateway GeoResult or None) or GeoFailed.
    """
    if progress:
        progress("connecting")
    try:
        return await _query_chain(list(proxy["curl_args"]), None, progress, via_proxy=True, note=None)
    except ProxyUnreachable as e:
        if not with_fallback:
            raise
        fallback = None
        fallback_error = None
        try:
            fallback = await geolocate_gateway(proxy, progress)
        except Exception as fe:
            fallback_error = redact(str(fe))
            log.info("gateway fallback failed: %s", fallback_error)
        raise ProxyUnreachable(str(e), fallback=fallback, fallback_error=fallback_error) from None


# --------------------------------------------------------------------------------------
# ISO 3166-1 alpha-2 -> country name (ipinfo.io only returns the code)
# --------------------------------------------------------------------------------------
COUNTRY_NAMES: dict[str, str] = {
    "AD": "Andorra", "AE": "United Arab Emirates", "AF": "Afghanistan", "AG": "Antigua and Barbuda",
    "AI": "Anguilla", "AL": "Albania", "AM": "Armenia", "AO": "Angola", "AQ": "Antarctica",
    "AR": "Argentina", "AS": "American Samoa", "AT": "Austria", "AU": "Australia", "AW": "Aruba",
    "AX": "Åland Islands", "AZ": "Azerbaijan", "BA": "Bosnia and Herzegovina", "BB": "Barbados",
    "BD": "Bangladesh", "BE": "Belgium", "BF": "Burkina Faso", "BG": "Bulgaria", "BH": "Bahrain",
    "BI": "Burundi", "BJ": "Benin", "BL": "Saint Barthélemy", "BM": "Bermuda", "BN": "Brunei",
    "BO": "Bolivia", "BQ": "Caribbean Netherlands", "BR": "Brazil", "BS": "Bahamas", "BT": "Bhutan",
    "BV": "Bouvet Island", "BW": "Botswana", "BY": "Belarus", "BZ": "Belize", "CA": "Canada",
    "CC": "Cocos (Keeling) Islands", "CD": "DR Congo", "CF": "Central African Republic",
    "CG": "Republic of the Congo", "CH": "Switzerland", "CI": "Côte d'Ivoire", "CK": "Cook Islands",
    "CL": "Chile", "CM": "Cameroon", "CN": "China", "CO": "Colombia", "CR": "Costa Rica", "CU": "Cuba",
    "CV": "Cape Verde", "CW": "Curaçao", "CX": "Christmas Island", "CY": "Cyprus", "CZ": "Czechia",
    "DE": "Germany", "DJ": "Djibouti", "DK": "Denmark", "DM": "Dominica", "DO": "Dominican Republic",
    "DZ": "Algeria", "EC": "Ecuador", "EE": "Estonia", "EG": "Egypt", "EH": "Western Sahara",
    "ER": "Eritrea", "ES": "Spain", "ET": "Ethiopia", "FI": "Finland", "FJ": "Fiji",
    "FK": "Falkland Islands", "FM": "Micronesia", "FO": "Faroe Islands", "FR": "France", "GA": "Gabon",
    "GB": "United Kingdom", "GD": "Grenada", "GE": "Georgia", "GF": "French Guiana", "GG": "Guernsey",
    "GH": "Ghana", "GI": "Gibraltar", "GL": "Greenland", "GM": "Gambia", "GN": "Guinea",
    "GP": "Guadeloupe", "GQ": "Equatorial Guinea", "GR": "Greece", "GS": "South Georgia",
    "GT": "Guatemala", "GU": "Guam", "GW": "Guinea-Bissau", "GY": "Guyana", "HK": "Hong Kong",
    "HM": "Heard Island", "HN": "Honduras", "HR": "Croatia", "HT": "Haiti", "HU": "Hungary",
    "ID": "Indonesia", "IE": "Ireland", "IL": "Israel", "IM": "Isle of Man", "IN": "India",
    "IO": "British Indian Ocean Territory", "IQ": "Iraq", "IR": "Iran", "IS": "Iceland", "IT": "Italy",
    "JE": "Jersey", "JM": "Jamaica", "JO": "Jordan", "JP": "Japan", "KE": "Kenya", "KG": "Kyrgyzstan",
    "KH": "Cambodia", "KI": "Kiribati", "KM": "Comoros", "KN": "Saint Kitts and Nevis",
    "KP": "North Korea", "KR": "South Korea", "KW": "Kuwait", "KY": "Cayman Islands", "KZ": "Kazakhstan",
    "LA": "Laos", "LB": "Lebanon", "LC": "Saint Lucia", "LI": "Liechtenstein", "LK": "Sri Lanka",
    "LR": "Liberia", "LS": "Lesotho", "LT": "Lithuania", "LU": "Luxembourg", "LV": "Latvia", "LY": "Libya",
    "MA": "Morocco", "MC": "Monaco", "MD": "Moldova", "ME": "Montenegro", "MF": "Saint Martin",
    "MG": "Madagascar", "MH": "Marshall Islands", "MK": "North Macedonia", "ML": "Mali", "MM": "Myanmar",
    "MN": "Mongolia", "MO": "Macau", "MP": "Northern Mariana Islands", "MQ": "Martinique",
    "MR": "Mauritania", "MS": "Montserrat", "MT": "Malta", "MU": "Mauritius", "MV": "Maldives",
    "MW": "Malawi", "MX": "Mexico", "MY": "Malaysia", "MZ": "Mozambique", "NA": "Namibia",
    "NC": "New Caledonia", "NE": "Niger", "NF": "Norfolk Island", "NG": "Nigeria", "NI": "Nicaragua",
    "NL": "Netherlands", "NO": "Norway", "NP": "Nepal", "NR": "Nauru", "NU": "Niue", "NZ": "New Zealand",
    "OM": "Oman", "PA": "Panama", "PE": "Peru", "PF": "French Polynesia", "PG": "Papua New Guinea",
    "PH": "Philippines", "PK": "Pakistan", "PL": "Poland", "PM": "Saint Pierre and Miquelon",
    "PN": "Pitcairn Islands", "PR": "Puerto Rico", "PS": "Palestine", "PT": "Portugal", "PW": "Palau",
    "PY": "Paraguay", "QA": "Qatar", "RE": "Réunion", "RO": "Romania", "RS": "Serbia", "RU": "Russia",
    "RW": "Rwanda", "SA": "Saudi Arabia", "SB": "Solomon Islands", "SC": "Seychelles", "SD": "Sudan",
    "SE": "Sweden", "SG": "Singapore", "SH": "Saint Helena", "SI": "Slovenia", "SJ": "Svalbard and Jan Mayen",
    "SK": "Slovakia", "SL": "Sierra Leone", "SM": "San Marino", "SN": "Senegal", "SO": "Somalia",
    "SR": "Suriname", "SS": "South Sudan", "ST": "São Tomé and Príncipe", "SV": "El Salvador",
    "SX": "Sint Maarten", "SY": "Syria", "SZ": "Eswatini", "TC": "Turks and Caicos Islands", "TD": "Chad",
    "TF": "French Southern Territories", "TG": "Togo", "TH": "Thailand", "TJ": "Tajikistan", "TK": "Tokelau",
    "TL": "Timor-Leste", "TM": "Turkmenistan", "TN": "Tunisia", "TO": "Tonga", "TR": "Türkiye",
    "TT": "Trinidad and Tobago", "TV": "Tuvalu", "TW": "Taiwan", "TZ": "Tanzania", "UA": "Ukraine",
    "UG": "Uganda", "UM": "U.S. Outlying Islands", "US": "United States", "UY": "Uruguay",
    "UZ": "Uzbekistan", "VA": "Vatican City", "VC": "Saint Vincent and the Grenadines", "VE": "Venezuela",
    "VG": "British Virgin Islands", "VI": "U.S. Virgin Islands", "VN": "Vietnam", "VU": "Vanuatu",
    "WF": "Wallis and Futuna", "WS": "Samoa", "XK": "Kosovo", "YE": "Yemen", "YT": "Mayotte",
    "ZA": "South Africa", "ZM": "Zambia", "ZW": "Zimbabwe",
}
