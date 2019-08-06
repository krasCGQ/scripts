#!/usr/bin/env bash
# VPN status wrapper for i3status (i3status-rust preferred)
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Default display
STATUS="VPN "

# Check if tun0 is exist
[[ -d /proc/sys/net/ipv4/conf/tun0 ]] && STATUS+="" || STATUS+=""

# Final output
echo "${STATUS}"
