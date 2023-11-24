#
# SPDX-FileCopyrightText: 2021-2023 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later
#

from os.path import join as path_join

from feedparser import parse as feedparser_parse

from notifier import config, utils


def compare_release(previous_file: str, current: str):
    """
    Compare between two different release versions to determine if we need to announce.
    :param previous_file: Path to cached file containing exactly the previous version string.
    :param current: A string which is the current version we are going to compare against.
    :return: Boolean status, True if needs announcing otherwise False and thus skipping
             announcement for this particular kernel version.
    """
    previous: str = utils.read_from_file(previous_file)
    if previous is None:  # this is new to us
        return True

    if 'mainline' in previous_file:
        # compare major version first
        old_version: int = previous.split('.')[0]
        new_version: int = current.split('.')[0]
        if new_version > old_version:
            return True

        # compare patchlevel changes next if major version remains the same
        old_patchlevel: int = previous.split('.')[1].split('-')[0]
        new_patchlevel: int = current.split('.')[1].split('-')[0]
        if new_patchlevel > old_patchlevel:
            return True

        try:
            # compare changes to release candidate number if possible
            old_candidate: str = previous.split('-')[1]
            new_candidate: str = current.split('-')[1]
            if new_candidate != old_candidate:
                return True
        except IndexError:
            # if we encounter IndexError, there are two possibilities:
            # - it's the first candidate for next stable release
            # - it's the final mainline release, ready for stable branching
            return True

    elif 'next' in previous_file:
        # compare timestamp for linux-next
        old_date: int = previous.split('-')[1]
        new_date: int = current.split('-')[1]
        if new_date > old_date:
            return True

    else:  # stable or longterm
        # compare only kernel sublevel for stable and longterm releases
        old_sublevel: int = previous.split('.')[2]
        new_sublevel: int = current.split('.')[2]
        if new_sublevel > old_sublevel:
            return True

    return False  # up to date for this series


def prepare_message(version: str, release_type: str, release_date: str):
    """
    This is the message that will be sent by announce() below.
    :param version: Kernel version string.
    :param release_type: Kernel release type string.
    :param release_date: Kernel release date string.
    :return: A string that is the formatted message of template below.
    """
    # common parts for all types of releases
    message: str = """*New Linux kernel release available!*

Version: `{}` ({})
Date: {}"""

    # currently specific to stable or longterm releases
    if release_type == 'stable' or release_type == 'longterm':
        # extract the major version out so we can link to plain text changelog
        version_major: int = version.split('.')[0]

        message += """

[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v{}.x/ChangeLog-{})"""

        return message.format(version, release_type, release_date, version_major, version)

    return message.format(version, release_type, release_date)


def announce(path: str, dry_run: bool):
    # official link of the RSS feed
    korg_url: str = 'https://www.kernel.org/feeds/kdist.xml'
    releases: dict = feedparser_parse(korg_url)

    # from first to last
    for i in range(0, len(releases.entries)):
        # get release type and kernel version from id tag
        release_type: str
        version: str
        [_, release_type, version, _, *_] = releases.entries[i].id.split(',')

        # if notifying for -next releases is undesired, stop and continue the list
        if config.linux_notify_next is False and release_type == 'linux-next':
            continue

        version_file: str  # declare it first

        # mainline and linux-next must be treated differently
        if release_type == 'mainline' or release_type == 'linux-next':
            version_file = path_join('{}/{}-version'.format(path, release_type))

        else:
            version_major: int
            version_minor: int
            [version_major, version_minor, _, *_] = version.split('.')

            # stable version caching must conform to x.y-version format
            version_file = path_join('{}/{}.{}-version'.format(path, version_major, version_minor))

        # announce new version
        if compare_release(version_file, version):
            # use time value sequence converted into ISO 8601 format instead
            release_date: str = utils.date_from_struct_time(releases.entries[i].published_parsed)

            message = prepare_message(version, release_type, release_date)
            if utils.push_notification(message, dry_run):
                utils.write_to_file(version_file, version)
