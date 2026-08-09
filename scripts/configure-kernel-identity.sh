#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )); then
  printf 'Usage: %s KERNEL_SOURCE CONFIG_FRAGMENT\n' "$0" >&2
  exit 2
fi

kernel_source="$1"
config_fragment="$2"
defconfig="$kernel_source/arch/arm64/configs/gki_defconfig"
setlocalversion="$kernel_source/scripts/setlocalversion"

for required in \
  "$defconfig" \
  "$setlocalversion" \
  "$kernel_source/scripts/config" \
  "$config_fragment"; do
  [[ -f "$required" ]] || {
    printf 'Missing kernel identity input: %s\n' "$required" >&2
    exit 2
  }
done

while IFS='=' read -r option value; do
  [[ -z "$option" || "$option" == \#* ]] && continue
  symbol="${option#CONFIG_}"
  case "$value" in
    y) "$kernel_source/scripts/config" --file "$defconfig" -e "$symbol" ;;
    n) "$kernel_source/scripts/config" --file "$defconfig" -d "$symbol" ;;
    *) "$kernel_source/scripts/config" --file "$defconfig" --set-val "$symbol" "$value" ;;
  esac
done < "$config_fragment"

python3 - "$setlocalversion" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
updated, replacements = re.subn(
    r"(?m)^(scm_version\(\)\s*\{\s*\n)",
    r"\1\t# Disabled by NothingUsers kernel builder: do not append git/dirty suffix.\n\treturn 0\n",
    text,
    count=1,
)
if replacements != 1:
    raise SystemExit("Could not patch scm_version() in scripts/setlocalversion")
path.write_text(updated)
PY
chmod +x "$setlocalversion"

printf 'Kernel identity configured from %s\n' "$config_fragment"
