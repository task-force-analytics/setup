# Makefile
# Targets:
#   make setup:     SSH鍵生成・登録 / リモートをsshに切り替え / macOSのplistを更新
#   make dotfiles:  chezmoi でドットファイル反映

SHELL := /bin/zsh
.ONESHELL:
.SILENT:
.DEFAULT_GOAL := help

# setup:
#   make setup
#   make setup NO_SSH=1
#   make setup SSH_KEY_TITLE="github-$(shell hostname)-$(shell date +%Y%m%d)"

# dotfiles:
#   make dotfiles REPO="git@github.com:you/dotfiles.git"
#   make dotfiles REPO="git@github.com:you/dotfiles.git" BRANCH=main
#   make dotfiles REPO="git@github.com:you/dotfiles.git" DOTFILES_DRY_RUN=1 DOTFILES_EXTERNALS=1

# setup.sh 用
SSH_KEY_TITLE ?=
NO_SSH ?= 0

# dotfiles.sh 用
REPO ?=
BRANCH ?= main
DOTFILES_DRY_RUN ?= 0
DOTFILES_EXTERNALS ?= 0

SETUP_SCRIPT    := ./setup.sh
DOTFILES_SCRIPT := ./dotfiles.sh

.PHONY: help setup dotfiles

help:
	echo "Usage:"
	echo "  make setup     [NO_SSH=1] [SSH_KEY_TITLE='github-<host>-<YYYYMMDD>']"
	echo "  make dotfiles  REPO='git@github.com:you/dotfiles.git' [BRANCH='main'] [DOTFILES_DRY_RUN=1] [DOTFILES_EXTERNALS=1]"
	echo
	echo "Notes:"
	echo "  - Brew のインストール/Bundle は bootstrap.sh 側で実施してください。"
	echo "  - NO_SSH=1 は ./setup.sh --no-ssh と同義。"
	echo "  - dotfiles は --repo が必須です。"

setup:
	set -euo pipefail
	chmod +x "$(SETUP_SCRIPT)"
	"$(SETUP_SCRIPT)" \
		$(if $(filter 1,$(NO_SSH)),--no-ssh) \
		$(if $(SSH_KEY_TITLE),--ssh-key-title "$(SSH_KEY_TITLE)")

dotfiles:
	set -euo pipefail
	if [[ -z "$(REPO)" ]]; then
		echo "[error] REPO is required (e.g., git@github.com:you/dotfiles.git)"; exit 1; fi
	chmod +x "$(DOTFILES_SCRIPT)"
	"$(DOTFILES_SCRIPT)" \
		--repo "$(REPO)" \
		$(if $(BRANCH),--branch "$(BRANCH)") \
		$(if $(filter 1,$(DOTFILES_DRY_RUN)),--dry-run) \
		$(if $(filter 1,$(DOTFILES_EXTERNALS)),--externals)
