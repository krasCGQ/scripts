# Kud's Personal Scripts

This repository hosts personal scripts I often use on my PCs and server(s). If you feel any of these scripts suit your needs, feel free to use, star this repository and revisit whenever the scripts get updated. Adjustments _might be_ required for some (if not most or all) scripts, however.

In order to be able to use these scripts, please run these commands accordingly:

```
# Some Bash scripts
$ git submodule update --init
# or clone this repository recursively
$ git clone --recursive git://github.com/krasCGQ/scripts

# Python 3 scripts, from PyPI in user mode (latest version whenever possible):
$ python3 -m pip install --user -r requirements.txt
# or from ones provided by distro (recommended, but not all may be available):
$ sudo pacman -S $(for i in $(cat requirements.txt); do echo python-$i; done) # Arch Linux
```

Enjoy!

## License

### All scripts in this repository (excluding dependencies as submodules):

```
Copyright (C) 2017-2020 Albert I (krasCGQ)

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

### Also applies to [snippets/rom_sign](./snippets/rom_sign):

```
Copyright 2017-2020 Albert I (krasCGQ)

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

Complete license can be read [here](./LICENSE.rom_sign).

### Prebuilt dtbToolLineage:

dtbToolLineage is based on initial dtbTool source by Code Aurora Forum (CAF),
which is licensed under a modified BSD 3-Clause license, which can be read
[here](./LICENSE.dtbTool).
