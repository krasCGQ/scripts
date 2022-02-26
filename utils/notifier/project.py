#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os import makedirs as os_makedirs
from os.path import exists as path_exists, join as path_join

from feedparser import parse as feedparser_parse

from notifier import config, utils


def announce(path, dry_run:bool):
    for i in range(0, len(config.project_lists)):
        # parse each project and service
        project = config.project_lists[i].split(':')[0]
        service = config.project_lists[i].split(':')[1]

        # url of the project
        project_url = 'https://' + service + '.net/projects/' + project
        if service == 'sourceforge':
            rss_url = project_url + '/rss'
        elif service == 'osdn':
            rss_url = project_url + '/storage/!rss'
        else:
            # error out
            raise Exception(service + " isn't a valid service. Valid services: sourceforge, osdn.")

        list = feedparser_parse(rss_url)

        # start from the oldest
        for j in range(len(list.entries) - 1, -1, -1):
            # get the file name instead of full path
            name = list.entries[j].title.split('/')[-1]
            digest = hashlib_sha384(list.entries[j].title.encode()).hexdigest()

            service_path = path_join(path + '/' + service)
            # create service directory if not exists
            if not path_exists(service_path):
                os_makedirs(service_path)

            # cache file: use file name
            cache_file = path_join(service_path + '/' + name)
            # both hashes are different, announce it
            if utils.get_digest_from_content(cache_file) != digest:
                if service == 'sourceforge':
                    msg = '*New file detected on SourceForge:* [' + project + '](' + project_url + ')\n'
                elif service == 'osdn':
                    msg = '*New file detected on OSDN File Storage:* [' + project + '](' + project_url + ')\n'
                msg += '\n'
                msg += 'Name: `' + name + '`\n' # avoid markdown parsing
                msg += 'Upload date: ' + list.entries[j].published + '\n'
                msg += '\n'
                if service == 'sourceforge':
                    msg += '[Download](' + list.entries[j].link + ')'
                elif service == 'osdn':
                    # use shortlink provided by OSDN
                    msg += '[Download](https://' + service + '.net/dl/' + project + '/' + name + ')'

                utils.push_notification(msg, dry_run)
                if not dry_run:
                    utils.write_to_file(cache_file, list.entries[j].title)
