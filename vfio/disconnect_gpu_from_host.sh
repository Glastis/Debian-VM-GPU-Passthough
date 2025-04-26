#!/bin/bash

NVIDIA_MODS="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
UNBIND_AUDIO=false
SILENT=false

log() {
    if [ "$SILENT" = "false" ]; then
        echo "$@"
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

detect_gpu() {
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

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Disconnect GPU from host for VM passthrough"
    echo
    echo "Options:"
    echo "  -g, --gpu-pci     GPU PCI address (default: auto-detect)"
    echo "  -a, --audio-pci   Audio PCI address (default: auto-detect)"
    echo "  -i, --interactive Interactive mode for GPU and audio selection"
    echo "  -n, --no-audio    Do not unbind audio device"
    echo "  -s, --silent      Reduce verbosity"
    echo "  -h, --help        Show this help message"
    exit 0
}

parse_args() {
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
                log "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

stop_display_service() {
    log "[1] Switching to console"
    service sddm stop
    sudo systemctl isolate multi-user.target
}

unload_nvidia_modules() {
    log "[2] Unloading NVIDIA modules"
    local max_attempts=4
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        for module in $NVIDIA_MODS; do
            sudo modprobe -r $module || log "Module $module already unloaded"
            sleep 0.5
        done
        attempt=$((attempt + 1))
    done
}

unbind_pci_devices() {
    log "[3] PCI unbinding"
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo $AUDIO_PCI > /sys/bus/pci/drivers/snd_hda_intel/unbind
    fi
    echo $GPU_PCI > /sys/bus/pci/drivers/nvidia/unbind
}

bind_to_vfio() {
    log "[4] Binding to vfio-pci"
    modprobe vfio
    modprobe vfio_pci
    modprobe vfio_iommu_type1

    echo $GPU_PCI > /sys/bus/pci/drivers/vfio-pci/bind
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo $AUDIO_PCI > /sys/bus/pci/drivers/vfio-pci/bind
    fi
}

main() {
    parse_args "$@"
    detect_gpu
    stop_display_service
    unload_nvidia_modules
    sleep 1
    unbind_pci_devices
    bind_to_vfio
    log "[✔] GPU at $GPU_PCI ready for VM"
}

main "$@"
