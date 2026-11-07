# 3dvr-comfyui-worker

Custom RunPod serverless ComfyUI worker image for the 3DVR image rig, with
face tools baked in. Built by GitHub Actions and published to GHCR:

    ghcr.io/tmsteph/3dvr-comfyui-faces:latest

The stock endpoint image (`runpod/worker-comfyui:main-base`) ships with zero
custom nodes, so every face workflow failed with
`Node 'ReActorFaceSwap' not found`. This image fixes that by baking the nodes
and their models into the image itself.

## What is baked in

Base: `runpod/worker-comfyui:5.10.0-base-cuda12.8.1` (pinned). The base
image's handler and start command are untouched.

Custom nodes (pinned commits):

- ComfyUI-ReActor 0.7.1-b3 (face swap), cloned from the author's Codeberg
  repo. The GitHub repo (Gourieff/comfyui-reactor-node) was disabled by
  GitHub staff; Codeberg is the author's official home for the project now.
  Its `install.py` runs during the build, which pip-installs
  `onnxruntime-gpu` plus its `requirements.txt`.
- ComfyUI_IPAdapter_plus by cubiq (GitHub), pinned commit.

Models (downloaded at build time, so cold starts never fetch them):

- `models/insightface/inswapper_128.onnx` (ReActor swap model, from the
  ReActor Hugging Face dataset)
- `models/insightface/models/buffalo_l/` (buffalo_l face analysis pack:
  det_10g, w600k_r50, genderage, 2d106det, 1k3d68)
- `models/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin` (IPAdapter FaceID
  Plus v2, SDXL, from h94/IP-Adapter-FaceID)
- `models/loras/ip-adapter-faceid-plusv2_sdxl_lora.safetensors` (FaceID LoRA)
- `models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors`
  (CLIP Vision ViT-H, from h94/IP-Adapter's SDXL image encoder)

No diffusion checkpoints are baked in, and the image contains no secrets
(public repo, public image).

## Endpoint notes

Point a RunPod serverless endpoint at the GHCR image above and attach the
network volume `comfyui-photoreal-us-wa1` as usual (the stock worker mounts
it at `/runpod-volume` and symlinks the ComfyUI model folders from it), so
checkpoints (CyberRealistic, Juggernaut, etc.) keep coming from the volume
exactly as on the stock endpoint. The baked-in models live in the image's
own `/comfyui/models`, which the worker merges with the volume paths.

## Rebuilding

Push to `main` or run the `build-image` workflow manually. The workflow
frees disk space first (the base image is large), builds with Buildx, caches
layers in GHCR (`:buildcache`), and pushes `:latest` plus a `:sha-<commit>`
tag. The Dockerfile ends with sanity checks (model files present,
onnxruntime sees the CUDA provider, ComfyUI's own `--quick-test-for-ci`
node-graph import test), so a broken build fails in CI instead of on a
live worker.

Note: inswapper and buffalo_l are InsightFace models, released for
non-commercial research use; this rig is a personal project.
