#!/bin/bash
# Build libnice 0.1.21 + its GStreamer plugin (libgstnice) for the V2H board.
# gupnp disabled: the board lacks libgupnp-igd and ICE works without it
# (UPnP IGD is only a NAT-traversal hint; STUN/host/srflx candidates unaffected).
# crypto=gnutls: board ships libgnutls.so.30 (matches Debian bookworm choice).
set -euxo pipefail
. /venv/bin/activate
pip install -q meson || pip install --no-index --find-links /work/deps meson
# board's glib codegen tools (pure python) — needed by meson glib_mkenums lookup
export PATH="/work/tools:$PATH"

# ---------- staged board sysroot (gstreamer/glib/gnutls dev from the board) ----------
mkdir -p /stage && tar -xzf /work/stage_gst.tgz -C /stage
tar -xzf /work/stage_extra.tgz -C /stage 2>/dev/null || true
# same libc linker-script pitfall as build_dx_stream.sh
rm -f /stage/usr/lib/libc.so* /stage/usr/lib/ld-*.so* /stage/usr/lib/ld-linux*.so* \
      /stage/usr/lib/libpthread* /stage/usr/lib/libm.so* /stage/usr/lib/libmvec* \
      /stage/usr/lib/libdl* /stage/usr/lib/librt* /stage/usr/lib/libresolv* \
      /stage/usr/lib/libnsl* /stage/usr/lib/libutil* /stage/usr/lib/libnss* \
      /stage/usr/lib/libanl* /stage/usr/lib/libBroken* /stage/usr/lib/libthread_db* \
      /stage/usr/lib/libstdc++.so* /stage/usr/lib/libgcc_s* /stage/usr/lib/libatomic* \
      /stage/usr/lib/libc_nonshared.a

cat > /work/pkgconf.sh <<'EOF'
#!/bin/sh
export PKG_CONFIG_SYSROOT_DIR=/stage
export PKG_CONFIG_LIBDIR=/stage/usr/lib/pkgconfig:/stage/usr/local/lib/pkgconfig
exec /usr/bin/pkg-config "$@"
EOF
chmod +x /work/pkgconf.sh

cat > /work/native_libnice.ini <<'EOF'
[binaries]
pkg-config = '/work/pkgconf.sh'
c = '/usr/bin/gcc'
cpp = '/usr/bin/g++'

[built-in options]
c_args = ['-mcpu=cortex-a55']
c_link_args = ['-L/stage/usr/lib', '-Wl,-rpath-link,/stage/usr/lib']
EOF

mkdir -p /build && tar -xzf /work/libnice_src.tgz -C /build
cd /build/libnice-0.1.21
meson setup builddir --prefix=/usr --buildtype=release \
  --native-file=/work/native_libnice.ini \
  -Dgupnp=disabled -Dgstreamer=enabled -Dcrypto-library=gnutls \
  -Dintrospection=disabled -Dtests=disabled -Dexamples=disabled
meson compile -C builddir -j 8
DESTDIR=/stage meson install -C builddir --no-rebuild

# ---------- collect output ----------
mkdir -p /work/out_nice
cd /stage/usr
tar -czf /work/out_nice/nice_libs.tgz \
  lib/libnice.so* lib/gstreamer-1.0/libgstnice.so* 2>/dev/null || \
  tar -czf /work/out_nice/nice_libs.tgz \
  $(find . -name 'libnice.so*' -o -name 'libgstnice.so*' | tr '\n' ' ')
tar -tzf /work/out_nice/nice_libs.tgz
echo DONE
