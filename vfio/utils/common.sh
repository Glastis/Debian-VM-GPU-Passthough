#!/bin/bash

SILENT=false

log() {
    if [ "$SILENT" = "false" ]; then
        echo "$@"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "[ERROR] Please run as root"
        exit 1
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
        echo "$gpu_info" | cut -d' ' -f1
    fi
}

select_audio() {
    local gpu_pci="$1"
    local audio_info=$(lspci -nn | grep -i "audio" | grep "$gpu_pci")
    
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
        echo "$audio_info" | cut -d' ' -f1
    fi
}

detect_gpu() {
    local gpu_info=$(lspci -nn | grep -i "nvidia\|geforce\|quadro" | grep -i "vga\|3d\|display")
    if [ -z "$gpu_info" ]; then
        log "Error: No NVIDIA GPU detected"
        log "Please run the script with -g option to specify GPU PCI address"
        log "Example: $0 -g 0000:01:00.0"
        exit 1
    fi

    GPU_PCI=$(select_gpu "$gpu_info")
}

detect_devices() {
    detect_gpu
    AUDIO_PCI=$(select_audio "$GPU_PCI")
}

parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--gpu-pci)
                GPU_PCI="$2"
                shift 2
                ;;
            -a|--audio-pci)
                AUDIO_PCI="$2"
                shift 2
                ;;
            -i|--interactive)
                INTERACTIVE="true"
                shift
                ;;
            -n|--no-audio)
                UNBIND_AUDIO=false
                shift
                ;;
            -s|--silent)
                SILENT=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                return 1
                ;;
        esac
    done
} 