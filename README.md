# ⚠️ WARNING: PROJECT UNDER DEVELOPMENT ⚠️

This project is currently under active development and may contain bugs or incomplete features. Use at your own risk.

- The installation process may modify critical system settings. Read carefully the script output.
- Some features may not work as expected
- Breaking changes may occur in future updates
- Always backup your system before proceeding

# QEMU VFIO GPU Passthrough Setup

This project provides a complete setup for GPU passthrough with QEMU and VFIO. It includes scripts to build the last QEMU version with all necessary features and configure your system for GPU passthrough.

## Features

- Latest QEMU version with all necessary features
- Automatic GPU detection and configuration
- VFIO setup and configuration
- GRUB configuration for IOMMU and VFIO
- GPU ROM generation
- Interactive installation process

## Requirements

- A CPU with IOMMU support (Intel VT-d or AMD-Vi)
- A GPU that supports passthrough
- Linux distribution (tested on Debian 12)
- Root access for installation

## Dependencies

The following packages will be installed during the setup:
- docker-ce
- dialog
- pciutils
- screen
- libvirt-daemon-system
- libvirt-clients
- bridge-utils
- virt-manager
- ovmf

## Installation

1. Clone the repository:
```bash
git clone https://github.com/Glastis/Debian-VM-GPU-Passthough.git
cd Debian-VM-GPU-Passthough
```

2. Run the installation script:
```bash
./install.sh
```

The script will:
- Check BIOS and GRUB settings
- Install required dependencies
- Build the last QEMU version
- Configure VFIO
- Generate GPU ROM
- Create necessary symlinks

## Usage

To start a VM with GPU passthrough, use the `launch_vm_passthrough.sh` script:

```bash
./launch_vm_passthrough.sh [options]
```

### Options

- `-g, --gpu-pci` : GPU PCI address (default: auto-detect)
- `-a, --audio-pci` : Audio PCI address (default: auto-detect)
- `-i, --interactive` : Interactive mode for GPU, audio and USB selection
- `-t, --text` : Use text interface instead of curses
- `-n, --no-audio` : Do not bind audio device
- `-s, --silent` : Reduce verbosity
- `-d, --disk PATH` : Path to virtual disk image (required)
- `-h, --help` : Show help message

### Example

```bash
./launch_vm_passthrough.sh -d /path/to/disk.qcow2 -i
```

### Important Notes

⚠️ **WARNING**: When the script starts:
1. The GPU will be disconnected from the host system
2. All displays connected to the GPU will go black
3. You will need to access the system via SSH
4. The VM will run in a screen session named `vm_passthrough`

To access the VM after GPU disconnection:
1. Connect to your system via SSH
2. Attach to the screen session:
```bash
screen -r vm_passthrough
```
3. To detach from the screen session without stopping the VM:
   - Press `Ctrl+A` followed by `D`
4. To terminate the VM and restore the GPU:
   - Press `Ctrl+A` followed by `D` to detach
   - Then run:
```bash
screen -X -S vm_passthrough quit
```

The script will:
- Load necessary VFIO modules
- Unbind the GPU from the host
- Bind it to VFIO
- Start the VM with GPU passthrough
- Restore the GPU to the host when the VM is stopped

### Monitoring

To check the GPU passthrough status:
```bash
dmesg | grep -i vfio
```

### Advanced Configuration

- The GPU ROM is generated in `vfio/gpu.rom`
- VFIO modules are automatically loaded at boot
- GRUB configuration is updated with necessary parameters
- Your user is added to the `kvm` and `libvirt` groups

### Notes

- A system reboot is required after installation to apply GRUB changes
- You need to log out and log back in after installation for group changes to take effect
- Make sure IOMMU is enabled in your BIOS before running the installation

## Troubleshooting

If you encounter issues:
1. Check if IOMMU is enabled in BIOS
2. Verify that your GPU is properly detected
3. Check the logs for any error messages
4. Ensure all required packages are installed

## License

[Add your license here] 