#!/usr/bin/env python3
# Copyright (C) 2019-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from hashlib import sha384
from os import environ, makedirs, remove
from os.path import exists, join, isdir

from argparse import ArgumentParser
from feedparser import parse
from git import cmd as git_cmd
from requests import post

# get content from a file
def get_content(file):
    try:
        file = open(file, 'rb')
        content = file.read().decode()
        file.close()

    except FileNotFoundError:
        content = None

    return content

# get content hash from a file using sha384
def get_hash(file):
    content = get_content(file)

    if content is not None:
        return sha384(content.encode()).hexdigest()
    else:
        # assume empty
        return ''

# write content to a file
def write_to(file, content):
    file = open(file, 'w+')
    file.write(content)
    file.close()

# telegram sendMessage wrapper
def notify(msg):
    tg_url = 'https://api.telegram.org/bot' + environ['TELEGRAM_TOKEN'] + '/SendMessage'
    query = {
        'chat_id': environ['TELEGRAM_CHAT'],
        'text': msg + '\n\n— @KudNotifier —',
        'parse_mode': 'Markdown',
        'disable_web_page_preview': 'true'
    }

    post(tg_url, data=query)

# git release announcement
def git_announce():
    # initialize GitPython
    git = git_cmd.Git()
    # list of urls to announce
    url = ['git://git.zx2c4.com/wireguard-linux-compat']

    # for each url...
    for i in range (0, len(url)):
        # repository name
        repo = url[i].split('/')[-1]
        # list of tags
        tags = git.ls_remote('--tags', url[i]).split('\n')

        repo_path = join(path + '/' + repo)
        # create repo directory if not exists
        if not exists(repo_path):
            makedirs(repo_path)

        # parse every 2 entries, next one is tagged commit
        for j in range (0, len(tags), 2):
            tag = tags[j].replace('/', '\t').split('\t')
            tag_file = join(repo_path + '/' + tag[3])
            # short SHA-1 format – first 12 letters
            tag_sha = tag[0][:12]

            # although rare since tag re-releases are uncommon, announce if tag is different
            if get_content(tag_file) != tag_sha:
                msg = '*New Git release detected!*\n'
                msg += '\n'
                msg += 'Repository: [' + repo + '](' + url[i].replace('git:', 'https:') + ')' + '\n'
                msg += 'Tag: `' + tag[3] + '` (`' + tag_sha + '`)\n'
                msg += 'Commit: `' + tags[j + 1][:12] + '`'

                notify(msg)
                # write tag sha
                write_to(tag_file, tag_sha)

# linux kernel announcement
def linux_announce():
    # url of release rss
    korg_url = 'https://www.kernel.org/feeds/kdist.xml'
    list = parse(korg_url)

    # from first to last
    for i in range (0, len(list.entries)):
        # skip linux-next; we only want stable and mainline releases
        if 'linux-next' not in list.entries[i].title:
            # release details is under id
            details = list.entries[i].id.split(',')
            digest = sha384(list.entries[i].title.encode()).hexdigest()

            if 'mainline' in list.entries[i].title:
                # mainline must be treated differently
                version_file = join(path + '/mainline-version')
            else:
                release = details[2].split('.')
                version = release[0] + '.' + release[1]
                # version naming: x.y-version
                version_file = join(path + '/' + version + '-version')

            # announce new version
            if get_hash(version_file) != digest:
                if 'mainline' in list.entries[i].title:
                    msg = '*New Linux mainline release available!*\n'
                    msg += '\n'
                else:
                    msg = '*New Linux ' + version + ' series release available!*\n'
                    msg += '\n'
                    msg += 'Release type: ' + details[1] + '\n'
                msg += 'Version: `' + details[2] + '`\n'
                msg += 'Release date: ' + details[3]
                if 'mainline' not in list.entries[i].title:
                    msg += '\n\n'
                    msg += '[Changes from previous release](https://cdn.kernel.org/pub/linux/kernel/v' + release[0] + '.x/ChangeLog-' + details[2] + ')'

                notify(msg)
                # write new version
                write_to(version_file, list.entries[i].title)

# OSDN File Storage announcement
def osdn_announce():
    # project name
    project_name = 'kudproject'
    # url of the project
    base_url = 'https://osdn.net/projects/' + project_name
    osdn_url = base_url + '/storage/!rss'
    list = parse(osdn_url)

    # start from the oldest
    for i in range(len(list.entries) - 1, -1, -1):
        # get the file name instead of full path
        name = list.entries[i].title.split('/')[-1]
        digest = sha384(list.entries[i].title.encode()).hexdigest()
        # cache file: use file name
        cache_file = join(path + '/' + name)

        # both hashes are different, announce it
        if get_hash(cache_file) != digest:
            # i hab nu idea pls halp // pun intended
            msg = '*New file detected on *[KudProject](' + base_url + ')*\'s OSDN!*\n'
            msg += '\n'
            msg += '`' + name + '`\n'
            msg += 'Upload date: ' + list.entries[i].published + '\n'
            msg += '\n'
            # use shortlink provided by OSDN
            msg += '[Download](https://osdn.net/dl/' + project_name + '/' + name + ')'

            notify(msg)
            # write new version
            write_to(cache_file, list.entries[i].title)

# main functions
if __name__ == '__main__':
    parser = ArgumentParser(description='All-in-one Telegram announcement script using Telegram Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired',
                        type=str, choices=['git', 'linux', 'osdn'])

    args = parser.parse_args()

    path = join(environ['HOME'] + '/.tg-announce/')
    # attempt removal of file of same name
    if exists(path) and not isdir(path):
        remove(path)

    path = join(path + args.type)
    # create cache directory if not exists
    if not exists(path):
        makedirs(path)

    if args.type == 'git':
        git_announce()
    elif args.type == 'linux':
        linux_announce()
    elif args.type == 'osdn':
        osdn_announce()
