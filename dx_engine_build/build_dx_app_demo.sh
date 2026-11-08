#!/bin/bash
set -euxo pipefail
. /venv/bin/activate

mkdir -p /stage && tar -xzf /work/board_stage.tgz -C /stage
mkdir -p /usr/local/include
rm -f /usr/local/lib/libdxrt.so* /usr/local/lib/libonnxruntime.so*; rm -rf /usr/local/include/dxrt
mkdir -p /rt350 && tar -xzf /work/rt350_stage.tgz -C /rt350
cp -a /rt350/usr/local/lib/. /usr/local/lib/
cp -a /rt350/usr/local/include/dxrt /usr/local/include/dxrt
ldconfig
mkdir -p /opt/board/usr
cp -a /stage/usr/include /opt/board/usr/
cp -a /stage/usr/lib /opt/board/usr/
grep -ohE '\$\{_IMPORT_PREFIX\}/lib/opencv4/3rdparty/[A-Za-z0-9_+.-]+\.a' /opt/board/usr/lib/cmake/opencv4/OpenCVModules*.cmake | sort -u | while read -r p; do
  f=$(echo "$p" | sed 's#\${_IMPORT_PREFIX}#/opt/board/usr#'); mkdir -p "$(dirname "$f")"; ar rcs "$f"
done

mkdir -p /build/dx_app && tar -xzf /work/dx_app_src.tgz -C /build/dx_app
cd /build/dx_app
sed -i 's/-march=native/-mcpu=cortex-a55/' src/bindings/python/dx_postprocess/CMakeLists.txt
cat > cmake/toolchain.aarch64.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(onnxruntime_LIB_DIRS /usr/local/lib)
set(onnxruntime_INCLUDE_DIRS /usr/local/include/onnxruntime)
set(DXRT_INSTALLED_DIR /usr/local)
set(OpenCV_DIR /opt/board/usr/lib/cmake/opencv4)
set(CMAKE_C_COMPILER /usr/bin/gcc)
set(CMAKE_CXX_COMPILER /usr/bin/g++)
set(CMAKE_C_FLAGS_INIT "-mcpu=cortex-a55")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a55")
EOF

mkdir -p build_aarch64 && cd build_aarch64
LDF="-Wl,--allow-shlib-undefined -Wl,-rpath-link,/opt/board/usr/lib"
cmake .. -G Ninja -DCMAKE_TOOLCHAIN_FILE=/build/dx_app/cmake/toolchain.aarch64.cmake \
  -DCMAKE_BUILD_TYPE=release -DDXAPP_PYTHON=/venv/bin/python \
  -DCMAKE_EXE_LINKER_FLAGS="$LDF" -DCMAKE_SHARED_LINKER_FLAGS="$LDF"

cd /build/dx_app
. scripts/build_target_resolver.sh
DEMO=$(dxapp_resolve_minimal_targets)
cd build_aarch64
ALL=$(ninja -t targets all | sed 's/:.*//' | sort -u)
TARGETS=""
for t in $DEMO; do
  if grep -qxF -- "$t" <<<"$ALL"; then TARGETS="$TARGETS $t"; else echo "MISSING target $t"; fi
done
grep -iE "graph" <<<"$ALL" | head -5 || true
GRAPHPY=""
echo "C++ targets: $TARGETS $GRAPHPY"
ninja -k 0 -j12 $TARGETS || echo 'SOME TARGETS FAILED (see FAILED lines)'
mkdir -p /work/out_demo/bin /work/out_demo/py
for t in $TARGETS; do f=$(find . -type f -name "$t" -perm -u+x | head -1); if [ -n "$f" ]; then cp "$f" /work/out_demo/bin/; else echo "NOT BUILT: $t"; fi; done
find . -name "dx_graph*.so" -exec cp {} /work/out_demo/py/ \; || true
strip --strip-unneeded /work/out_demo/bin/* || true
ls -la /work/out_demo/bin | wc -l; ls -la /work/out_demo/py
