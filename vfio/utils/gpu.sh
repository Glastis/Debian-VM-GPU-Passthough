#!/bin/bash

select_gpu_curses() {
    local gpu_info="$1"
    local gpu_count=$(echo "$gpu_info" | wc -l)

    if [ $gpu_count -gt 1 ]; then
        if [ "$INTERACTIVE" != "true" ]; then
            log "Error: Multiple NVIDIA GPUs detected"
            log "Please run the script with -i option to choose a GPU interactively"
            log "or specify GPU PCI address with -g option"
            log "Example: $0 -i"
            log "Example: $0 -g 0000:01:00.0"
            exit 1
        fi

        local menu_items=()
        local i=1
        while IFS= read -r line; do
            menu_items+=("$i" "$line")
            i=$((i + 1))
        done <<< "$gpu_info"

        local choice
        choice=$(dialog --stdout --menu "Select GPU" 20 60 10 "${menu_items[@]}")
        if [ $? -eq 0 ]; then
            echo "$gpu_info" | sed -n "${choice}p" | cut -d' ' -f1
        else
            log "No GPU selected"
            exit 1
        fi
    else
        echo "$gpu_info" | cut -d' ' -f1
    fi
}

select_gpu() {
    local gpu_info="$1"
    local gpu_count=$(echo "$gpu_info" | wc -l)

    if [ $gpu_count -gt 1 ]; then
        if [ "$INTERACTIVE" != "true" ]; then
            log "Error: Multiple NVIDIA GPUs detected"
            log "Please run the script with -i option to choose a GPU interactively"
            log "or specify GPU PCI address with -g option"
            log "Example: $0 -i"
            log "Example: $0 -g 0000:01:00.0"
            exit 1
        fi

        if [ "$CURSES" = "false" ]; then
            log "Multiple NVIDIA GPUs detected:"
            local i=1
            while IFS= read -r line; do
                log "$i) $line"
                i=$((i + 1))
            done <<< "$gpu_info"

            local choice
            read -p "Select GPU (1-$gpu_count): " choice
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $gpu_count ]; then
                log "Invalid choice"
                exit 1
            fi

            echo "$gpu_info" | sed -n "${choice}p" | cut -d' ' -f1
        else
            select_gpu_curses "$gpu_info"
        fi
    else
        echo "$gpu_info" | cut -d' ' -f1
    fi
}

detect_gpu() {
    local gpu_info=$(lspci -D -nn | grep -i "nvidia\|geforce\|quadro" | grep -i "vga\|3d\|display")
    if [ -z "$gpu_info" ]; then
        log "Error: No NVIDIA GPU detected"
        log "Please run the script with -g option to specify GPU PCI address"
        log "Example: $0 -g 0000:01:00.0"
        exit 1
    fi

    GPU_PCI=$(select_gpu "$gpu_info")
} 