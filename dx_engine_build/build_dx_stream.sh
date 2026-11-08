#!/bin/bash
set -euxo pipefail
. /venv/bin/activate
pip install -q meson || pip install --no-index --find-links /work/deps meson

# ---------- staged board sysroot ----------
mkdir -p /stage && tar -xzf /work/stage_gst.tgz -C /stage
tar -xzf /work/stage_extra.tgz -C /stage 2>/dev/null || true
tar -xzf /work/rt350_stage.tgz -C /stage
mkdir -p /stage/usr/local/lib/pkgconfig /stage/usr/local/include

# Drop the C-runtime/toolchain libs from the sysroot: staged libc.so is a linker
# script with absolute board paths that breaks -L/stage/usr/lib. The container's
# own glibc 2.39 (same version as the board) is used for linking instead.
rm -f /stage/usr/lib/libc.so* /stage/usr/lib/ld-*.so* /stage/usr/lib/ld-linux*.so* \
      /stage/usr/lib/libpthread* /stage/usr/lib/libm.so* /stage/usr/lib/libmvec* \
      /stage/usr/lib/libdl* /stage/usr/lib/librt* /stage/usr/lib/libresolv* \
      /stage/usr/lib/libnsl* /stage/usr/lib/libutil* /stage/usr/lib/libnss* \
      /stage/usr/lib/libanl* /stage/usr/lib/libBroken* /stage/usr/lib/libthread_db* \
      /stage/usr/lib/libstdc++.so* /stage/usr/lib/libgcc_s* /stage/usr/lib/libatomic* \
      /stage/usr/lib/libc_nonshared.a /stage/usr/lib/libasan* /stage/usr/lib/libubsan* \
      /stage/usr/lib/libtsan* /stage/usr/lib/liblsan* /stage/usr/lib/libgomp* \
      /stage/usr/lib/libitm* /stage/usr/lib/libquadmath*

# eigen3.pc (headers are staged, the board has no .pc)
cat > /stage/usr/lib/pkgconfig/eigen3.pc <<'EOF'
prefix=/usr
includedir=${prefix}/include
Name: Eigen3
Description: A C++ template library for linear algebra
Version: 3.4.0
Cflags: -I${includedir}/eigen3
EOF

# ---------- dependency packages ----------
# json-glib must come from jammy (1.6.6): noble's 1.8 needs g_once_init_leave_pointer
# (glib >= 2.80), but the board's Yocto glib is 2.78.
mkdir -p /debroot /debs && cd /debs
apt-get update -qq 2>&1 | tail -2 || true
python3 - <<'PY'
import urllib.request
base = "http://ports.ubuntu.com/ubuntu-ports/pool/main/j/json-glib/"
for p in ("libjson-glib-1.0-0_1.6.6-1build1_arm64.deb",
          "libjson-glib-dev_1.6.6-1build1_arm64.deb"):
    urllib.request.urlretrieve(base + p, p)
PY
PKGS="libmosquitto1 libmosquitto-dev"
if ! apt-get download $PKGS 2>/dev/null; then
  for p in $PKGS; do apt-get download "$p" || echo "DEB-DL-FAIL $p"; done
fi
ls *.deb
for d in *.deb; do dpkg -x "$d" /debroot; done
cp -a /debroot/usr/lib/aarch64-linux-gnu/libjson-glib* /stage/usr/local/lib/
cp -a /debroot/usr/lib/aarch64-linux-gnu/libmosquitto* /stage/usr/local/lib/
cp -a /debroot/usr/include/json-glib-1.0 /stage/usr/local/include/
cp -a /debroot/usr/include/mosquitto*.h /stage/usr/local/include/ 2>/dev/null || true
for p in json-glib-1.0 libmosquitto; do
  f=/debroot/usr/lib/aarch64-linux-gnu/pkgconfig/$p.pc
  [ -f "$f" ] && cp "$f" /stage/usr/local/lib/pkgconfig/
done
sed -i 's#^prefix=.*#prefix=/usr/local#; s#^libdir=.*#libdir=${prefix}/lib#; s#^includedir=.*#includedir=${prefix}/include#' \
  /stage/usr/local/lib/pkgconfig/json-glib-1.0.pc /stage/usr/local/lib/pkgconfig/libmosquitto.pc 2>/dev/null || true

# ---------- source deps ----------
mkdir -p /depsrc && cd /depsrc
python3 - <<'PY'
import urllib.request
for url, fn in [
  ("https://chromium.googlesource.com/libyuv/libyuv/+archive/3bdb3b94caaf12487af7c5f91f830ef0064be250.tar.gz", "libyuv.tgz"),
  ("https://github.com/confluentinc/librdkafka/archive/refs/tags/v2.2.0.tar.gz", "rdkafka.tgz"),
]:
    print("fetch", url, flush=True)
    urllib.request.urlretrieve(url, fn)
PY
mkdir -p libyuv && tar -xzf libyuv.tgz -C libyuv
# upstream bug at this commit: the aarch64 NEON/I8MM block defines
# HAS_RGBTOUVMATRIXROW_NEON but its impl needs HAS_ARGBTOUVMATRIXROW_NEON, which
# upstream excludes under GCC -> row_any.cc references a nonexistent symbol.
sed -i '/HAS_ARGBTOUVMATRIXROW_NEON_I8MM/{n;/^#define HAS_RGBTOUVMATRIXROW_NEON$/d}' \
  libyuv/include/libyuv/row.h
mkdir -p rdkafka && tar -xzf rdkafka.tgz -C rdkafka --strip-components=1

# libyuv -> upstream CMakeLists (per-file -march for neon64/sve/sme objects)
cd /depsrc/libyuv
cmake -B b -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_C_FLAGS="-mcpu=cortex-a55" -DCMAKE_CXX_FLAGS="-mcpu=cortex-a55" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
ninja -C b yuv yuv_shared
cp b/libyuv.a b/libyuv.so* /stage/usr/local/lib/
cp -a include/libyuv.h include/libyuv /stage/usr/local/include/

# librdkafka -> shared lib, minimal features (board lacks sasl/lz4; ssl off)
cd /depsrc/rdkafka
cmake -B b -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DWITH_SSL=OFF -DWITH_SASL=OFF -DWITH_ZSTD=OFF -DWITH_LZ4_EXT=OFF -DWITH_CURL=OFF \
  -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DENABLE_DEVEL=OFF \
  -DCMAKE_C_FLAGS="-mcpu=cortex-a55" -DCMAKE_EXE_LINKER_FLAGS="-L/stage/usr/lib" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L/stage/usr/lib -Wl,-rpath-link,/stage/usr/lib"
ninja -C b
DESTDIR=/stage ninja -C b install

# ---------- pkg-config wrapper + meson native file ----------
cat > /work/pkgconf.sh <<'EOF'
#!/bin/sh
export PKG_CONFIG_SYSROOT_DIR=/stage
export PKG_CONFIG_LIBDIR=/stage/usr/lib/pkgconfig:/stage/usr/local/lib/pkgconfig
exec /usr/bin/pkg-config "$@"
EOF
chmod +x /work/pkgconf.sh

cat > /work/native.ini <<'EOF'
[binaries]
pkg-config = '/work/pkgconf.sh'
c = '/usr/bin/gcc'
cpp = '/usr/bin/g++'

[built-in options]
c_args = ['-mcpu=cortex-a55', '-I/stage/usr/local/include']
cpp_args = ['-mcpu=cortex-a55', '-I/stage/usr/local/include']
c_link_args = ['-L/stage/usr/lib', '-L/stage/usr/local/lib', '-Wl,-rpath-link,/stage/usr/lib', '-Wl,-rpath-link,/stage/usr/local/lib']
cpp_link_args = ['-L/stage/usr/lib', '-L/stage/usr/local/lib', '-Wl,-rpath-link,/stage/usr/lib', '-Wl,-rpath-link,/stage/usr/local/lib']
EOF

# ---------- gst-dxstream-plugin ----------
mkdir -p /build && tar -xzf /work/dx_stream_src.tgz -C /build
cd /build/dx_stream/gst-dxstream-plugin
# GLES disabled: board ships GLES2 headers only (no GLES3/gl3.h) — backend can't run.
meson setup builddir --prefix=/usr/local --buildtype=release --native-file=/work/native.ini \
  -Dwith_gles=disabled
meson compile -C builddir -j 8
meson install -C builddir --destdir=/stage --no-rebuild

# ---------- custom libraries (postprocess + msgconv) ----------
for d in /build/dx_stream/dx_stream/custom_library/postprocess_library/*/ \
         /build/dx_stream/dx_stream/custom_library/message_convert_library/*/; do
  [ -f "$d/meson.build" ] || continue
  echo "=== custom lib: $d"
  rm -rf "$d/builddir"
  meson setup "$d/builddir" "$d" --prefix=/usr/local --buildtype=release --native-file=/work/native.ini
  meson compile -C "$d/builddir" && meson install -C "$d/builddir" --destdir=/stage --no-rebuild || echo "LIB-FAIL $d"
done

# ---------- collect output ----------
mkdir -p /work/out_stream
tar -czf /work/out_stream/usrlocal.tgz -C /stage usr/local
find /stage/usr/local -name "*.so*" -o -name "*.pc" -o -name "meson-info" | sort > /work/out_stream/filelist.txt
tar -tzf /work/out_stream/usrlocal.tgz | wc -l
echo DONE
