#!/bin/bash

SILENT=false

log() {
    if [ "$SILENT" = "false" ]; then
        echo "$@"
    fi
} 