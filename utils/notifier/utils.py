#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from hashlib import sha384 as hashlib_sha384
from os import getenv as os_getenv

from requests import post as requests_post


def get_cache_dir():
    """
    Returns cache directory root that will be storing notifier data.
    It prefers XDG_CACHE_HOME if set, otherwise default to current user's own cache directory.
    :return: A string containing cache directory root.
    """
    cache_dir = os_getenv('HOME') + '/.cache'
    if os_getenv('XDG_CACHE_HOME') is not None:
        cache_dir = os_getenv('XDG_CACHE_HOME')
    return cache_dir


def read_from_file(file):
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


def get_digest_from_content(file):
    """
    Get digest of a content from provided file.
    :param file: File to read the content from.
    :return: A digest derived from provided content, or empty if nothing is supplied.
    """
    content = read_from_file(file)
    if content is not None:
        return hashlib_sha384(content.encode()).hexdigest()
    return ''


def write_to_file(file, content):
    """
    Write the provided content to a file.
    :param file: File to write the content to.
    :param content: Content to write.
    """
    with open(file, 'w+') as file:
        file.write(content)


def push_notification(message):
    """
    Push a notification through Telegram Bot API containing the provided message.
    :param message: Part of a body containing the message to be sent.
    """
    tg_url = 'https://api.telegram.org/bot' + os_getenv('TELEGRAM_TOKEN') + '/SendMessage'
    query = {
        'chat_id': os_getenv('TELEGRAM_CHAT'),
        'text': message + '\n\n— @KudNotifier —',
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    requests_post(tg_url, data=query)
