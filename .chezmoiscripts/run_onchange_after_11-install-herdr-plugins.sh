#!/usr/bin/env bash
set -euo pipefail

# Registration is user-wide and works without starting or restarting a server.
# Use an offline maintenance session so an old default server cannot reject
# registration after a binary upgrade. This does not start a session server.
install_plugin() {
  local id="$1" source="$2" ref="$3"
  local installed
  installed="$(herdr --session dotfiles-setup plugin list --json)"
  if ! jq -e --arg id "$id" --arg ref "$ref" \
    '.result.plugins | any(.plugin_id == $id and .source.requested_ref == $ref)' \
    <<< "$installed" >/dev/null; then
    # File viewer has no Linux ARM64 release asset. Keep its build toolchain
    # under mise, matching the rest of the dotfiles runtime management.
    if [ "$id" = herdr-file-viewer ] && [ "$(uname -s)" = Linux ] && \
       [ "$(uname -m)" = aarch64 ]; then
      mise install rust@1.96.0
      mise exec rust@1.96.0 -- herdr --session dotfiles-setup plugin install "$source" --ref "$ref" --yes
    else
      herdr --session dotfiles-setup plugin install "$source" --ref "$ref" --yes
    fi
  fi
}

# Pin published releases: upstream main can reference assets not released yet.
install_plugin herdr-file-viewer smarzban/herdr-file-viewer v1.17.0
install_plugin persiyanov.reviewr persiyanov/herdr-reviewr v0.46.0
