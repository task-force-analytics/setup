#!/usr/bin/env bash
set -euo pipefail

REPO=""
BRANCH=""
DRY_RUN=0           # 1 なら適用せず差分のみ
USE_EXTERNALS=0     # 1 なら init に --use-externals=all を付与（必要なら）

usage() {
  cat <<'USAGE' >&2
Usage: dotfiles.sh --repo <git-url> [--branch <name>] [--dry-run] [--externals]
  --repo       必須。chezmoiのソースGit URL（ssh/https どちらでも可）
  --branch     任意。対象ブランチ
  --dry-run    任意。適用せず差分のみ（chezmoi diff）
  --externals  任意。init時に --use-externals=all を付与
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2-}"; shift 2;;
    --branch) BRANCH="${2-}"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --externals) USE_EXTERNALS=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done

[[ -n "$REPO" ]] || usage

log() { printf "\033[1;34m[dotfiles]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

# OSチェック
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || { err "This script only works on Apple Silicon macOS."; exit 1; }

BREW="$(command -v brew || true)"
if [[ -z "$BREW" && -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
fi
[[ -x "${BREW:-/nonexistent}" ]] || { err "Homebrew が見つかりません。先に setup.sh / make setup を実行してください。"; exit 1; }

eval "$("$BREW" shellenv)"
if ! command -v chezmoi >/dev/null 2>&1; then
  log "Installing chezmoi via Homebrew..."
  brew install chezmoi
fi

CHEZ_SRC="$HOME/.local/share/chezmoi"
if [[ "$REPO" == git@github.com:* ]]; then
  if ! ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    log "SSH 接続テストに失敗した可能性があります（Permission denied など）。"
    log "必要なら: ssh-add ~/.ssh/id_ed25519_github や ~/.ssh/config の Host github.com 設定を確認してください。"
  fi
fi
if [[ -d "$CHEZ_SRC/.git" ]]; then
  log "chezmoi: already initialized"
  current_url="$(chezmoi git config --get remote.origin.url || true)"
  if [[ -n "$current_url" && "$current_url" != "$REPO" ]]; then
    err "既存の chezmoi リポが異なるURLを指しています。
  current: $current_url
  target : $REPO
必要なら、次を実行してから進めてください:
  chezmoi git remote set-url origin \"$REPO\""
    exit 1
  fi

  # ブランチ指定があれば切替、無ければ通常 pull
  if [[ -n "$BRANCH" ]]; then
    log "Switching branch to '$BRANCH'"
    chezmoi git fetch origin "$BRANCH"
    chezmoi git checkout "$BRANCH"
    chezmoi git pull -- --rebase
  else
    log "Pulling latest changes"
    chezmoi git pull -- --rebase
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "Dry-run: showing diff only"
    chezmoi diff || true
  else
    log "Applying dotfiles..."
    chezmoi apply
  fi
else
  log "Initializing chezmoi from: $REPO"
  init_args=(init)
  [[ "$USE_EXTERNALS" -eq 1 ]] && init_args+=(--use-externals=all)
  [[ -n "$BRANCH" ]] && init_args+=(--branch "$BRANCH")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    chezmoi "${init_args[@]}" "$REPO"
    log "Dry-run: showing diff only"
    chezmoi diff || true
  else
    chezmoi "${init_args[@]}" --apply "$REPO"
  fi
fi

log "Dotfiles ${DRY_RUN:+(dry-run) }done."
