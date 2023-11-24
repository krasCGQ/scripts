#
# Configuration file for KudNotifier script.
# Please do not rename or introduce variables.
#

# notifier.git
# Please define in either git or http(s) protocols.
# ssh protocol isn't supported as you may want this script to run unattended.
git_urls: list[str] = [
    'https://git.zx2c4.com/wireguard-linux-compat'
]

# notifier.linux
# Whether to notify for -next releases or not.
# Defaults to True and can be set to False if not desired.
linux_notify_next: bool = True

# notifier.project
# List of projects it should monitor in format of <project-name>:<service-name>.
# Valid options for <service-name> are (only so far) sourceforge and osdn.
projects_list: list[str] = [
    'kudproject:osdn'
]

# notifier.utils
# Set a desired message byline. Otherwise set this to an empty string.
utils_byline = '\n\n— @KudNotifier —'
