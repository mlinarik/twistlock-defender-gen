# Prisma Cloud Defender - Interactive Installer

This repo contains small interactive installer scripts to help install a single-container Prisma Cloud Defender using Docker.

Files added:
- `scripts/install-defender.sh` — Bash script for Linux/macOS (interactive, prompts for options and can create a systemd service)
- `scripts/install-defender.ps1` — PowerShell script for Windows (interactive, prompts for options)

Quick start

Linux / macOS (bash):

```bash
chmod +x scripts/install-defender.sh
./scripts/install-defender.sh
```

Windows (PowerShell):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\install-defender.ps1
```

Notes and safety
- These scripts do not automatically register Defender with Prisma Cloud — they only run the container. Follow your Prisma Cloud Console/Docs for registration steps and correct image URIs.
- You must provide the correct container image URI (consult your Prisma Cloud documentation or administrator). Example: `registry.prismacloud.io/defender:latest` (this is only an example; confirm the exact registry and tag used by your deployment).
- The scripts will check for Docker and prompt for registry credentials if necessary.
- On Linux, the Bash script can optionally create a systemd unit that starts the container at boot. The container itself is run with Docker restart policy, which is sufficient for most deployments.

Customization
- If your deployment requires specific kernel capabilities or extra mounts (e.g., `/var/run/docker.sock`), add them when prompted.

If you want me to wire in specific defaults from your Prisma Cloud deployment (image URI, expected environment variables, recommended mounts), tell me what values to use and I can update the scripts to prefill those options.
