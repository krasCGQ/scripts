#!/usr/bin/env bash
# VPN status wrapper for i3status (i3status-rust preferred)
# Copyright (C) 2019-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Default display
STATUS="VPN "

# Check if one of the following interfaces is exist
# wg* should match even WireGuard interface made by third party VPN
NET=/proc/sys/net/ipv4/conf
for i in $NET/tun0 "$NET"/wg*; do
    [[ -d $i ]] && UP=true && break
done
[[ -n $UP ]] && STATUS+="" || STATUS+=""

# Final output
echo "${STATUS}"
