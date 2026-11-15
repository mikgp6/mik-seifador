#!/bin/sh
# Mik Seifador - publicar uma atualização para todos (box Linux / Mac)
# Uso: publicar_atualizacao.sh <pasta MultitrackAoVivo> <keymap> "notas" [pasta do clone]
# Precisa: git + python3 e login no GitHub (gh auth login / credencial do git).
set -e
KIT="$1"; KEYMAP="$2"; NOTAS="$3"; REPO="${4:-$HOME/mik-seifador-publicar}"
AQUI="$(cd "$(dirname "$0")" && pwd)"
[ -d "$REPO/.git" ] || git clone https://github.com/mikgp6/mik-seifador.git "$REPO"
git -C "$REPO" pull --ff-only origin main 2>/dev/null || true
python3 "$AQUI/montar_publicacao.py" --kit "$KIT" --keymap "$KEYMAP" --repo "$REPO" --notas "$NOTAS" >/dev/null
BUILD=$(python3 -c "import json;print(json.load(open('$REPO/manifest.json'))['build'])")
git -C "$REPO" add -A kit
if git -C "$REPO" diff --cached --quiet; then
  git -C "$REPO" checkout -- manifest.json 2>/dev/null || true
  echo "Nada mudou no kit."; exit 0
fi
git -C "$REPO" commit -q -m "kit: build $BUILD"
REF=$(git -C "$REPO" rev-parse HEAD)
python3 "$AQUI/montar_publicacao.py" --kit "$KIT" --repo "$REPO" --build "$BUILD" --ref "$REF" --notas "$NOTAS" --so-manifest
git -C "$REPO" add manifest.json
git -C "$REPO" commit -q -m "build $BUILD: $NOTAS"
git -C "$REPO" push origin main
echo "Publicado: build $BUILD (ref $REF)"
