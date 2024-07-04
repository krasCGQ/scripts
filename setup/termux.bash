#!/data/data/com.termux/files/usr/bin/bash
#
# SPDX-FileCopyrightText: 2019-2020, 2022, 2024 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Termux environment setup
#

# List of basic packages to be installed
readonly _basic_pkglist=(
    # Both of these packages have to be installed to have functioning pip.
    # Python is implicitly installed as a dependency for both packages
    'python-ensurepip-wheels'
    'python-pip'

    'axel'      # alternative CLI download manager
    'git'       # version control system
    'mediainfo' # check media information
    'wget'      # CLI download manager
    'zsh'       # Unix shell
)

# Mimic Termux's custom message output
pr_info() { echo "[-] $*"; }

# This is triggered upon completion or failure
clean_up() {
    _status=$?
    test -d .files/.git || rm -rf .files
    rm -f nano-syntax-highlighting-master.zip
    exit ${_status}
}

trap clean_up ERR EXIT INT


# This script is expected to be run on home directory
cd "$HOME" || exit 1

pr_info "Executing system update..."
pkg upgrade -o Dpkg::Options::='--force-confnew' -y

pr_info "Installing basic packages..."
pkg install --no-install-recommends -y "${_basic_pkglist[@]}"

pr_info "Installing / updating pipx..."
python -m pip install -U pipx
python -m pipx ensurepath

if command -v yt-dlp >/dev/null; then
    pr_info "Updating yt-dlp..."
    python -m pipx upgrade --pip-args='--pre' yt-dlp
else
    pr_info "Installing yt-dlp..."
    python -m pipx install --pip-args='--pre' yt-dlp
    pkg install --no-install-recommends -y ffmpeg
fi

pr_info "Updating nano-syntax-highlighting..."
wget --https-only -O nano-syntax-highlighting-master.zip -nc \
    https://github.com/galenguyer/nano-syntax-highlighting/archive/refs/heads/master.zip
test -d .config/nano/syntax-highlighting || mkdir -p .config/nano/syntax-highlighting
rm -f .config/nano/syntax-highlighting/*.nanorc  # always clean prior installs
unzip -j nano-syntax-highlighting-master.zip '*/*.nanorc' -d .config/nano/syntax-highlighting

pr_info "Cloning dotfiles repo..."
if [[ ! -d .files/.git ]]; then
    rm -rf .files  # ensure nothing gets in our way
    git clone --recurse-submodules https://github.com/krasCGQ/dotfiles.git .files
fi

pr_info "Creating and fixing nanorc for Termux..."
sed -e "s|/usr/share/nano-s|$HOME/.config/nano/s|;s|^include \"/usr|include \"$PREFIX|g" \
    -e "s|\~|$HOME/.files|" .files/.config/nano/nanorc >.config/nano/nanorc

pr_info "Moving to Zsh..."
chsh -s zsh

pr_info "Done. Please restart Termux manually."
