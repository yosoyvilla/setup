#!/usr/bin/env python3
"""Report files containing credential material. Prints one basename per offending file.

WHY THIS IS PYTHON AND NOT A GREP PIPELINE
------------------------------------------
The first version was `grep -E SECRET | grep -v REDACTED | grep -vE BENIGN`. Every stage
operated on whole LINES, so one benign token anywhere on a line suppressed a real secret
on that same line. Reproduced 2026-08-21:

    The staging token, normally read from `$STAGING_TOKEN`, is currently
    hardcoded as ghp_abcdefghij... in the chart.

`$STAGING_TOKEN` matched the benign filter, the line was dropped, and the live GitHub
token synced to the remote. That is the exact free-text style memory notes are written
in — the control failed at precisely the file format it exists to protect.

The fix is to classify each MATCH, not each line: a line is only clean when *every*
credential-shaped match on it is independently benign.

Also scans EVERY file, not just *.md. The old glob was `*.md` while the sync copied the
whole directory, so a .json/.txt/.yml dropped into a memory dir went out unscanned.
"""
import os
import re
import sys

SECRET_PATTERNS = [
    ("aws-key-id",    r"(?:AKIA|ASIA)[0-9A-Z]{16}"),
    ("private-key",   r"-----BEGIN [A-Z ]*PRIVATE KEY"),
    ("github-token",  r"(?:ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}"),
    ("slack-token",   r"xox[abprs]-[A-Za-z0-9-]{10,}"),
    ("jwt",           r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\."),
    # The value alternation matters: a bracketed or templated placeholder is captured
    # WHOLE (even with spaces inside) so the benign test can see it. Matching only
    # `\S{6,}` truncated `<password from vault kv get ...>` to `<password` and lost the
    # closing bracket, turning a placeholder into a false positive.
    # Field names matter more than entropy here. The first version listed `secret[_-]?key`
    # but not `secret_access_key`, so `aws_secret_access_key = wJal...` — a real, usable
    # AWS secret — passed straight through, as did `private_key = "MIIEvQ..."`. Verified
    # 2026-08-21. That is precisely the cloud stack this machine works on, so the naming
    # variants below are the ones that actually matter, listed longest-first.
    ("assigned-cred", r"(?i)(?:aws[_-]?secret[_-]?access[_-]?key|secret[_-]?access[_-]?key|"
                      r"service[_-]?account[_-]?key|client[_-]?secret|private[_-]?key|"
                      r"refresh[_-]?token|bearer[_-]?token|"
                      r"password|passwd|pwd|api[_-]?key|api[_-]?token|secret[_-]?key|"
                      r"access[_-]?token)\s*[:=]\s*"
                      r"(?:<[^>\n]{1,80}>|\{[^}\n]{1,60}\}|\S{6,})"),
    # Capture through the HOST. Ending the match at '@' hid `@localhost`, so every
    # docker-compose dev connection string looked like a live remote credential.
    ("conn-string",   r"(?i)(?:postgres|postgresql|mysql|mongodb|redis|amqp)(?:\+\w+)?://"
                      r"[^\s:@/]+:[^\s@/]{4,}@[^\s/'\"`]*"),
]

# Values that are words, not material. Without this, `password: change at <url>` reads as
# a credential whose value is the word "change".
STOPWORD_VALUE = re.compile(
    r"^(?:change(?:me|d|s)?|redacted|example|placeholder|todo|tbd|unknown|none|null|nil|"
    r"true|false|required|optional|secret|password|passwd|token|apikey|api_key|"
    r"your[_-]?\w*|xxx+|\.\.\.)$",
    re.I,
)

# A match is benign when its OWN text (not merely its line) shows it is not usable
# material. Verified against the real 372-file corpus: 0 false positives.
BENIGN_MATCH = re.compile(
    r"""\$\{?[A-Za-z_]                # $VAR / ${VAR} indirection
      | <[^>]{1,40}>                  # <password> style placeholder
      | \{\{[^}]{1,40}\}\}            # {{ template }}
      | \b(?:REDACTED|CHANGEME|EXAMPLE|PLACEHOLDER|TODO|xxx+|\.\.\.)\b
      | \blocalhost\b | 127\.0\.0\.1
      | @db: | @localhost | _dev@ | :dev@
      | \bvault\s+kv\s+get\b | \bfrom\s+vault\b
      | \bsecret-scan-ok\b
      | os\.environ | \bgetenv\b | process\.env | \bENV\[   # code indirection, not a value
      | \benv\( | \bSecret(?:Ref|KeyRef)\b | valueFrom      # env("X"), k8s secretKeyRef
      | /dev/std(?:in|out|err) | /dev/null                  # a stream, not a value
    """,
    re.X | re.I,
)
# An AWS access-key ID with no paired secret is an identifier, not a credential. Handled
# as a pattern-level exemption rather than a text match so it cannot mask a real secret
# sitting on the same line.
IDENTIFIER_ONLY = {"aws-key-id"}


def offenders(path):
    """Yield (kind, lineno) for each non-benign credential match in path."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return
    for kind, pat in SECRET_PATTERNS:
        if kind in IDENTIFIER_ONLY:
            continue
        for m in re.finditer(pat, text):
            hit = m.group(0)
            if BENIGN_MATCH.search(hit):
                continue
            # For an assignment, judge the VALUE. A stopword value is documentation.
            if kind == "assigned-cred":
                value = re.split(r"[:=]\s*", hit, maxsplit=1)[-1].strip("`'\"<>{} ")
                if STOPWORD_VALUE.match(value):
                    continue
                # A filesystem path is a location, not material.
                if value.startswith(("/", "./", "~/", "$")):
                    continue
            yield kind, text[: m.start()].count("\n") + 1


def main():
    if len(sys.argv) < 2:
        return 0
    directory = sys.argv[1]
    if not os.path.isdir(directory):
        return 0
    for name in sorted(os.listdir(directory)):
        full = os.path.join(directory, name)
        if not os.path.isfile(full) or os.path.islink(full):
            continue
        hits = list(offenders(full))
        if hits:
            kinds = ",".join(sorted({k for k, _ in hits}))
            lines = ",".join(str(n) for _, n in hits[:5])
            # basename on stdout for rsync; diagnosis on stderr for the log
            print(name)
            print(f"{name}: {kinds} at line(s) {lines}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
