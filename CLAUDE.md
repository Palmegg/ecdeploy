# ecdeploy - project guide

## Dev & deploy (git-flow, same model as ecDocs)
- Local working copy on DEVBOX2 (C:\Users\devbox2\projects\ecdeploy). Edit, commit, push to GitHub (Palmegg/ecdeploy, branch main). GitHub is the single source of truth.
- Deploy: 'Deploy ecdeploy' desktop shortcut (= C:\Users\devbox2\bin\deploy-ecdeploy.ps1) -> pushes, then the server runs 'git pull' in /var/www/sites/ecdeploy.
- Never edit on the server (/var/www/sites/ecdeploy on websites-lxc is a read-only puller).

## Secrets
- Real .env is gitignored (local + on the server only). Commit .env.example. Never 'git add -A' blindly.

## Type: static
