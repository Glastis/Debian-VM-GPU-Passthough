#!/bin/bash
set -e

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/args.sh"

SILENT=false
UNBIND_AUDIO=false

unbind_from_vfio() {
    log "[INFO] Unbinding devices from VFIO driver..."
    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo "$AUDIO_PCI" > /sys/bus/pci/drivers/vfio-pci/unbind || true
    fi
    echo "$GPU_PCI" > /sys/bus/pci/drivers/vfio-pci/unbind || true
}

load_nvidia_modules() {
    log "[INFO] Loading NVIDIA modules..."
    modprobe nvidia
    modprobe nvidia_drm
    modprobe nvidia_modeset
    modprobe nvidia_uvm
    modprobe nouveau
}

bind_to_host() {
    log "[INFO] Binding devices to host drivers..."
    echo "nvidia" > /sys/bus/pci/devices/$GPU_PCI/driver_override
    echo $GPU_PCI > /sys/bus/pci/drivers/nvidia/bind
    echo "" > /sys/bus/pci/devices/$GPU_PCI/driver_override

    if [ "$UNBIND_AUDIO" = "true" ] && [ -n "$AUDIO_PCI" ]; then
        echo "snd_hda_intel" > /sys/bus/pci/devices/$AUDIO_PCI/driver_override
        echo $AUDIO_PCI > /sys/bus/pci/drivers/snd_hda_intel/bind
        echo "" > /sys/bus/pci/devices/$AUDIO_PCI/driver_override
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
        if ! parse_common_args "$1" "$2"; then
            log "Unknown option: $1"
            show_help
            exit 1
        fi
        shift
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
    load_nvidia_modules
    sleep 0.5
    bind_to_host
    sleep 1
    start_desktop_environment
    log "[OK] GPU and audio devices are now reconnected to host"
}

main "$@"