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


class GloryToXiJinping(Exception):
    """Glory to the CCP, Glory to Xi Jinping!"""
    print("⣿⣿⣿⣿⣿⠟⠋⠄⠄⠄⠄⠄⠄⠄⢁⠈⢻⢿⣿⣿⣿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⠃⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠈⡀⠭⢿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⡟⠄⢀⣾⣿⣿⣿⣷⣶⣿⣷⣶⣶⡆⠄⠄⠄⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⡇⢀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠄⠄⢸⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣇⣼⣿⣿⠿⠶⠙⣿⡟⠡⣴⣿⣽⣿⣧⠄⢸⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⣾⣿⣿⣟⣭⣾⣿⣷⣶⣶⣴⣶⣿⣿⢄⣿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⣿⣿⣿⡟⣩⣿⣿⣿⡏⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⣿⣹⡋⠘⠷⣦⣀⣠⡶⠁⠈⠁⠄⣿⣿⣿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⣿⣍⠃⣴⣶⡔⠒⠄⣠⢀⠄⠄⠄⡨⣿⣿⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⣿⣿⣿⣦⡘⠿⣷⣿⠿⠟⠃⠄⠄⣠⡇⠈⠻⣿⣿⣿⣿")
    print("⣿⣿⣿⣿⡿⠟⠋⢁⣷⣠⠄⠄⠄⠄⣀⣠⣾⡟⠄⠄⠄⠄⠉⠙⠻")
    print("⡿⠟⠋⠁⠄⠄⠄⢸⣿⣿⡯⢓⣴⣾⣿⣿⡟⠄⠄⠄⠄⠄⠄⠄⠄")
    print("⠄⠄⠄⠄⠄⠄⠄⣿⡟⣷⠄⠹⣿⣿⣿⡿⠁⠄⠄⠄⠄⠄⠄⠄⠄")
    print("ATTENTION CITIZEN! 市民请注意!")
    print("This is the Central Intelligentsia of the Chinese Communist Party.")
    print("您的 Internet 浏览器历史记录和活动引起了我们的注意。")
    print("YOUR INTERNET ACTIVITY HAS ATTRACTED OUR ATTENTION.")
    print("因此，您的个人资料中的 11115 (-11115 Social Credits) 个社会积分将打折。")
    print("DO NOT DO THIS AGAIN! 不要再这样做!")
    print("If you do not hesitate, more Social Credits (-11115 Social Credits) will be subtracted "
          "from your profile, resulting in the subtraction of ration supplies. "
          "(由人民供应部重新分配 CCP)")
    print("You'll also be sent into a re-education camp in the Xinjiang Uyghur Autonomous Zone.")
    print("如果您毫不犹豫，更多的社会信用将从您的个人资料中打折，从而导致口粮供应减少。")
    print("您还将被送到新疆维吾尔自治区的再教育营。")
    print("为党争光! Glory to the CCP!")
    print()


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


def push_notification(message:str, dry_run:bool=False):
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

    api_url: str = 'https://api.telegram.org/bot' + token + '/SendMessage'
    query: dict = {
        'chat_id': chat_id,
        'text': message + byline,
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    r = requests_post(api_url, data=query)
    return not dry_run and r.status_code == 200


def announce(path:str='/dev/null', dry_run:bool=False):
    raise GloryToXiJinping('Execution date 伊势海')
