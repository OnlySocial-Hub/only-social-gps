"""GeoResult normalisation for the three providers, plus curl exit-code classification. No network."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import proxy_geo as pg  # noqa: E402

GEO_KEYS = {"ip", "lat", "lon", "city", "region", "country", "country_code", "isp", "org", "asn", "timezone",
            "provider", "via_proxy", "note", "checked_at", "elapsed_ms", "flag"}

IP_API = {"status": "success", "country": "Canada", "countryCode": "CA", "region": "NS", "regionName": "Nova Scotia",
          "city": "Dartmouth", "zip": "B3A", "lat": 44.6835, "lon": -63.5778, "timezone": "America/Halifax",
          "isp": "Bell Canada", "org": "Bell Canada", "as": "AS855 Bell Canada", "query": "134.41.93.130"}

IPWHOIS = {"ip": "134.41.93.130", "success": True, "type": "IPv4", "country": "Canada", "country_code": "CA",
           "region": "Nova Scotia", "region_code": "NS", "city": "Halifax", "latitude": 44.6426926,
           "longitude": -63.5768785, "connection": {"asn": 855, "org": "Bell Canada", "isp": "Bell Canada",
                                                    "domain": "bell.ca"},
           "timezone": {"id": "America/Halifax", "abbr": "ADT", "is_dst": True, "offset": -10800, "utc": "-03:00"}}

IPINFO = {"ip": "134.41.93.130", "hostname": "x.bellaliant.net", "city": "Dartmouth", "region": "Nova Scotia",
          "country": "CA", "loc": "44.6713,-63.5772", "org": "AS855 Bell Canada", "postal": "B3A",
          "timezone": "America/Halifax"}


class NormaliseTests(unittest.TestCase):
    def check_common(self, r, provider):
        self.assertEqual(set(r), GEO_KEYS)
        self.assertEqual(r["provider"], provider)
        self.assertEqual(r["ip"], "134.41.93.130")
        self.assertEqual(r["country_code"], "CA")
        self.assertEqual(r["country"], "Canada")
        self.assertEqual(r["region"], "Nova Scotia")
        self.assertEqual(r["asn"], "AS855")
        self.assertEqual(r["isp"], "Bell Canada")
        self.assertEqual(r["timezone"], "America/Halifax")
        self.assertEqual(r["flag"], "\U0001F1E8\U0001F1E6")
        self.assertIsInstance(r["lat"], float)
        self.assertIsInstance(r["lon"], float)
        self.assertFalse(r["via_proxy"])
        self.assertIsNone(r["note"])

    def test_ip_api(self):
        r = pg.normalize_ip_api(IP_API)
        self.check_common(r, "ip-api.com")
        self.assertEqual((r["lat"], r["lon"], r["city"]), (44.6835, -63.5778, "Dartmouth"))
        self.assertEqual(r["org"], "Bell Canada")

    def test_ip_api_failure(self):
        with self.assertRaises(pg.GeoFailed) as cm:
            pg.normalize_ip_api({"status": "fail", "message": "reserved range", "query": "203.0.113.9"})
        self.assertIn("reserved range", str(cm.exception))

    def test_ipwhois(self):
        r = pg.normalize_ipwhois(IPWHOIS)
        self.check_common(r, "ipwho.is")
        self.assertAlmostEqual(r["lat"], 44.6426926)
        self.assertAlmostEqual(r["lon"], -63.5768785)
        self.assertEqual(r["city"], "Halifax")

    def test_ipwhois_failure(self):
        with self.assertRaises(pg.GeoFailed):
            pg.normalize_ipwhois({"success": False, "message": "Reserved range"})

    def test_ipinfo(self):
        r = pg.normalize_ipinfo(IPINFO)
        self.check_common(r, "ipinfo.io")
        self.assertEqual((r["lat"], r["lon"], r["city"]), (44.6713, -63.5772, "Dartmouth"))

    def test_ipinfo_failure_and_bogon(self):
        with self.assertRaises(pg.GeoFailed):
            pg.normalize_ipinfo({"error": {"title": "Wrong ip", "message": "Please provide a valid IP address"}})
        with self.assertRaises(pg.GeoFailed):
            pg.normalize_ipinfo({"ip": "10.0.0.1", "bogon": True})
        with self.assertRaises(pg.GeoFailed):
            pg.normalize_ipinfo({"ip": "1.1.1.1"})  # no loc

    def test_country_name_lookup(self):
        r = pg.normalize_ipinfo(dict(IPINFO, country="GB"))
        self.assertEqual(r["country"], "United Kingdom")
        r = pg.normalize_ipinfo(dict(IPINFO, country="ZZ"))
        self.assertEqual(r["country"], "ZZ")

    def test_asn_forms(self):
        self.assertEqual(pg._asn("AS855 Bell Canada"), "AS855")
        self.assertEqual(pg._asn(855), "AS855")
        self.assertEqual(pg._asn("855"), "AS855")
        self.assertIsNone(pg._asn(None))
        self.assertIsNone(pg._asn(""))

    def test_provider_chain_urls(self):
        chain = pg.provider_chain(None)
        self.assertEqual([c[0] for c in chain], ["querying ip-api.com", "querying ipwho.is", "querying ipinfo.io"])
        self.assertTrue(chain[0][1].startswith("http://ip-api.com/json/?fields="))
        self.assertEqual(chain[2][1], "https://ipinfo.io/json")
        chain = pg.provider_chain("1.1.1.1")
        self.assertTrue(chain[0][1].startswith("http://ip-api.com/json/1.1.1.1?"))
        self.assertEqual(chain[1][1], "https://ipwho.is/1.1.1.1")
        self.assertEqual(chain[2][1], "https://ipinfo.io/1.1.1.1/json")


class CurlClassificationTests(unittest.TestCase):
    def make(self, exit_code, time_connect=0.0, timed_out=False):
        r = pg.CurlResult()
        r.exit_code = exit_code
        r.time_connect = time_connect
        r.timed_out = timed_out
        return r

    def test_proxy_level(self):
        self.assertTrue(self.make(7).proxy_level_failure)      # couldn't connect
        self.assertTrue(self.make(5).proxy_level_failure)      # couldn't resolve proxy
        self.assertTrue(self.make(97).proxy_level_failure)     # SOCKS error
        self.assertTrue(self.make(28, 0.0).proxy_level_failure)  # timeout before connect
        self.assertTrue(self.make(28, 0.0, timed_out=True).proxy_level_failure)

    def test_provider_level(self):
        self.assertFalse(self.make(28, 0.4).proxy_level_failure)  # connected to proxy, provider slow
        self.assertFalse(self.make(22, 0.4).proxy_level_failure)  # HTTP error
        self.assertFalse(self.make(6, 0.4).proxy_level_failure)   # DNS through proxy
        self.assertFalse(self.make(0, 0.4).proxy_level_failure)


if __name__ == "__main__":
    unittest.main()
