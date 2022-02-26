#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os import getenv as os_getenv
from sys import stderr as sys_stderr

from requests import post as requests_post

from notifier.config import utils_byline as byline


def get_cache_dir():
    """
    Returns cache directory root that will be storing notifier data.
    It prefers XDG_CACHE_HOME if set, otherwise default to current user's own cache directory.
    :return: A string containing cache directory root.
    """
    cache_dir: str = os_getenv('HOME') + '/.cache'
    if os_getenv('XDG_CACHE_HOME') is not None:
        cache_dir = os_getenv('XDG_CACHE_HOME')
    return cache_dir


def read_from_file(file:str):
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


def get_digest_from_content(file:str):
    """
    Get digest of a content from provided file.
    :param file: File to read the content from.
    :return: A digest derived from provided content, or empty if nothing is supplied.
    """
    content: str = read_from_file(file)
    if content is not None:
        return hashlib_sha384(content.encode()).hexdigest()
    return ''


def write_to_file(file:str, content:str):
    """
    Write the provided content to a file.
    :param file: File to write the content to.
    :param content: Content to write.
    """
    with open(file, 'w+') as file:
        file.write(content)


def push_notification(message:str, dry_run:bool):
    """
    Push a notification through Telegram Bot API containing the provided message.
    :param message: Part of a body containing the message to be sent.
    :param dry_run: Boolean on whether to simulate the notification by printing it out or not.
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
        return

    api_url: str = 'https://api.telegram.org/bot' + token + '/SendMessage'
    query: dict = {
        'chat_id': chat_id,
        'text': message + byline,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    requests_post(api_url, data=query)
