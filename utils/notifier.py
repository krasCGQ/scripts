#!/usr/bin/env python3
#
# Copyright (C) 2019-2023 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from importlib import import_module
from os import remove as os_remove
from os.path import exists as path_exists, isdir as path_isdir, join as path_join
from sys import modules as sys_modules

from argparse import ArgumentParser, BooleanOptionalAction

try:
    from notifier import config
    del sys_modules['notifier.config']
except ImportError or ModuleNotFoundError:
    raise Exception('No config file was found. Copy the sample file and try again.')
from notifier import utils


def main():
    parser = ArgumentParser(
        description='Universal Telegram notifier bot script that makes use of Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired', type=str)
    parser.add_argument('--dry-run',
                        help='simulate what would have been announced',
                        action=BooleanOptionalAction)

    args = parser.parse_args()

    notifier = import_module(f'.{args.type}', 'notifier')

    path: str = path_join('{}/kud-notifier/'.format(utils.get_cache_dir()))
    # attempt removal of file of same name
    if path_exists(path) and not path_isdir(path):
        os_remove(path)

    path = path_join(path + args.type)
    utils.create_dir_if_not_exist(path)

    notifier.announce(path, args.dry_run)


if __name__ == '__main__':
    main()
