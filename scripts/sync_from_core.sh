#!/usr/bin/env bash
# Sync custom_components/google_assistant_sdk_custom with the google_assistant_sdk
# integration from a home-assistant/core release.
#
# The integration (including all translations) is taken from the homeassistant
# wheel published on PyPI, so no Lokalise access or core checkout is needed.
# Afterwards the domain/manifest are adjusted, scripts/custom.patch is applied
# and the minimum Home Assistant version in hacs.json is set to the oldest
# release that ships the same integration code.
#
# Usage: scripts/sync_from_core.sh [--no-patch] [HA_VERSION]
#   HA_VERSION  Home Assistant release to sync from (default: latest on PyPI).
#   --no-patch  Skip applying scripts/custom.patch. Useful for regenerating the
#               patch: run with --no-patch, commit or stash, re-apply the custom
#               changes by hand and save `git diff` to scripts/custom.patch.
#
# Nothing is committed; review the result with `git status` / `git diff`.

set -euo pipefail

APPLY_PATCH=1
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --no-patch) APPLY_PATCH=0 ;;
    -h | --help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) VERSION="$arg" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$REPO_ROOT/custom_components/google_assistant_sdk_custom"
PATCH="$REPO_ROOT/scripts/custom.patch"
UPSTREAM_DOMAIN="google_assistant_sdk"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL https://pypi.org/pypi/homeassistant/json |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])')"
fi
echo "Syncing from Home Assistant $VERSION"

WHEEL_URL="$(curl -fsSL "https://pypi.org/pypi/homeassistant/$VERSION/json" |
  python3 -c '
import json, sys
urls = [u["url"] for u in json.load(sys.stdin)["urls"] if u["filename"].endswith(".whl")]
print(urls[0] if urls else "")
')"
if [[ -z "$WHEEL_URL" ]]; then
  echo "No wheel found for homeassistant $VERSION" >&2
  exit 1
fi

echo "Downloading $WHEEL_URL"
curl -fsSL -o "$TMP/ha.whl" "$WHEEL_URL"
unzip -q "$TMP/ha.whl" "homeassistant/components/$UPSTREAM_DOMAIN/*" -d "$TMP/wheel"
SRC="$TMP/wheel/homeassistant/components/$UPSTREAM_DOMAIN"

# The minimum Home Assistant version is the oldest release that ships the same
# integration code (translations, strings and quality scale excluded), since
# that code is known to work with it.
echo "Finding the oldest release with the same integration code"
MIN_VERSION="$(python3 - "$SRC" "$VERSION" "$UPSTREAM_DOMAIN" <<'EOF'
import json
from pathlib import Path
import re
import sys
import urllib.error
import urllib.request

src, version, domain = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
files = sorted(
    p.name
    for p in src.iterdir()
    if p.is_file() and p.name not in ("quality_scale.yaml", "strings.json")
)


def key(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split("."))


with urllib.request.urlopen("https://pypi.org/pypi/homeassistant/json") as resp:
    releases = json.load(resp)["releases"]
older = sorted(
    (v for v in releases if re.fullmatch(r"\d+\.\d+\.\d+", v) and key(v) < key(version)),
    key=key,
    reverse=True,
)


def same_code(tag: str) -> bool:
    for name in files:
        url = (
            f"https://raw.githubusercontent.com/home-assistant/core/{tag}"
            f"/homeassistant/components/{domain}/{name}"
        )
        try:
            with urllib.request.urlopen(url) as resp:
                if resp.read() != (src / name).read_bytes():
                    return False
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return False
            raise
    return True


minimum = version
for tag in older:
    if not same_code(tag):
        break
    minimum = tag
print(minimum)
EOF
)"
echo "Minimum Home Assistant version: $MIN_VERSION"

# Replace the integration with the upstream copy (translations included).
rm -rf "$DST"
cp -r "$SRC" "$DST"
# Core-only metadata, not applicable to custom integrations.
rm -f "$DST/quality_scale.yaml"

# Rename the domain.
sed -i \
  -e "s/^DOMAIN: Final = \"$UPSTREAM_DOMAIN\"$/DOMAIN: Final = \"google_assistant_sdk_custom\"/" \
  -e 's/^DEFAULT_NAME: Final = "Google Assistant SDK"$/DEFAULT_NAME: Final = "Google Assistant SDK Custom"/' \
  "$DST/const.py"
grep -q '^DOMAIN: Final = "google_assistant_sdk_custom"$' "$DST/const.py" ||
  { echo "Failed to rename DOMAIN in const.py" >&2; exit 1; }

# Adjust manifest.json for a custom integration.
python3 - "$DST/manifest.json" <<'EOF'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    upstream = json.load(f)

requirements = [r.replace("==", ">=") for r in upstream.get("requirements", [])]
requirements.insert(0, "beautifulsoup4")

manifest = {}
for key, value in upstream.items():
    if key == "quality_scale":
        continue
    if key == "domain":
        value = "google_assistant_sdk_custom"
    elif key == "name":
        value = "Google Assistant SDK Custom"
    elif key == "documentation":
        value = "https://github.com/tronikos/google_assistant_sdk_custom"
    elif key == "requirements":
        value = requirements
    manifest[key] = value
    if key == "name":
        manifest["version"] = "0.0.0"
    elif key == "iot_class":
        manifest["issue_tracker"] = (
            "https://github.com/tronikos/google_assistant_sdk_custom/issues"
        )

# Same formatting as prettier: one key per line, short arrays inline.
lines = [f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}" for k, v in manifest.items()]
with open(path, "w", encoding="utf-8") as f:
    f.write("{\n" + ",\n".join(lines) + "\n}\n")
EOF

if [[ "$APPLY_PATCH" == 1 ]]; then
  echo "Applying $PATCH"
  if ! (cd "$REPO_ROOT" && git apply --reject --whitespace=nowarn "$PATCH"); then
    echo "Some hunks failed to apply. Resolve the *.rej files under $DST" >&2
    echo "and then refresh scripts/custom.patch." >&2
    exit 1
  fi
fi

# Update the minimum Home Assistant version required by HACS.
python3 - "$REPO_ROOT/hacs.json" "$MIN_VERSION" <<'EOF'
import json
import sys

path, version = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    hacs = json.load(f)
hacs["homeassistant"] = version
with open(path, "w", encoding="utf-8") as f:
    json.dump(hacs, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF

echo "Done. Synced from Home Assistant $VERSION (minimum $MIN_VERSION); review with 'git status' and 'git diff'."
