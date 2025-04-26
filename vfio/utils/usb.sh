#!/bin/bash

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

detect_usb() {
    if [ "$INTERACTIVE" = "true" ]; then
        select_usb
    fi
} 