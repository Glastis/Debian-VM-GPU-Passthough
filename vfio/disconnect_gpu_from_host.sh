#!/bin/bash

source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/pci.sh"

NVIDIA_MODS="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
UNBIND_AUDIO=false
SILENT=false

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
        echo $(get_full_pci_id "$AUDIO_PCI") > /sys/bus/pci/drivers/snd_hda_intel/unbind
    fi
    echo $(get_full_pci_id "$GPU_PCI") > /sys/bus/pci/drivers/nvidia/unbind
}

bind_to_vfio() {
    log "[4] Binding to vfio-pci"
    modprobe vfio
    modprobe vfio_pci
    modprobe vfio_iommu_type1

    echo $(get_full_pci_id "$GPU_PCI") > /sys/bus/pci/drivers/vfio-pci/bind
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo $(get_full_pci_id "$AUDIO_PCI") > /sys/bus/pci/drivers/vfio-pci/bind
    fi
}

main() {
    parse_args "$@"
    detect_devices
    stop_display_service
    unload_nvidia_modules
    sleep 1
    unbind_pci_devices
    bind_to_vfio
    log "[✔] GPU at $GPU_PCI ready for VM"
}

main "$@"
