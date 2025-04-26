#!/bin/bash

set -e

OUT_DIR="$PWD/qemu-build"

# Nettoyage ancien dossier
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Dockerfile inline
cat > Dockerfile.qemu <<'EOF'
FROM debian:12
RUN apt update && apt install -y \
     git build-essential ninja-build pkg-config \
     python3-pip python3-setuptools \
     libglib2.0-dev libfdt-dev libpixman-1-dev \
     zlib1g-dev libaio-dev libbrlapi-dev libbz2-dev \
     libcap-ng-dev libcurl4-openssl-dev libibverbs-dev \
     libjpeg-dev libncurses5-dev libnuma-dev libpng-dev \
     librbd-dev librdmacm-dev libsasl2-dev libsdl2-dev \
     libseccomp-dev libsnappy-dev libssh-dev libusb-1.0-0-dev \
     libvde-dev libvte-2.91-dev liblzo2-dev flex bison \
     libspice-server-dev \
     libusbredirparser-dev \
     libepoxy-dev


WORKDIR /build

RUN git clone --depth=1 https://gitlab.com/qemu-project/qemu.git

WORKDIR /build/qemu

RUN ./configure --prefix=/output \
    --target-list=x86_64-softmmu,arm-softmmu \
    --enable-kvm \
    --enable-spice \
    --enable-libusb \
    --enable-usb-redir \
    --enable-vnc \
    --enable-virtfs \
    --enable-opengl \
    --enable-guest-agent \
    --disable-xen \
    --enable-slirp \
    --enable-tools


RUN make -j$(nproc)
RUN make install
EOF

# Build l'image
docker build -f Dockerfile.qemu -t qemu-build-temp .

# Créer un conteneur temporaire
CONTAINER_ID=$(docker create qemu-build-temp)

# Copier les fichiers
docker cp "$CONTAINER_ID":/output/. "$OUT_DIR"

# Nettoyer conteneur et dockerfile
docker rm "$CONTAINER_ID"
rm Dockerfile.qemu

echo "✅ QEMU (FULL passthrough ready) installé dans $OUT_DIR"
echo "Exemple : $OUT_DIR/bin/qemu-system-x86_64 --version"
