# krasCGQ's Personal Scripts

This small repository hosts personal scripts used on my PCs and build server. They'll always be updated when needed. If you feel any of these scripts suit your needs, feel free to use, star this repository and revisit whenever the scripts get updated. Adjustments to your directories _may be_ needed.

In order to be able to use these scripts, please run these commands accordingly:

```
# Some Bash scripts
$ git submodule update --init # or clone this repository recursively

# Python 3 scripts
$ sudo pip3 install -r requirements.txt
```

Enjoy!

## Standalone Shell Scripts List

* `build-clang`: Clang build script (mostly modified for my local environment and changes adjusted from [khusika/build-tools-clang](https://github.com/khusika/build-tools-clang))
* `killswitch`: VPN kill switch enabler/disabler for UFW (requires `sudo` privileges as `ufw` is only visible to `root` user); only supports VPN connected through `tun0`
* `kudbuild`: KudKernel build script; only supports mido (treble) and X00T

## Bash Snippets List

* `pia`: Setup and connect to Private Internet Access using OpenVPN CLI with MACE DNS and VPN kill switch enabled (thus depends on `killswitch`)
* `rom_sign`: Android ROM signing wrapper; run `rom_sign` at root of your ROM source after sourcing.
* `tg_sendinline`: Send Telegram posts with inline button URLs using Bot API

## Python Snippets List

* `bmt.py`: ELF (bare-metal) GCC toolchain build script
* `dkms_rebuild.py`: Rebuild DKMS modules of currently running kernel with Clang via gcc and g++ wrappers

## Credits

* [Nathan Chancellor (nathanchance)](https://github.com/nathanchance) - `build-clang` script, which has been modified accordingly on this repository

## License

### All scripts in this repository (except submodules)

```
Copyright (C) 2017-2019 Albert I (krasCGQ)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
```

Complete license can be read [here](./LICENSE).

### Also applies to [snippets/rom_sign](./snippets/rom_sign)

```
Copyright 2017-2019 Albert I (krasCGQ)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
