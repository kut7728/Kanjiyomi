#!/usr/bin/env python3
"""Turn-end check: behavior changes must update docs/.

Cursor stop hook stdout: {"followup_message": "..."} or {}.
Claude Code Stop hook also reads {"decision": "block", "reason": "..."}.
Prints {} when nothing should continue. One follow-up per change set
(loop_count >= 1, and hooks.json loop_limit 1).
"""
import json
import subprocess
import sys

SKIP_PREFIXES = (
    "docs/",
    "legacy/",
    ".cursor/hooks/",
    ".git/",
)
SKIP_EXACT = {
    ".cursor/hooks.json",
    ".claude/settings.json",
    ".DS_Store",
}
SKIP_NAMES = {
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "Podfile.lock",
    "Package.resolved",
    "Cargo.lock",
    "poetry.lock",
    "Gemfile.lock",
}


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")


def stop():
    emit({})
    raise SystemExit(0)


def git_bytes(*args):
    return subprocess.run(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    ).stdout


def changed_paths():
    raw = git_bytes("status", "--porcelain", "-uall", "-z")
    parts = raw.split(b"\0")
    paths = []
    i = 0
    while i < len(parts):
        item = parts[i]
        i += 1
        if len(item) < 4:
            continue
        status = item[:2]
        path = item[3:]
        if b"R" in status or b"C" in status:
            if i < len(parts) and parts[i]:
                path = parts[i]
                i += 1
        paths.append(path.decode("utf-8", "replace"))
    return paths


def is_docs(path):
    return path == "docs" or path.startswith("docs/")


def is_ignored(path):
    if path in SKIP_EXACT or path.startswith(SKIP_PREFIXES):
        return True
    name = path.rsplit("/", 1)[-1]
    return name in SKIP_NAMES or name == ".DS_Store"


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        stop()
    if not isinstance(payload, dict):
        stop()
    if payload.get("status", "completed") != "completed":
        stop()
    if int(payload.get("loop_count") or 0) >= 1:
        stop()
    if git_bytes("rev-parse", "--is-inside-work-tree").strip() != b"true":
        stop()

    docs_changed = False
    behavior = []
    for path in changed_paths():
        if is_docs(path):
            docs_changed = True
            continue
        if is_ignored(path):
            continue
        behavior.append(path)

    if not behavior or docs_changed:
        stop()

    shown = ", ".join(behavior[:12])
    if len(behavior) > 12:
        shown += " 외 {}개".format(len(behavior) - 12)
    message = (
        "사양이나 동작이 바뀔 수 있는 수정인데 docs/는 그대로입니다. "
        "코드를 더 고치기 전에 해당 문서와 그 단계 README.md 결정 표를 갱신하세요. "
        "바뀐 파일: " + shown + ". "
        "순수 리팩터링·오타·포맷뿐이면 문서 변경이 필요 없는 이유를 한 줄로 적고 종료하세요."
    )
    emit({
        "followup_message": message,
        "decision": "block",
        "reason": message,
    })


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        emit({})
        raise SystemExit(0)
