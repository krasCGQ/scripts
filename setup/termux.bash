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
# - axel: alternative CLI download manager
# - git: version control system
# - nano: CLI text editor
# - python: Python 3
# - wget: CLI download manager
# - zsh: Unix shell
prInfo "Installing basic packages..."
pkg install --no-install-recommends -y \
    antibody \
    axel \
    git \
    nano \
    python \
    wget \
    zsh

# Python 3 modules, since outdated versions are installed by default
prInfo "Upgrading Python 3 modules..."
python3 -m pip install --upgrade \
    pip \
    setuptools

# dotfiles
prInfo "Setting up dotfiles..."
git clone git://github.com/krasCGQ/dotfiles .files
git -C "$HOME"/.files submodule update --init scripts
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
