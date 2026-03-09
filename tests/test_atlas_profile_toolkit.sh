#!/bin/bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/atlas-profile-toolkit.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

HOME_DIR="$TMP_ROOT/home"
ATLAS_ROOT="$HOME_DIR/Library/Application Support/com.openai.atlas"
HOST_DIR="$ATLAS_ROOT/browser-data/host"
KIT_ROOT="$TMP_ROOT/kit"

mkdir -p "$HOST_DIR"

write_local_state() {
  cat > "$HOST_DIR/Local State" <<'EOF'
{
  "profile": {
    "last_used": "user-target",
    "last_active_profiles": ["user-target"],
    "info_cache": {
      "user-source": {"name": "Source"},
      "user-target": {"name": "Target"}
    }
  }
}
EOF
}

make_profile() {
  local name="$1"
  local history_count="$2"
  local bookmark_count="$3"
  local ext_count="$4"
  shift 4
  local cookies=("$@")

  local dir="$HOST_DIR/$name"
  mkdir -p "$dir/Extensions" "$dir/Local Storage"

  sqlite3 "$dir/History" <<SQL
CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT);
INSERT INTO urls (url) VALUES
$(for i in $(seq 1 "$history_count"); do
    if [ "$i" -eq "$history_count" ]; then
      printf "('https://history-%s.example/%s')" "$name" "$i"
    else
      printf "('https://history-%s.example/%s')," "$name" "$i"
    fi
  done);
SQL

  sqlite3 "$dir/Cookies" <<'SQL'
CREATE TABLE cookies (
  creation_utc INTEGER NOT NULL DEFAULT 0,
  host_key TEXT NOT NULL DEFAULT '',
  top_frame_site_key TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '',
  value TEXT NOT NULL DEFAULT '',
  encrypted_value BLOB NOT NULL DEFAULT X'',
  path TEXT NOT NULL DEFAULT '/',
  expires_utc INTEGER NOT NULL DEFAULT 0,
  is_secure INTEGER NOT NULL DEFAULT 0,
  is_httponly INTEGER NOT NULL DEFAULT 0,
  last_access_utc INTEGER NOT NULL DEFAULT 0,
  has_expires INTEGER NOT NULL DEFAULT 0,
  is_persistent INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 1,
  samesite INTEGER NOT NULL DEFAULT -1,
  source_scheme INTEGER NOT NULL DEFAULT 0,
  source_port INTEGER NOT NULL DEFAULT 0,
  last_update_utc INTEGER NOT NULL DEFAULT 0,
  source_type INTEGER NOT NULL DEFAULT 0,
  has_cross_site_ancestor INTEGER NOT NULL DEFAULT 0
);
SQL

  local cookie
  for cookie in "${cookies[@]}"; do
    IFS='|' read -r host key value <<< "$cookie"
    sqlite3 "$dir/Cookies" \
      "INSERT INTO cookies (host_key,name,value,encrypted_value,path) VALUES ('$host','$key','$value',X'00','/');"
  done

  python3 - <<'PY' "$dir/Bookmarks" "$bookmark_count" "$name"
import json, sys
path, count, name = sys.argv[1], int(sys.argv[2]), sys.argv[3]
children = []
for i in range(count):
    children.append({
        "date_added": "0",
        "guid": f"{name}-{i}",
        "id": str(i + 1),
        "name": f"{name}-bookmark-{i}",
        "type": "url",
        "url": f"https://{name}.bookmark/{i}"
    })
data = {
    "checksum": "",
    "roots": {
        "bookmark_bar": {"children": children, "name": "Bookmarks Bar", "type": "folder"},
        "other": {"children": [], "name": "Other Bookmarks", "type": "folder"},
        "synced": {"children": [], "name": "Mobile Bookmarks", "type": "folder"}
    },
    "version": 1
}
with open(path, "w") as fh:
    json.dump(data, fh)
PY

  local i
  for i in $(seq 1 "$ext_count"); do
    mkdir -p "$dir/Extensions/ext-$i/1.0.0"
  done
}

write_local_state
make_profile "user-source" 4 3 2 \
  ".chatgpt.com|session|old-openai" \
  ".youtube.com|yt|keep-youtube" \
  ".bilibili.com|bili|keep-bili"
make_profile "user-target" 1 0 0 \
  ".chatgpt.com|session|new-openai"

run_tool() {
  HOME="$HOME_DIR" \
  APP_NAME="Fake Atlas" \
  APP_PATH="/Applications/Fake Atlas.app" \
  ATLAS_ROOT="$ATLAS_ROOT" \
  HOST_DIR="$HOST_DIR" \
  LOCAL_STATE="$HOST_DIR/Local State" \
  ATLAS_PROFILE_KIT_ROOT="$KIT_ROOT" \
  ATLAS_SKIP_QUIT=1 \
  ATLAS_SKIP_OPEN=1 \
  bash "$SCRIPT" "$@"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [ "$actual" != "$expected" ]; then
    echo "ASSERTION FAILED: $msg (expected=$expected actual=$actual)" >&2
    exit 1
  fi
}

run_tool refresh-master user-source

MASTER="$KIT_ROOT/master-profile"
[ -d "$MASTER" ] || { echo "master profile missing" >&2; exit 1; }

master_openai="$(sqlite3 "$MASTER/Cookies" "select count(*) from cookies where host_key like '%chatgpt%' or host_key like '%openai%';")"
master_youtube="$(sqlite3 "$MASTER/Cookies" "select count(*) from cookies where host_key = '.youtube.com';")"
master_history="$(sqlite3 "$MASTER/History" "select count(*) from urls;")"
master_exts="$(find "$MASTER/Extensions" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"

assert_eq "$master_openai" "0" "master should scrub Atlas/OpenAI cookies"
assert_eq "$master_youtube" "1" "master should keep third-party cookies"
assert_eq "$master_history" "4" "master should keep history"
assert_eq "$master_exts" "2" "master should keep extensions"

run_tool inject-active

TARGET="$HOST_DIR/user-target"
target_openai="$(sqlite3 "$TARGET/Cookies" "select count(*) from cookies where host_key like '%chatgpt%' or host_key like '%openai%';")"
target_youtube="$(sqlite3 "$TARGET/Cookies" "select count(*) from cookies where host_key = '.youtube.com';")"
target_history="$(sqlite3 "$TARGET/History" "select count(*) from urls;")"
target_bookmarks="$(python3 - <<'PY' "$TARGET/Bookmarks"
import json, sys
data = json.load(open(sys.argv[1]))
print(len(data["roots"]["bookmark_bar"]["children"]))
PY
)"
target_exts="$(find "$TARGET/Extensions" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"

assert_eq "$target_openai" "1" "active target should keep current Atlas auth cookie"
assert_eq "$target_youtube" "1" "active target should inherit third-party cookies from master"
assert_eq "$target_history" "4" "active target should inherit master history"
assert_eq "$target_bookmarks" "3" "active target should inherit master bookmarks"
assert_eq "$target_exts" "2" "active target should inherit master extensions"

echo "atlas-profile-toolkit integration test passed"
