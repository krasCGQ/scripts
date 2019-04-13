#!/usr/bin/env python3
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from contextlib import suppress
from glob import glob
from os import chdir, environ, getcwd, mkdir, remove, symlink
from os.path import exists, isdir
from sh import ErrorReturnCode_2, ErrorReturnCode_128, curl, git, rm, tar

# Sync sources from git repository
def sync_git(name, url):
    print("Syncing %s..." %(name))

    try:
        git('-C', name, 'status')

    except ErrorReturnCode_128:
        git.clone(url, name, depth='1', b='master')

    git('-C', name, 'fetch', 'origin', 'master')
    git('-C', name, 'reset', 'origin/master', hard=True)

# Download and extract certain version of a tarball
def sync_tarball(name, version, ext, url):
    # Define source + tarball names
    source = name + '-' + version
    tarball = source + '.tar.' + ext

    print("Fetching %s..." %(source))

    # List all leftovers
    leftovers = glob(name + '-*')
    with suppress(ValueError):
        try: # exclude current version
            leftovers = leftovers.remove(source)
            leftovers = leftovers.remove(tarball)
        except AttributeError: # just empty the value, nothing left
            leftovers = []

    # Delete all leftovers
    for i in range(0, len(leftovers)):
        if isdir(leftovers[i]):
            rm('-rf', leftovers[i])

        else:
            remove(leftovers[i])

    if not isdir(source):
        # Remove file of the same source name
        if exists(source):
            remove(source)

        # Fetch source tarball with curl if it doesn't exist
        # TODO: aria2 / Axel / Wget support?
        if not exists(tarball):
            curl('-LO', url + tarball)

        try: # extract source tarball
            tar('xf', tarball)

        except ErrorReturnCode_2: # delete it, corrupted download
            remove(tarball)
            raise

    # Create symlink to source in GCC
    with suppress(FileExistsError):
        symlink(source, 'gcc/' + name)

# Sync toolchain components
def bmt_sync():
    # GNU Project download URL
    gnu_dir = 'https://ftp.gnu.org/gnu/'

    # Function start
    print("Updating sources...")

    # Create working directory if it doesn't exist
    if not isdir(bmt_dir):
        if exists(bmt_dir):
            remove(bmt_dir)

        mkdir(bmt_dir)

    # Switch to working directory
    chdir(bmt_dir)

    # Binutils and GCC
    sync_git('binutils', 'git://sourceware.org/git/binutils-gdb')
    sync_git('gcc', 'git://gcc.gnu.org/git/gcc')

    # GMP, ISL, MPC, MPFR
    sync_tarball('gmp', '6.1.2', 'xz', gnu_dir + 'gmp/')
    sync_tarball('isl', '0.21', 'xz', 'http://isl.gforge.inria.fr/')
    sync_tarball('mpc', '1.1.0', 'gz', gnu_dir + 'mpc/')
    sync_tarball('mpfr', '4.0.2', 'xz', gnu_dir + 'mpfr/')

    # Switch back to origin
    chdir(current_dir)

    # Function ending
    print("Done")

# Origin where the script is executed
current_dir = getcwd()

# Location of working directory
bmt_dir = environ['HOME'] + '/build/bmt'

try: # run default commands
    bmt_sync()

except: # go back to origin, avoid stranding nowhere
    chdir(current_dir)
    raise
