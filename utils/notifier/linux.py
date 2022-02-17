#
# Copyright (C) 2021-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os.path import join as path_join

from feedparser import parse as feedparser_parse

from notifier import utils


def announce(path):
    # url of release rss
    korg_url = 'https://www.kernel.org/feeds/kdist.xml'
    list = feedparser_parse(korg_url)

    # from first to last
    for i in range (0, len(list.entries)):
        # skip linux-next; we only want stable and mainline releases
        if 'linux-next' not in list.entries[i].title:
            # release details is under id
            details = list.entries[i].id.split(',')
            digest = hashlib_sha384(list.entries[i].title.encode()).hexdigest()

            if 'mainline' in list.entries[i].title:
                # mainline must be treated differently
                version_file = path_join(path + '/mainline-version')
            else:
                release = details[2].split('.')
                version = release[0] + '.' + release[1]
                # version naming: x.y-version
                version_file = path_join(path + '/' + version + '-version')

            # announce new version
            if utils.get_digest_from_content(version_file) != digest:
                if 'mainline' in list.entries[i].title:
                    msg = '*New Linux mainline release available!*\n'
                    msg += '\n'
                else:
                    msg = '*New Linux ' + version + ' series release available!*\n'
                    msg += '\n'
                    msg += 'Release type: ' + details[1] + '\n'
                msg += 'Version: `' + details[2] + '`\n'
                msg += 'Release date: ' + details[3]
                if 'mainline' not in list.entries[i].title:
                    msg += '\n\n'
                    msg += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + release[0] + '.x/ChangeLog-' + details[2] + ')'

                utils.push_notification(msg)
                # write new version
                utils.write_to_file(version_file, list.entries[i].title)