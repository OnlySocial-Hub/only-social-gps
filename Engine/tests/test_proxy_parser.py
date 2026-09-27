"""Proxy parser tests — every notation listed in BRIEF.md. No hardware, no network."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import proxy_geo as pg  # noqa: E402


class ParseProxyTests(unittest.TestCase):
    def assertProxy(self, text, scheme, host, port, username, password):
        p = pg.parse_proxy(text)
        self.assertEqual((p["scheme"], p["host"], p["port"], p["username"], p["password"]),
                         (scheme, host, port, username, password), text)
        return p

    def test_colon_host_first(self):
        self.assertProxy("1.2.3.4:1080:alice:s3cret", "socks5h", "1.2.3.4", 1080, "alice", "s3cret")

    def test_colon_user_first(self):
        self.assertProxy("alice:s3cret:proxy.example.com:1080", "socks5h", "proxy.example.com", 1080, "alice", "s3cret")

    def test_ambiguity_rule_field2_numeric_wins(self):
        # field 2 numeric -> host:port:user:pass even though field 4 is numeric too
        self.assertProxy("host:1080:user:1234", "socks5h", "host", 1080, "user", "1234")

    def test_at_form(self):
        self.assertProxy("alice:s3cret@1.2.3.4:1080", "socks5h", "1.2.3.4", 1080, "alice", "s3cret")

    def test_at_form_reversed(self):
        self.assertProxy("1.2.3.4:1080@alice:s3cret", "socks5h", "1.2.3.4", 1080, "alice", "s3cret")

    def test_password_with_at_and_colon(self):
        self.assertProxy("alice:p@ss:w0rd@1.2.3.4:1080", "socks5h", "1.2.3.4", 1080, "alice", "p@ss:w0rd")

    def test_socks5_url(self):
        self.assertProxy("socks5://alice:s3cret@1.2.3.4:1080", "socks5", "1.2.3.4", 1080, "alice", "s3cret")

    def test_socks5h_url_trailing_slash(self):
        self.assertProxy("socks5h://alice:s3cret@1.2.3.4:1080/", "socks5h", "1.2.3.4", 1080, "alice", "s3cret")

    def test_no_auth(self):
        self.assertProxy("1.2.3.4:1080", "socks5h", "1.2.3.4", 1080, None, None)
        self.assertProxy("socks5://1.2.3.4:1080", "socks5", "1.2.3.4", 1080, None, None)

    def test_http_and_https(self):
        p = self.assertProxy("http://u:p@10.0.0.1:3128", "http", "10.0.0.1", 3128, "u", "p")
        self.assertEqual(p["curl_args"], ["--proxy", "http://10.0.0.1:3128", "--proxy-user", "u:p"])
        p = self.assertProxy("https://proxy.example.com:443", "https", "proxy.example.com", 443, None, None)
        self.assertEqual(p["curl_args"], ["--proxy", "https://proxy.example.com:443"])

    def test_ipv6_bracketed(self):
        p = self.assertProxy("socks5h://u:p@[2001:db8::1]:1080", "socks5h", "2001:db8::1", 1080, "u", "p")
        self.assertEqual(p["curl_args"][:2], ["--socks5-hostname", "[2001:db8::1]:1080"])
        self.assertProxy("[::1]:1080", "socks5h", "::1", 1080, None, None)
        self.assertProxy("[::1]:1080:u:p", "socks5h", "::1", 1080, "u", "p")
        self.assertProxy("u:p@[::1]:1080", "socks5h", "::1", 1080, "u", "p")

    def test_quotes_and_whitespace(self):
        self.assertProxy('  "1.2.3.4:1080:alice:s3cret"  \n', "socks5h", "1.2.3.4", 1080, "alice", "s3cret")
        self.assertProxy("'socks5://alice:s3cret@1.2.3.4:1080/'", "socks5", "1.2.3.4", 1080, "alice", "s3cret")

    def test_url_encoded_credentials(self):
        self.assertProxy("socks5://al%40ice:p%3Ass@1.2.3.4:1080", "socks5", "1.2.3.4", 1080, "al@ice", "p:ss")

    def test_scheme_case_and_aliases(self):
        self.assertProxy("SOCKS5H://u:p@h:1", "socks5h", "h", 1, "u", "p")
        self.assertProxy("socks://u:p@h:1", "socks5h", "h", 1, "u", "p")

    def test_normalized_masks_password(self):
        p = pg.parse_proxy("socks5://alice:s3cret@1.2.3.4:1080")
        self.assertEqual(p["normalized"], "socks5://alice:***@1.2.3.4:1080")
        self.assertNotIn("s3cret", p["normalized"])
        p = pg.parse_proxy("1.2.3.4:1080")
        self.assertEqual(p["normalized"], "socks5h://1.2.3.4:1080")

    def test_curl_args(self):
        p = pg.parse_proxy("socks5h://alice:s3cret@h:1080")
        self.assertEqual(p["curl_args"], ["--socks5-hostname", "h:1080", "--proxy-user", "alice:s3cret"])
        p = pg.parse_proxy("socks5://h:1080")
        self.assertEqual(p["curl_args"], ["--socks5", "h:1080"])

    def test_errors(self):
        for bad in ["", "   ", "host", "host:0", "host:65536", "host:abc", "ftp://h:1", "a:b:c",
                    "2001:db8::1:1080", "2001:db8::1", "host:1080:user:", "[::1", "[::1]1080", None]:
            with self.assertRaises(pg.ProxyParseError, msg=repr(bad)):
                pg.parse_proxy(bad)

    def test_result_shape(self):
        p = pg.parse_proxy("1.2.3.4:1080:alice:s3cret")
        self.assertEqual(set(p), {"scheme", "host", "port", "username", "password", "normalized", "curl_args"})


class MaskingTests(unittest.TestCase):
    def test_redact_known_secret(self):
        pg.parse_proxy("socks5://bob:hunter2xyz@h:1")
        self.assertEqual(pg.redact("curl: hunter2xyz leaked"), "curl: *** leaked")

    def test_mask_proxy_free_text(self):
        self.assertEqual(pg.mask_proxy("socks5://bob:hunter2@h:1"), "socks5://bob:***@h:1")
        self.assertEqual(pg.mask_proxy("bob:hunter2@h:1"), "socks5h://bob:***@h:1")
        self.assertEqual(pg.mask_proxy("h:1:bob:hunter2"), "socks5h://bob:***@h:1")
        self.assertNotIn("hunter2", pg.mask_proxy("garbage bob:hunter2@ more"))

    def test_flag(self):
        self.assertEqual(pg.flag_emoji("CA"), "\U0001F1E8\U0001F1E6")
        self.assertIsNone(pg.flag_emoji(None))
        self.assertIsNone(pg.flag_emoji("CAN"))


if __name__ == "__main__":
    unittest.main()
