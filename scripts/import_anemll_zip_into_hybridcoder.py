#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

ANEMLL_CORE_SOURCE_DIR = Path("anemll-swift-cli") / "Sources" / "AnemllCore"
ANEMLL_CHAT_MANIFEST = Path("ANEMLLChat") / "ANEMLLChat" / "Models" / "ModelPackageManifest.swift"
TARGET_CORE_DIR = Path("ios") / "HybridCoder" / "Services" / "ANEMLLCore"
TARGET_MODELS_DIR = Path("ios") / "HybridCoder" / "Models" / "ANEMLL"
PATCH_PLAN_PATH = Path("docs") / "anemll-import-patch-plan.json"

REQUIRED_CORE_FILES = [
    "FFNChunk.swift",
    "InferenceManager.swift",
    "MetalArgmax.swift",
    "ModelLoader.swift",
    "SamplingConfig.swift",
    "Tokenizer.swift",
    "YAMLConfig.swift",
]

REPO_SENTINELS = [
    Path("ios") / "HybridCoder.xcodeproj" / "project.pbxproj",
    Path("ios") / "HybridCoder" / "Services" / "AIOrchestrator.swift",
    Path("ios") / "HybridCoder" / "Services" / "ModelRegistry.swift",
    Path("ios") / "HybridCoder" / "Views" / "ModelManagerView.swift",
]

PATCH_PLAN = {
    "xcode_packages": {
        "add": [
            {"url": "https://github.com/jpsim/Yams.git", "product": "Yams"},
            {"existing_package": "swift-transformers", "product": "Tokenizers"}
        ]
    },
    "registry": {
        "runtime_case": "anemll",
        "model_id": "anemll/imported-bundle",
        "display_name": "ANEMLL Imported Bundle"
    },
    "orchestrator": {
        "new_service": "ANEMLLCoderService",
        "required_methods": [
            "warmUpCodeGenerationModel branching by runtime",
            "unloadCodeGenerationModel branching by runtime",
            "generateCode branching by runtime",
            "generateCodeExplanation branching by runtime",
            "streaming code generation branching by runtime"
        ]
    },
    "ui": {
        "model_manager": "render all code-generation runtimes, not only the active Qwen runtime"
    }
}


@dataclass(frozen=True)
class ImportedFile:
    source: str
    destination: str
    sha256: str


def sha256_file(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def locate_anemll_root(extract_root: Path) -> Path:
    for candidate in extract_root.rglob("anemll-swift-cli"):
        if candidate.is_dir() and (candidate / "Sources" / "AnemllCore").is_dir():
            return candidate.parent
    raise RuntimeError("Could not locate anemll-swift-cli/Sources/AnemllCore inside the zip archive.")


def ensure_repo_layout(repo_root: Path) -> None:
    missing = [str(path) for path in REPO_SENTINELS if not (repo_root / path).exists()]
    if missing:
        raise RuntimeError(
            "Target repository does not match the expected HybridCoder layout. Missing: " + ", ".join(missing)
        )


def copy_file(source: Path, destination: Path) -> ImportedFile:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return ImportedFile(
        source=str(source),
        destination=str(destination),
        sha256=sha256_file(destination)
    )


def import_sources(zip_path: Path, repo_root: Path) -> list[ImportedFile]:
    imported: list[ImportedFile] = []
    with tempfile.TemporaryDirectory(prefix="anemll-import-") as temp_dir:
        extract_root = Path(temp_dir)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(extract_root)
        anemll_root = locate_anemll_root(extract_root)

        core_root = anemll_root / ANEMLL_CORE_SOURCE_DIR
        for file_name in REQUIRED_CORE_FILES:
            source = core_root / file_name
            if not source.exists():
                raise RuntimeError(f"Required ANEMLL source file is missing: {source}")
            imported.append(copy_file(source, repo_root / TARGET_CORE_DIR / file_name))

        manifest_source = anemll_root / ANEMLL_CHAT_MANIFEST
        if manifest_source.exists():
            imported.append(
                copy_file(
                    manifest_source,
                    repo_root / TARGET_MODELS_DIR / "ANEMLLModelPackageManifest.swift"
                )
            )
    return imported


def write_patch_plan(repo_root: Path) -> Path:
    destination = repo_root / PATCH_PLAN_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(PATCH_PLAN, indent=2) + "\n", encoding="utf-8")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description="Vendor ANEMLL sources into the HybridCoder repo.")
    parser.add_argument("--zip", required=True, type=Path, help="Path to Anemll-main.zip")
    parser.add_argument("--repo-root", required=True, type=Path, help="Path to the HybridCoder repo root")
    args = parser.parse_args()

    zip_path = args.zip.expanduser().resolve()
    repo_root = args.repo_root.expanduser().resolve()

    if not zip_path.exists():
        raise SystemExit(f"Zip file does not exist: {zip_path}")
    if not repo_root.exists():
        raise SystemExit(f"Repository root does not exist: {repo_root}")

    ensure_repo_layout(repo_root)
    imported = import_sources(zip_path, repo_root)
    patch_plan = write_patch_plan(repo_root)

    print("ANEMLL source import complete")
    print(f"Imported {len(imported)} files:")
    for item in imported:
        print(f"- {item.destination} [{item.sha256[:12]}]")
    print(f"Patch plan written to: {patch_plan}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"[anemll-import] ERROR: {exc}", file=sys.stderr)
        raise
