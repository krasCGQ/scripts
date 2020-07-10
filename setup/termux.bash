#!/data/data/com.termux/files/usr/bin/bash -e
# Termux environment setup
# Copyright (C) 2019-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Modified styled message print from my scripts
prInfo() { echo "[-] $*"; }

# Move to home directory just in case
cd "$HOME" || exit 1

# Initiate system update
prInfo "Executing system update..."
pkg update -o Dpkg::Options::="--force-confnew" -y

## Install a number of basic packages
# Explainer:
# - antibody: Zsh plugin manager
# - git: version control system
# - nano: CLI text editor
# - zsh: Unix shell
prInfo "Installing basic packages..."
pkg install --no-install-recommends -y \
    antibody \
    git \
    nano \
    zsh

# dotfiles
prInfo "Setting up dotfiles..."
git clone --depth=1 git://github.com/krasCGQ/dotfiles .files
mkdir -p .config/nano
# .zshrc
ln -sf "$HOME"/.files/.zshrc-android "$HOME"/.zshrc
# nanorc
<"$HOME"/.files/.config/nano/nanorc |
    sed -e "s|/usr|$PREFIX|" >"$HOME"/.config/nano/nanorc

# Move to zsh
prInfo "Moving to Zsh..."
chsh -s zsh

# Done!
prInfo "Done."
