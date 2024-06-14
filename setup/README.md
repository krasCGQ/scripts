## Kras' Termux setup script

I expect that the script is run on a recently bootstrapped Termux environment, although running it again to update existing setup is also supported to a varying degree. In order to use this script, run the following command:

```bash
curl -s https://raw.githubusercontent.com/krasCGQ/scripts/master/setup/termux.bash | bash
```

Replace `master` with `termux-setup` if you want to test staging script with changes yet to be committed into `master` branch. Note that it might take a few minutes for any recent pushes to be reflected properly.

Additionally, it's possible to run the script **AFTER** you [set up desired mirror(s) first](https://github.com/termux/termux-packages/wiki/Mirrors). This is especially important for people with slow or unreliable connections to default sources provided with bootstrap environment. It usually revolves around running the following two commands and their on-screen steps:

```bash
pkg install -o Dpkg::Options::='--force-confnew' -y termux-tools
termux-change-repo
```

As the script changes default shell to Zsh, you need to restart Termux (or create a new window) for it to be applied. You can switch back to Bash by executing ```chsh -s bash``` as soon as the script finished its job.

### A note to consider

Since it's a personal setup, packages and apps that will be installed by this script are mostly those that I use often with _no reliable Android app counterparts_.

This setup script is licensed under the very same GPLv3+ that applies with most part of the repository.
