#!/bin/bash
set -euo pipefail

# 1. 第一時間鎖定絕對路徑與母目錄
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0")
readonly ORIGINAL_SCRIPT_DIR=$(dirname "$ORIGINAL_SCRIPT_PATH")

# 2. 擷取環境變數 (嚴禁使用 ml 指令)
readonly ACTIVE_MODULES="${LOADEDMODULES:-}"

# 3. 混合哈希計算 (腳本內容 + 已載入模組)
SCRIPT_HASH=$( (cat "$ORIGINAL_SCRIPT_PATH"; echo "$ACTIVE_MODULES") | sha256sum | awk '{print $1}' )

# 4. 啟動日誌攔截
readonly LOG_FILE="${ORIGINAL_SCRIPT_DIR}/${SCRIPT_HASH}.log.$(date +%Y%m%d_%H%M%S)"
exec > >(tee -a "$LOG_FILE") 2>&1

readonly MFC_VERSION="v5.7.0"
readonly MFC_REPO="https://github.com/MFlowCode/MFC.git"
readonly BUILD_CORES="8"

echo "[INFO] Required dependencies: gcc, mpi (mpifort)"
if ! command -v mpifort &> /dev/null || ! command -v gcc &> /dev/null; then
    echo "[FATAL] Missing required compilers. Load environment modules before execution."
    exit 1
fi

BASE_SOFT=""
BASE_MOD=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --software_root) BASE_SOFT="$2"; shift ;;
        --module_root) BASE_MOD="$2"; shift ;;
        *) echo "[FATAL] Unsupported argument: $1" ; exit 1 ;;
    esac
    shift
done

if [ -z "$BASE_SOFT" ] || [ -z "$BASE_MOD" ]; then
    echo "[FATAL] Missing arguments."
    echo "Usage: $0 --software_root /path/to/software --module_root /path/to/module"
    exit 1
fi

readonly SOFTWARE_DIR=$(readlink -m "${BASE_SOFT}/mfc/${MFC_VERSION}/${SCRIPT_HASH}")
# 注意：副檔名已強制改為 Lmod 原生 .lua 格式
readonly MODULE_FILE=$(readlink -m "${BASE_MOD}/mfc/${MFC_VERSION}/${SCRIPT_HASH}.lua")

echo "[INFO] Initializing target directories..."
rm -rf "$SOFTWARE_DIR"
mkdir -p "$(dirname "$SOFTWARE_DIR")"

echo "[INFO] Cloning and building MFC..."
git clone --depth 1 --branch "$MFC_VERSION" "$MFC_REPO" "$SOFTWARE_DIR"
cd "$SOFTWARE_DIR"
bash ./mfc.sh build -j"${BUILD_CORES}"

echo "[INFO] Formatting Lua dependencies..."
LUA_DEPENDS=""
if [ -n "$ACTIVE_MODULES" ]; then
    # 將 gcc/11.5:hpcx 轉換為 Lua 陣列字串 "gcc/11.5", "hpcx"
    FORMATTED_MODS=$(echo "$ACTIVE_MODULES" | sed 's/:/", "/g')
    LUA_DEPENDS="depends_on(\"${FORMATTED_MODS}\")"
fi

echo "[INFO] Generating Lua modulefile..."
mkdir -p "$(dirname "$MODULE_FILE")"
cat <<EOF > "$MODULE_FILE"
help([[MFC auto-generated deployment module. Hash: ${SCRIPT_HASH}]])
whatis("Name: MFC")
whatis("Version: ${MFC_VERSION}")
whatis("Compile Hash: ${SCRIPT_HASH}")

${LUA_DEPENDS}

local mfc_root = "${SOFTWARE_DIR}"
setenv("MFC_ROOT", mfc_root)
prepend_path("PATH", mfc_root)
set_alias("mfc", "cd " .. mfc_root .. " && ./mfc.sh")
EOF

echo "[INFO] Deployment completed."
echo "[INFO] Archiving script and execution log into data workspace..."
cp "$ORIGINAL_SCRIPT_PATH" "${SOFTWARE_DIR}/script_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${SOFTWARE_DIR}/"

echo "[INFO] Software path: $SOFTWARE_DIR"
echo "[INFO] Module path: $MODULE_FILE"

printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))

echo "[INFO] Renaming script to match hash..."
mv "$ORIGINAL_SCRIPT_PATH" "${ORIGINAL_SCRIPT_DIR}/${SCRIPT_HASH}.sh"
