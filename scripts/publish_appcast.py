#!/usr/bin/env python3
"""Publish only the exact appcast of a verified stable GitHub release."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

from sparkle_tools import ROOT, read_appcast


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        if urllib.parse.urlsplit(new_url).scheme != "https":
            raise ValueError("Refusing non-HTTPS asset redirect")
        redirected = super().redirect_request(request, response, code, message, headers, new_url)
        # GitHub's asset endpoint redirects to a signed storage URL. Never send
        # the repository token to that host.
        if redirected is not None:
            redirected.remove_header("Authorization")
        return redirected


def fetch(url, token, *, destination=None, maximum=4 * 1024 * 1024, asset=False):
    if urllib.parse.urlsplit(url).netloc != "api.github.com":
        raise ValueError("Unexpected GitHub API endpoint")
    request = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/octet-stream" if asset else "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "AnyUsagePin-appcast-publisher",
    })
    opener = urllib.request.build_opener(SafeRedirect())
    with opener.open(request, timeout=120) as response:
        if destination is None:
            data = response.read(maximum + 1)
            if len(data) > maximum:
                raise ValueError("Release metadata exceeds size limit")
            return data
        total = 0
        with destination.open("wb") as output:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                total += len(chunk)
                if total > maximum:
                    raise ValueError("Downloaded asset exceeds declared size")
                output.write(chunk)
        if total != maximum:
            raise ValueError("Downloaded asset size differs from release metadata")


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def publish(options):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", options.repository):
        raise ValueError("Invalid repository")
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise ValueError("GH_TOKEN is required")
    endpoint = f"https://api.github.com/repos/{options.repository}/releases"
    selector = "latest"
    if options.release_tag:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", options.release_tag):
            raise ValueError("Release tag must be a stable vX.Y.Z tag")
        selector = "tags/" + options.release_tag
    release = json.loads(fetch(f"{endpoint}/{selector}", token))
    tag = release.get("tag_name", "")
    if release.get("draft") is not False or release.get("prerelease") is not False or not release.get("published_at"):
        raise ValueError("Release must be stable and published")
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Latest release does not have a stable version tag")
    version = tag[1:]
    names = ("appcast.xml", f"AnyUsagePin-{version}-macos-universal.dmg", "SHA256SUMS")
    assets = release.get("assets", [])
    if not isinstance(assets, list) or len(assets) >= 100:
        raise ValueError("Invalid or potentially truncated release assets")
    if sum(str(asset.get("name", "")).endswith(".dmg") for asset in assets) != 1:
        raise ValueError("Expected exactly one release DMG")
    selected = {}
    for name in names:
        matches = [asset for asset in assets if asset.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Missing or ambiguous release asset: {name}")
        asset = matches[0]
        if asset.get("state") != "uploaded" or type(asset.get("size")) is not int or asset["size"] <= 0 or type(asset.get("id")) is not int:
            raise ValueError(f"Incomplete release asset: {name}")
        expected_url = f"https://github.com/{options.repository}/releases/download/{tag}/{name}"
        if asset.get("browser_download_url") != expected_url:
            raise ValueError(f"Unexpected release asset URL: {name}")
        selected[name] = asset
    with tempfile.TemporaryDirectory(prefix="verified-appcast-") as temporary:
        directory = Path(temporary)
        for name, asset in selected.items():
            if name != names[1] and asset["size"] > 4 * 1024 * 1024:
                raise ValueError(f"Release metadata too large: {name}")
            fetch(f"https://api.github.com/repos/{options.repository}/releases/assets/{asset['id']}", token,
                  asset=True, destination=directory / name, maximum=asset["size"])
        data = (directory / "appcast.xml").read_bytes()
        item, enclosure, xml_version, _, signature = read_appcast(data)
        expected_url = selected[names[1]]["browser_download_url"]
        if xml_version != version or enclosure.get("url") != expected_url or int(enclosure.get("length")) != selected[names[1]]["size"]:
            raise ValueError("Appcast version, URL or size does not match release DMG")
        if item.findtext("link") != f"https://github.com/{options.repository}/releases/tag/{tag}":
            raise ValueError("Unexpected appcast release link")
        hashes = {}
        for line in (directory / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
            match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *]([^/\\]+)", line)
            if not match or match[2] in hashes or match[2] not in names[:2]:
                raise ValueError("Malformed, duplicate or unexpected SHA256SUMS entry")
            hashes[match[2]] = match[1].lower()
        if names[1] not in hashes:
            raise ValueError("SHA256SUMS does not include the final DMG")
        for name, expected in hashes.items():
            if checksum(directory / name) != expected:
                raise ValueError(f"SHA256 mismatch: {name}")
        with (ROOT / "macos/Runner/Info.plist").open("rb") as stream:
            public_key = base64.b64decode(plistlib.load(stream)["SUPublicEDKey"], validate=True)
        if len(public_key) != 32:
            raise ValueError("Malformed application Ed25519 public key")
        # RFC 8410 SubjectPublicKeyInfo wrapping the raw Ed25519 public key.
        (directory / "public.der").write_bytes(bytes.fromhex("302a300506032b6570032100") + public_key)
        (directory / "signature.bin").write_bytes(signature)
        result = subprocess.run([
            "openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER",
            "-inkey", str(directory / "public.der"), "-rawin",
            "-in", str(directory / names[1]), "-sigfile", str(directory / "signature.bin"),
        ], capture_output=True, text=True)
        if result.returncode:
            raise ValueError("DMG Ed25519 signature verification failed (OpenSSL 3 required)")
        options.output.mkdir(parents=True, exist_ok=True)
        (options.output / "appcast.xml").write_bytes(data)
    print(f"Verified {options.repository} {tag}; published exact appcast to {options.output / 'appcast.xml'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--release-tag", help="Verify a specific stable release locally; CI always uses latest")
    options = parser.parse_args()
    try:
        publish(options)
    except urllib.error.HTTPError as error:
        print(f"Publication failed: GitHub HTTP {error.code}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        print(f"Publication failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
