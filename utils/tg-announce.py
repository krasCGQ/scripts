#!/usr/bin/env python3
# Copyright (C) 2019-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from hashlib import sha384
from os import environ, makedirs, remove
from os.path import exists, join, isdir

from argparse import ArgumentParser
from feedparser import parse
from requests import post

# get content hash from a file using sha384
def get_hash(file):
    if exists(file):
        file = open(file, 'rb')
        hash = sha384(file.read()).hexdigest()
        file.close()
    else:
        # assume empty
        hash = ''

    return hash

# write content to a file
def write_to(file, content):
    file = open(file, 'w+')
    file.write(content)
    file.close()

# telegram sendMessage wrapper
def notify(msg):
    token = environ['TELEGRAM_TOKEN']
    chat_id = environ['TELEGRAM_CHAT']
    tg_url = 'https://api.telegram.org/bot' + token + '/SendMessage'
    query = {
        'chat_id': chat_id,
        'text': msg,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    return post(tg_url, data=query)

# linux kernel announcement
def linux_announce():
    # url of release rss
    korg_url = 'https://www.kernel.org/feeds/kdist.xml'
    list = parse(korg_url)

    # from first to last
    for i in range (0, len(list.entries)):
        # skip linux-next; we only want stable and mainline releases
        if 'linux-next' not in list.entries[i].title:
            # release details is under id
            details = list.entries[i].id.split(',')

            if 'mainline' in list.entries[i].title:
                # mainline must be treated differently
                version_file = join(path + '/mainline-version')
            else:
                release = details[2].split('.')
                version = release[0] + '.' + release[1]
                # version naming: x.y-version
                version_file = join(path + '/' + version + '-version')

            # get content hash if any
            hash_a = get_hash(version_file)
            # sha384 of the new version
            hash_b = sha384(str.encode(list.entries[i].title)).hexdigest()

            # both hashes are different, announce it
            if hash_a != hash_b:
                if 'mainline' in list.entries[i].title:
                    msg = '*New Linux mainline release available!*\n'
                else:
                    msg = '*New Linux ' + version + ' series release available!*\n'
                    msg += 'Release type: ' + details[1] + '\n'
                msg += 'Version: ' + details[2] + '\n'
                msg += 'Release date: ' + details[3]
                if 'mainline' not in list.entries[i].title:
                    msg += '\n\n'
                    msg += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + release[0] + '.x/ChangeLog-' + details[2] + ')'

                notify(msg)
                # write new version
                write_to(version_file, list.entries[i].title)

# main functions
if __name__ == '__main__':
    parser = ArgumentParser(description='All-in-one Telegram announcement script using Telegram Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired',
                        type=str, choices=['linux'])

    args = parser.parse_args()

    path = environ['HOME'] + '/.tg-announce/'
    # attempt removal of file of same name
    if exists(path) and not isdir(path):
        remove(path)

    path = path + args.type
    # create cache directory if not exists
    if not exists(path):
        makedirs(path)

    if args.type == 'linux':
        linux_announce()
