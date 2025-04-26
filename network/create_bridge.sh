#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run as root"
    exit 1
fi

INTERFACE=$(ip link show | grep -v "lo:" | grep -v "virbr" | grep -v "vnet" | grep "state UP" | head -n1 | cut -d: -f2 | tr -d ' ')
BRIDGE="br0"

if [ -z "$INTERFACE" ]; then
    echo "[ERROR] No active network interface found"
    exit 1
fi

if ! command -v brctl &> /dev/null; then
    echo "[INFO] Installing bridge-utils..."
    apt-get update && apt-get install -y bridge-utils
fi

echo "[INFO] Disabling interface $INTERFACE..."
ip link set $INTERFACE down

if ! brctl show | grep -q $BRIDGE; then
    echo "[INFO] Creating bridge $BRIDGE..."
    brctl addbr $BRIDGE
fi

echo "[INFO] Adding $INTERFACE to bridge $BRIDGE..."
brctl addif $BRIDGE $INTERFACE

echo "[INFO] Enabling interfaces..."
ip link set $BRIDGE up
ip link set $INTERFACE up

echo "[INFO] Getting IP via DHCP..."
dhclient $BRIDGE

echo "[OK] Bridge $BRIDGE is ready"
