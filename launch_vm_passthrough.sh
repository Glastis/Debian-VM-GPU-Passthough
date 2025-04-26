#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ ! -f "gpu.rom" ]; then
    echo "Error: GPU ROM file not found at vfio/gpu.rom"
    echo "Please run the installation script first to generate the ROM"
    exit 1
fi

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

GPU_PCI=""
AUDIO_PCI=""
INTERACTIVE=false
TEXT_MODE=false
NO_AUDIO=false
SILENT=false
DISK_PATH=""
SHOW_LOGS=false

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
    choices=$(dialog --stdout --checklist "Select USB devices to pass through" 20 120 10 "${menu_items[@]}")
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

select_audio_curses() {
    if [ -z "$AUDIO_PCI" ]; then
        local audio_list=$(lspci -nn | grep -i "audio" | sed 's/\[.*\]//')
        local audio_count=$(echo "$audio_list" | wc -l)

        if [ $audio_count -eq 0 ]; then
            dialog --msgbox "No audio devices found" 5 40
            return
        fi

        local menu_items=()
        local i=1
        while IFS= read -r line; do
            local pci_id=$(echo "$line" | awk '{print $1}')
            local vendor_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f1)
            local device_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f2)
            local vendor_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f1)
            local device_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f2)
            menu_items+=("$i" "$pci_id - $vendor_name $device_name" "off")
            i=$((i + 1))
        done <<< "$audio_list"

        local choice
        choice=$(dialog --stdout --radiolist "Select audio device to pass through" 20 60 10 "${menu_items[@]}")
        if [ $? -eq 0 ]; then
            AUDIO_PCI=$(echo "$audio_list" | sed -n "${choice}p" | awk '{print $1}')
        fi
    else
        local pci_id="$AUDIO_PCI"
        local vendor_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f1)
        local device_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f2)
        local vendor_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f1)
        local device_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f2)
        dialog --msgbox "Using audio device: $pci_id - $vendor_name $device_name" 7 60
    fi
}

select_audio() {
    if [ "$CURSES" = "true" ]; then
        select_audio_curses
    else
        if [ -z "$AUDIO_PCI" ]; then
            local audio_list=$(lspci -nn | grep -i "audio" | sed 's/\[.*\]//')
            local audio_count=$(echo "$audio_list" | wc -l)

            if [ $audio_count -eq 0 ]; then
                log "No audio devices found"
                return
            fi

            log "Available audio devices:"
            local i=1
            while IFS= read -r line; do
                local pci_id=$(echo "$line" | awk '{print $1}')
                local vendor_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f1)
                local device_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f2)
                local vendor_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f1)
                local device_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f2)
                log "$i) $pci_id - $vendor_name $device_name"
                i=$((i + 1))
            done <<< "$audio_list"

            while true; do
                read -p "Select audio device (1-$audio_count) or 'q' to skip: " choice
                if [ "$choice" = "q" ]; then
                    break
                fi

                if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $audio_count ]; then
                    log "Invalid choice"
                    continue
                fi

                AUDIO_PCI=$(echo "$audio_list" | sed -n "${choice}p" | awk '{print $1}')
                log "Selected audio device: $AUDIO_PCI"
                break
            done
        else
            local pci_id="$AUDIO_PCI"
            local vendor_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f1)
            local device_id=$(lspci -n -s "$pci_id" | awk '{print $3}' | cut -d: -f2)
            local vendor_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f1)
            local device_name=$(lspci -nn -s "$pci_id" | grep -o "\[.*\]" | sed 's/\[//;s/\]//' | cut -d: -f2)
            log "Using audio device: $pci_id - $vendor_name $device_name"
        fi
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
    echo "  -l, --logs        Show logs after VM launch"
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
            -l|--logs)
                SHOW_LOGS=true
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

    if [ -z "$DISK_IMG" ]; then
        log "[ERROR] Virtual disk image path is required"
        log "Use -d or --disk option to specify the path"
        exit 1
    fi

    if [ "$INTERACTIVE" = "true" ]; then
        if [ -z "$GPU_PCI" ]; then
            select_gpu
        fi
        if [ "$NO_AUDIO" = "false" ]; then
            select_audio
        fi
        select_usb
    fi

    log "[INFO] Starting VM passthrough session..."
    log "[INFO] GPU: $GPU_PCI"
    if [ -n "$AUDIO_PCI" ]; then
        log "[INFO] Audio: $AUDIO_PCI"
    fi
    if [ ${#USB_DEVICES[@]} -gt 0 ]; then
        log "[INFO] USB devices: ${USB_DEVICES[*]}"
    fi

    local vm_args="-g $GPU_PCI -d $DISK_IMG"
    if [ -n "$AUDIO_PCI" ]; then
        vm_args+=" -a $AUDIO_PCI"
    fi
    if [ "$UNBIND_AUDIO" = "false" ]; then
        vm_args+=" -n"
    fi
    if [ "$SILENT" = "true" ]; then
        vm_args+=" -s"
    fi
    for usb_device in "${USB_DEVICES[@]}"; do
        vm_args+=" -u $usb_device"
    done

    mkdir -p logs
    local log_file="vm_passthrough_$(date +%Y%m%d_%H%M%S).log"
    touch "logs/$log_file"
    ln -sf "$log_file" logs/latest.log

    log "[DEBUG] Starting screen session with log file: $log_file"
    log "[DEBUG] Command to execute: $VM_SCRIPT $vm_args"

    sudo -u root screen -dmS "$SCREEN_NAME" bash -c "
        echo 'Starting VM passthrough session...' >> \"logs/$log_file\" 2>&1
        echo 'Disconnecting GPU from host...' >> \"logs/$log_file\" 2>&1
        bash vfio/disconnect_gpu_from_host.sh -g $GPU_PCI -a $AUDIO_PCI -n $UNBIND_AUDIO -s $SILENT >> \"logs/$log_file\" 2>&1
        echo 'Binding devices to vfio-pci...' >> \"logs/$log_file\" 2>&1
        bash vfio/bind_group16.sh -g $GPU_PCI -a $AUDIO_PCI -n $UNBIND_AUDIO -s $SILENT >> \"logs/$log_file\" 2>&1
        echo 'Starting VM...' >> \"logs/$log_file\" 2>&1
        bash $VM_SCRIPT $vm_args >> \"logs/$log_file\" 2>&1
        echo 'Reconnecting GPU to host...' >> \"logs/$log_file\" 2>&1
        bash vfio/reconnect_gpu_to_host.sh -g $GPU_PCI -a $AUDIO_PCI -n $UNBIND_AUDIO -s $SILENT >> \"logs/$log_file\" 2>&1
    "

    log "[INFO] VM launched in screen session '$SCREEN_NAME'"
    log "[INFO] Use 'screen -r $SCREEN_NAME' to attach to the session"
    log "[INFO] Use 'screen -X -S $SCREEN_NAME quit' to terminate the session"
    log "[INFO] Logs are saved in $log_file"
    log "[INFO] Latest logs can be found in logs/latest.log"

    if [ "$SHOW_LOGS" = "true" ]; then
        tail -f "logs/$log_file"
    fi
}

main "$@" 