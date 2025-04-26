#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être lancé en tant que root (sudo)." >&2
    exit 1
fi

source "vfio/utils/logging.sh"
source "vfio/utils/root.sh"
source "vfio/utils/gpu.sh"

QEMU_BIN="qemu-system-x86_64"
QEMU_PATH="qemu-build/bin/$QEMU_BIN"
GPU_ROM_PATH="gpu.rom"
PACKAGES="docker-ce dialog pciutils screen libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf"
VFIO_MODULES="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"
GRUB_OPTIONS="amd_iommu=on intel_iommu=on iommu=pt"
GRUB_MODIFIED=false

INTERACTIVE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        *)
            echo "Option inconnue: $1"
            exit 1
            ;;
    esac
done

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
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/&$GRUB_OPTIONS vfio-pci.ids=$gpu_ids /" /etc/default/grub
        update-grub
        GRUB_MODIFIED=true
        log "[INFO] GRUB updated. A reboot will be required."
    fi

    if ! grep -q "vfio" /etc/modules; then
        log "[INFO] Adding VFIO modules..."
        for module in $VFIO_MODULES; do
            echo "$module" | tee -a /etc/modules
        done
    fi

    if ! lsmod | grep -q "vfio"; then
        log "[INFO] Loading VFIO modules..."
        for module in $VFIO_MODULES; do
            modprobe "$module"
        done
    fi
}

check_packages() {
    local missing_packages=""
    for package in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages="$missing_packages $package"
        fi
    done
    echo "$missing_packages"
}

install_dependencies() {
    local missing_packages=$(check_packages)
    
    if [ -z "$missing_packages" ]; then
        log "[INFO] All required packages are already installed"
        return
    fi

    local packages_message="The following packages will be installed:\n  - $missing_packages"
    if ! get_consent "$packages_message" "package installation"; then
        return
    fi

    log "[INFO] Installing dependencies..."
    apt-get update
    apt-get install -y $missing_packages
    usermod -aG kvm,libvirt $SUDO_USER
    log "[INFO] Added user to kvm and libvirt groups"
    log "[INFO] Please log out and log back in for group changes to take effect"
}

check_qemu() {
    if [ -f "$QEMU_BIN" ] || [ -L "$QEMU_BIN" ]; then
        log "[INFO] QEMU binary found at $QEMU_BIN"
        if "$QEMU_BIN" --version >/dev/null 2>&1; then
            log "[INFO] QEMU is working correctly"
            return 0
        else
            log "[WARNING] QEMU binary exists but doesn't work properly"
            return 1
        fi
    fi
    return 1
}

build_qemu() {
    if check_qemu; then
        log "[INFO] Using existing QEMU binary"
        return
    fi

    log "[INFO] Building QEMU..."
    bash build-qemu.sh
}

create_symlink() {
    log "[INFO] Creating symlink..."
    if [ -L "$QEMU_BIN" ]; then
        rm "$QEMU_BIN"
    fi
    ln -s "$QEMU_PATH" "$QEMU_BIN"
}

check_gpu_rom() {
    if [ -f "$GPU_ROM_PATH" ]; then
        log "[INFO] GPU ROM already exists at $GPU_ROM_PATH"
        return 0
    fi
    return 1
}

generate_gpu_rom() {
    if check_gpu_rom; then
        log "[INFO] Using existing GPU ROM"
        return
    fi

    log "[INFO] Generating GPU ROM..."
    local generate_args="-o $GPU_ROM_PATH"
    if [ "$INTERACTIVE" = true ]; then
        generate_args="$generate_args -i"
    fi
    bash vfio/generate_gpu_rom.sh $generate_args
}

main() {
    check_root
    check_bios_grub
    install_dependencies
    build_qemu
    create_symlink
    generate_gpu_rom
    log "[OK] Installation completed successfully!"
    if [ "$GRUB_MODIFIED" = true ]; then
        log "[INFO] A reboot is required to apply GRUB changes."
    fi
}

main "$@" 