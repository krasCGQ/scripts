#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os import makedirs as os_makedirs
from os.path import exists as path_exists, join as path_join

from feedparser import parse as feedparser_parse

from notifier import utils


def announce(path):
    # list of project names
    projects = ['kudproject']
    # only valid for SourceForge and OSDN File Storage
    services = ['osdn']

    for i in range(0, len(projects)):
        # url of the project
        base_url = 'https://' + services[i] + '.net/projects/' + projects[i]
        if services[i] == 'sourceforge':
            project_url = base_url + '/rss'
        elif services[i] == 'osdn':
            project_url = base_url + '/storage/!rss'
        else:
            # error out
            raise Exception(services[i] + " isn't a valid service. Valid services: sourceforge, osdn.")

        list = feedparser_parse(project_url)

        # start from the oldest
        for j in range(len(list.entries) - 1, -1, -1):
            # get the file name instead of full path
            name = list.entries[j].title.split('/')[-1]
            digest = hashlib_sha384(list.entries[j].title.encode()).hexdigest()

            service_path = path_join(path + '/' + services[i])
            # create service directory if not exists
            if not path_exists(service_path):
                os_makedirs(service_path)

            # cache file: use file name
            cache_file = path_join(service_path + '/' + name)
            # both hashes are different, announce it
            if utils.get_digest_from_content(cache_file) != digest:
                if services[i] == 'sourceforge':
                    msg = '*New file detected on SourceForge:* [' + projects[i] + '](' + project_url + ')\n'
                elif services[i] == 'osdn':
                    msg = '*New file detected on OSDN File Storage:* [' + projects[i] + '](' + project_url + ')\n'
                msg += '\n'
                msg += 'Name: `' + name + '`\n' # avoid markdown parsing
                msg += 'Upload date: ' + list.entries[j].published + '\n'
                msg += '\n'
                if services[i] == 'sourceforge':
                    msg += '[Download](' + list.entries[j].link + ')'
                elif services[i] == 'osdn':
                    # use shortlink provided by OSDN
                    msg += '[Download](https://' + services[i] + '.net/dl/' + projects[i] + '/' + name + ')'

                utils.push_notification(msg)
                # write new version
                utils.write_to_file(cache_file, list.entries[j].title)
