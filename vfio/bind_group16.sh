#!/bin/bash
set -e

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/args.sh"

SILENT=false
UNBIND_AUDIO=false

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
            log "or specify GPU and audio PCI addresses with -g and -a options"
            log "Example: $0 -i"
            log "Example: $0 -g 0000:01:00.0 -a 0000:01:00.1"
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

detect_devices() {
    local gpu_info=$(lspci -nn | grep -i "nvidia\|geforce\|quadro" | grep -i "vga\|3d\|display")
    if [ -z "$gpu_info" ]; then
        log "Error: No NVIDIA GPU detected"
        log "Please run the script with -g and -a options to specify PCI addresses"
        log "Example: $0 -g 0000:01:00.0 -a 0000:01:00.1"
        exit 1
    fi

    GPU_PCI=$(select_gpu "$gpu_info")
    AUDIO_PCI=$(select_audio "$GPU_PCI")
}

load_vfio_modules() {
    log "[INFO] Loading VFIO modules..."
    modprobe vfio
    modprobe vfio_pci
    modprobe vfio_iommu_type1
}

bind_devices() {
    log "[INFO] Binding devices to VFIO driver..."
    echo $GPU_PCI > /sys/bus/pci/drivers/vfio-pci/bind
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo $AUDIO_PCI > /sys/bus/pci/drivers/vfio-pci/bind
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Bind GPU and audio devices to VFIO driver for passthrough"
    echo
    echo "Options:"
    echo "  -g, --gpu-pci     GPU PCI address (default: auto-detect)"
    echo "  -a, --audio-pci   Audio PCI address (default: auto-detect)"
    echo "  -i, --interactive Interactive mode for GPU and audio selection"
    echo "  -n, --no-audio    Do not bind audio device"
    echo "  -s, --silent      Reduce verbosity"
    echo "  -h, --help        Show this help message"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        if ! parse_common_args "$1" "$2"; then
            log "Unknown option: $1"
            show_help
            exit 1
        fi
        shift
    done
}

main() {
    check_root
    parse_args "$@"
    detect_devices
    load_vfio_modules
    bind_devices
    log "[OK] GPU and audio devices are now ready for passthrough"
}

main "$@"
