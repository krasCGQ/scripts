#
# Copyright (C) 2021-2023 Albert I (krasCGQ)
#
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


def announce(path: str, dry_run: bool):
    # url of release rss
    korg_url: str = 'https://www.kernel.org/feeds/kdist.xml'
    releases: dict = feedparser_parse(korg_url)

    # from first to last
    for i in range(0, len(releases.entries)):
        # if notifying for -next releases is undesired, stop and continue the list
        if config.linux_notify_next is False and 'linux-next' in releases.entries[i].title:
            continue

        # release details is under id
        details: list[str] = releases.entries[i].id.split(',')

        # mainline and -next must be treated differently
        version_file: str
        if 'mainline' in releases.entries[i].title:
            version_file = path_join(path + '/mainline-version')
        elif 'linux-next' in releases.entries[i].title:
            version_file = path_join(path + '/next-version')
        else:
            release: list[str] = details[2].split('.')
            version: str = release[0] + '.' + release[1]
            # version naming: x.y-version
            version_file = path_join(path + '/' + version + '-version')

        # announce new version
        if compare_release(version_file, details[2]):
            message: str
            if 'mainline' in releases.entries[i].title:
                message = '*New Linux mainline release available!*\n'
                message += '\n'
            elif 'linux-next' in releases.entries[i].title:
                message = '*New linux-next release available!*\n'
                message += '\n'
            else:
                message = '*New Linux ' + version + ' series release available!*\n'
                message += '\n'
                message += 'Release type: ' + details[1] + '\n'
            message += 'Version: `' + details[2] + '`\n'
            message += 'Release date: ' + details[3]
            if 'mainline' not in releases.entries[i].title and 'linux-next' not in releases.entries[i].title:
                message += '\n\n'
                message += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + release[
                    0] + '.x/ChangeLog-' + details[2] + ')'

            if utils.push_notification(message, dry_run):
                utils.write_to_file(version_file, details[2])
