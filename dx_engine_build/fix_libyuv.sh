#!/bin/bash
set -euxo pipefail
mkdir -p /depsrc/libyuv
python3 - <<'PY'
import urllib.request
urllib.request.urlretrieve("https://chromium.googlesource.com/libyuv/libyuv/+archive/3bdb3b94caaf12487af7c5f91f830ef0064be250.tar.gz", "/depsrc/libyuv.tgz")
PY
tar -xzf /depsrc/libyuv.tgz -C /depsrc/libyuv
sed -i '/HAS_ARGBTOUVMATRIXROW_NEON_I8MM/{n;/^#define HAS_RGBTOUVMATRIXROW_NEON$/d}' \
  /depsrc/libyuv/include/libyuv/row.h
cd /depsrc/libyuv
cmake -B b -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_C_FLAGS="-mcpu=cortex-a55" -DCMAKE_CXX_FLAGS="-mcpu=cortex-a55" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
ninja -C b yuv yuv_shared
nm -D b/libyuv.so | grep -c NEON || true
nm -D --undefined-only b/libyuv.so | grep NEON || echo "NO-UNDEFINED-NEON"
mkdir -p /work/out_stream/libyuv_fix
cp b/libyuv.a b/libyuv.so /work/out_stream/libyuv_fix/
