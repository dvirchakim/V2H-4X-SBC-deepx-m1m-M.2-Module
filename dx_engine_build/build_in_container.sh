#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends g++ cmake ninja-build python3-dev python3-venv python3-pip ca-certificates >/dev/null
python3 -m venv /venv
. /venv/bin/activate
pip install -q scikit-build-core "pybind11>=2.11,<3" numpy wheel setuptools

mkdir -p /stage/lib/include /stage/lib/lib /stage/extern
cp -r /work/prebuilt/include/dxrt /stage/lib/include/
cp -r /work/dx_rt_src/extern/include /stage/extern/include
cp /work/prebuilt/lib/* /stage/lib/lib/
cd /stage/lib/lib
ln -sf libdxrt.so.3.4.2 libdxrt.so.3 && ln -sf libdxrt.so.3 libdxrt.so
ln -sf libonnxruntime.so.1.20.1 libonnxruntime.so.1 && ln -sf libonnxruntime.so.1 libonnxruntime.so

rm -rf /build_pkg && cp -r /work/dx_rt_src/python_package /build_pkg
cd /build_pkg
export LIBRARY_PATH=/stage/lib/lib LD_LIBRARY_PATH=/stage/lib/lib
export CMAKE_ARGS="-DDX_ROOT_DIR=/stage -DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath,/usr/local/lib"
mkdir -p /work/dist
pip wheel . --no-deps --no-build-isolation -w /work/dist -v
ls -la /work/dist
