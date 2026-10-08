#!/usr/bin/env bash
# SYCLomatic needs CUDA SDK headers to parse the sources (no GPU, no toolkit). The pip-format wheels carry them.
set -euo pipefail
out=${1:-$PWD/cuda-headers}      # mount this at /cuda-headers in the dev image
# Strata's own uv in .uvbin first (the folder holds everything Strata installs); a uv on the PC as fallback
uv=${UV:-}
[ -n "$uv" ] || for c in .uvbin/uv .uvbin/bin/uv; do [ -x "$c" ] && { uv=$c; break; }; done
[ -n "$uv" ] || uv=$(command -v uv || true)
[ -n "$uv" ] || { echo "uv is needed (https://docs.astral.sh/uv/)"; exit 1; }
mkdir -p "$out/include"
# uv pip install --target unpacks the wheels straight into $out/wheels (no download subcommand in uv pip)
"$uv" pip install -q --target "$out/wheels" --no-deps \
  nvidia-cuda-runtime-cu12==12.8.90 nvidia-cuda-nvcc-cu12==12.8.93 nvidia-cublas-cu12==12.8.4.1 nvidia-cuda-cccl-cu12==12.8.90 nvidia-curand-cu12==10.3.9.90
# the wheels' include/ trees land as <pkg>/include: gather every header into $out/include
find "$out/wheels" -type d -name include -print0 | while IFS= read -r -d '' inc; do
  (cd "$inc" && find . -type f -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$out/include/$(dirname "$f")"
    cp -f "$inc/$f" "$out/include/$f"
  done
done
rm -rf "$out/wheels"
ls "$out/include" | head -50
for h in cuda.h cuda_runtime.h cuda_runtime_api.h crt/host_defines.h cuda_fp16.h cuda_bf16.h cublas_v2.h; do
  [ -f "$out/include/$h" ] && echo "ok   $h" || echo "MISS $h"; done
grep -m1 CUDA_VERSION "$out/include/cuda.h" || true
