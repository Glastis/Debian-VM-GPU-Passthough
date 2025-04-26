#!/bin/bash
set -e

source "vfio/utils/logging.sh"
source "vfio/utils/root.sh"
source "vfio/utils/gpu.sh"

QEMU_BIN="qemu-system-x86_64"
QEMU_PATH="qemu-build/bin/$QEMU_BIN"
PACKAGES="docker.io dialog pciutils screen libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf"
VFIO_MODULES="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"
GRUB_OPTIONS="amd_iommu=on intel_iommu=on iommu=pt"

get_consent() {
    local message="$1"
    local action="$2"
    log "[INFO] $message"
    while true; do
        read -p "Do you want to proceed? (y/n) " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) log "[INFO] Operation skipped"; return 1;;
            * ) log "Please answer yes or no.";;
        esac
    done
}

check_bios_grub() {
    log "[INFO] Checking BIOS and GRUB settings..."

    if ! dmesg | grep -q "IOMMU enabled"; then
        log "[WARNING] IOMMU is not enabled in BIOS"
        log "[INFO] Please enable the following options in BIOS:"
        log "  - Intel VT-d or AMD-Vi (depending on your CPU)"
        log "  - SVM Mode (for AMD)"
        log "  - IOMMU"
        exit 1
    fi

    detect_gpu
    local gpu_ids=$(echo "$GPU_PCI" | sed 's/\./:/g')
    if [ -n "$AUDIO_PCI" ]; then
        gpu_ids+=",$(echo "$AUDIO_PCI" | sed 's/\./:/g')"
    fi

    if ! grep -q "vfio-pci.ids" /etc/default/grub; then
        local grub_message="The following GRUB options will be added:\n  - $GRUB_OPTIONS\n  - vfio-pci.ids=$gpu_ids"
        if ! get_consent "$grub_message" "GRUB modification"; then
            return
        fi

        log "[INFO] Configuring GRUB..."
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/&$GRUB_OPTIONS vfio-pci.ids=$gpu_ids /" /etc/default/grub
        sudo update-grub
        log "[INFO] GRUB updated. A reboot will be required."
    fi

    if ! grep -q "vfio" /etc/modules; then
        log "[INFO] Adding VFIO modules..."
        for module in $VFIO_MODULES; do
            echo "$module" | sudo tee -a /etc/modules
        done
    fi

    if ! lsmod | grep -q "vfio"; then
        log "[INFO] Loading VFIO modules..."
        for module in $VFIO_MODULES; do
            sudo modprobe "$module"
        done
    fi
}

install_dependencies() {
    local packages_message="The following packages will be installed:\n  - $PACKAGES"
    if ! get_consent "$packages_message" "package installation"; then
        return
    fi

    log "[INFO] Installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y $PACKAGES
    sudo usermod -aG kvm,libvirt $USER
    log "[INFO] Added user to kvm and libvirt groups"
    log "[INFO] Please log out and log back in for group changes to take effect"
}

build_qemu() {
    log "[INFO] Building QEMU..."
    ./build-qemu.sh
}

create_symlink() {
    log "[INFO] Creating symlink..."
    if [ -L "$QEMU_BIN" ]; then
        rm "$QEMU_BIN"
    fi
    ln -s "$QEMU_PATH" "$QEMU_BIN"
}

generate_gpu_rom() {
    log "[INFO] Generating GPU ROM..."
    sudo vfio/generate_gpu_rom.sh -s
}

main() {
    check_root
    check_bios_grub
    install_dependencies
    build_qemu
    create_symlink
    generate_gpu_rom
    log "[OK] Installation completed successfully!"
    log "[INFO] A reboot is required to apply GRUB changes."
}

main "$@" 