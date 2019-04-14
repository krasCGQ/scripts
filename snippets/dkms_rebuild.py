#!/usr/bin/env python3
# Rebuild DKMS modules of currently running kernel with Clang
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from os import environ, uname
from os.path import exists, isdir
from subprocess import CalledProcessError, PIPE, run
from sys import stderr

# Common function for running a specific process
def run_process(cmd):
    global result

    try:
        result = run([cmd], shell=True, check=True, stdout=PIPE, stderr=PIPE)

    except CalledProcessError:
        result.stderr.decode('utf-8')

        return False

    return result

# Don't run script if not root
if run_process('sudo -v') is False:
    raise Exception("Script requires root to run its core function, but current user doesn't appear to be a sudo.")

# Location of wrappers
wrapper_dir = environ['SCRIPTDIR'] + '/binds'

# Current kernel version
kernel = uname()[2]

# Make sure session is running kernel that exists in /usr/lib/modules
if not isdir('/usr/lib/modules/' + kernel):
    raise FileNotFoundError("Current kernel doesn't exist in /usr/lib/modules.")

# Bind mount gcc and g++ Clang wrappers to /usr/bin
run_process('sudo mount -B ' + wrapper_dir + '/gcc /usr/bin/gcc')
run_process('sudo mount -B ' + wrapper_dir + '/g++ /usr/bin/g++')

# List DKMS modules that we're going to reinstall
modules = run_process('dkms status | grep ' + kernel + ' | cut -d \',\' -f 1,2 | sed -e \'s|, |/|g\'')
modules = modules.stdout.decode('utf-8').rstrip().split()

# Reinstall DKMS modules
for i in range(0, len(modules)):
    print("Reinstalling DKMS module:", modules[i])
    run_process('sudo dkms uninstall ' + modules[i] + ' -k ' + kernel)
    if run_process('sudo dkms install ' + modules[i] + ' -k ' + kernel) is False:
        failed = True
    else:
        failed = False

# Umount wrappers
run_process('sudo umount /usr/bin/gcc')
run_process('sudo umount /usr/bin/g++')

if failed is not True:
    # Check for module signature force check config on current kernel
    if exists('/proc/config.gz'):
        forced_sig = run_process('gzip -cd /proc/config.gz | grep MODULE_SIG_FORCE=y')
    else:
        forced_sig = run_process('grep MODULE_SIG_FORCE=y /proc/config')

    if forced_sig.stdout.decode('utf-8').rstrip() == '':
        # Restart systemd-modules-load service
        print("The operation completed successfully. Restarting systemd-modules-load...")
        run_process('sudo systemctl restart systemd-modules-load')

    else:
        # Skip service restart as we've no idea how to sign these modules
        print("Module signature force check enabled, skipping service restart...", file=stderr)

    print("Done.")

else:
    print("""Failed to re-install DKMS module(s).
Please re-install desired DKMS module(s) and run this script again.""")
    raise OSError("Exiting due to previous error(s).")
