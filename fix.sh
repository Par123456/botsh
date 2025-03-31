#!/bin/bash

pkg update -y

pkg install -y \
    openssl \
    openssl-tool \
    curl \
    libcurl \
    jq \
    python \
    wget

ln -sf /data/data/com.termux/files/usr/lib/libssl.so.3 /data/data/com.termux/files/usr/lib/libssl.so.1.1
ln -sf /data/data/com.termux/files/usr/lib/libcrypto.so.3 /data/data/com.termux/files/usr/lib/libcrypto.so.1.1

chmod 755 /data/data/com.termux/files/usr/lib/libssl.so.3
chmod 755 /data/data/com.termux/files/usr/lib/libcrypto.so.3

pkg clean

echo "SSL fix completed. Please restart Termux."
