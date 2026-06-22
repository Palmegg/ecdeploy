# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# ecdeploy - project guide

## What this is
ecDeploy is the home where we **develop, upgrade and maintain a Windows provisioning script** used on brand-new PCs. It is the next generation of "SpeedTune" (see `Speedtune.ps1`, the previous-generation reference — keep it for reference; the goal is to rebuild it better/faster/smarter).

Runtime flow on a new device:
1. A small **`.bat` bootstrap** runs after first sign-in, downloads ecDeploy onto the machine, and launches it.
2. The script then: **speeds up Intune app installs**, **keeps the PC awake** during provisioning (anti-sleep), and **deletes the `GRS` registry key/folder if an app install failed**.

The repo is published as a **static site (nginx on websites-lxc)** precisely so devices can fetch the bootstrap + script over HTTPS — i.e. ecDeploy is the hosting/source location (replacing the old `ast.oo.dk/SpeedTune/` hosting that `Speedtune.ps1` downloads from). "Static" here means the deploy/hosting model, not that the payload is a website.

No build/lint/test tooling — the scripts ship as-is; whatever is committed and pushed is what devices download.

### Predecessor reference (`Speedtune.ps1`)
A Danish-language WinForms GUI ("SpeedPrep") launched on new devices. It stages files in `C:\SpeedTune`, downloads assets + child scripts (`Countdown_GRS.ps1`, `GRS.ps1`, `Countdown.ps1`) from `ast.oo.dk/SpeedTune/`, offers technician actions (automated process, re-evaluate GRS, anti-sleep, open Intune logs, app list, task manager), and recursively cleans up `C:\SpeedTune` on exit. Known bug: [Speedtune.ps1:28](Speedtune.ps1#L28) calls `Write-Log` but the function is named `Write-ToLog`. Use it to understand intended behavior, not as a quality bar.

## Dev & deploy (git-flow, same model as ecDocs)
- Local working copy on DEVBOX2 (C:\Users\devbox2\projects\ecdeploy). Edit, commit, push to GitHub (Palmegg/ecdeploy, branch main). GitHub is the single source of truth.
- Deploy: 'Deploy ecdeploy' desktop shortcut (= C:\Users\devbox2\bin\deploy-ecdeploy.ps1) -> pushes, then the server runs 'git pull' in /var/www/sites/ecdeploy.
- Never edit on the server (/var/www/sites/ecdeploy on websites-lxc is a read-only puller).

## Secrets
- Real .env is gitignored (local + on the server only). Commit .env.example. Never 'git add -A' blindly.

## Type: static
