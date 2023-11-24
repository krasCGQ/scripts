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


def prepare_message():
    """
    This is the message that will be sent by announce() below.
    :return: A string that is the template below.
    """
    message: str = """*New file detected on {}:* [{}]({})

Name: `{}`
Upload date: {}

[Download]({})"""

    return message


def announce(path: str, dry_run: bool):
    # catch for any unsupported service and bail out early
    for i in range(0, len(config.project_lists)):
        service: str = config.project_lists[i].split(':')[1]
        if service != 'sourceforge' and service != 'osdn':
            raise Exception(
                'Expected sourceforge or osdn for project service, found {}'.format(service))

    for i in range(0, len(config.project_lists)):
        project: str
        service: str
        # parse each project and service
        [project, service, *_] = config.project_lists[i].split(':')

        # URL of the project
        project_url: str = 'https://{}.net/projects/{}'.format(service, project)

        # declare variables first
        project_rss: str
        service_name: str

        if service == 'sourceforge':
            project_rss = '{}/rss'.format(project_url)
            service_name = 'SourceForge'

        elif service == 'osdn':
            project_rss = '{}/storage/!rss'.format(project_url)
            service_name = 'OSDN File Storage'

        # only provide latest 20 (OSDN) or 100 (SourceForge) files uploaded to the service
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
                # use time value sequence converted into ISO 8601 format instead
                upload_date: str = utils.date_from_struct_time(list.entries[j].published_parsed)

                if service == 'osdn':
                    # use shortlink for OSDN File Storage
                    download_url = 'https://osdn.net/dl/{}/{}'.format(project, file_name)
                else:
                    download_url = list.entries[j].link

                message: str = prepare_message()  # why we need this workaround?
                message = message.format(service_name, project, project_url, file_name, upload_date,
                                         download_url)
                if utils.push_notification(message, dry_run):
                    utils.write_to_file(cache_file, list.entries[j].title)
