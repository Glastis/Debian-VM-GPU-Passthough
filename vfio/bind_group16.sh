#!/bin/bash
#set -e

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/audio.sh"
source "$(dirname "$0")/utils/args.sh"
source "$(dirname "$0")/utils/pci.sh"

SILENT=false
UNBIND_AUDIO=false
PATH_PCI="/sys/bus/pci"
PATH_PCI_DRIVERS="$PATH_PCI/drivers"
PATH_PCI_DEVICES="$PATH_PCI/devices"
GROUP="16"
GROUP_PATH="/sys/kernel/iommu_groups/$GROUP/devices"
VFIO_DRIVER="vfio-pci"

load_vfio_modules() {
    log "[INFO] Loading VFIO modules..."
    modprobe vfio_pci
}

unload_previous_driver() {
    DEVICE="$1"
    log "[INFO] Unloading previous driver for $DEVICE"
    if [ -L "$PATH_PCI_DRIVERS/$DEVICE" ]; then
        echo "[INFO] → Unbind de $DEVICE"
        echo "$DEVICE" > "$PATH_PCI_DRIVERS/$DEVICE/unbind"
    else
        echo "[INFO] → Aucun driver actif pour $DEVICE"
    fi
}

bind_device() {
    DEVICE="$1"
    log "[INFO] Binding device $DEVICE to VFIO driver"
    echo "$VFIO_DRIVER" > "$PATH_PCI_DEVICES/$DEVICE/driver_override"
    echo "$DEVICE" > $PATH_PCI/drivers_probe
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

main() {
    check_root
    parse_args "$@"
    detect_devices
    load_vfio_modules
    for dev_path in $GROUP_PATH; do
        DEVICE=$(basename "$devpath")
        unload_previous_driver "$DEVICE"
        bind_device "$DEVICE"
    done
    log "[OK] GPU and audio devices are now ready for passthrough"
}

main "$@"
