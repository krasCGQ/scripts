#
# SPDX-FileCopyrightText: 2019-2023 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later
#

from os.path import join as path_join

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
        utils.create_dir_if_not_exist(repo_path)

        # parse every 2 entries, next one is tagged commit
        for j in range(0, len(tags), 2):
            tag_sha1: str
            tag_name: str
            # split tag SHA-1 and name from list of tags
            [tag_sha1, tag_name, *_] = tags[j].split('\t')
            # omit first occurrence of "refs/tags/" from tag name
            tag_name = tag_name.replace('refs/tags/', '', 1)

            # we will cache tag SHA-1 under the tag name itself
            tag_file: str = path_join('{}/{}'.format(repo_path, tag_name))

            # get the first 12 characters of tagged commit for notification purposes
            tagged_commit: str = tags[j + 1].split('\t')[0][:12]

            # we announce availability of new tags when either of these conditions are met:
            # - the tag is just newly pushed
            # - the tag's SHA-1 is updated due to a force push, albeit rarely
            if utils.read_from_file(tag_file) != tag_sha1:
                # replace git with https when needed
                if 'git:' in git_url:
                    git_url = git_url.replace('git:', 'https:')

                # when announcing, we only need first 12 characters of tag SHA-1
                message: str = prepare_message()  # why we need this workaround?
                message = message.format(git_repo, git_url, tag_name, tag_sha1[:12], tagged_commit)
                if utils.push_notification(message, dry_run):
                    # however, we still cache the full SHA-1
                    utils.write_to_file(tag_file, tag_sha1)
