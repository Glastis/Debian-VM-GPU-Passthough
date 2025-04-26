#!/bin/bash
set -e

OUTPUT_FILE="../gpu.rom"

source "$(dirname "$0")/utils/logging.sh"
source "$(dirname "$0")/utils/root.sh"
source "$(dirname "$0")/utils/gpu.sh"
source "$(dirname "$0")/utils/args.sh"

generate_rom() {
    log "[INFO] Generating GPU ROM..."
    log "[INFO] Temporarily enabling ROM for $GPU_PCI..."
    echo 1 | sudo tee /sys/bus/pci/devices/$GPU_PCI/rom > /dev/null || true

    log "[INFO] Attempting to dump VBIOS..."
    if [ ! -f "/sys/bus/pci/devices/$GPU_PCI/rom" ]; then
        log "[ERROR] ROM file not found for GPU $GPU_PCI"
        exit 1
    fi

    local output_dir=$(dirname "$OUTPUT_FILE")
    if [ ! -d "$output_dir" ]; then
        log "[INFO] Creating output directory: $output_dir"
        mkdir -p "$output_dir"
    fi

    log "[INFO] Writing ROM to: $OUTPUT_FILE"
    cat "/sys/bus/pci/devices/$GPU_PCI/rom" > "$OUTPUT_FILE"
    log "[OK] GPU ROM generated successfully at $OUTPUT_FILE"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Generate GPU ROM for passthrough"
    echo
    echo "Options:"
    echo "  -g, --gpu-pci     GPU PCI address (default: auto-detect)"
    echo "  -i, --interactive Interactive mode for GPU selection"
    echo "  -o, --output      Output file path (default: ../gpu.rom)"
    echo "  -s, --silent      Reduce verbosity"
    echo "  -h, --help        Show this help message"
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            *)
                if ! parse_common_args "$1" "$2"; then
                    log "Unknown option: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

main() {
    check_root
    parse_args "$@"
    detect_gpu
    generate_rom
}

main "$@" 