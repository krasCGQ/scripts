#!/usr/bin/env python3
# Copyright (C) 2019-2021 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

from hashlib import sha384
from os import environ, makedirs, remove
from os.path import exists, join, isdir
from re import sub as sub

from argparse import ArgumentParser
from bs4 import BeautifulSoup as bs
from feedparser import parse
from git import cmd as git_cmd
from requests import get as fetchurl, post

# get content from a file
def get_content(file):
    try:
        with open(file, 'rb') as file:
            return file.read().decode()
    except FileNotFoundError:
        return None

# get content hash from a file using sha384
def get_hash(file):
    content = get_content(file)
    if content is not None:
        return sha384(content.encode()).hexdigest()
    return '' # assume empty

# write content to a file
def write_to(file, content):
    with open(file, 'w+') as file:
        file.write(content)

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

# projects (SourceForge, OSDN File Storage) announcement
def project_announce():
    # list of project names
    projects = ['kudproject']
    # only valid for SourceForge and OSDN File Storage
    services = ['osdn']

    for i in range(0, len(projects)):
        # url of the project
        base_url = 'https://' + services[i] + '.net/projects/' + projects[i]
        if services[i] == 'sourceforge':
            project_url = base_url + '/rss'
        elif services[i] == 'osdn':
            project_url = base_url + '/storage/!rss'
        else:
            # error out
            raise Exception(services[i] + " isn't a valid service. Valid services: sourceforge, osdn.")

        list = parse(project_url)

        # start from the oldest
        for j in range(len(list.entries) - 1, -1, -1):
            # get the file name instead of full path
            name = list.entries[j].title.split('/')[-1]
            digest = sha384(list.entries[j].title.encode()).hexdigest()

            service_path = join(path + '/' + services[i])
            # create service directory if not exists
            if not exists(service_path):
                makedirs(service_path)

            # cache file: use file name
            cache_file = join(service_path + '/' + name)
            # both hashes are different, announce it
            if get_hash(cache_file) != digest:
                if services[i] == 'sourceforge':
                    msg = '*New file detected on SourceForge:* [' + projects[i] + '](' + project_url + ')\n'
                elif services[i] == 'osdn':
                    msg = '*New file detected on OSDN File Storage:* [' + projects[i] + '](' + project_url + ')\n'
                msg += '\n'
                msg += 'Name: `' + name + '`\n' # avoid markdown parsing
                msg += 'Upload date: ' + list.entries[j].published + '\n'
                msg += '\n'
                if services[i] == 'sourceforge':
                    msg += '[Download](' + list.entries[j].link + ')'
                elif services[i] == 'osdn':
                    # use shortlink provided by OSDN
                    msg += '[Download](https://' + services[i] + '.net/dl/' + projects[i] + '/' + name + ')'

                notify(msg)
                # write new version
                write_to(cache_file, list.entries[j].title)

# COVID-19 update for Sulawesi Tenggara
def update_covid_sultra():
    with fetchurl('https://corona.sultraprov.go.id') as r:
        if not r.ok:
            raise Exception("Unable to retrieve data. Status %s" %(r.status_code))
        data = bs(r.text, 'html5lib').body

    # last updated data
    updated = data.find('span', attrs={'class': 'subheading'}).text
    # total confirmed cases are on 2nd <h2> tag
    new = data.find_all('h2', limit=2)[1].text
    new = new.replace('  ', '').rstrip().split('\n')
    # contains two <table> tags, will be further split below
    tables = data.find_all('table', attrs={'class': 'table table-bordered'}, limit=2)
    # stats changes are on 1st <table> tag
    stat = sub('\n\s*\n', '\n', tables[0].text)
    stat = stat.replace('  ', '').strip().split('\n')
    # tracing changes are on 2nd <table> tag
    trace = sub('\n\s*\n', '\n', tables[1].text)
    trace = trace.replace('  (', ' (').replace('  ', '').strip().split('\n')

    # parsed content to post, including disclaimer
    msg = '*Perkembangan COVID-19 di Sulawesi Tenggara*\n'
    # replace with less weird wording
    msg += updated.replace('Update Terakhir :', 'Data per').replace('-', 'pukul') + '\n'
    msg += '\n'
    # disclaimer as what reported by central task force might be different
    msg += '_Data yang dilaporkan dapat berbeda dengan yang tertera pada data harian pusat._\n'
    msg += '\n'
    msg += '*Kasus Konfirmasi:* ' + new[1] + '\n'
    msg += '*Kasus Aktif:* ' + stat[3] + '\n'
    msg += '*Telah Sembuh:* ' + stat[4] + '\n'
    msg += '*Meninggal Dunia:* ' + stat[5] + '\n'
    msg += '*Suspek:* ' + trace[3] + '\n'
    msg += '*Kontak Erat:* ' + trace[4] + '\n'
    # this one is essentially not required, this is relative to previous number of added cases
    # but we report it anyways since it's listed on the website for some reason, somehow =)
    msg += '*Kasus Baru:* ' + trace[5] + '\n'
    msg += '\n'
    msg += '*Sumber data:* https://corona.sultraprov.go.id'

    notify(msg)

# main functions
if __name__ == '__main__':
    parser = ArgumentParser(description='All-in-one Telegram announcement script using Telegram Bot API.')
    parser.add_argument('-t', '--type', help='select announcement type desired',
                        type=str, choices=['covid_sultra', 'git', 'linux', 'project'])

    args = parser.parse_args()

    path = join(environ['HOME'] + '/.tg-announce/')
    # attempt removal of file of same name
    if exists(path) and not isdir(path):
        remove(path)

    path = join(path + args.type)
    # create cache directory if not exists
    # since we don't save anything for posting updated data for COVID-19, don't create anything
    if not exists(path) and not args.type.startswith('covid'):
        makedirs(path)

    if args.type == 'covid_sultra':
        update_covid_sultra()
    elif args.type == 'git':
        git_announce()
    elif args.type == 'linux':
        linux_announce()
    elif args.type == 'project':
        project_announce()
