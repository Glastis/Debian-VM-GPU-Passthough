#!/bin/bash
#set -e

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/args.sh"
source "$(dirname "$0")/utils/pci.sh"

DESKTOP_ENVIRONMENT="sddm"
SILENT=false
UNBIND_AUDIO=false
PATH_PCI="/sys/bus/pci"
PATH_PCI_DRIVERS="$PATH_PCI/drivers"
PATH_PCI_DEVICES="$PATH_PCI/devices"

unbind_from_vfio() {
    log "[INFO] Unbinding devices from VFIO driver..."
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo "$(get_full_pci_id "$AUDIO_PCI")" > "$PATH_PCI_DRIVERS/vfio-pci/unbind" || true
    fi
    echo "$(get_full_pci_id "$GPU_PCI")" > "$PATH_PCI_DRIVERS/vfio-pci/unbind" || true
}

load_nvidia_modules() {
    log "[INFO] Loading NVIDIA modules..."
    modprobe nvidia
    modprobe nvidia_drm
    modprobe nvidia_modeset
    modprobe nvidia_uvm
}

bind_to_host() {
    log "[INFO] Binding devices to host drivers..."
    local full_gpu_pci=$(get_full_pci_id "$GPU_PCI")
    log "[INFO] Full GPU PCI: $full_gpu_pci"
    echo "nvidia" > "$PATH_PCI_DEVICES/$full_gpu_pci/driver_override"
    echo $full_gpu_pci > "$PATH_PCI_DRIVERS/nvidia/bind"
    echo "" > "$PATH_PCI_DEVICES/$full_gpu_pci/driver_override"

    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        local full_audio_pci=$(get_full_pci_id "$AUDIO_PCI")
        echo "snd_hda_intel" > "$PATH_PCI_DEVICES/$full_audio_pci/driver_override"
        echo $full_audio_pci > "$PATH_PCI_DRIVERS/snd_hda_intel/bind"
        echo "" > "$PATH_PCI_DEVICES/$full_audio_pci/driver_override"
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Reconnect GPU and audio devices to host drivers"
    echo
    echo "Options:"
    echo "  -g, --gpu-pci     GPU PCI address (default: auto-detect)"
    echo "  -a, --audio-pci   Audio PCI address (default: auto-detect)"
    echo "  -i, --interactive Interactive mode for GPU and audio selection"
    echo "  -n, --no-audio    Do not bind audio device"
    echo "  -s, --silent      Reduce verbosity"
    echo "  -h, --help        Show this help message"
    echo "  -e, --environment Desktop environment to use, default is 'sddm'"
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
            -e|--environment)
                DESKTOP_ENVIRONMENT="$2"
                shift 2
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

start_desktop_environment() {
    log "[INFO] Starting desktop environment..."
    if [ "$DESKTOP_ENVIRONMENT" = "sddm" ] || 
       [ "$DESKTOP_ENVIRONMENT" = "gdm" ] ||
       [ "$DESKTOP_ENVIRONMENT" = "lightdm" ] ||
       [ "$DESKTOP_ENVIRONMENT" = "xdm" ]; then
        systemctl start $DESKTOP_ENVIRONMENT
    else
        log "[ERROR] Invalid desktop environment: $DESKTOP_ENVIRONMENT"
        exit 1
    fi
}

main() {
    check_root
    parse_args "$@"
    detect_devices
    unbind_from_vfio
    bind_to_host
    load_nvidia_modules
    start_desktop_environment
    log "[OK] GPU and audio devices are now reconnected to host"
}

main "$@"
