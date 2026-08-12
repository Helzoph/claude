#!/usr/bin/env python3
"""Synchronize Emil Kowalski's upstream skills into this plugin."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

COMPATIBILITY_SKILLS = ("pick-ui-library", "prototype", "review-animations")
SYNC_VERSION_BASE = "0.1.0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="Checked-out upstream repository containing the skills/ directory",
    )
    parser.add_argument(
        "--target",
        type=Path,
        default=Path("plugins/emil-design-skills/skills"),
        help="Plugin skills directory to replace",
    )
    parser.add_argument(
        "--revision",
        help="Upstream git revision; auto-detected when source is a git checkout",
    )
    return parser.parse_args()


def fail(message: str) -> None:
    raise RuntimeError(message)


def discover_skill_dirs(root: Path) -> list[Path]:
    skills_root = root / "skills"
    if not skills_root.is_dir():
        fail(f"Upstream skills directory not found: {skills_root}")

    skill_dirs = sorted(path for path in skills_root.iterdir() if path.is_dir())
    if not skill_dirs:
        fail(f"No skill directories found under: {skills_root}")

    missing = [path for path in skill_dirs if not (path / "SKILL.md").is_file()]
    if missing:
        names = ", ".join(path.name for path in missing)
        fail(f"Upstream directories missing SKILL.md: {names}")
    return skill_dirs


def frontmatter(text: str, skill_file: Path) -> list[str]:
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        fail(f"Missing YAML frontmatter: {skill_file}")

    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return lines[: index + 1]
    fail(f"Unterminated YAML frontmatter: {skill_file}")


def validate_skill_tree(root: Path, *, enforce_codex_compatibility: bool) -> list[str]:
    skill_dirs = discover_skill_dirs(root)
    names: list[str] = []
    for skill_dir in skill_dirs:
        skill_file = skill_dir / "SKILL.md"
        metadata = frontmatter(skill_file.read_text(encoding="utf-8"), skill_file)
        keys = {
            line.split(":", 1)[0].strip()
            for line in metadata
            if ":" in line and not line.lstrip().startswith("#")
        }
        if "name" not in keys or "description" not in keys:
            fail(f"Skill frontmatter needs name and description: {skill_file}")
        if enforce_codex_compatibility and any(
            line.strip() == "disable-model-invocation: true" for line in metadata
        ):
            fail(f"Codex-incompatible invocation flag remains: {skill_file}")
        names.append(skill_dir.name)
    return names


def normalize_codex_compatibility(root: Path) -> None:
    for skill_name in COMPATIBILITY_SKILLS:
        skill_file = root / "skills" / skill_name / "SKILL.md"
        if not skill_file.is_file():
            fail(f"Expected compatibility skill not found: {skill_file}")

        lines = skill_file.read_text(encoding="utf-8").splitlines(keepends=True)
        frontmatter_closed = False
        for index, line in enumerate(lines[1:], start=1):
            if line.strip() == "---":
                frontmatter_closed = True
                break
            if line.strip() == "disable-model-invocation: true":
                # Rationale: Codex rejects true for this field; normalize only the
                # known upstream metadata line and leave the skill body untouched.
                lines[index] = line.replace("true", "false")
                # Rationale: keep scanning until the closing delimiter; replacing a
                # metadata line does not mean the frontmatter has ended.
        if not frontmatter_closed:
            fail(f"Unterminated YAML frontmatter: {skill_file}")
        skill_file.write_text("".join(lines), encoding="utf-8")


def detect_revision(source: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(source), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    revision = result.stdout.strip()
    return revision or None


def update_plugin_versions(plugin_root: Path, revision: str) -> None:
    version = f"{SYNC_VERSION_BASE}+upstream.{revision[:12]}"
    for manifest_path in (
        plugin_root / ".claude-plugin" / "plugin.json",
        plugin_root / ".codex-plugin" / "plugin.json",
    ):
        if not manifest_path.is_file():
            fail(f"Plugin manifest not found: {manifest_path}")
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        payload["version"] = version
        manifest_path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )


def sync(source: Path, target: Path, revision: str | None) -> int:
    source = source.resolve()
    target = target.resolve()
    validate_skill_tree(source, enforce_codex_compatibility=False)

    target.parent.mkdir(parents=True, exist_ok=True)
    staging_root = Path(
        tempfile.mkdtemp(prefix=f".{target.name}.staging-", dir=target.parent)
    )
    staging = staging_root / "skills"
    try:
        # Rationale: stage and validate the complete tree before replacing the
        # existing copy, so a malformed upstream change cannot leave a partial plugin.
        shutil.copytree(source / "skills", staging)
        normalize_codex_compatibility(staging_root)
        skill_names = validate_skill_tree(
            staging_root,
            enforce_codex_compatibility=True,
        )

        if target.exists():
            if target.is_symlink():
                fail(f"Refusing to replace symlink target: {target}")
            # Rationale: this exact directory is the generated sync target; replacing
            # it removes stale upstream skills while preserving all plugin metadata.
            shutil.rmtree(target)
        staging.replace(target)
        staging_root.rmdir()
    except Exception:
        if staging_root.exists():
            shutil.rmtree(staging_root)
        raise

    license_source = source / "LICENSE"
    license_target = target.parent / "LICENSE"
    if (
        license_source.is_file()
        and license_source.resolve() != license_target.resolve()
    ):
        shutil.copy2(license_source, license_target)

    revision = revision or detect_revision(source)
    if revision:
        # Rationale: embedding the upstream commit in semver build metadata makes
        # plugin caches observe each sync without pretending this wrapper owns releases.
        update_plugin_versions(target.parent, revision)

    print(f"Synced {len(skill_names)} skills from {source}")
    if revision:
        print(f"Upstream revision: {revision}")
    return 0


def main() -> int:
    args = parse_args()
    try:
        return sync(args.source, args.target, args.revision)
    except (OSError, RuntimeError, json.JSONDecodeError) as error:
        print(f"Sync failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
