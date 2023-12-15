# Kud's Personal Scripts

This repository hosts personal scripts I often use on my PCs and server(s). If you feel any of these scripts suit your needs, feel free to use, star this repository and revisit whenever the scripts get updated. Adjustments _might be_ required for some (if not most or all) scripts, however.

In order to be able to use these scripts, please run these commands accordingly:

```
# Some Bash scripts
$ git submodule update --init
# or clone this repository recursively
$ git clone --recursive https://github.com/krasCGQ/scripts.git

# Python 3 scripts, from PyPI in user mode (latest version whenever possible):
$ python3 -m pip install --user -r requirements.txt
# or from ones provided by distro (recommended, but not all may be available):
$ sudo pacman -S $(for i in $(< requirements.txt); do echo python-${i,,}; done) # Arch Linux
```

Some scripts (with `.ion` extension) requires [latest development version of Ion Shell](https://gitlab.redox-os.org/redox-os/ion/#compile-instructions-for-distribution) installed. Follow given instructions, except that you need to install them in `/usr/local` unless you're using distro-provided package.

Enjoy!

## Licensing

A copy of the following mentioned licenses are provided in this repository for reference.

* Excluding script dependencies and stated otherwise, all scripts in this repository are licensed under GPLv3+.

* `snippets/rom_sign` is additionally licensed under Apache 2.0 to acknowledge the fact that some parts of the script are direct adaptation of examples provided in AOSP documentation ([also Apache-licensed](https://source.android.com/license)).

* Prebuilt `dtbToolLineage` from [the LineageOS Project](https://www.lineageos.org) hosted in this repository is instead licensed under BSD 3-Clause license, used by Code Aurora Forum (now known as [CodeLinaro](https://www.codelinaro.org)) for the original dtbTool project.
