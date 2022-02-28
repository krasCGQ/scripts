#
# Copyright (C) 2021-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os.path import join as path_join

from feedparser import parse as feedparser_parse

from notifier import config, utils


def announce(path:str, dry_run:bool):
    # url of release rss
    korg_url: str = 'https://www.kernel.org/feeds/kdist.xml'
    list = feedparser_parse(korg_url)

    # from first to last
    for i in range (0, len(list.entries)):
        # if notifying for -next releases is undesired, stop and continue the list
        if config.linux_notify_next is False and 'linux-next' in list.entries[i].title:
            continue

        # release details is under id
        details: list[str] = list.entries[i].id.split(',')
        digest: str = hashlib_sha384(list.entries[i].title.encode()).hexdigest()

        # mainline and -next must be treated differently
        version_file: str
        if 'mainline' in list.entries[i].title:
            version_file = path_join(path + '/mainline-version')
        elif 'linux-next' in list.entries[i].title:
            version_file = path_join(path + '/next-version')
        else:
            release: list[str] = details[2].split('.')
            version: str = release[0] + '.' + release[1]
            # version naming: x.y-version
            version_file = path_join(path + '/' + version + '-version')

        # announce new version
        if utils.get_digest_from_content(version_file) != digest:
            message: str
            if 'mainline' in list.entries[i].title:
                message = '*New Linux mainline release available!*\n'
                message += '\n'
            elif 'linux-next' in list.entries[i].title:
                message = '*New linux-next release available!*\n'
                message += '\n'
            else:
                message = '*New Linux ' + version + ' series release available!*\n'
                message += '\n'
                message += 'Release type: ' + details[1] + '\n'
            message += 'Version: `' + details[2] + '`\n'
            message += 'Release date: ' + details[3]
            if 'mainline' not in list.entries[i].title and 'linux-next' not in list.entries[i].title:
                message += '\n\n'
                message += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + release[0] + '.x/ChangeLog-' + details[2] + ')'

            if utils.push_notification(message, dry_run):
                utils.write_to_file(version_file, list.entries[i].title)
