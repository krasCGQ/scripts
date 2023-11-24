#
# Copyright (C) 2019-2023 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from os import makedirs as os_makedirs
from os.path import exists as path_exists, join as path_join

from git import cmd as git_cmd

from notifier import config, utils


def prepare_message():
    """
    This is the message that will be sent by announce() below.
    :return: A string that is the template below.
    """
    message: str = """*New git release detected!*

Repository: [{}]({})
Tag: `{}` (`{}`)
Commit: `{}`"""

    return message


def announce(path: str, dry_run: bool):
    # initialize GitPython
    git = git_cmd.Git()

    # repeat process for each url...
    for i in range(0, len(config.git_urls)):
        git_url: str = config.git_urls[i]
        # this is the repository name
        git_repo: str = git_url.split('/')[-1]
        # get list of tags
        tags: list[str] = git.ls_remote('--tags', git_url).split('\n')

        repo_path: str = path_join('{}/{}'.format(path, git_repo))
        # create repo directory if not exists
        if not path_exists(repo_path):
            os_makedirs(repo_path)

        # parse every 2 entries, next one is tagged commit
        for j in range(0, len(tags), 2):
            tag_sha1: str
            tag_name: str
            # extract tag SHA-1 and name out from list of tags
            [tag_sha1, _, _, tag_name, *_] = tags[j].replace('\t', '/').split('/')

            # we will cache tag SHA-1 under the tag name itself
            tag_file: str = path_join('{}/{}'.format(repo_path, tag_name))

            # get the first 12 characters of tagged commit for notification purposes
            tagged_commit: str = tags[j + 1].split('\t')[0][:12]

            # although rare since tag re-releases are uncommon, announce if tag is different
            if utils.read_from_file(tag_file) != tag_sha1:
                if 'git:' in git_url:
                    git_url = git_url.replace('git:', 'https:')

                # when announcing, we only need first 12 characters of tag SHA-1
                message: str = prepare_message.format(git_repo, git_url, tag_name, tag_sha1[:12],
                                                      tagged_commit)
                if utils.push_notification(message, dry_run):
                    # however, we still cache the full SHA-1
                    utils.write_to_file(tag_file, tag_sha1)
