# ComfyUI (NVIDIA) Docker

ComfyUI is a powerful and modular Stable Diffusion WebUI with support for FLUX, SD, and other AI image generation models.

## Quick Start

1. **Update UID/GID**: Edit `compose.yaml` and set `WANTED_UID` and `WANTED_GID` to your user's values:

   ```bash
   id -u  # Get your UID
   id -g  # Get your GID
   ```

2. **Start the container**:

   ```bash
   docker compose up -d
   ```

3. **Access the WebUI**: Open [http://localhost:8188](http://localhost:8188) in your browser

4. **First run**: The first time you start the container, it will:
   - Download ComfyUI from GitHub
   - Create a Python virtual environment
   - Install all required packages (~5GB)
   - Install ComfyUI Manager

   This process can take 10-20 minutes depending on your internet connection. Monitor progress with:

   ```bash
   docker compose logs -f
   ```

## Directory Structure

- `run/` volume: Contains ComfyUI source code, virtual environment, and HuggingFace data
- `basedir/` volume: Contains your models, custom nodes, inputs, outputs, and user files
  - `basedir/models/` - Store checkpoints, LoRAs, VAEs, etc.
  - `basedir/input/` - Input images
  - `basedir/output/` - Generated images
  - `basedir/custom_nodes/` - Custom nodes
  - `basedir/user/` - User workflows and settings

## GPU Support

### NVIDIA Driver Requirements

- **GTX 10xx GPUs**: Use `ubuntu24_cuda12.6.3-latest` tag and set `PREINSTALL_TORCH=true`
- **RTX 20xx/30xx/40xx GPUs**: Use `latest` tag (default)
- **RTX 50xx (Blackwell) GPUs**: Use `ubuntu24_cuda12.8-latest` tag and NVIDIA driver 570+

Check your CUDA version:

```bash
nvidia-smi  # Look for "CUDA Version" in the output
```

## Configuration

### Environment Variables

Common environment variables in `compose.yaml`:

- `USE_UV=true` - Use uv instead of pip (recommended for speed)
- `WANTED_UID` / `WANTED_GID` - Match your host user for file permissions
- `BASE_DIRECTORY=/basedir` - Separate run and user files (recommended)
- `SECURITY_LEVEL=normal` - ComfyUI Manager security level (normal/weak/strong)
- `USE_NEW_MANAGER=true` - Use integrated ComfyUI Manager (v0.5.0+)
- `COMFY_CMDLINE_EXTRA` - Additional command-line arguments for ComfyUI

### Command-Line Arguments

Add to `COMFY_CMDLINE_EXTRA` for performance tuning:

- `--fast` - Enable faster processing
- `--normalvram` - For GPUs with 8-16GB VRAM
- `--lowvram` - For GPUs with 4-8GB VRAM
- `--reserve-vram 1` - Reserve 1GB VRAM for system
- `--fp16-vae` - Use FP16 for VAE (saves VRAM)

Example:

```yaml
- COMFY_CMDLINE_EXTRA=--fast --normalvram --reserve-vram 1
```

## Installing Models

### Method 1: ComfyUI Manager (Recommended)

1. Access the WebUI at [http://localhost:8188](http://localhost:8188)
2. Click "Manager" button
3. Go to "Model Manager"
4. Search and download models directly

### Method 2: Manual Installation

Copy model files to the appropriate directory in the `basedir` volume:

```bash
# Find volume location
docker volume inspect comfyui_basedir

# Or copy directly (example for Stable Diffusion checkpoint)
docker cp model.safetensors comfyui-nvidia:/basedir/models/checkpoints/
```

Common model locations:

- Checkpoints: `basedir/models/checkpoints/`
- LoRAs: `basedir/models/loras/`
- VAE: `basedir/models/vae/`
- Embeddings: `basedir/models/embeddings/`
- Upscale models: `basedir/models/upscale_models/`

## Troubleshooting

### Container won't start

Check logs:

```bash
docker compose logs
```

### Out of VRAM errors

Add memory optimization flags:

```yaml
- COMFY_CMDLINE_EXTRA=--lowvram --fp16-vae
```

### Custom nodes with "Import Failed"

1. Go to Manager → Custom Nodes Manager
2. Filter by "Import Failed"
3. Click "Try fix" button
4. Restart ComfyUI

### Reset to clean state

To start fresh (keeps models if using BASE_DIRECTORY):

```bash
docker compose down
docker volume rm comfyui_run
docker compose up -d
```

## Updating

### Update ComfyUI

Use ComfyUI Manager in the WebUI:

1. Manager → Update ComfyUI
2. Restart container: `docker compose restart`

### Update Container Image

```bash
docker compose pull
docker compose up -d
```

## Advanced Usage

### Custom Scripts

Create `user_script.bash` in the run volume to run custom setup:

```bash
#!/bin/bash
# Install system packages
DEBIAN_FRONTEND=noninteractive sudo apt update
DEBIAN_FRONTEND=noninteractive sudo apt install -y package-name

# Install Python packages
source /comfy/mnt/venv/bin/activate
pip3 install your-package

exit 0
```

### External Access

To expose ComfyUI beyond localhost, modify the ports in `compose.yaml`:

```yaml
ports:
  - 8188:8188 # Accessible from network
```

Or keep localhost-only and use a reverse proxy (recommended):

```yaml
ports:
  - 127.0.0.1:8188:8188 # Localhost only
```

### Integration with Ollama

Uncomment and configure `extra_hosts` in `compose.yaml`:

```yaml
extra_hosts:
  - ollama.internal:YOUR_OLLAMA_IP
```

Then use `http://ollama.internal:11434` in ComfyUI nodes.

## Resources

- [ComfyUI GitHub](https://github.com/comfyanonymous/ComfyUI)
- [ComfyUI Examples](https://comfyanonymous.github.io/ComfyUI_examples/)
- [ComfyUI Docker GitHub](https://github.com/mmartial/ComfyUI-Nvidia-Docker)
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)
- [Model Downloads - Hugging Face](https://huggingface.co/)
- [Model Downloads - CivitAI](https://civitai.com/)

## Support

For issues related to:

- **ComfyUI itself**: [ComfyUI Issues](https://github.com/comfyanonymous/ComfyUI/issues)
- **Docker container**: [ComfyUI-Nvidia-Docker Issues](https://github.com/mmartial/ComfyUI-Nvidia-Docker/issues)
