#!/usr/bin/env bash
set -euo pipefail

GIT_HOSTNAME="github.com"
BREW="/opt/homebrew/bin/brew"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DO_SSH=1
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_github"
SSH_KEY_TITLE=""

usage() {
  cat >&2 <<'EOT'
Usage: ./setup.sh [--no-ssh] [--ssh-key-title "<title>"]

Options:
  --no-ssh             SSH鍵の生成・登録・リモート切替をスキップ
  --ssh-key-title STR  鍵コメント（既定: github-<hostname>-<YYYYMMDD>）
EOT
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-ssh) DO_SSH=0; shift ;;
    --ssh-key-title) SSH_KEY_TITLE="${2-}"; shift 2 ;;
    *) echo "[setup] Unknown arg: $1" >&2; usage ;;
  esac
done

log() { printf "\033[1;32m[setup]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }
trap 'code=$?; err "Failed at line $LINENO: $BASH_COMMAND (exit $code)"; exit $code' ERR

# OSチェック
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { err "This script only works on Apple Silicon macOS."; exit 1; }

if ! "$BREW" -v >/dev/null 2>&1; then
  err "Homebrew not found. Run bootstrap first:
  bash <(curl -fsSL https://raw.githubusercontent.com/<OWNER>/setup/<BRANCH>/bootstrap.sh) --owner <OWNER> --branch <BRANCH>"
fi
eval "$("$BREW" shellenv)"

command -v gh >/dev/null 2>&1 || { err "'gh' not found. Run bootstrap first."; exit 1; }

if ! gh auth status --hostname "$GIT_HOSTNAME" >/dev/null 2>&1; then
  log "gh auth login (HTTPS, web flow)"
  gh auth login --hostname "$GIT_HOSTNAME" --web --git-protocol https \
    --scopes "repo,read:org,admin:public_key"
else
  log "gh auth: OK"
fi
scopes="$(
  gh api --hostname "$GIT_HOSTNAME" -i /user 2>/dev/null \
    | awk -F': ' 'BEGIN{IGNORECASE=1}/^x-oauth-scopes:/{gsub(/[[:space:]]/,"",$2); print $2; exit}' \
    || true
)"

if [[ -n "$scopes" ]]; then
  need_ok=1
  for need in admin:public_key repo read:org; do
    [[ ",$scopes," == *",$need,"* ]] || { need_ok=0; break; }
  done
  if [[ $need_ok -eq 0 ]]; then
    log "Adding missing token scopes via gh auth refresh"
    gh auth refresh -h "$GIT_HOSTNAME" -s admin:public_key -s repo -s read:org \
      || err "gh auth refresh failed; continuing"
  fi
else
  log "Token scopes not detectable; skipping refresh"
fi

# SSH鍵生成
if [[ "$DO_SSH" -eq 1 ]]; then
  mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"

  if [[ -z "$SSH_KEY_TITLE" ]]; then
    host="$(hostname | tr -cd '[:alnum:]-')"
    SSH_KEY_TITLE="github-${host}-$(date +%Y%m%d)"
  fi

  if [[ ! -f "${SSH_KEY_PATH}" || ! -f "${SSH_KEY_PATH}.pub" ]]; then
    log "Generating SSH key: ${SSH_KEY_PATH} (no passphrase, comment='${SSH_KEY_TITLE}')"
    ssh-keygen -t ed25519 -C "$SSH_KEY_TITLE" -f "$SSH_KEY_PATH" -N ""
  else
    log "SSH key exists: ${SSH_KEY_PATH}"
  fi

  chmod 600 "${SSH_KEY_PATH}"; chmod 644 "${SSH_KEY_PATH}.pub"

  fp="$(ssh-keygen -lf "${SSH_KEY_PATH}" | awk '{print $2}')"
  if ! ssh-add -l 2>/dev/null | grep -q "$fp"; then
    log "Adding key to keychain"
    ssh-add --apple-use-keychain "${SSH_KEY_PATH}" || ssh-add "${SSH_KEY_PATH}" || true
  else
    log "SSH key already loaded"
  fi

  # SSH公開鍵登録
  gh auth refresh -h "$GIT_HOSTNAME" -s admin:public_key || true
  PUB="$(cat "${SSH_KEY_PATH}.pub")"
  if gh ssh-key list --json key --jq '.[].key' | grep -qxF "$PUB"; then
    log "GitHub: same public key already registered"
  else
    log "Registering public key to GitHub"
    gh ssh-key add "${SSH_KEY_PATH}.pub" --title "${SSH_KEY_TITLE}"
  fi
  if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?$ ]]; then
      owner="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"
      new="git@github.com:${owner}/${name}.git"
      log "Switching origin to SSH: $new"
      git -C "$REPO_DIR" remote set-url origin "$new"
    else
      log "Origin is not HTTPS GitHub (skip switching): $url"
    fi
  fi
  log "Testing SSH connectivity (optional)"
  ssh -o StrictHostKeyChecking=accept-new -T "git@${GIT_HOSTNAME}" || true

  # SSH configの設定
  SSH_CONFIG="${HOME}/.ssh/config"
  log "Configuring SSH config"

  # ~/.ssh/configが存在しない場合は作成
  if [[ ! -f "$SSH_CONFIG" ]]; then
    log "Creating SSH config file: $SSH_CONFIG"
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
  fi

  # github.comのエントリが存在するかチェック
  if ! grep -q "^Host github\.com$" "$SSH_CONFIG" 2>/dev/null; then
    log "Adding GitHub SSH config entry"
    cat >> "$SSH_CONFIG" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ${SSH_KEY_PATH}
  AddKeysToAgent yes
  UseKeychain yes
EOF
  else
    log "GitHub SSH config entry already exists"
    # 既存のエントリがある場合の警告
    if ! grep -q "${SSH_KEY_PATH}" "$SSH_CONFIG"; then
      log "Warning: Existing GitHub config uses different key. Manual update may be needed."
    fi
  fi
  chmod 600 "$SSH_CONFIG"
  log "SSH config updated successfully"
else
  log "Skipping SSH steps (--no-ssh)"
fi

# macOSのplist設定
# defaults write com.apple.finder FXPreferredViewStyle -string "clmv"  # Finderをカラム表示
defaults write com.apple.finder AppleShowAllFiles -bool true         # Finderに不可視ファイルを表示
defaults write NSGlobalDomain AppleShowAllExtensions -bool true      # 拡張子を常に表示
# defaults write com.apple.screencapture "show-thumbnail" -bool false  # スクリーンショットのフローティング非表示
killall Finder || true

cat <<'EOS'

✅ Setup done.

Next steps:
  1) You can now apply dotfiles with your preferred method (e.g., chezmoi).

EOS
