#!/usr/bin/env python3
"""Install Anemll archive contents into a HybridCoder repository."""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

SKIP_NAMES = {".git", ".github", ".DS_Store", "__MACOSX"}


@dataclass
class CopyStats:
    created: int = 0
    updated: int = 0
    skipped: int = 0



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Overlay Anemll zip contents into a HybridCoder repository",
    )
    parser.add_argument(
        "--zip",
        required=True,
        help="Path to a zip archive OR an https:// URL to a zip archive",
    )
    parser.add_argument("--repo-root", required=True, type=Path, help="Path to HybridCoder repository root")
    parser.add_argument(
        "--strip-components",
        type=int,
        default=1,
        help="Leading path components to strip from zip entries (default: 1)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show what would be copied without writing")
    return parser.parse_args()



def is_http_url(value: str) -> bool:
    parsed = urllib.parse.urlparse(value)
    return parsed.scheme in {"http", "https"} and bool(parsed.netloc)



def validate_repo_root(repo_root: Path) -> None:
    if not repo_root.exists() or not repo_root.is_dir():
        raise FileNotFoundError(f"Repository root not found: {repo_root}")
    if not (repo_root / ".git").exists():
        raise ValueError(f"Target does not look like a git repository: {repo_root}")



def resolve_zip_source(zip_arg: str, temp_dir: Path) -> Path:
    if is_http_url(zip_arg):
        destination = temp_dir / "download.zip"
        try:
            with urllib.request.urlopen(zip_arg) as response, destination.open("wb") as output:
                shutil.copyfileobj(response, output)
        except Exception as error:  # noqa: BLE001
            raise FileNotFoundError(f"Failed to download zip URL {zip_arg}: {error}") from error
        return destination

    zip_path = Path(zip_arg).expanduser().resolve()
    if not zip_path.exists() or not zip_path.is_file():
        raise FileNotFoundError(f"Zip archive not found: {zip_path}")
    return zip_path



def should_skip(parts: tuple[str, ...]) -> bool:
    return any(part in SKIP_NAMES for part in parts)



def safe_rel_from_zip(member_name: str, strip_components: int) -> Path | None:
    entry = PurePosixPath(member_name)
    parts = entry.parts
    if entry.is_absolute() or ".." in parts:
        raise ValueError(f"Refusing unsafe zip entry: {member_name}")

    if len(parts) <= strip_components:
        return None

    stripped = parts[strip_components:]
    if should_skip(stripped):
        return None

    return Path(*stripped)



def same_contents_bytes(dst: Path, content: bytes) -> bool:
    if not dst.exists() or dst.stat().st_size != len(content):
        return False
    return dst.read_bytes() == content



def overlay_zip(zip_path: Path, repo_root: Path, dry_run: bool, strip_components: int) -> CopyStats:
    stats = CopyStats()

    try:
        archive = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as error:
        raise ValueError(f"Invalid zip archive: {error}") from error

    with archive:
        for member in archive.infolist():
            if member.is_dir():
                continue

            rel = safe_rel_from_zip(member.filename, strip_components)
            if rel is None:
                stats.skipped += 1
                continue

            destination = repo_root / rel
            destination.parent.mkdir(parents=True, exist_ok=True)

            content = archive.read(member)

            if same_contents_bytes(destination, content):
                stats.skipped += 1
                continue

            if destination.exists():
                stats.updated += 1
            else:
                stats.created += 1

            if not dry_run:
                destination.write_bytes(content)

    return stats



def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.expanduser().resolve()
    strip_components = max(0, args.strip_components)

    try:
        validate_repo_root(repo_root)
    except (FileNotFoundError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="anemll_install_") as tmp:
        temp_dir = Path(tmp)
        try:
            zip_path = resolve_zip_source(args.zip, temp_dir)
            stats = overlay_zip(zip_path, repo_root, args.dry_run, strip_components)
        except (FileNotFoundError, ValueError) as error:
            print(f"Error: {error}", file=sys.stderr)
            return 2

    mode = "DRY RUN" if args.dry_run else "DONE"
    print(
        f"[{mode}] created={stats.created} updated={stats.updated} skipped={stats.skipped} "
        f"source={args.zip} target={repo_root} strip_components={strip_components}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
