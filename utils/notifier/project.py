#
# Copyright (C) 2019-2023 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os import makedirs as os_makedirs
from os.path import exists as path_exists, join as path_join

from feedparser import parse as feedparser_parse

from notifier import config, utils


def announce(path: str, dry_run: bool):
    for i in range(0, len(config.project_lists)):
        project: str
        service: str
        # parse each project and service
        [project, service, *_] = config.project_lists[i].split(':')

        # url of the project
        project_url: str = 'https://{}.net/projects/{}'.format(service, project)
        project_rss: str
        if service == 'sourceforge':
            project_rss = '{}/rss'.format(project_url)
        elif service == 'osdn':
            project_rss = '{}/storage/!rss'.format(project_url)
        else:
            # error out
            raise Exception(
                '{} is not a supported service. Valid services: sourceforge, osdn.'.format(service))

        list = feedparser_parse(project_rss)

        # start from the oldest
        for j in range(len(list.entries) - 1, -1, -1):
            # get the file name instead of full path
            file_name: str = list.entries[j].title.split('/')[-1]
            digest: str = hashlib_sha384(list.entries[j].title.encode()).hexdigest()

            service_path: str = path_join('{}/{}'.format(path, service))
            # create service directory if not exists
            if not path_exists(service_path):
                os_makedirs(service_path)

            # cache file: use file name
            cache_file: str = path_join('{}/{}'.format(service_path, file_name))
            # both hashes are different, announce it
            if utils.get_digest_from_content(cache_file) != digest:
                message: str
                if service == 'sourceforge':
                    message = '*New file detected on SourceForge:* [' + project + '](' + project_url + ')\n'
                elif service == 'osdn':
                    message = '*New file detected on OSDN File Storage:* [' + project + '](' + project_url + ')\n'
                message += '\n'
                message += 'Name: `' + file_name + '`\n'  # avoid markdown parsing
                message += 'Upload date: ' + list.entries[j].published + '\n'
                message += '\n'
                if service == 'sourceforge':
                    message += '[Download](' + list.entries[j].link + ')'
                elif service == 'osdn':
                    # use shortlink provided by OSDN
                    message += '[Download](https://' + service + '.net/dl/' + project + '/' + file_name + ')'

                if utils.push_notification(message, dry_run):
                    utils.write_to_file(cache_file, list.entries[j].title)
