#!/data/data/com.termux/files/usr/bin/bash
#
# SPDX-FileCopyrightText: 2019-2020, 2022, 2024 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Termux environment setup
#

set -e

# Modified styled message print from my scripts
prInfo() { echo "[-] $*"; }

# List of basic packages to be installed
readonly _basic_pkglist=(
    # Both of these packages have to be installed to have functioning pip.
    # Python is implicitly installed as a dependency for both packages
    'python-ensurepip-wheels'
    'python-pip'

    'axel'    # alternative CLI download manager
    'git'     # version control system
    'wget'    # CLI download manager
    'zsh'     # Unix shell
)

# This script is expected to be run on home directory
cd "$HOME" || exit 1

prInfo "Executing system update..."
pkg update -o Dpkg::Options::="--force-confnew" -y

prInfo "Installing basic packages..."
pkg install --no-install-recommends -y "${_basic_pkglist[@]}"

prInfo "Updating nano-syntax-highlighting..."
wget --https-only -O nano-syntax-highlighting-master.zip -nc \
    https://github.com/galenguyer/nano-syntax-highlighting/archive/refs/heads/master.zip
test -d .config/nano/syntax-highlighting || mkdir -p .config/nano/syntax-highlighting
rm -f .config/nano/syntax-highlighting/*.nanorc  # always clean prior installs
unzip -j nano-syntax-highlighting-master.zip '*/*.nanorc' -d .config/nano/syntax-highlighting

prInfo "Cloning dotfiles repo..."
if [[ ! -d .files/.git ]]; then
    rm -rf .files  # ensure nothing gets in our way
    git clone --recurse-submodules https://github.com/krasCGQ/dotfiles.git .files
fi

prInfo "Creating and fixing nanorc for Termux..."
sed -e "s|/usr/share/nano-s|$HOME/.config/nano/s|;s|^include \"/usr|include \"$PREFIX|g" \
    -e "s|\~|$HOME/.files|" .files/.config/nano/nanorc >.config/nano/nanorc

prInfo "Moving to Zsh..."
chsh -s zsh

prInfo "Done. Please restart Termux manually."
