# V2H-4X-SBC + DEEPX DX-M1M — DX AI Studio Demo Image

Deployment workspace for the **iMDT V2H SBC** (Renesas RZ/V2H, Cortex-A55 aarch64)
paired with a **DEEPX DX-M1M** M.2 AI accelerator — built into a clean,
self-contained **demonstration/base image** that can be flashed to any number of
equivalent boards.

The image runs the full **DX AI Studio** web environment on boot
(`http://<board-ip>:8080`), with every Setup page reporting the real installed
state — no false "missing" items.

## Stack

| Layer | Version | Notes |
|---|---|---|
| Kernel | `6.1.141-cip43-yocto-standard` | Yocto image (no Debian packaging) |
| DX-RT userland | **3.5.0** (`5.502926e`) | `dxrtd` + `dxrt-cli` in `/usr/local` |
| RT + PCIe drivers | **2.7.0** | built for this kernel, `/lib/modules/.../extra`, loaded by `dxrt.service` |
| M1M firmware | **2.7.6** | flashed via `dxrt-cli -u` |
| GStreamer | 1.22.12 | dxstream plugin **3.2.0** — 13 elements incl. `dxinfer` |
| WebRTC stack | complete | `webrtcbin`, `nicesrc/sink`, `srtpenc/dec`, `dtlssrtpenc/dec` |
| Xvfb | noble arm64 chain | self-contained under `/opt/containers/xvfb` — powers Live Display |
| Python | 3.12.11 | venv: `/opt/containers/dx-ai-studio/.venv` |
| Studio | BETA v0.13 | systemd `dx-ai-studio.service`, port 8080 |

## What's on the board

```
/opt/containers/dx-ai-studio   Studio app (v0.13) + shared .venv
/opt/containers/dx-runtime     DX-RT 3.5.0 runtime, dx_app, demo models/videos
/opt/containers/workspace/res  Stream models (15) + video packs (40 files)
/opt/containers/xvfb           Xvfb userland (319 MB, LD_LIBRARY_PATH-wrapped)
/usr/lib/gstreamer-1.0/        libgstdxstream, libgstnice, libgstwebrtc,
                               libgstsctp, libgstsrtp, libgstdtls plugins
/usr/local/share/gstdxstream/lib   18 postprocess + msgconv libraries
```

**Demo assets:** 26/26 app demo models, 24/24 app videos, 15/15 stream models,
16/16 stream videos — all verified. The full 497-model zoo is intentionally not
installed (~45 GB > the 25 GB partition); demo completeness is the criterion.

## Cameras — MIPI ×2 + USB

Verified working through the Studio's own pipeline manager (camera → dxinfer →
NPU). Three sources:

| Camera | Stable device path | Notes |
|---|---|---|
| MIPI CSI-2 #1 | `/dev/v4l/by-path/platform-16000000.video0-video-index4` | AP1302 ISP + AR1335 13 MP |
| MIPI CSI-2 #2 | `/dev/v4l/by-path/platform-16010000.video1-video-index4` | AP1302 ISP + AR1335 13 MP |
| USB (Brio 105) | `/dev/v4l/by-path/platform-15850000.usb-*` or `/dev/v4l/by-id/usb-046d_Brio_105_*` | UVC — negotiates on its own |

`/dev/videoN` indices are **not stable across boots** (UVC may probe before CRU)
— always use the `by-path`/`by-id` names in pipelines.

The CRU nodes only stream when their media-ctl pad chain and the video-node
format are one coherent size — unconstrained `v4l2src` negotiation picks a
mismatched size and corrupts the node. Handled two ways:

- **`v4l2-init.service`** (board-files): topology-driven boot init — finds every
  `CRU output` media device and configures it at 1920x1080 before the Studio.
- **Studio patch** (`_prepare_v4l2_sources`): every `v4l2src` on a CRU device
  gets its pipe re-initialised at pipeline start, and a
  `video/x-raw,format=UYVY,width=1920,height=1080` capsfilter is injected when
  the pipeline doesn't already pin caps. Supported: 1280x720 / 1920x1080 /
  4096x3072.

In Pipeline Builder just drop a `v4l2src` element and set `device` to a
by-path name — caps are optional.

## Quick start — reproduce on a fresh board

Binary bundles are on the [**Releases**](../../releases) page
(`dx-studio-v2h-m1m-v1.0.zip`).

```bash
# 1. DX Stream plugin + postprocess/message libs + dep libs
tar -xzf dxstream_deploy.tgz -C /
ldconfig

# 2. WebRTC stack (nicesrc + webrtcbin + srtp/sctp + nss for libsrtp2)
tar -xzf nice_libs.tgz     -C /usr
tar -xzf webrtc_bundle.tgz -C /
tar -xzf nss_bundle.tgz    -C /
ldconfig && rm -f /root/.cache/gstreamer-1.0/registry.aarch64.bin

# 3. Xvfb (live display)
mkdir -p /opt/containers/xvfb
tar -xzf xvfb_root.tgz -C /opt/containers/xvfb   # produces .../root
install -m755 board-files/Xvfb /usr/local/bin/Xvfb

# 4. Camera init + Studio autostart
install -m755 board-files/v4l2-init.sh board-files/v4l2-init-all.sh /usr/local/bin/
install -m644 board-files/v4l2-init.service /etc/systemd/system/
install -m644 board-files/dx-ai-studio.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now v4l2-init dx-ai-studio

# 5. Verify
dxrt-cli -s                       # 3 NPUs @ 1 GHz
gst-inspect-1.0 dxinfer           # dxstream plugin registered
gst-inspect-1.0 webrtcbin         # WebRTC ready
journalctl -u dx-ai-studio | grep -i code   # pairing code
```

## Cross-build pipeline

Everything deployable is cross-built for aarch64 in a QEMU container
(`dx-aarch64-builder`, see `dx_engine_build/Dockerfile.base`) against a sysroot
staged **from the board itself** (`stage_gst.tgz`, `stage_extra.tgz`,
`rt350_stage.tgz`) — headers and libs match the target exactly.

| Script | Builds |
|---|---|
| `build_dx_stream.sh` | libgstdxstream + 18 custom libs; deps libyuv/json-glib/mosquitto/rdkafka; GLES off (board has GLES2 only) |
| `build_libnice.sh` | libnice 0.1.21 + gst plugin; `gupnp=disabled`, gnutls crypto |
| `build_dx_app*.sh` | dx_app C++ demos (52 demo + 2 graph binaries) |
| `fix_libyuv.sh` | NEON symbol fix for pinned libyuv commit |

Notable fixes baked in: libyuv `HAS_RGBTOUVMATRIXROW_NEON` upstream bug,
jammy json-glib for glib 2.78 compat, bookworm gst 1.22 plugins for WebRTC.

## Studio patches

`patches/dx-all-suite-setup-fixes.patch` — apply on a stock `dx-ai-studio`
tree (`git am` or `patch -p1`). Makes setup diagnostics honest on embedded
images:

- `dx_runtime` version read from `dx_rt/release.ver`, not the umbrella repo marker
- demo-step `ok` judged by `demo_ok` (same rule as `quick_start_plan()`)
- DKMS check passes when modules are loaded via `/lib/modules` (non-DKMS install)
- disk space measured on the filesystem containing `DX_APP_ROOT`, not `/`
- CRU camera prep in `PipelineManager.start()` — media-pipe init + caps
  injection so MIPI cameras just work (see Cameras above)

Upstream commits in `dx-all-suite` (local): `v1.0` = `9673ee9`, then
`9241830`, `8c1942b`, `ab15cef`.

## Verified behaviour

- Boot → Studio on `:8080` in ~60 s; pairing code in the service journal.
- Inference: yolo26n through `dxinfer` runs on the M1M (~55 ms/frame);
  full `urisourcebin → decodebin → dxpreprocess → dxinfer → dxpostprocess → dxosd`
  chain runs to EOS with `dxrtd` allocating NPU tasks.
- WebRTC: `webrtcbin` instantiates via GI — the exact path `webrtc.py` uses.
- Survives reboots; image state contains no per-board tokens.

## Known limitations

- `dx-compiler` stays red — DX-COM is x86-only and needs DEEPX Portal
  credentials; compilation is off-board by design.
- NPU voltage reads `0 mV` since FW 2.7.6 — cosmetic; clocks/temps/inference normal.
- `decodebin` prints cosmetic `Failed to open DRP Driver` lines (Renesas HW
  decoder autoplug; falls back to software — pipeline unaffected).
- `sctpbinsrc` (WebRTC data channels) is not registered — Studio uses media
  transport only.
- Board gets a DHCP address; reserve by MAC if a fixed demo IP is wanted.
