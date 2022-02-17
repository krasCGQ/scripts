#!/usr/bin/env python3
# Copyright (C) 2019-2021 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from os import environ, makedirs, remove
from os.path import exists, join, isdir

from argparse import ArgumentParser

from notifier import git, linux, project, utils

# main functions
if __name__ == '__main__':
    parser = ArgumentParser(description='All-in-one Telegram announcement script using Telegram Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired',
                        type=str, choices=['git', 'linux', 'project'])

    args = parser.parse_args()

    path = join(environ['HOME'] + '/.tg-announce/')
    # attempt removal of file of same name
    if exists(path) and not isdir(path):
        remove(path)

    path = join(path + args.type)
    # create cache directory if not exists
    if not exists(path):
        makedirs(path)

    if args.type == 'git':
        git.announce(path)
    elif args.type == 'linux':
        linux.announce(path)
    elif args.type == 'project':
        project.announce(path)
