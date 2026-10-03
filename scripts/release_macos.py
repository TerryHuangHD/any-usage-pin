#!/usr/bin/env python3
"""Build a Developer ID-signed universal app and notarized macOS disk image."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile

from sparkle_tools import create_appcast


ROOT = Path(__file__).resolve().parent.parent
TEAM_ID = "V6C4PTHC4J"
IDENTITY = "Developer ID Application: LI-SHENG TECHNOLOGY CO., LTD. (V6C4PTHC4J)"
BUNDLE_ID = "com.terryhuanghd.AnyUsagePin"


def run(arguments, *, capture=False, check=True):
    print("$ " + shlex.join(str(argument) for argument in arguments), flush=True)
    return subprocess.run(
        [str(argument) for argument in arguments],
        cwd=ROOT,
        text=True,
        capture_output=capture,
        check=check,
    )


def read_entitlements(component):
    result = run(
        ["codesign", "--display", "--entitlements", "-", "--xml", component],
        capture=True,
    )
    return plistlib.loads(result.stdout.encode("utf-8")) if result.stdout.strip() else {}


def sparkle_components(app):
    framework = app / "Contents/Frameworks/Sparkle.framework"
    version = framework / "Versions/B"
    components = [
        (version / "Autoupdate", version / "Autoupdate"),
        (version / "Updater.app", version / "Updater.app/Contents/MacOS/Updater"),
    ]
    for name in ("Installer", "Downloader"):
        bundle = version / f"XPCServices/{name}.xpc"
        if bundle.exists():
            components.append((bundle, bundle / f"Contents/MacOS/{name}"))
    components.append((framework, version / "Sparkle"))
    for component, executable in components:
        if not component.exists() or not executable.is_file():
            raise RuntimeError(f"Missing Sparkle distribution component: {component}")
    return components


def sign_sparkle(app):
    # Explicit inside-out order; retain the shipped helper entitlements, notably
    # Autoupdate's application identifier, rather than applying app entitlements.
    entitlements = {}
    with tempfile.TemporaryDirectory(prefix="sparkle-entitlements-") as directory:
        for index, (component, _) in enumerate(sparkle_components(app)):
            original = read_entitlements(component)
            entitlements[component] = original
            arguments = [
                "codesign", "--force", "--options", "runtime", "--timestamp",
                "--sign", IDENTITY,
            ]
            if original:
                entitlement_file = Path(directory) / f"{index}.plist"
                entitlement_file.write_bytes(plistlib.dumps(original))
                arguments.extend(["--entitlements", entitlement_file])
            run([*arguments, component])
    return entitlements


def verify_app(app, sparkle_entitlements):
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
    binaries = [
        app,
        app / "Contents/Frameworks/App.framework",
        app / "Contents/Frameworks/FlutterMacOS.framework",
    ]
    executables = [
        app / "Contents/MacOS/AnyUsagePin",
        binaries[1] / "Versions/A/App",
        binaries[2] / "Versions/A/FlutterMacOS",
    ]
    for component, executable in sparkle_components(app):
        binaries.append(component)
        executables.append(executable)
    for bundle, executable in zip(binaries, executables):
        run(["codesign", "--verify", "--strict", "--verbose=2", bundle])
        entitlements = read_entitlements(bundle)
        if entitlements.get("com.apple.security.get-task-allow"):
            raise RuntimeError(f"Release signature permits debugging: {bundle}")
        if bundle in sparkle_entitlements and entitlements != sparkle_entitlements[bundle]:
            raise RuntimeError(f"Sparkle entitlements changed during signing: {bundle}")
        signature = run(["codesign", "--display", "--verbose=4", bundle], capture=True)
        details = signature.stdout + signature.stderr
        if f"TeamIdentifier={TEAM_ID}" not in details or f"Authority={IDENTITY}" not in details:
            raise RuntimeError(f"Unexpected signing identity: {bundle}\n{details}")
        if "Timestamp=" not in details:
            raise RuntimeError(f"Missing secure signing timestamp: {bundle}")
        if "(runtime)" not in details:
            raise RuntimeError(f"Missing Hardened Runtime signature: {bundle}")
        architectures = set(run(["lipo", "-archs", executable], capture=True).stdout.split())
        if not {"arm64", "x86_64"}.issubset(architectures):
            raise RuntimeError(f"Expected a universal binary: {executable}: {architectures}")


def notarize(artifact, profile_arguments, output, *, staple_target=None):
    result = run(
        [
            "xcrun", "notarytool", "submit", artifact,
            *profile_arguments, "--wait", "--output-format", "json",
        ],
        capture=True,
        check=False,
    )
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Notarization did not return JSON: {result.stderr}\n{result.stdout}") from error
    (output / f"{artifact.name}.notary.json").write_text(
        json.dumps(response, indent=2) + "\n", encoding="utf-8",
    )
    submission_id = response.get("id")
    print(f"Notarization: {response.get('status')} ({submission_id})", flush=True)
    if result.returncode != 0 or response.get("status") != "Accepted":
        if submission_id:
            log = run(
                ["xcrun", "notarytool", "log", submission_id, *profile_arguments],
                capture=True,
                check=False,
            )
            (output / f"{artifact.name}.notary.log.json").write_text(
                log.stdout + log.stderr, encoding="utf-8",
            )
        raise RuntimeError(f"Apple has not accepted {artifact.name}; do not publish it")
    target = staple_target if staple_target is not None else artifact
    run(["xcrun", "stapler", "staple", target])
    run(["xcrun", "stapler", "validate", target])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notary-profile", help="Existing notarytool Keychain profile")
    parser.add_argument("--keychain", help="Keychain containing the notarytool profile")
    parser.add_argument(
        "--prepare-only", action="store_true",
        help="Build a signed, explicitly unnotarized DMG for local verification only",
    )
    options = parser.parse_args()
    if not options.prepare_only and not options.notary_profile:
        parser.error("--notary-profile is required for a formal, notarized release")
    if options.keychain and not options.notary_profile:
        parser.error("--keychain requires --notary-profile")

    profile_arguments = ["--keychain-profile", options.notary_profile] if options.notary_profile else []
    if options.keychain:
        profile_arguments.extend(["--keychain", options.keychain])
    if not options.prepare_only:
        run(["xcrun", "notarytool", "history", *profile_arguments, "--output-format", "json"], capture=True)

    run(["flutter", "build", "macos", "--release"])
    built_app = ROOT / "build/macos/Build/Products/Release/AnyUsagePin.app"
    with (built_app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleIdentifier"] != BUNDLE_ID:
        raise RuntimeError(f"Unexpected bundle identifier: {info['CFBundleIdentifier']}")
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    releases = ROOT / "build/releases"
    releases.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=f"{version}-{build}-", dir=releases))
    app = output / "AnyUsagePin.app"
    run(["ditto", built_app, app])
    sparkle_entitlements = sign_sparkle(app)
    # Sign remaining inner frameworks before the containing app.
    for framework in ("App.framework", "FlutterMacOS.framework"):
        run([
            "codesign", "--force", "--options", "runtime", "--timestamp",
            "--sign", IDENTITY, app / "Contents/Frameworks" / framework,
        ])
    run([
        "codesign", "--force", "--options", "runtime", "--timestamp",
        "--sign", IDENTITY, "--entitlements",
        ROOT / "macos/Runner/Release.entitlements", app,
    ])
    verify_app(app, sparkle_entitlements)

    if not options.prepare_only:
        archive = output / "AnyUsagePin.zip"
        run(["ditto", "-c", "-k", "--keepParent", app, archive])
        # The ZIP receives approval; the ticket is stapled to its contained app.
        notarize(archive, profile_arguments, output, staple_target=app)
        verify_app(app, sparkle_entitlements)
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", app])
        archive.unlink()

    staging = output / "dmg-content"
    staging.mkdir()
    run(["ditto", app, staging / app.name])
    (staging / "Applications").symlink_to("/Applications")
    suffix = "-unnotarized" if options.prepare_only else ""
    dmg = output / f"AnyUsagePin-{version}-macos-universal{suffix}.dmg"
    run(["hdiutil", "create", "-volname", f"AnyUsagePin {version}", "-srcfolder", staging, "-fs", "HFS+", "-format", "UDZO", dmg])
    run(["codesign", "--sign", IDENTITY, "--timestamp", "--verbose=2", dmg])
    run(["codesign", "--verify", "--strict", "--verbose=2", dmg])
    if not options.prepare_only:
        notarize(dmg, profile_arguments, output)
        run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg])

    # Never sign an update enclosure until Apple's ticket is stapled to the
    # final DMG. Neither appcast generation nor checksumming mutates that DMG.
    appcast = create_appcast(dmg, version, build) if not options.prepare_only else None
    checksums = []
    for artifact in (dmg, appcast):
        if artifact is None:
            continue
        digest = hashlib.sha256()
        with artifact.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        checksums.append(f"{digest.hexdigest()}  {artifact.name}\n")
    checksum_file = output / "SHA256SUMS"
    checksum_file.write_text("".join(checksums), encoding="utf-8")
    print(json.dumps({
        "dmg": str(dmg), "version": version, "build": build,
        "team_id": TEAM_ID, "notarized": not options.prepare_only,
        "appcast": str(appcast) if appcast is not None else None,
        "checksums": str(checksum_file),
    }, indent=2), flush=True)
    if options.prepare_only:
        print("Signed-only artifact: NOT notarized and NOT ready for a formal public release.", flush=True)


if __name__ == "__main__":
    main()
