#!/usr/bin/env python3
# Copyright (C) 2019-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from contextlib import suppress
from feedparser import parse
from hashlib import sha384
from os import environ, mkdir, remove
from os.path import exists, join, isdir
from requests import post

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

def main():
    korg_url = 'https://www.kernel.org/feeds/kdist.xml'
    list = parse(korg_url)

    for i in range (0, len(list.entries)):
        # skip linux-next; we only want stable and mainline releases
        if 'linux-next' not in list.entries[i].title:
            details = list.entries[i].id.split(',')
            # mainline must be treated differently
            if 'mainline' in list.entries[i].title:
                version_file = join(path + '/mainline-version')
            else:
                release = details[2].split('.')
                version = release[0] + '.' + release[1]
                version_file = join(path + '/' + version + '-version')

            if exists(version_file):
                file = open(version_file, 'rb')
                hash_a = sha384(file.read()).hexdigest()
                file.close()
            else:
                hash_a = ''

            hash_b = sha384(str.encode(list.entries[i].title)).hexdigest()

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
                file = open(version_file, 'w+')
                file.write(list.entries[i].title)
                file.close()

if __name__ == '__main__':
    path = environ['HOME'] + '/.korg-announce'

    with suppress(FileExistsError):
        if not isdir(path):
            with suppress(FileNotFoundError):
                remove(path)

        mkdir(path)

    main()
