# repo-sync — clone/update every non-archived repository the token can see.
#
# Forge-agnostic: FORGE selects the API dialect (gitea | gitlab | github).
# Expects in the environment (set by the per-instance wrapper):
#   FORGE, BASE_URL, DEST_DIR, TOKEN         required
#   STATE_DIR                                 holds the pinned known_hosts
#   LOG_LEVEL                                 DEBUG | INFO | WARN | ERROR (default INFO)
#   SSH_HOST, SSH_PORT                        host/port whose key is pinned (default: host of BASE_URL, 22)
#
# Runs under writeShellApplication (bash, errexit/nounset/pipefail, shellcheck-clean).

IFS=$'\n\t'
umask 077

# ------------------------------ logging ---------------------------------------
lvl_num() { case "${1:-INFO}" in DEBUG) echo 0 ;; INFO) echo 1 ;; WARN) echo 2 ;; ERROR) echo 3 ;; *) echo 1 ;; esac }
should_log() { [ "$(lvl_num "${1}")" -ge "$(lvl_num "${LOG_LEVEL:-INFO}")" ]; }
log() {
  local level="${1:-INFO}"
  shift || true
  should_log "$level" || return 0
  local ts
  ts="$(date -Is)"
  local msg="${*:-}"
  local prio
  case "$level" in DEBUG) prio=debug ;; INFO) prio=info ;; WARN) prio=warning ;; ERROR) prio=err ;; esac
  if command -v systemd-cat >/dev/null 2>&1 && [ -n "${INVOCATION_ID:-}" ]; then
    printf '%s %s %s\n' "$ts" "$level" "$msg" | systemd-cat -t repo-sync -p "$prio"
  fi
  printf '[%s] %-5s %s\n' "$ts" "$level" "$msg" >&2
}
die() {
  log ERROR "$*"
  exit 1
}
on_err() {
  local rc="$1" line="$2"
  log ERROR "Unhandled error at ${BASH_SOURCE[0]}:${line} (rc=${rc})"
  exit "$rc"
}
trap 'on_err $? $LINENO' ERR
# ------------------------------------------------------------------------------

# ------------------------------ preflights ------------------------------------
FORGE="${FORGE:-gitea}"
: "${BASE_URL:?BASE_URL required (e.g. https://git.example.com)}"
: "${DEST_DIR:?DEST_DIR required (e.g. ~/git/example)}"
: "${TOKEN:?TOKEN required (personal access token)}"

case "$FORGE" in gitea | gitlab | github) ;; *) die "Unsupported FORGE: $FORGE (gitea|gitlab|github)" ;; esac

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
require_cmd curl
require_cmd jq
require_cmd git
require_cmd ssh-keyscan
require_cmd sed
require_cmd install

# Normalize base URL (strip trailing slash for consistency)
BASE_URL="${BASE_URL%/}"

if ! printf '%s' "$BASE_URL" | grep -Eq '^https?://[^/]+($|/)'; then
  die "BASE_URL seems invalid: $BASE_URL"
fi

# SSH endpoint to pin. GitHub's API lives on api.github.com but clones go to
# github.com, so default the host accordingly; everything else derives from BASE_URL.
if [ -z "${SSH_HOST:-}" ]; then
  if [ "$FORGE" = github ]; then
    SSH_HOST="github.com"
  else
    SSH_HOST="$(printf '%s\n' "$BASE_URL" | sed -E 's~^https?://([^/]+).*~\1~')"
  fi
fi
SSH_PORT="${SSH_PORT:-22}"

STATE_DIR="${STATE_DIR:-${STATE_DIRECTORY:-${XDG_STATE_HOME:-$HOME/.local/state}/repo-sync}}"
KNOWN_HOSTS="${STATE_DIR}/known_hosts"

install -m 700 -d "$STATE_DIR" || die "Failed to create state dir: $STATE_DIR"
install -m 755 -d "$DEST_DIR" || die "Failed to create dest dir: $DEST_DIR"
[ -w "$DEST_DIR" ] || die "Dest dir not writable: $DEST_DIR"

# Pin the host key (idempotent; warn on failure but continue — StrictHostKeyChecking
# still enforces trust if a key is already present).
if ! ssh-keyscan -p "$SSH_PORT" -T 5 "$SSH_HOST" >>"$KNOWN_HOSTS" 2>/dev/null; then
  log WARN "ssh-keyscan failed for ${SSH_HOST}:${SSH_PORT}; continuing"
fi
# git runs GIT_SSH_COMMAND through a shell, so the inner quotes ARE honoured —
# needed for space-containing state dirs (macOS "Application Support").
# shellcheck disable=SC2089,SC2090
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=\"$KNOWN_HOSTS\""

# ------------------------------ forge dialect ---------------------------------
# api <page>  → JSON array of repositories for that page (empty array = done)
# project     → jq program turning one element into "owner<TAB>name<TAB>ssh_url"
case "$FORGE" in
gitea)
  auth_header="Authorization: token ${TOKEN}"
  probe_url="${BASE_URL}/api/v1/version"
  api() { curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 -H "$auth_header" "${BASE_URL}/api/v1/user/repos?page=$1&limit=50"; }
  project='.[] | select(.archived|not) | "\((.owner.login // .owner.username))\t\(.name)\t\((.ssh_url // ""))"'
  ;;
gitlab)
  auth_header="PRIVATE-TOKEN: ${TOKEN}"
  probe_url="${BASE_URL}/api/v4/version"
  # membership=true: everything the token's user is a member of (any group depth);
  # namespace.full_path nests group/subgroup/… under DEST_DIR.
  api() { curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 -H "$auth_header" "${BASE_URL}/api/v4/projects?membership=true&archived=false&simple=true&per_page=100&page=$1"; }
  project='.[] | select((.archived // false)|not) | "\(.namespace.full_path)\t\(.path)\t\((.ssh_url_to_repo // ""))"'
  ;;
github)
  auth_header="Authorization: Bearer ${TOKEN}"
  probe_url="${BASE_URL}/rate_limit"
  api() { curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 -H "$auth_header" -H "Accept: application/vnd.github+json" "${BASE_URL}/user/repos?per_page=100&page=$1&affiliation=owner,collaborator,organization_member"; }
  project='.[] | select(.archived|not) | "\(.owner.login)\t\(.name)\t\((.ssh_url // ""))"'
  ;;
esac

# Quick connectivity probe (non-fatal but helpful)
if ! curl -fsS --connect-timeout 5 --max-time 10 -H "$auth_header" "$probe_url" >/dev/null 2>&1; then
  log WARN "${FORGE} API probe failed (${probe_url}); continuing anyway"
fi
# ------------------------------------------------------------------------------

log INFO "Starting ${FORGE} sync (base=${BASE_URL}, dest=${DEST_DIR}, ssh=${SSH_HOST}:${SSH_PORT})"

# Track results for summary
declare -a CLONED UPDATED SKIPPED_NO_SSH FETCH_FAILED PULL_FAILED CLONE_FAILED

clone_or_update() {
  local owner="$1" name="$2" ssh_url="$3"
  local repo_dir="${DEST_DIR}/${owner}/${name}"
  install -m 755 -d "$(dirname "$repo_dir")"

  if [ -d "$repo_dir/.git" ]; then
    log INFO "Updating ${owner}/${name}"
    if ! git -C "$repo_dir" fetch --all --prune; then
      log WARN "fetch failed for ${owner}/${name}"
      FETCH_FAILED+=("${owner}/${name}")
      return 0
    fi
    local branch
    branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD || echo main)"
    if ! git -C "$repo_dir" pull --ff-only origin "$branch"; then
      log WARN "pull (ff-only) failed for ${owner}/${name} on ${branch}"
      PULL_FAILED+=("${owner}/${name}")
    else
      UPDATED+=("${owner}/${name}")
    fi
  else
    log INFO "Cloning ${owner}/${name}"
    if ! git clone --depth=1 "$ssh_url" "$repo_dir"; then
      log ERROR "clone failed for ${owner}/${name}"
      CLONE_FAILED+=("${owner}/${name}")
      return 0
    fi
    CLONED+=("${owner}/${name}")
  fi
}
# ------------------------------------------------------------------------------

page=1
while :; do
  log DEBUG "Fetching page ${page}"
  chunk="$(api "$page")"

  # Stop when the API returns an empty array
  if [ "$(printf '%s' "$chunk" | jq 'length')" -eq 0 ]; then
    log INFO "No more repos (page ${page}). Done."
    break
  fi

  # Process substitution keeps the counters in this shell (not a subshell)
  while IFS=$'\t' read -r owner name ssh_url; do
    if [ -z "$ssh_url" ]; then
      log WARN "Skipping ${owner}/${name} (no ssh_url)"
      SKIPPED_NO_SSH+=("${owner}/${name}")
      continue
    fi
    clone_or_update "$owner" "$name" "$ssh_url"
  done < <(printf '%s\n' "$chunk" | jq -r "$project")

  page=$((page + 1))
done

# ------------------------------ summary ---------------------------------------
count() { printf '%s\n' "$#"; }

log INFO "Summary: cloned=$(count "${CLONED[@]:-}") updated=$(count "${UPDATED[@]:-}") skipped_no_ssh=$(count "${SKIPPED_NO_SSH[@]:-}") fetch_failed=$(count "${FETCH_FAILED[@]:-}") pull_failed=$(count "${PULL_FAILED[@]:-}") clone_failed=$(count "${CLONE_FAILED[@]:-}")"

print_section() {
  local title="$1"
  shift
  local -a items=("$@")
  [ "${#items[@]}" -eq 0 ] && return 0
  printf '\n=== %s (%d) ===\n' "$title" "${#items[@]}"
  printf '%s\n' "${items[@]}" | sort
}

print_section "CLONED" "${CLONED[@]:-}"
print_section "UPDATED" "${UPDATED[@]:-}"
print_section "SKIPPED (no ssh_url)" "${SKIPPED_NO_SSH[@]:-}"
print_section "FETCH FAILED" "${FETCH_FAILED[@]:-}"
print_section "PULL FAILED" "${PULL_FAILED[@]:-}"
print_section "CLONE FAILED" "${CLONE_FAILED[@]:-}"

log INFO "${FORGE} sync complete."
