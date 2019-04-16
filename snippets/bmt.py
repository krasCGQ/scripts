#!/usr/bin/env python3
# ELF (bare-metal) GCC toolchain compilation script
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from argparse import ArgumentParser
from contextlib import suppress
from glob import glob
from os import chdir, environ, getcwd, mkdir, remove, symlink
from os.path import exists, isdir
from sh import ErrorReturnCode_2, ErrorReturnCode_128, curl, git, make, nproc, rm, tar
from subprocess import DEVNULL, PIPE, run

# Parse parameters
def parse_params():
    params = ArgumentParser(description="A script that allows you to build ELF (bare-metal) GCC toolchain from source.")
    shared = params.add_mutually_exclusive_group()
    params.add_argument('-a', '--arch', choices=['aarch64', 'arm', 'x86_64'],
                        help="build toolchain for selected target.", required=True)
    shared.add_argument('-s', '--sync-only', dest='sync_only', action='store_true',
                        help="don't build toolchain, just sync sources.")
    shared.add_argument('-b', '--build-only', dest='build_only', action='store_true',
                        help="don't sync sources, just build toolchain.")

    return vars(params.parse_args())

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

    print("Updating sources...")

    # Create working directory if it doesn't exist
    if not isdir(bmt_dir):
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

    print("Done.")

# Run ./configure with specified parameters
def configure(project, flags):
    # Common configuration flags
    common_flags = ['CFLAGS="-g0 -O2 -fstack-protector-strong"',
                    'CXXFLAGS="-g0 -O2 -fstack-protector-strong"',
                    '--target=' + target, '--prefix=' + bmt_dir + '/' + target,
                    '--disable-multilib', '--disable-werror']

    run('./../' + project + '/configure ' + ' '.join(common_flags) + ' ' + flags, shell=True, check=True, stdout=DEVNULL)

# Build bare-metal toolchain
def bmt_build():
    # Set toolchain directory to PATH
    environ['PATH'] = bmt_dir + '/' + target + '/bin:' + environ['PATH']

    # Number of threads
    threads = str(nproc('--all')).rstrip()

    # Enter working directory
    chdir(bmt_dir)

    # Re-create build folders
    print("Cleaning working directory...")
    rm(glob('build-*'), '-rf')
    mkdir('build-binutils')
    mkdir('build-gcc')

    # Remove target toolchain
    rm('-rf', target)

    # Build Binutils
    chdir('build-binutils')

    print("Configuring Binutils...")
    configure('binutils', '--disable-gdb --enable-gold')

    print("Building Binutils...")
    make('-j' + threads)

    print("Installing Binutils...")
    make('install', '-j' + threads)

    # Build GCC
    chdir('../build-gcc')

    print("Configuring GCC...")
    configure('gcc', '--enable-languages=c --without-headers')

    print("Building GCC...")
    make('all-gcc', '-j' + threads)

    print("Installing GCC...")
    make('install-gcc', '-j' + threads)

    print("Building libgcc for target...")
    make('all-target-libgcc', '-j' + threads)

    print("Installing libgcc for target...")
    make('install-target-libgcc', '-j' + threads)

    chdir(bmt_dir)

# Print toolchain information to userspace
def bmt_summary():
    # Toolchain version
    version = run(bmt_dir + '/' + target + '/bin/' + target + '-gcc --version | head -1', shell=True, stdout=PIPE)

    # Print summary
    print("Successfully built toolchain with the following details:\n"
          "Version     : " + version.stdout.decode('utf-8').rstrip() + "\n"
          "Install Path: " + bmt_dir + '/' + target)

# Origin where the script is executed
current_dir = getcwd()

# Location of working directory
bmt_dir = environ['HOME'] + '/build/bmt'

try: # run default commands
    args = parse_params()

    if not args['build_only']:
        bmt_sync()

    if not args['sync_only']:
        # Define target toolchain
        if args['arch'] == 'arm': # ARM
            target = args['arch'] + '-eabi'
        else: # AArch64 and x86_64
            target = args['arch'] + '-elf'

        bmt_build()
        bmt_summary()

except: # go back to origin, avoid stranding nowhere
    chdir(current_dir)
    raise
