#!/bin/bash
set -e

RAM_MB=16384
DISK_IMG="win-atlas.qcow2"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS="./OVMF_VARS_WIN.fd"
GPU_PCI="2b:00.0"
AUDIO_PCI=""
USB_DEVICES=()
CORES=8

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Start VM with GPU passthrough"
    echo
    echo "Options:"
    echo "  -r, --ram         RAM in MB (default: $RAM_MB)"
    echo "  -d, --disk        Disk image path (default: $DISK_IMG)"
    echo "  -g, --gpu-pci     GPU PCI address (default: $GPU_PCI)"
    echo "  -a, --audio-pci   Audio PCI address (default: virtual audio)"
    echo "  -c, --cores       Number of CPU cores (default: $CORES)"
    echo "  -u, --usb         USB device (vendorid:productid, can be used multiple times)"
    echo "  -h, --help        Show this help message"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--ram)
                RAM_MB="$2"
                shift 2
                ;;
            -d|--disk)
                DISK_IMG="$2"
                shift 2
                ;;
            -g|--gpu-pci)
                GPU_PCI="$2"
                shift 2
                ;;
            -a|--audio-pci)
                AUDIO_PCI="$2"
                shift 2
                ;;
            -c|--cores)
                CORES="$2"
                shift 2
                ;;
            -u|--usb)
                USB_DEVICES+=("$2")
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    echo "[INFO] Starting QEMU (GPU passthrough, no virtual display)"
    echo "[INFO] RAM: ${RAM_MB}MB"
    echo "[INFO] Disk: $DISK_IMG"
    echo "[INFO] GPU: $GPU_PCI"
    echo "[INFO] Cores: $CORES"
    if [ -n "$AUDIO_PCI" ]; then
        echo "[INFO] Audio: $AUDIO_PCI (passthrough)"
    else
        echo "[INFO] Audio: virtual (ich9-intel-hda)"
    fi
    if [ ${#USB_DEVICES[@]} -gt 0 ]; then
        echo "[INFO] USB devices: ${USB_DEVICES[*]}"
    fi

    local qemu_cmd="./qemu-system-x86_64 \
        -display none \
        -vga none \
        -serial stdio \
        -overcommit mem-lock=on \
        -enable-kvm \
        -cpu host,kvm=on,hv-relaxed,hv-vapic,hv-time,hv-stimer,hv-synic,hv-ipi,hv-vpindex,hv-runtime \
        -smp cores=$CORES,threads=1,sockets=1 \
        -m ${RAM_MB}M \
        -machine type=q35,accel=kvm \
        -drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE \
        -drive if=pflash,format=raw,file=$OVMF_VARS \
        -drive file=$DISK_IMG,format=qcow2,if=virtio \
        -boot order=c \
        -netdev user,id=net0 -device virtio-net,netdev=net0 \
        -device vfio-pci,host=$GPU_PCI,x-vga=on,romfile=./3080.rom"

    if [ -n "$AUDIO_PCI" ]; then
        qemu_cmd+=" -device vfio-pci,host=$AUDIO_PCI"
    else
        qemu_cmd+=" -device ich9-intel-hda -device hda-duplex"
    fi

    qemu_cmd+=" -device qemu-xhci,id=usb"

    for usb_device in "${USB_DEVICES[@]}"; do
        qemu_cmd+=" -device usb-host,vendorid=0x${usb_device%:*},productid=0x${usb_device#*:}"
    done

    eval "$qemu_cmd"
}

main "$@"
