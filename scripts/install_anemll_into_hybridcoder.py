#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run_python(script: Path, *args: str) -> None:
    command = [sys.executable, str(script), *args]
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="End-to-end ANEMLL installer for a local HybridCoder checkout.")
    parser.add_argument("--zip", required=True, type=Path, help="Path to Anemll-main.zip")
    parser.add_argument("--repo-root", required=True, type=Path, help="Path to the HybridCoder repo root")
    parser.add_argument("--report", type=Path, help="Optional path for the import report")
    args = parser.parse_args()

    repo_root = args.repo_root.expanduser().resolve()
    zip_path = args.zip.expanduser().resolve()
    report_path = args.report.expanduser().resolve() if args.report else None

    import_script = Path(__file__).with_name("import_anemll_zip_into_hybridcoder.py")
    patch_script = Path(__file__).with_name("apply_anemll_runtime_patches.py")

    import_args = ["--zip", str(zip_path), "--repo-root", str(repo_root)]
    if report_path is not None:
        import_args.extend(["--report", str(report_path)])

    run_python(import_script, *import_args)
    run_python(patch_script, "--repo-root", str(repo_root))

    print("ANEMLL installation into HybridCoder completed.")
    print("Next step: open the Xcode project and build to verify any remaining compile drift.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
