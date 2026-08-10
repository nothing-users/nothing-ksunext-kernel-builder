#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )); then
  printf 'Usage: %s KLEAF_WORKSPACE KERNEL_SOURCE\n' "$0" >&2
  exit 2
fi

workspace="$1"
kernel_source="$2"
setup_env="$workspace/build/kernel/_setup_env.sh"

[[ -f "$setup_env" ]] || {
  printf 'Missing Kleaf environment script: %s\n' "$setup_env" >&2
  exit 2
}
git -C "$kernel_source" rev-parse --verify HEAD >/dev/null
source_date_epoch="$(git -C "$kernel_source" show -s --format=%ct HEAD)"
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || {
  printf 'Invalid kernel commit timestamp: %s\n' "$source_date_epoch" >&2
  exit 1
}

python3 - "$setup_env" "$source_date_epoch" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source_date_epoch = sys.argv[2]
text = path.read_text()
pattern = re.compile(
    r'export KBUILD_BUILD_TIMESTAMP="\$\(date -d @\$\{SOURCE_DATE_EPOCH\}\)"\n'
    r'export KBUILD_BUILD_HOST=build-host\n'
    r'export KBUILD_BUILD_USER=build-user\n'
)
replacement = (
    f"export SOURCE_DATE_EPOCH={source_date_epoch}\n"
    'export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@${SOURCE_DATE_EPOCH}")"\n'
    "export KBUILD_BUILD_HOST=mrvoki\n"
    "export KBUILD_BUILD_USER=wee\n"
)
updated, replacements = pattern.subn(replacement, text, count=1)
if replacements != 1:
    raise SystemExit("Could not patch Kleaf build identity defaults")
path.write_text(updated)
PY

chmod +x "$setup_env"
printf 'Kleaf identity configured: wee@mrvoki, SOURCE_DATE_EPOCH=%s\n' "$source_date_epoch"
