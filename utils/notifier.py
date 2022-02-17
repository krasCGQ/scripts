#!/usr/bin/env python3
#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from importlib import import_module
from os import environ as os_environ, makedirs as os_makedirs, remove as os_remove
from os.path import exists as path_exists, isdir as path_isdir, join as path_join

from argparse import ArgumentParser


if __name__ == '__main__':
    parser = ArgumentParser(description='All-in-one Telegram announcement script using Telegram Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired', type=str)

    args = parser.parse_args()

    notifier = import_module(f'.{args.type}', 'notifier')

    path = path_join(os_environ['HOME'] + '/.tg-announce/')
    # attempt removal of file of same name
    if path_exists(path) and not path_isdir(path):
        os_remove(path)

    path = path_join(path + args.type)
    # create cache directory if not exists
    if not path_exists(path):
        os_makedirs(path)

    notifier.announce(path)
