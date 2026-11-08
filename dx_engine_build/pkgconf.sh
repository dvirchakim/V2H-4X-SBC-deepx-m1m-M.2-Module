#!/bin/sh
export PKG_CONFIG_SYSROOT_DIR=/stage
export PKG_CONFIG_LIBDIR=/stage/usr/lib/pkgconfig:/stage/usr/local/lib/pkgconfig
exec /usr/bin/pkg-config "$@"
