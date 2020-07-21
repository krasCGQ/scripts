#!/usr/bin/sudo /usr/bin/bash
# shellcheck shell=bash
# VPN kill switch enabler/disabler script for UFW
# Copyright (C) 2018-2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# The script is referenced and inspired from:
# https://thetinhat.com/tutorials/misc/linux-vpn-drop-protection-firewall.html
# Modified to be as dead simple and minimal as possible.

die() {
    [[ -n $1 ]] &&
        echo "! $1"

    exit 1
}

# Do nothing on CTRL-C
trap '' INT

trap die ERR

# Location of IP addresses list file
IP_LIST=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.ip-address.saved

if [[ $# -ge 1 && $# -le 3 ]]; then
    # Just to remove IP addresses list file if we're going to be enable
    # Actual $1 parsing is after everything else is queried
    case $1 in
    -e | --enable | on)
        [[ -f $IP_LIST ]] &&
            rm -f "$IP_LIST"
        ;;
    esac

    if [[ $# -eq 2 ]] && echo "$2" | grep -q "/"; then
        # Port + protocol combo
        PORT_PROTOCOL="$2"
    elif [[ $# -eq 3 ]]; then
        # FIXME: This is ugly but it works
        if echo "$2" | grep -qv '[[:alpha:]]'; then
            # Static IP address
            IP_ADDRESS="$2"
            [[ $(echo "$IP_ADDRESS" | sed -e 's/[.]/ /g' | wc -w) -ne 4 ]] &&
                die "Invalid IP address specified!"
        else
            # Assume it's a URL with dynamic IP addresses
            if [[ ! -f $IP_LIST ]]; then
                # Use getent from Glibc to obtain list of IP addresses
                IP_ADDRESS="$(getent hosts "$2" | awk '{print $1}')"
                [[ -z $IP_ADDRESS ]] &&
                    die "Unable to resolve $2."

                # Save IP addresses list to .ip-address.saved
                echo "$IP_ADDRESS" >"$IP_LIST"
            fi
        fi
        if echo "$3" | grep -q "/"; then
            # Port/protocol combo
            PORT_PROTOCOL="$3"
        fi
    fi

    case $1 in
    # Disable kill switch
    -d | --disable | off)
        # Load list of IP addresses is exist then delete it
        if [[ -f $IP_LIST ]]; then
            IP_ADDRESS="$(<"$IP_LIST")"
            rm -f "$IP_LIST"
        fi

        CONFIG=("default allow outgoing"
            "delete allow out on tun0"
            "delete allow out 53/udp")

        if [[ -n $IP_ADDRESS ]]; then
            for IP in $IP_ADDRESS; do
                [[ -n $PORT_PROTOCOL ]] &&
                    CONFIG+=("delete allow out proto ${PORT_PROTOCOL#*/} to $IP port ${PORT_PROTOCOL/\/*/}") ||
                    CONFIG+=("delete allow out to $IP")
            done
        else
            [[ -n $PORT_PROTOCOL ]] &&
                CONFIG+=("delete allow out $PORT_PROTOCOL")
        fi
        ;;

    # Enable kill switch
    -e | --enable | on)
        CONFIG=("default deny outgoing"
            "allow out on tun0"
            "allow out 53/udp")

        if [[ -n $IP_ADDRESS ]]; then
            for IP in $IP_ADDRESS; do
                [[ -n $PORT_PROTOCOL ]] &&
                    CONFIG+=("allow out proto ${PORT_PROTOCOL#*/} to $IP port ${PORT_PROTOCOL/\/*/}") ||
                    CONFIG+=("allow out to $IP")
            done
        else
            [[ -n $PORT_PROTOCOL ]] &&
                CONFIG+=("allow out $PORT_PROTOCOL")
        fi
        ;;

    # Suicide
    *)
        die "Invalid parameter specified!"
        ;;
    esac
else
    die "Usage: $0 <-e|--enable|on|-d|--disable|off> [IP|URL] [port/protocol]"
fi

for COMMAND in "${CONFIG[@]}"; do
    # Word splitting is required here.
    # shellcheck disable=SC2086
    ufw $COMMAND
done
