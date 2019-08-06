#!/usr/bin/env bash
# Battery info wrapper for i3status (i3status-rust preferred)
# Copyright (C) 2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Power supply sysclass path
POWER=/sys/class/power_supply

# Check for battery status
battery_status() {
    local CAPACITY

    # Add space in between if more than a battery is present
    [[ -n $STATUS ]] && STATUS+=" "
    # Display current percentage if exist, otherwise report it down
    if [[ $(cat $POWER/"$1"/present) -eq 1 ]]; then
        STATUS+="${1/BAT/}:"
        CAPACITY=$(cat $POWER/"$1"/capacity)
        # Some battery report incorrect percentage after they run out of power
        [[ $CAPACITY -le 5 && $(cat $POWER/"$1"/power_now) -eq 0 ]] && STATUS+="0%" || STATUS+="$CAPACITY%"
    else
        STATUS+="${1/BAT/}:DOWN"
    fi
}

# Recursively find present batteries
for BAT in $(find $POWER -name 'BAT*' | sort -n); do
    battery_status "$(basename "$BAT")"
done

# Additionally, check if we're charging or not
[[ $(cat $POWER/ACAD/online) -eq 1 ]] && STATUS+=" "

# Final output
echo " $STATUS"
