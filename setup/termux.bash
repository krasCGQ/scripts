#!/data/data/com.termux/files/usr/bin/bash
#
# SPDX-FileCopyrightText: 2019-2020, 2022, 2024-2026 Albert I (krasCGQ)
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
    'b3sum'     # BLAKE3 checksum utility
    'git'       # version control system
    'mediainfo' # check media information
    'sheldon'   # shell plugin manager
    'wget'      # CLI download manager
    'zsh'       # Unix shell
)

# Mimic Termux's custom message output
pr_info() { echo "[-] $*"; }

# This is triggered upon completion or failure
clean_up() {
    _status=$?
    cd "$HOME" || true
    test -f .config/sheldon/plugins.toml || rm -rf .config/sheldon
    test -d .files/.git || rm -rf .files
    rm -f nano-syntax-highlighting-master.tar.gz
    if [[ -n "${_bgutil_version}" ]]; then
        test -f bgutil-ytdlp-pot-provider/server/build/main.js ||
            rm -rf bgutil-ytdlp-pot-provider{,"${_bgutil_version}"}
        rm -f "bgutil-ytdlp-pot-provider-${_bgutil_version}.tar.gz"
    fi
    exit ${_status}
}

install_yt-dlp_pot_provider() {
    local _project _repo_url
    _project=bgutil-ytdlp-pot-provider
    _repo_url="https://github.com/Brainicism/${_project}"
    _bgutil_version=$(curl -s -I ${_repo_url}/releases/latest | grep ^l | cut -d / -f 8 | \
        tr -d '[:space:]')
    export _bgutil_version  # this needs to be exported for cleanup trigger

    if PATH="$HOME/.local/bin:$PATH" command -v yt-dlp >/dev/null; then
        pr_info "Installing build dependencies for ${_project}..."
        pkg install --no-install-recommends -y nodejs pango xorgproto

        if [[ ! -d "${_project}-${_bgutil_version}" ]]; then
            rm -rf "${_project}"  # remove old version if any exists
            pr_info "Obtaining latest version of ${_project}..."
            wget -O "${_project}-${_bgutil_version}.tar.gz" -nc \
                "${_repo_url}/archive/refs/tags/${_bgutil_version}.tar.gz"
            tar -xvf "${_project}-${_bgutil_version}.tar.gz"
        fi

        if [[ ! -f "${_project}-${_bgutil_version}/server/build/main.js" ]]; then
            pr_info "Building the provider server..."
            cd "${_project}-${_bgutil_version}/server" || true
            GYP_DEFINES="android_ndk_path=''" npm install && npx tsc

            # This is retained to avoid possible version conflict
            rm -f "$HOME/.config/yt-dlp/plugins/${_project}.zip"

            pr_info "Installing the plugin..."
            cd ../plugin || true
            pipx inject -f yt-dlp .
            cd ../.. || true

            # Create symlink so generate_once.js can be found automatically
            ln -s "${_project}-${_bgutil_version}" "${_project}"
        fi
    fi
}

trap clean_up ERR EXIT INT


# This script is expected to be run on home directory
cd "$HOME" || exit 1

pr_info "Executing system update..."
[[ $TERMUX_VERSION =~ googleplay. ]] || _fdroid=true
pkg ${_fdroid:+'--check-mirror'} upgrade -o Dpkg::Options::='--force-confnew' -y
unset _fdroid

pr_info "Installing basic packages..."
pkg install --no-install-recommends -y "${_basic_pkglist[@]}"

pr_info "Installing / updating pipx..."
python -m pip install -U pipx
pipx ensurepath --prepend  # without --all-shells affects only Bash

pr_info "Installing external dependencies for yt-dlp..."
pkg install --no-install-recommends -y deno ffmpeg

if command -v yt-dlp >/dev/null; then
    pr_info "Updating yt-dlp..."
    pipx reinstall 'yt-dlp[default]'
    pipx upgrade --pip-args='--pre' yt-dlp
else
    pr_info "Installing yt-dlp..."
    pipx install --pip-args='--pre' 'yt-dlp[default]'
fi

# Install POT provider if yt-dlp is present
install_yt-dlp_pot_provider

pr_info "Updating nano-syntax-highlighting..."
wget -O nano-syntax-highlighting-master.tar.gz -nc \
    https://github.com/galenguyer/nano-syntax-highlighting/archive/refs/heads/master.tar.gz
test -d .config/nano/syntax-highlighting || mkdir -p .config/nano/syntax-highlighting
rm -f .config/nano/syntax-highlighting/*.nanorc  # always clean prior installs
tar -C .config/nano/syntax-highlighting -xvf nano-syntax-highlighting-master.tar.gz \
    --strip-components 1 --wildcards '*/*.nanorc'

if [[ -d .files/.git ]]; then
    pr_info "Updating dotfiles repo..."
    git -C .files pull --recurse-submodules || true  # skip if not possible in current state
else
    pr_info "Cloning dotfiles repo..."
    rm -rf .files  # ensure nothing gets in our way
    git clone --recurse-submodules https://github.com/krasCGQ/dotfiles.git .files
fi

pr_info "Creating and fixing nanorc for Termux..."
sed -e "s|/usr/share/nano-s|$HOME/.config/nano/s|;s|^include \"/usr|include \"$PREFIX|g" \
    -e "s|\~|$HOME/.files|" .files/.config/nano/nanorc >.config/nano/nanorc

pr_info "Symlinking wgetrc..."
ln -sf .files/.config/wgetrc .config/wgetrc

# If Sheldon config file exists (in case of updating), don't try to add or update plugins
if [[ ! -f .config/sheldon/plugins.toml ]]; then
    pr_info "Configuring Zsh plugins..."
    yes | sheldon init --shell zsh
    sheldon add --github zsh-users/zsh-autosuggestions autosuggestions
    sheldon add --github zdharma-continuum/fast-syntax-highlighting fsyh
    sheldon add --github NickKaramoff/ohmyzsh-key-bindings keybindings
    # Pure should always be the last one to be sourced
    sheldon add --github sindresorhus/pure --use async.zsh pure.zsh -- pure
fi

if ! grep -q 'This was generated by setup/termux.bash' .zshrc 2>/dev/null; then
    pr_info "Generating zshrc..."
    cat << ZSHRC >.zshrc
#!/hint/zsh
#
# This was generated by setup/termux.bash
#

# On Termux environment, source common zshrc first
source "\$HOME/.files/.config/zsh/.zshrc"

# Manually export all XDG-compliant path variables since systemd is absent
eval "\$(grep -v '^#' \$HOME/.files/.config/environment.d/10-common-vars.conf | sed 's/^/export /g')"

#
# Parts that attempt to source plugins as defined in Sheldon config file won't actually run
# since it actually exists on the default path instead. We do this here manually
#
unset SHELDON_CONFIG_FILE SHELDON_LOCK_FILE
eval "\$(sheldon source)"
ZSHRC
fi

pr_info "Moving to Zsh..."
chsh -s zsh

pr_info "Done. Please restart Termux manually."
