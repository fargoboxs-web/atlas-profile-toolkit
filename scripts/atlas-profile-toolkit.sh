#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-ChatGPT Atlas}"
APP_PATH="${APP_PATH:-/Applications/ChatGPT Atlas.app}"
ATLAS_ROOT="${ATLAS_ROOT:-$HOME/Library/Application Support/com.openai.atlas}"
HOST_DIR="${HOST_DIR:-$ATLAS_ROOT/browser-data/host}"
LOCAL_STATE="${LOCAL_STATE:-$HOST_DIR/Local State}"
KIT_ROOT="${ATLAS_PROFILE_KIT_ROOT:-$HOME/.atlas-profile-kit}"
MASTER_PROFILE_DIR="$KIT_ROOT/master-profile"
BACKUP_ROOT="$KIT_ROOT/backups"
META_DIR="$KIT_ROOT/meta"
COOKIE_MATCH_WHERE="host_key LIKE '%chatgpt%' OR host_key LIKE '%openai%' OR host_key LIKE '%auth0%' OR host_key LIKE '%oaistatic%' OR host_key LIKE '%sentinel%'"

usage() {
  cat <<'EOF'
Usage: atlas-profile-toolkit.sh <command> [args]

Commands:
  help                   Show this help
  list                   Show Atlas profiles found on this machine
  refresh-master [name]  Refresh the saved master from a profile, scrubbing Atlas auth from the master copy
  capture-master [name]  Snapshot the active Atlas user profile into a scrubbed master copy
  prepare-switch         Copy the scrubbed master into Atlas staging profiles for the next account switch
  inject-active          Inject the saved master into the current active profile while preserving current Atlas auth
  restore-active         Replace the current active Atlas user profile with the scrubbed master
  open                   Open ChatGPT Atlas

Notes:
  - Atlas is always closed before profile data is copied.
  - refresh-master and capture-master remove Atlas/OpenAI auth state from the saved master.
  - inject-active keeps the current Atlas/OpenAI auth state while importing the master browser environment.
  - restore-active is the fallback command if a new Atlas account still opens into a sparse environment.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ensure_prereqs() {
  need_cmd python3
  need_cmd sqlite3
  need_cmd rsync
  need_cmd osascript
  need_cmd open

  [ -d "$ATLAS_ROOT" ] || {
    echo "Atlas data root not found: $ATLAS_ROOT" >&2
    exit 1
  }
  [ -d "$HOST_DIR" ] || {
    echo "Atlas host profile dir not found: $HOST_DIR" >&2
    exit 1
  }
  [ -f "$LOCAL_STATE" ] || {
    echo "Atlas Local State not found: $LOCAL_STATE" >&2
    exit 1
  }
}

timestamp() {
  date '+%Y%m%d_%H%M%S'
}

ensure_kit_dirs() {
  mkdir -p "$KIT_ROOT" "$BACKUP_ROOT" "$META_DIR"
}

atlas_running() {
  [ "${ATLAS_SKIP_QUIT:-0}" = "1" ] && return 1
  pgrep -x "$APP_NAME" >/dev/null 2>&1
}

quit_atlas() {
  [ "${ATLAS_SKIP_QUIT:-0}" = "1" ] && return 0
  if atlas_running; then
    echo "Closing $APP_NAME ..."
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 5); do
      atlas_running || return 0
      sleep 1
    done

    echo "AppleScript quit did not stop Atlas. Sending TERM to Atlas processes ..."
    pkill -TERM -f '/Applications/ChatGPT Atlas.app/Contents/.*/ChatGPT Atlas' >/dev/null 2>&1 || true

    for _ in $(seq 1 10); do
      atlas_running || return 0
      sleep 1
    done
    echo "Atlas did not exit cleanly within 15 seconds." >&2
    exit 1
  fi
}

open_atlas() {
  [ "${ATLAS_SKIP_OPEN:-0}" = "1" ] && return 0
  open -a "$APP_PATH"
}

active_profile_name() {
  python3 - <<'PY' "$LOCAL_STATE"
import json, sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text())
profile = state.get("profile", {})
print(profile.get("last_used", "Default"))
PY
}

profile_path() {
  local name="$1"
  printf '%s\n' "$HOST_DIR/$name"
}

list_profiles() {
  python3 - <<'PY' "$LOCAL_STATE" "$HOST_DIR"
import json
import sys
import time
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text())
host_dir = Path(sys.argv[2])
profile = state.get("profile", {})
active = profile.get("last_used", "Default")
info_cache = profile.get("info_cache", {})

dirs = {}
for path in host_dir.iterdir():
    if not path.is_dir():
        continue
    name = path.name
    if name == "Default" or name.startswith("user-") or name.startswith("login-staging"):
        dirs[name] = path

print(f"Active profile: {active}")
print("")
for name in sorted(dirs):
    info = info_cache.get(name, {})
    label = []
    if name == active:
        label.append("ACTIVE")
    if name.startswith("login-staging"):
        label.append("STAGING")
    elif name.startswith("user-"):
        label.append("USER")
    else:
        label.append("BASE")
    mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(dirs[name].stat().st_mtime))
    display = info.get("name", "")
    marker = ",".join(label)
    print(f"{name}\t{marker}\t{mtime}\t{display}")
PY
}

copy_profile() {
  local src="$1"
  local dest="$2"

  mkdir -p "$dest"
  rsync -a --delete --ignore-times \
    --exclude='Cache' \
    --exclude='Code Cache' \
    --exclude='GPUCache' \
    --exclude='DawnCache' \
    --exclude='DawnGraphiteCache' \
    --exclude='GrShaderCache' \
    --exclude='GraphiteDawnCache' \
    --exclude='ShaderCache' \
    --exclude='*.tmp' \
    --exclude='LOCK' \
    --exclude='lockfile' \
    "$src/" "$dest/"
}

backup_dir() {
  local src="$1"
  local label="$2"
  local stamp
  stamp="$(timestamp)"
  local dest="$BACKUP_ROOT/${stamp}_${label}"

  if [ -d "$src" ]; then
    mkdir -p "$dest"
    rsync -a "$src/" "$dest/"
    echo "Backup saved: $dest"
  fi
}

find_profile_dirs() {
  local pattern="$1"
  find "$HOST_DIR" -maxdepth 1 -mindepth 1 -type d -name "$pattern" -print | sort
}

remove_auth_storage_paths() {
  local root="$1"
  if [ -d "$root" ]; then
    find "$root" \
      \( -iname '*chatgpt*' -o -iname '*openai*' -o -iname '*oaistatic*' -o -iname '*sentinel*' -o -iname '*auth0*' \) \
      -exec rm -rf {} +
  fi
}

copy_auth_storage_paths() {
  local src_root="$1"
  local dest_root="$2"

  [ -d "$src_root" ] || return 0

  python3 - <<'PY' "$src_root" "$dest_root"
import os
import shutil
import sys
from pathlib import Path

patterns = ("chatgpt", "openai", "auth0", "oaistatic", "sentinel")
src = Path(sys.argv[1])
dest = Path(sys.argv[2])

if not src.exists():
    raise SystemExit(0)

for current, dirs, files in os.walk(src):
    current_path = Path(current)
    rel = current_path.relative_to(src)
    rel_str = "" if str(rel) == "." else str(rel).lower()

    if rel_str and any(pattern in rel_str for pattern in patterns):
        target = dest / rel
        shutil.copytree(current_path, target, dirs_exist_ok=True)
        dirs[:] = []
        continue

    for filename in files:
        file_rel = Path(filename) if str(rel) == "." else rel / filename
        rel_lower = str(file_rel).lower()
        if any(pattern in rel_lower for pattern in patterns):
            target = dest / file_rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(current_path / filename, target)
PY
}

create_cookie_snapshot() {
  local src_db="$1"
  local dest_db="$2"

  [ -f "$src_db" ] || return 0
  mkdir -p "$(dirname "$dest_db")"

  python3 - <<'PY' "$src_db" "$dest_db" "$COOKIE_MATCH_WHERE"
import sqlite3
import sys
from pathlib import Path

src_db, dest_db, where = sys.argv[1:]
src = sqlite3.connect(src_db)
dest_path = Path(dest_db)
if dest_path.exists():
    dest_path.unlink()
dest = sqlite3.connect(dest_db)

schema_row = src.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='cookies'").fetchone()
if schema_row is None:
    raise SystemExit(0)

dest.execute(schema_row[0])
cols = [row[1] for row in src.execute("PRAGMA table_info(cookies)")]
column_list = ", ".join(cols)
placeholders = ", ".join("?" for _ in cols)
rows = src.execute(f"SELECT {column_list} FROM cookies WHERE {where}").fetchall()
if rows:
    dest.executemany(f"INSERT INTO cookies ({column_list}) VALUES ({placeholders})", rows)
dest.commit()
src.close()
dest.close()
PY
}

restore_cookie_snapshot() {
  local snapshot_db="$1"
  local target_db="$2"

  [ -f "$snapshot_db" ] || return 0
  mkdir -p "$(dirname "$target_db")"

  python3 - <<'PY' "$snapshot_db" "$target_db" "$COOKIE_MATCH_WHERE"
import shutil
import sqlite3
import sys
from pathlib import Path

snapshot_db, target_db, where = sys.argv[1:]
snapshot_path = Path(snapshot_db)
target_path = Path(target_db)

if not snapshot_path.exists():
    raise SystemExit(0)

if not target_path.exists():
    shutil.copy2(snapshot_path, target_path)
    raise SystemExit(0)

src = sqlite3.connect(snapshot_db)
dest = sqlite3.connect(target_db)

schema_row = src.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='cookies'").fetchone()
if schema_row is None:
    raise SystemExit(0)

dest.execute(schema_row[0].replace("CREATE TABLE cookies", "CREATE TABLE IF NOT EXISTS cookies", 1))
cols = [row[1] for row in src.execute("PRAGMA table_info(cookies)")]
column_list = ", ".join(cols)
placeholders = ", ".join("?" for _ in cols)
rows = src.execute(f"SELECT {column_list} FROM cookies").fetchall()

dest.execute(f"DELETE FROM cookies WHERE {where}")
if rows:
    dest.executemany(f"INSERT INTO cookies ({column_list}) VALUES ({placeholders})", rows)
dest.commit()
src.close()
dest.close()
PY
}

extract_auth_snapshot() {
  local src="$1"
  local snapshot="$2"

  mkdir -p "$snapshot"

  local rel
  for rel in "Cookies" "Network/Cookies"; do
    create_cookie_snapshot "$src/$rel" "$snapshot/$rel"
  done

  for rel in "IndexedDB" "Local Storage" "Session Storage" "Service Worker" "Storage" "WebStorage"; do
    copy_auth_storage_paths "$src/$rel" "$snapshot/$rel"
  done
}

restore_auth_snapshot() {
  local snapshot="$1"
  local target="$2"

  local rel
  for rel in "Cookies" "Network/Cookies"; do
    restore_cookie_snapshot "$snapshot/$rel" "$target/$rel"
  done

  for rel in "IndexedDB" "Local Storage" "Session Storage" "Service Worker" "Storage" "WebStorage"; do
    remove_auth_storage_paths "$target/$rel"
    copy_auth_storage_paths "$snapshot/$rel" "$target/$rel"
  done
}

scrub_master_profile() {
  local target="$1"

  local cookie_db
  for cookie_db in "$target/Cookies" "$target/Network/Cookies"; do
    if [ -f "$cookie_db" ]; then
      sqlite3 "$cookie_db" <<SQL
DELETE FROM cookies
WHERE $COOKIE_MATCH_WHERE;
VACUUM;
SQL
    fi
  done

  local search_root
  for search_root in \
    "$target/IndexedDB" \
    "$target/Local Storage" \
    "$target/Session Storage" \
    "$target/Service Worker" \
    "$target/Storage" \
    "$target/WebStorage"; do
    remove_auth_storage_paths "$search_root"
  done

  rm -rf \
    "$target/Extension State/LOG" \
    "$target/Extension State/LOG.old" \
    "$target/Extensions Temp" \
    "$target/Sessions"
}

refresh_master() {
  local source_name="${1:-$(active_profile_name)}"
  local source_path
  source_path="$(profile_path "$source_name")"
  [ -d "$source_path" ] || {
    echo "Source profile does not exist: $source_name" >&2
    exit 1
  }

  ensure_kit_dirs
  quit_atlas

  if [ -d "$MASTER_PROFILE_DIR" ]; then
    backup_dir "$MASTER_PROFILE_DIR" "previous-master"
  fi

  local temp_dir="$KIT_ROOT/.master-$(timestamp)"
  mkdir -p "$temp_dir"

  echo "Capturing Atlas profile: $source_name"
  copy_profile "$source_path" "$temp_dir"
  scrub_master_profile "$temp_dir"

  rm -rf "$MASTER_PROFILE_DIR"
  mv "$temp_dir" "$MASTER_PROFILE_DIR"
  printf '%s\n' "$source_name" > "$META_DIR/master-source.txt"

  echo "Master profile saved to: $MASTER_PROFILE_DIR"
}

capture_master() {
  refresh_master "${1:-}"
}

require_master() {
  [ -d "$MASTER_PROFILE_DIR" ] || {
    echo "Master profile not found. Run: $0 refresh-master" >&2
    exit 1
  }
}

prepare_switch() {
  require_master
  ensure_kit_dirs
  quit_atlas

  local targets=()
  while IFS= read -r line; do
    [ -n "$line" ] && targets+=("$line")
  done < <(printf '%s\n' "$HOST_DIR/Default"; find_profile_dirs 'login-staging*')

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "No staging targets found." >&2
    exit 1
  fi

  echo "Preparing Atlas staging profiles ..."
  local target
  for target in "${targets[@]}"; do
    backup_dir "$target" "prepare-switch-$(basename "$target")"
    copy_profile "$MASTER_PROFILE_DIR" "$target"
    echo "Seeded: $target"
  done
}

restore_active() {
  require_master
  ensure_kit_dirs
  quit_atlas

  local active_name
  active_name="$(active_profile_name)"
  local active_path
  active_path="$(profile_path "$active_name")"
  [ -d "$active_path" ] || {
    echo "Active profile does not exist: $active_name" >&2
    exit 1
  }

  backup_dir "$active_path" "restore-active-${active_name}"
  copy_profile "$MASTER_PROFILE_DIR" "$active_path"

  echo "Restored scrubbed master into active profile: $active_name"
  echo "Atlas login will need to be completed again after reopening the app."
}

inject_active() {
  require_master
  ensure_kit_dirs
  quit_atlas

  local active_name
  active_name="$(active_profile_name)"
  local active_path
  active_path="$(profile_path "$active_name")"
  [ -d "$active_path" ] || {
    echo "Active profile does not exist: $active_name" >&2
    exit 1
  }

  local auth_snapshot="$KIT_ROOT/.auth-$(timestamp)"
  mkdir -p "$auth_snapshot"

  backup_dir "$active_path" "inject-active-${active_name}"
  echo "Extracting current Atlas auth from: $active_name"
  extract_auth_snapshot "$active_path" "$auth_snapshot"

  echo "Injecting master into active profile: $active_name"
  copy_profile "$MASTER_PROFILE_DIR" "$active_path"
  restore_auth_snapshot "$auth_snapshot" "$active_path"
  rm -rf "$auth_snapshot"

  echo "Injected master into active profile while preserving current Atlas auth: $active_name"
}

main() {
  ensure_prereqs

  local cmd="${1:-help}"
  case "$cmd" in
    help|-h|--help)
      usage
      ;;
    list)
      list_profiles
      ;;
    refresh-master)
      refresh_master "${2:-}"
      ;;
    capture-master)
      capture_master "${2:-}"
      ;;
    prepare-switch)
      prepare_switch
      ;;
    inject-active)
      inject_active
      ;;
    restore-active)
      restore_active
      ;;
    open)
      open_atlas
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
