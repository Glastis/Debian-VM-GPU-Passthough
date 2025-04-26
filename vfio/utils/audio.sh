#!/bin/bash

select_audio_curses() {
    local gpu_pci="$1"
    local audio_info=$(lspci -D -nn | grep -i "audio" | grep "$gpu_pci")
    
    if [ -z "$audio_info" ]; then
        if [ "$UNBIND_AUDIO" = "true" ]; then
            dialog --msgbox "No audio device detected for GPU $gpu_pci" 5 60
            exit 1
        else
            echo ""
            return
        fi
    fi

    local audio_count=$(echo "$audio_info" | wc -l)
    if [ $audio_count -gt 1 ]; then
        if [ "$INTERACTIVE" != "true" ]; then
            log "Error: Multiple audio devices detected for GPU $gpu_pci"
            log "Please run the script with -i option to choose an audio device interactively"
            log "or specify audio PCI address with -a option"
            log "Example: $0 -g $gpu_pci -i"
            log "Example: $0 -g $gpu_pci -a 0000:01:00.1"
            exit 1
        fi

        local menu_items=()
        local i=1
        while IFS= read -r line; do
            menu_items+=("$i" "$line")
            i=$((i + 1))
        done <<< "$audio_info"

        local choice
        choice=$(dialog --stdout --menu "Select audio device for GPU $gpu_pci" 20 60 10 "${menu_items[@]}")
        if [ $? -eq 0 ]; then
            echo "$audio_info" | sed -n "${choice}p" | cut -d' ' -f1
        else
            log "No audio device selected"
            exit 1
        fi
    else
        echo "$audio_info" | cut -d' ' -f1
    fi
}

select_audio() {
    local gpu_pci="$1"
    local audio_info=$(lspci -D -nn | grep -i "audio" | grep "$gpu_pci")
    
    if [ -z "$audio_info" ]; then
        if [ "$UNBIND_AUDIO" = "true" ]; then
            log "Error: No audio device detected for GPU $gpu_pci"
            log "Please run the script with -a option to specify audio PCI address"
            log "Example: $0 -g $gpu_pci -a 0000:01:00.1"
            exit 1
        else
            echo ""
            return
        fi
    fi

    local audio_count=$(echo "$audio_info" | wc -l)
    if [ $audio_count -gt 1 ]; then
        if [ "$INTERACTIVE" != "true" ]; then
            log "Error: Multiple audio devices detected for GPU $gpu_pci"
            log "Please run the script with -i option to choose an audio device interactively"
            log "or specify audio PCI address with -a option"
            log "Example: $0 -g $gpu_pci -i"
            log "Example: $0 -g $gpu_pci -a 0000:01:00.1"
            exit 1
        fi

        if [ "$CURSES" = "false" ]; then
            log "Multiple audio devices detected for GPU $gpu_pci:"
            local i=1
            while IFS= read -r line; do
                log "$i) $line"
                i=$((i + 1))
            done <<< "$audio_info"

            local choice
            read -p "Select audio device (1-$audio_count): " choice
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $audio_count ]; then
                log "Invalid choice"
                exit 1
            fi

            echo "$audio_info" | sed -n "${choice}p" | cut -d' ' -f1
        else
            select_audio_curses "$gpu_pci"
        fi
    else
        echo "$audio_info" | cut -d' ' -f1
    fi
}

detect_devices() {
    detect_gpu
    AUDIO_PCI=$(select_audio "$GPU_PCI")
} 