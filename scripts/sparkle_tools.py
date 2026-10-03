#!/usr/bin/env python3
"""Pinned Sparkle distribution and local Keychain-backed appcast generation."""

import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SPARKLE_VERSION = "2.10.0"
SPARKLE_SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE_URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{SPARKLE_VERSION}/Sparkle-{SPARKLE_VERSION}.tar.xz"
REPOSITORY = "TerryHuangHD/any-usage-pin"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def tools_dir() -> Path:
    destination = ROOT / "build/sparkle" / SPARKLE_VERSION
    required = ("bin/generate_appcast", "bin/sign_update", "bin/generate_keys", "Sparkle.framework/Sparkle")
    if all((destination / name).is_file() for name in required):
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sparkle-", dir=destination.parent) as temporary:
        temporary = Path(temporary)
        archive = temporary / "Sparkle.tar.xz"
        digest = hashlib.sha256()
        with urllib.request.urlopen(SPARKLE_URL, timeout=120) as response, archive.open("wb") as output:
            for chunk in iter(lambda: response.read(1024 * 1024), b""):
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != SPARKLE_SHA256:
            raise RuntimeError("Sparkle distribution SHA256 mismatch")
        extracted = temporary / "distribution"
        extracted.mkdir()
        # data filtering rejects traversal, device files and escaping symlinks,
        # while retaining the internal symlinks used by macOS frameworks.
        with tarfile.open(archive, "r:xz") as source:
            source.extractall(extracted, filter="data")
        if not all((extracted / name).is_file() for name in required):
            raise RuntimeError("Sparkle distribution is incomplete")
        if destination.exists():
            raise RuntimeError(f"Incomplete Sparkle installation; remove {destination} and retry")
        extracted.rename(destination)
    return destination


def read_appcast(data: bytes):
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise ValueError("Appcast must not contain DTDs or entities")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError("Malformed appcast XML") from error
    if root.tag != "rss" or root.attrib != {"version": "2.0"}:
        raise ValueError("Expected RSS 2.0 appcast")
    channels = root.findall("channel")
    if len(channels) != 1 or len(root) != 1:
        raise ValueError("Expected exactly one appcast channel")
    channel = channels[0]
    if channel.attrib:
        raise ValueError("Unexpected channel attributes")
    allowed_channel = {"title", "link", "description", "language", "item"}
    if any(child.tag not in allowed_channel for child in channel):
        raise ValueError("Unexpected appcast channel metadata")
    items = channel.findall("item")
    if len(items) != 1:
        raise ValueError("Expected exactly one full stable update")
    item = items[0]
    allowed_item = {"title", "link", "pubDate", "enclosure", f"{{{NS}}}version", f"{{{NS}}}shortVersionString", f"{{{NS}}}minimumSystemVersion", f"{{{NS}}}hardwareRequirements"}
    if item.attrib or any(child.tag not in allowed_item for child in item):
        raise ValueError("Unexpected update metadata (channels, deltas and conditional updates are forbidden)")
    if len({child.tag for child in item}) != len(item):
        raise ValueError("Duplicate update metadata")
    for child in item:
        if child.tag != "enclosure" and (child.attrib or len(child)):
            raise ValueError("Unexpected nested update metadata")
    if len([child.tag for child in channel if child.tag != "item"]) != len({child.tag for child in channel if child.tag != "item"}):
        raise ValueError("Duplicate channel metadata")
    for child in channel:
        if child.tag != "item" and (child.attrib or len(child)):
            raise ValueError("Unexpected nested channel metadata")
    enclosures = item.findall("enclosure")
    if len(enclosures) != 1 or len(enclosures[0]):
        raise ValueError("Expected one full-update enclosure")
    enclosure = enclosures[0]
    allowed_attributes = {"url", "length", "type", f"{{{NS}}}edSignature"}
    if set(enclosure.attrib) != allowed_attributes or enclosure.get("type") != "application/octet-stream":
        raise ValueError("Unexpected enclosure attributes")
    version = item.findtext(f"{{{NS}}}shortVersionString", "")
    build = item.findtext(f"{{{NS}}}version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*(?:\.\d+)*", build):
        raise ValueError("Malformed stable version or build")
    if not re.fullmatch(r"[1-9]\d*", enclosure.get("length", "")):
        raise ValueError("Malformed enclosure length")
    signature = base64.b64decode(enclosure.get(f"{{{NS}}}edSignature", ""), validate=True)
    if len(signature) != 64:
        raise ValueError("Malformed Ed25519 signature")
    return item, enclosure, version, build, signature


def create_appcast(dmg: Path, version: str, build: str) -> Path:
    dmg = Path(dmg).resolve()
    if not dmg.is_file() or dmg.suffix != ".dmg":
        raise ValueError("Appcast input must be a final DMG")
    release = f"https://github.com/{REPOSITORY}/releases"
    with tempfile.TemporaryDirectory(prefix="appcast-", dir=dmg.parent) as temporary:
        archive_dir = Path(temporary)
        staged = archive_dir / dmg.name
        try:
            os.link(dmg, staged)
        except OSError:
            shutil.copyfile(dmg, staged)
        subprocess.run([
            str(tools_dir() / "bin/generate_appcast"), "--account", "any-usage-pin",
            "--maximum-deltas", "0", "--maximum-versions", "1",
            "--download-url-prefix", f"{release}/download/v{version}/",
            "--link", f"{release}/tag/v{version}", str(archive_dir),
        ], check=True)
        data = (archive_dir / "appcast.xml").read_bytes()
        _, enclosure, actual_version, actual_build, _ = read_appcast(data)
        if (actual_version, actual_build) != (version, build):
            raise RuntimeError("Generated appcast version/build does not match signed application")
        if enclosure.get("url") != f"{release}/download/v{version}/{dmg.name}" or int(enclosure.get("length")) != dmg.stat().st_size:
            raise RuntimeError("Generated appcast does not reference the final DMG")
        if list(archive_dir.glob("*.delta")):
            raise RuntimeError("Unexpected delta update generated")
        output = dmg.parent / "appcast.xml"
        output.write_bytes(data)
    return output
