#!/usr/bin/env python3
"""Mirror Claude memory files (~/.claude/projects/*/memory/*.md) into Engram.

Modes:
  sync      (default) reconcile every memory file against the manifest:
            new file -> engram save; changed -> save new + delete old; same -> no-op.
  backfill  one-time: adopt existing Engram obs (by exact project+title from
            `engram export`) into the manifest so the already-imported ~180
            memories are NOT re-saved as duplicates.

Source of truth = the memory files. State = ~/.claude/engram-sync-state.json
({abs_path: {hash, obs_id, project, title}}). Secrets are never sent to Engram.
Deletions of memory files are intentionally NOT mirrored (no destructive cascade).
"""
from __future__ import annotations
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
MANIFEST = os.path.join(HOME, ".claude", "engram-sync-state.json")
LOG = os.path.join(HOME, ".claude", "engram-sync.log")
ENGRAM = "/opt/homebrew/bin/engram"

# Real secret VALUES (not mere mentions of "password"). Files matching are skipped.
SECRET_RE = re.compile(
    r"ghp_[0-9A-Za-z]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|"
    r"xox[baprs]-[0-9A-Za-z-]{10,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|"
    r"aws_secret_access_key|SECRET_ACCESS_KEY=[A-Za-z0-9/+]{20,}"
)
SAVED_RE = re.compile(r"^Memory saved: #(\d+)", re.M)


def log(msg: str) -> None:
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"{datetime.now().isoformat(timespec='seconds')} {msg}\n")


def iter_memory_files():
    for path in sorted(glob.glob(os.path.join(PROJECTS, "*", "memory", "*.md"))):
        if os.path.basename(path) == "MEMORY.md":
            continue
        yield path


def project_for(path: str) -> str:
    # path = .../projects/<projdir>/memory/<file>.md  ->  <projdir>
    projdir = os.path.basename(os.path.dirname(os.path.dirname(path)))
    if projdir == "-Users-davidvilla":
        return "global"
    prefix = "-Users-davidvilla-Documents-"
    name = projdir[len(prefix):] if projdir.startswith(prefix) else projdir
    return name.lower()


def extract(text: str, path: str):
    """Return (title, body) using the SAME logic as the original bulk import."""
    desc = name = None
    body = text
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        end = None
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                end = i
                break
        if end is not None:
            for l in lines[1:end]:
                if desc is None and l.startswith("description:"):
                    desc = l[len("description:"):].strip().strip('"').strip("'")
                elif name is None and l.startswith("name:"):
                    name = l.split(":", 1)[1].strip()
            body = "\n".join(lines[end + 1:])
    title = desc or name or os.path.splitext(os.path.basename(path))[0]
    body = body.strip("\n")
    if not body.strip():
        body = text
    return title, body


def content_hash(title: str, body: str) -> str:
    return hashlib.sha256((title + "\x00" + body).encode("utf-8")).hexdigest()


def load_manifest() -> dict:
    try:
        with open(MANIFEST, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_manifest(m: dict) -> None:
    tmp = MANIFEST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2, sort_keys=True)
    os.replace(tmp, MANIFEST)


def engram_save(title: str, body: str, project: str):
    r = subprocess.run(
        [ENGRAM, "save", title, body, "--project", project],
        capture_output=True, text=True,
    )
    m = SAVED_RE.search(r.stdout or "")
    if m:
        return m.group(1)
    log(f"save FAILED proj={project} title={title!r} rc={r.returncode} "
        f"err={(r.stderr or '')[:200]!r} out={(r.stdout or '')[:200]!r}")
    return None


def engram_delete(obs_id: str) -> None:
    subprocess.run([ENGRAM, "delete", str(obs_id)], capture_output=True, text=True)


def engram_obs_count():
    r = subprocess.run([ENGRAM, "stats"], capture_output=True, text=True)
    m = re.search(r"Observations:\s*(\d+)", r.stdout or "")
    return int(m.group(1)) if m else None


def backfill():
    export_path = "/tmp/engram_export_backfill.json"
    subprocess.run([ENGRAM, "export", export_path], capture_output=True, text=True)
    with open(export_path, encoding="utf-8") as f:
        data = json.load(f)
    lookup = {}
    for o in data.get("observations", []):
        lookup.setdefault((o.get("project", ""), o.get("title", "")), str(o.get("id")))
    manifest = {}
    matched = unmatched = 0
    for path in iter_memory_files():
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        proj = project_for(path)
        title, body = extract(text, path)
        oid = lookup.get((proj, title))
        if oid:
            manifest[path] = {"hash": content_hash(title, body), "obs_id": oid,
                              "project": proj, "title": title}
            matched += 1
        else:
            unmatched += 1
            log(f"backfill: NO MATCH {path} (proj={proj} title={title!r})")
    save_manifest(manifest)
    print(f"backfill: matched={matched} unmatched={unmatched} manifest={len(manifest)}")


def sync():
    manifest = load_manifest()
    # SAFETY GUARD: a lost/corrupt manifest would make every file look "new" and
    # mass-duplicate all memories in Engram. If the manifest is empty but Engram
    # already holds observations, refuse to run and tell the user to backfill.
    if not manifest:
        cnt = engram_obs_count()
        if cnt and cnt > 0:
            log(f"ABORT: manifest empty/missing but Engram has {cnt} observations. "
                f"Refusing to mass re-save. Run `engram-sync.py backfill` to rebuild the manifest.")
            print("sync: ABORTED — manifest empty but Engram non-empty (run backfill)")
            return
    new = changed = noop = skipped_secret = 0
    for path in iter_memory_files():
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        if SECRET_RE.search(text):
            skipped_secret += 1
            log(f"sync: SKIP secret {path}")
            continue
        proj = project_for(path)
        title, body = extract(text, path)
        h = content_hash(title, body)
        ent = manifest.get(path)
        if ent is None:
            oid = engram_save(title, body, proj)
            if oid:
                manifest[path] = {"hash": h, "obs_id": oid, "project": proj, "title": title}
                new += 1
        elif ent.get("hash") != h:
            oid = engram_save(title, body, proj)  # save new BEFORE deleting old
            if oid:
                engram_delete(ent.get("obs_id"))
                manifest[path] = {"hash": h, "obs_id": oid, "project": proj, "title": title}
                changed += 1
        else:
            noop += 1
    save_manifest(manifest)
    print(f"sync: new={new} changed={changed} noop={noop} skipped_secret={skipped_secret}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "sync"
    if mode == "backfill":
        backfill()
    else:
        sync()
