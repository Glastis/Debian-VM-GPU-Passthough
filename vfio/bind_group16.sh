#!/bin/bash
set -e

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/args.sh"

SILENT=false
UNBIND_AUDIO=false

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
