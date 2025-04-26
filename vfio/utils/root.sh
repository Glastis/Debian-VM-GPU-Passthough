#!/bin/bash

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "[ERROR] Please run as root"
        exit 1
    fi
} 