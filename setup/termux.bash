# Termux environment setup
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Exit setup if encountering any errors
trap 'exit ${?}' ERR

# Move to HOME if it isn't
[[ $(pwd) != ${HOME} ]] && cd ${HOME}

# Variables here are basically to define upstream file names
ANTIBODY=antibody_Linux_arm64.tar.gz

# Basic packages
pkg install git nano zsh -y

# dotfiles
git clone https://gitlab.com/krasCGQ/dotfiles .files --single-branch
mkdir -p .config
for i in .config/nano .gitconfig; do
    ln -sf ${HOME}/.files/${i} ${HOME}/${i}
done
ln -sf ${HOME}/.files/.zshrc-android ${HOME}/.zshrc

# antibody
curl -LO https://github.com/getantibody/antibody/releases/latest/download/${ANTIBODY}
tar -xf ${ANTIBODY} antibody
mkdir -p ../usr/local/bin
mv -f antibody ../usr/local/bin

# Move to zsh
chsh -s zsh
