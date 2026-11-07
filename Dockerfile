# syntax=docker/dockerfile:1
# 3DVR ComfyUI worker: RunPod's stock serverless ComfyUI worker with face
# tools baked in (ReActor face swap + IPAdapter FaceID). No checkpoints are
# baked in -- they come from the RunPod network volume at runtime, exactly
# like the stock endpoint. No secrets anywhere in this image. The base
# image's handler and CMD are left untouched.
FROM runpod/worker-comfyui:5.10.0-base-cuda12.8.1

LABEL org.opencontainers.image.source="https://github.com/tmsteph/3dvr-comfyui-worker" \
      org.opencontainers.image.description="RunPod ComfyUI serverless worker with ReActor + IPAdapter FaceID baked in" \
      org.opencontainers.image.licenses="GPL-3.0-only"

# Pinned upstream commits for reproducible builds.
ARG REACTOR_COMMIT=fd9c127ad82a0016fde37fed7ba193018049f727
ARG IPADAPTER_COMMIT=a0f451a5113cf9becb0847b92884cb10cbdec0ef

ENV PIP_NO_INPUT=1

# ------------------------------------------------------------------ nodes --
# ReActor: the GitHub repo was disabled by GitHub staff; the author's
# official home is now Codeberg (same author, same project).
RUN git clone https://codeberg.org/Gourieff/comfyui-reactor-node.git \
      /comfyui/custom_nodes/comfyui-reactor-node \
    && git -C /comfyui/custom_nodes/comfyui-reactor-node checkout ${REACTOR_COMMIT}

RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git \
      /comfyui/custom_nodes/ComfyUI_IPAdapter_plus \
    && git -C /comfyui/custom_nodes/ComfyUI_IPAdapter_plus checkout ${IPADAPTER_COMMIT}

# --------------------------------------------------------- ReActor models --
# Pre-downloaded so cold starts never fetch models at runtime.
#   inswapper_128.onnx -> /comfyui/models/insightface/ (install.py below
#                         skips its own download when the file exists)
#   buffalo_l pack     -> /comfyui/models/insightface/models/buffalo_l/
RUN set -eux; \
    mkdir -p /comfyui/models/insightface/models/buffalo_l; \
    dl() { for i in 1 2 3 4 5; do wget -q -O "$2" "$1" && return 0; sleep 5; done; return 1; }; \
    dl https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx \
       /comfyui/models/insightface/inswapper_128.onnx; \
    dl https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/buffalo_l.zip \
       /tmp/buffalo_l.zip; \
    python -m zipfile -e /tmp/buffalo_l.zip /comfyui/models/insightface/models/buffalo_l/; \
    rm -f /tmp/buffalo_l.zip

# --------------------------------------------- ReActor prescribed install --
# install.py pip-installs onnxruntime-gpu + requirements.txt into the venv.
# It runs headless: folder_paths resolves because we run from /comfyui, and
# with no GPU visible at build time it installs the latest onnxruntime-gpu.
RUN cd /comfyui && python custom_nodes/comfyui-reactor-node/install.py

# ------------------------------------------------------ IPAdapter models --
RUN set -eux; \
    mkdir -p /comfyui/models/ipadapter /comfyui/models/loras /comfyui/models/clip_vision; \
    dl() { for i in 1 2 3 4 5; do wget -q -O "$2" "$1" && return 0; sleep 5; done; return 1; }; \
    dl https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin \
       /comfyui/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin; \
    dl https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl_lora.safetensors \
       /comfyui/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors; \
    dl https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors \
       /comfyui/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors

# -------------------------------------------------------------- sanity -----
# Fail the build loudly if anything above silently did not land.
RUN set -eux; \
    echo '== custom nodes =='; \
    ls /comfyui/custom_nodes; \
    echo '== model files =='; \
    ls -la /comfyui/models/insightface/ \
           /comfyui/models/insightface/models/buffalo_l/ \
           /comfyui/models/ipadapter/ \
           /comfyui/models/loras/ \
           /comfyui/models/clip_vision/; \
    test -s /comfyui/models/insightface/inswapper_128.onnx; \
    test -s /comfyui/models/insightface/models/buffalo_l/det_10g.onnx; \
    test -s /comfyui/models/insightface/models/buffalo_l/w600k_r50.onnx; \
    test -s /comfyui/models/insightface/models/buffalo_l/genderage.onnx; \
    test -s /comfyui/models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin; \
    test -s /comfyui/models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors; \
    test -s /comfyui/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors

RUN python -c "import onnxruntime as ort, cv2, numpy, onnx; \
print('onnxruntime', ort.__version__); \
print('providers:', ort.get_available_providers()); \
assert 'CUDAExecutionProvider' in ort.get_available_providers(), 'CUDAExecutionProvider missing'; \
print('cv2', cv2.__version__, '| numpy', numpy.__version__, '| onnx', onnx.__version__)"

# Full node-graph import test -- the same smoke test the base image runs on
# itself -- so a node that cannot import fails here, not on a live worker.
RUN cd /comfyui && timeout 900 python main.py --quick-test-for-ci --cpu
