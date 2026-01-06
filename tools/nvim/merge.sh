#!/usr/bin/env bash
# tools/nvim/merge.sh
# Generates ~/.config/nvim with merged config from all layers
#
# Strategy: Later layers override earlier ones at the file level.
# Files in lua/config/ and lua/plugins/ are symlinked from the highest-priority
# layer that contains them. Additional plugin directories (like plugins-work/)
# are also included.

set -eo pipefail

IFS=':' read -ra layer_names <<< "$LAYERS"
IFS=':' read -ra layer_paths <<< "$LAYER_PATHS"

echo "[INFO] Generating Neovim config at: $TARGET"
echo "[INFO] Layers: $LAYERS"

# Clean and create target directory structure
rm -rf "$TARGET"
mkdir -p "$TARGET/lua"

# Associative arrays to track files (later layers override earlier ones)
declare -A config_files    # filename -> source_path
declare -A plugin_files    # filename -> source_path
declare -A plugin_dirs     # dirname -> source_path
declare -A root_files      # filename -> source_path

# Process layers in order
for i in "${!layer_paths[@]}"; do
    layer_path="${layer_paths[$i]}"
    layer_name="${layer_names[$i]}"
    echo "[INFO] Processing layer: $layer_name ($layer_path)"

    # Process root files (*.lua, *.json)
    shopt -s nullglob
    for file in "$layer_path"/*.lua "$layer_path"/*.json; do
        [[ -f "$file" ]] || continue
        filename=$(basename "$file")
        root_files["$filename"]="$file"
    done
    shopt -u nullglob

    # Process lua/config/*.lua
    config_dir="$layer_path/lua/config"
    if [[ -d "$config_dir" ]]; then
        for file in "$config_dir"/*.lua; do
            [[ -f "$file" ]] || continue
            filename=$(basename "$file")
            config_files["$filename"]="$file"
        done
    fi

    # Process lua/plugins/*.lua
    plugins_dir="$layer_path/lua/plugins"
    if [[ -d "$plugins_dir" ]]; then
        for file in "$plugins_dir"/*.lua; do
            [[ -f "$file" ]] || continue
            filename=$(basename "$file")
            plugin_files["$filename"]="$file"
        done
    fi

    # Find additional plugin directories (plugins-work, plugins-stripe, etc.)
    lua_dir="$layer_path/lua"
    if [[ -d "$lua_dir" ]]; then
        for subdir in "$lua_dir"/plugins-*; do
            [[ -d "$subdir" ]] || continue
            dirname=$(basename "$subdir")
            plugin_dirs["$dirname"]="$subdir"
        done
    fi
done

# Create lua/config directory and symlink files
if [[ ${#config_files[@]} -gt 0 ]]; then
    mkdir -p "$TARGET/lua/config"
    echo "[INFO] Creating config symlinks..."
    for filename in "${!config_files[@]}"; do
        source_path="${config_files[$filename]}"
        ln -sf "$source_path" "$TARGET/lua/config/$filename"
        echo "       $filename"
    done
fi

# Create lua/plugins directory and symlink files
if [[ ${#plugin_files[@]} -gt 0 ]]; then
    mkdir -p "$TARGET/lua/plugins"
    echo "[INFO] Creating plugin symlinks..."
    for filename in "${!plugin_files[@]}"; do
        source_path="${plugin_files[$filename]}"
        ln -sf "$source_path" "$TARGET/lua/plugins/$filename"
        echo "       $filename"
    done
fi

# Symlink additional plugin directories
if [[ ${#plugin_dirs[@]} -gt 0 ]]; then
    echo "[INFO] Symlinking additional plugin directories..."
    for dirname in "${!plugin_dirs[@]}"; do
        source_path="${plugin_dirs[$dirname]}"
        ln -sf "$source_path" "$TARGET/lua/$dirname"
        echo "       $dirname/"
    done
fi

# Symlink root files
if [[ ${#root_files[@]} -gt 0 ]]; then
    echo "[INFO] Creating root file symlinks..."
    for filename in "${!root_files[@]}"; do
        source_path="${root_files[$filename]}"
        ln -sf "$source_path" "$TARGET/$filename"
        echo "       $filename"
    done
fi

# Generate layer info file for runtime detection
mkdir -p "$TARGET/lua/lib"
cat > "$TARGET/lua/lib/layers.lua" << EOF
-- Auto-generated layer information
-- Layers: $LAYERS
return {
    names = {"${layer_names[*]// /\", \"}"},
    paths = {"${layer_paths[*]// /\", \"}"},
}
EOF
echo "[INFO] Generated lua/lib/layers.lua"

echo "[OK] Neovim config generated at: $TARGET"
