#
# Copyright (C) 2021-2023 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from datetime import datetime
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


def announce(path: str, dry_run: bool):
    # official link of the RSS feed
    korg_url: str = 'https://www.kernel.org/feeds/kdist.xml'
    releases: dict = feedparser_parse(korg_url)

    # date and time format used within published tag
    date_format: str = '%a, %d %b %Y %H:%M:%S %z'

    # from first to last
    for i in range(0, len(releases.entries)):
        # get release type and kernel version from id tag
        release_type: str
        version: str
        [_, release_type, version, _, *_] = releases.entries[i].id.split(',')

        # if notifying for -next releases is undesired, stop and continue the list
        if config.linux_notify_next is False and release_type == 'linux-next':
            continue

        # get release date from published tag and convert to ISO format
        release_date: str = datetime.strptime(releases.entries[i].published,
                                              date_format).isoformat()

        # mainline and -next must be treated differently
        version_file: str

        if release_type == 'mainline':
            version_file = path_join(path + '/mainline-version')

        elif release_type == 'linux-next':
            version_file = path_join(path + '/next-version')

        else:
            version_major: int
            version_minor: int
            [version_major, version_minor, _, *_] = version.split('.')

            # stable version caching must conform to x.y-version format
            series: str = version_major + '.' + version_minor
            version_file = path_join(path + '/' + series + '-version')

        # announce new version
        if compare_release(version_file, version):
            message: str
            if release_type == 'mainline':
                message = '*New Linux mainline release available!*\n'
                message += '\n'
            elif release_type == 'linux-next':
                message = '*New linux-next release available!*\n'
                message += '\n'
            else:
                message = '*New Linux ' + series + ' series release available!*\n'
                message += '\n'
                message += 'Release type: ' + release_type + '\n'
            message += 'Version: `' + version + '`\n'
            message += 'Release date: ' + release_date
            if release_type != 'mainline' and release_type != 'linux-next':
                message += '\n\n'
                message += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + version_major + '.x/ChangeLog-' + version + ')'

            if utils.push_notification(message, dry_run):
                utils.write_to_file(version_file, version)
