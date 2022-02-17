#
# Copyright (C) 2019-2022 Albert I (krasCGQ)
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

from os import makedirs as os_makedirs
from os.path import exists as path_exists, join as path_join

from git import cmd as git_cmd

from notifier import config, utils

def announce(path):
    # initialize GitPython
    git = git_cmd.Git()

    # for each url...
    for i in range (0, len(config.git_urls)):
        url = config.git_urls[i]
        # repository name
        repo = url.split('/')[-1]
        # list of tags
        tags = git.ls_remote('--tags', url).split('\n')

        repo_path = path_join(path + '/' + repo)
        # create repo directory if not exists
        if not path_exists(repo_path):
            os_makedirs(repo_path)

        # parse every 2 entries, next one is tagged commit
        for j in range (0, len(tags), 2):
            tag = tags[j].replace('/', '\t').split('\t')
            tag_file = path_join(repo_path + '/' + tag[3])
            # short SHA-1 format – first 12 letters
            tag_sha = tag[0][:12]

            # although rare since tag re-releases are uncommon, announce if tag is different
            if utils.read_from_file(tag_file) != tag_sha:
                msg = '*New Git release detected!*\n'
                msg += '\n'
                msg += 'Repository: [' + repo + '](' + url.replace('git:', 'https:') + ')' + '\n'
                msg += 'Tag: `' + tag[3] + '` (`' + tag_sha + '`)\n'
                msg += 'Commit: `' + tags[j + 1][:12] + '`'

                utils.push_notification(msg)
                # write tag sha
                utils.write_to_file(tag_file, tag_sha)

