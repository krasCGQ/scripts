#
# SPDX-FileCopyrightText: 2019-2023, 2025 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os.path import join as path_join
from warnings import warn

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
    for i in range(0, len(config.projects_list)):
        service: str = config.projects_list[i].split(':')[1]
        if service != 'sourceforge' and service != 'osdn':
            raise Exception(
                'Expected sourceforge or osdn for project service, found {}'.format(service))

    for i in range(0, len(config.projects_list)):
        project: str
        service: str
        # parse each project and service
        [project, service, *_] = config.projects_list[i].split(':')

        if service == 'osdn':
            warn('OSDN has ceased operations on April 1, 2025. Please remove all OSDN projects from your config file, as the notifier will stop accepting it as a valid service in the future.', Warning)
            continue

        # create project directory
        project_path: str = path_join('{}/{}/{}'.format(path, service, project))
        utils.create_dir_if_not_exist(project_path)

        # URL of the project
        project_url: str = 'https://{}.net/projects/{}'.format(service, project)
        project_rss: str = '{}/rss'.format(project_url)

        service_name: str = 'SourceForge'

        # only provide latest 100 files uploaded to the service
        list = feedparser_parse(project_rss)

        # start from the oldest
        for j in range(len(list.entries) - 1, -1, -1):
            # title is remote path of the file itself, so save it as so first
            file_path: str = list.entries[j].title
            # extract file name out from remote path
            file_name: str = file_path.split('/')[-1]

            # hash the published date for comparison purposes
            date_published: str = list.entries[j].published
            date_digest: str = hashlib_sha384(date_published.encode()).hexdigest()

            # use the whole remote path as cached file name, but replace unsupported characters
            cache_name: str = file_path.replace('/', '_')
            cache_file: str = path_join('{}/{}'.format(project_path, cache_name))

            # file doesn't exist previously or reuploaded, announce it
            if utils.get_digest_from_content(cache_file) != date_digest:
                # use time value sequence converted into ISO 8601 format instead
                upload_date: str = utils.date_from_struct_time(list.entries[j].published_parsed)

                download_url: str = list.entries[j].link

                message: str = prepare_message()  # why we need this workaround?
                message = message.format(service_name, project, project_url, file_name, upload_date,
                                         download_url)
                if utils.push_notification(message, dry_run):
                    utils.write_to_file(cache_file, date_published)
