#!/bin/bash
set -e

source "vfio/utils/logging.sh"
source "vfio/utils/root.sh"
source "vfio/utils/gpu.sh"
source "vfio/utils/audio.sh"
source "vfio/utils/usb.sh"
source "vfio/utils/args.sh"

SCREEN_NAME="vm_passthrough"
VM_SCRIPT="vfio/launch_vm.sh"
USB_DEVICES=()
CURSES=true
DISK_IMG=""

select_usb_curses() {
    local usb_list=$(lsusb | sed 's/ID //' | sed 's/ Device /:/')
    local usb_count=$(echo "$usb_list" | wc -l)

    if [ $usb_count -eq 0 ]; then
        dialog --msgbox "No USB devices found" 5 40
        return
    fi

    local menu_items=()
    local i=1
    while IFS= read -r line; do
        menu_items+=("$i" "$line" "off")
        i=$((i + 1))
    done <<< "$usb_list"

    local choices
    choices=$(dialog --stdout --checklist "Select USB devices to pass through" 20 60 10 "${menu_items[@]}")
    if [ $? -eq 0 ]; then
        for choice in $choices; do
            local selected=$(echo "$usb_list" | sed -n "${choice}p")
            USB_DEVICES+=("$selected")
        done
    fi
}

select_usb() {
    if [ "$CURSES" = "true" ]; then
        select_usb_curses
    else
        local usb_list=$(lsusb | sed 's/ID //' | sed 's/ Device /:/')
        local usb_count=$(echo "$usb_list" | wc -l)

        if [ $usb_count -eq 0 ]; then
            log "No USB devices found"
            return
        fi

        log "Available USB devices:"
        local i=1
        while IFS= read -r line; do
            log "$i) $line"
            i=$((i + 1))
        done <<< "$usb_list"

        while true; do
            read -p "Select USB device (1-$usb_count) or 'q' to finish: " choice
            if [ "$choice" = "q" ]; then
                break
            fi

            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $usb_count ]; then
                log "Invalid choice"
                continue
            fi

            local selected=$(echo "$usb_list" | sed -n "${choice}p")
            USB_DEVICES+=("$selected")
            log "Added USB device: $selected"
        done
    fi
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Launch VM with GPU passthrough in a screen session"
    echo
    echo "Options:"
    echo "  -g, --gpu-pci     GPU PCI address (default: auto-detect)"
    echo "  -a, --audio-pci   Audio PCI address (default: auto-detect)"
    echo "  -i, --interactive Interactive mode for GPU, audio and USB selection"
    echo "  -t, --text        Use text interface instead of curses"
    echo "  -n, --no-audio    Do not bind audio device"
    echo "  -s, --silent      Reduce verbosity"
    echo "  -d, --disk        Path to virtual disk image (required)"
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
            -t|--text)
                CURSES="false"
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
            -d|--disk)
                DISK_IMG="$2"
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

cleanup() {
    log "[INFO] Cleaning up..."
    screen -X -S "$SCREEN_NAME" quit
    "vfio/reconnect_gpu_to_host.sh" -g "$GPU_PCI" -a "$AUDIO_PCI" -n "$UNBIND_AUDIO" -s "$SILENT"
}

main() {
    check_root
    parse_args "$@"
    detect_devices
    detect_usb

    if [ -z "$DISK_IMG" ]; then
        log "[ERROR] Virtual disk image path is required"
        log "Use -d or --disk option to specify the path"
        exit 1
    fi

    if [ "$INTERACTIVE" = "true" ]; then
        select_usb
    fi

    log "[INFO] Starting VM passthrough session..."
    log "[INFO] GPU: $GPU_PCI"
    log "[INFO] Audio: $AUDIO_PCI"
    if [ ${#USB_DEVICES[@]} -gt 0 ]; then
        log "[INFO] USB devices: ${USB_DEVICES[*]}"
    fi

    trap cleanup EXIT

    local vm_args="-g \"$GPU_PCI\" -d \"$DISK_IMG\""
    if [ -n "$AUDIO_PCI" ]; then
        vm_args+=" -a \"$AUDIO_PCI\""
    fi
    if [ "$UNBIND_AUDIO" = "false" ]; then
        vm_args+=" -n"
    fi
    if [ "$SILENT" = "true" ]; then
        vm_args+=" -s"
    fi
    for usb_device in "${USB_DEVICES[@]}"; do
        vm_args+=" -u \"$usb_device\""
    done

    screen -dmS "$SCREEN_NAME" bash -c "
        vfio/disconnect_gpu_from_host.sh -g \"$GPU_PCI\" -a \"$AUDIO_PCI\" -n \"$UNBIND_AUDIO\" -s \"$SILENT\" && \
        vfio/bind_group16.sh -g \"$GPU_PCI\" -a \"$AUDIO_PCI\" -n \"$UNBIND_AUDIO\" -s \"$SILENT\" && \
        $VM_SCRIPT $vm_args && \
        vfio/reconnect_gpu_to_host.sh -g \"$GPU_PCI\" -a \"$AUDIO_PCI\" -n \"$UNBIND_AUDIO\" -s \"$SILENT\"
    "

    log "[INFO] VM launched in screen session '$SCREEN_NAME'"
    log "[INFO] Use 'screen -r $SCREEN_NAME' to attach to the session"
    log "[INFO] Use 'screen -X -S $SCREEN_NAME quit' to terminate the session"
}

main "$@" 