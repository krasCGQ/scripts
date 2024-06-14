# Kras' Personal Scripts

This repository hosts personal scripts I often use on my working environments. If you feel any of these scripts suit your needs, feel free to use, star this repository and revisit whenever the scripts get updated. Adjustments _might be_ required for some (if not most or all) scripts, however.

To clone this repository, at least to use only Bash or Zsh scripts, this command should be enough:

```bash
git clone --recurse-submodules https://github.com/krasCGQ/scripts.git
```


## Python-specific

* Python 3.9+ is required to execute the notifier's main part (`notifier.py`) in `utils` folder.

* Modules written for the notifier script however, might require even newer version of Python depending on when they were introduced or last modified. As of December 2023, the notifier script and all of their currently present modules are known to work on both Python 3.11 (on Arch Linux) and 3.12 (on Void Linux).

* All explicitly listed dependencies are pinned to ensure stability of all scripts.

Installation of dependencies via PyPI is the only officially supported option, and it's strongly recommended to do so within a virtual environment. The following commands assume that you're executing them within `utils` folder:

```bash
python -m venv .venv --upgrade-deps
source .venv/bin/activate
python -m pip install -r requirements.txt
```


## Ion Shell-specific

Scripts with `.ion` extension are written for Ion. Such scripts require [the development version of Ion Shell](https://gitlab.redox-os.org/redox-os/ion/#installation) installed. However, given its WIP status, shell syntax(es) may change at any time and will end up breaking some or all of these scripts.

Alternatively for Arch Linux and derivatives, [`ion-git`](https://aur.archlinux.org/packages/ion-git) can be installed from AUR.


## Licensing

A copy of the following mentioned licenses are provided in this repository for reference.

* Excluding script dependencies and stated otherwise, all scripts in this repository are licensed under GPLv3+.

* `snippets/rom_sign` is additionally licensed under Apache 2.0 to acknowledge the fact that some parts of the script are direct adaptation of examples provided in AOSP documentation ([also Apache-licensed](https://source.android.com/license)).

* Prebuilt `dtbToolLineage` from [the LineageOS Project](https://www.lineageos.org) hosted in this repository is instead licensed under BSD 3-Clause license, used by Code Aurora Forum (now known as [CodeLinaro](https://www.codelinaro.org)) for the original dtbTool project.
