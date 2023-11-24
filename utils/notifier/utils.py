#
# Copyright (C) 2019-2023 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from datetime import datetime
from hashlib import sha384 as hashlib_sha384
from os import getenv as os_getenv, makedirs as os_makedirs
from os.path import exists as path_exists
from sys import stderr as sys_stderr
from time import struct_time, strftime as time_strftime

from requests import post as requests_post

from notifier.config import utils_byline as byline


def get_cache_dir():
    """
    Returns cache directory root that will be storing notifier data.
    It prefers XDG_CACHE_HOME if set, otherwise default to current user's own cache directory.
    :return: A string containing cache directory root.
    """
    return os_getenv('XDG_CACHE_HOME') if os_getenv(
        'XDG_CACHE_HOME') is not None else '{}/.cache'.format(os_getenv('HOME'))


def read_from_file(file: str):
    """
    Get content from a provided file.
    :param file: File to read the content from.
    :return: A string which is the content itself, or NoneType if file doesn't exist.
    """
    try:
        with open(file, 'rb') as file:
            return file.read().decode()
    except FileNotFoundError:
        return None


def get_digest_from_content(file: str):
    """
    Get digest of a content from provided file.
    :param file: File to read the content from.
    :return: A digest derived from provided content, or empty if nothing is supplied.
    """
    content: str = read_from_file(file)
    return hashlib_sha384(content.encode()).hexdigest() if content is not None else ''


def write_to_file(file: str, content: str):
    """
    Write the provided content to a file.
    :param file: File to write the content to.
    :param content: Content to write.
    """
    with open(file, 'w+') as file:
        file.write(content)


def date_from_struct_time(time_value: struct_time):
    """
    Convert a given time value sequence into an ISO 8601 format in UTC.
    :param time_value: A named tuple containing the time value sequence given.
    :return: A string that represents said time.
    """
    time_format: str = '%Y-%m-%dT%H:%M:%S%z'
    time: str = time_strftime(time_format, time_value)
    return datetime.strptime(time, time_format).isoformat()


def create_dir_if_not_exist(path: str):
    """
    Create a directory if it doesn't exist.
    :param path: A string containing the desired path.
    :return: None.
    """
    if not path_exists(path):
        os_makedirs(path)


def push_notification(message: str, dry_run: bool = False):
    """
    Push a notification through Telegram Bot API containing the provided message.
    :param message: Part of a body containing the message to be sent.
    :param dry_run: Boolean on whether to simulate the notification by printing to stdout or not.
                    This is assumed to be True if either token or chat ID aren't given.
                    Defaults to False.
    :return: Boolean indicating status of this function.
             Dry running will always return False, otherwise this depends on whether POST succeeds
             or not. We're not parsing why POST fails because it isn't informative for us.
    """
    chat_id: str = os_getenv('TELEGRAM_CHAT')
    token: str = os_getenv('TELEGRAM_TOKEN')
    if (chat_id is None or token is None) and not dry_run:
        print('Unable to retrieve Telegram token or target chat ID. Assuming dry run.',
              file=sys_stderr)
        dry_run = True

    if dry_run:
        print(message)
        print()
        return not dry_run

    api_url: str = 'https://api.telegram.org/bot{}/SendMessage'.format(token)
    query: dict = {
        'chat_id': chat_id,
        'text': message + byline,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    r = requests_post(api_url, data=query)
    return not dry_run and r.status_code == 200
