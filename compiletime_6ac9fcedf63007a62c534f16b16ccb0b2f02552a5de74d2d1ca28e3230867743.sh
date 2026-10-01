#!/bin/bash
set -euo pipefail
# ==========================================
# [請勿修改：哈希綁定、日誌攔截與參數解析]
# ==========================================
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0"); readonly ACTIVE_MODULES="${LOADEDMODULES:-}"
readonly SCRIPT_HASH=$( (cat "$ORIGINAL_SCRIPT_PATH"; echo "$ACTIVE_MODULES") | sha256sum | awk '{print $1}' )
readonly LOG_POOL_DIR="${HOME}/.log"; mkdir -p "$LOG_POOL_DIR"
readonly LOG_FILE="${LOG_POOL_DIR}/compiletime_${SCRIPT_HASH}_${SLURM_JOB_ID}.log"; exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== BEGIN ENV DUMP ==="; export -p; echo "=== END ENV DUMP ==="
while [[ "$#" -gt 0 ]]; do case $1 in --software_root) BASE_SOFT="$2"; shift 2 ;; --module_root) BASE_MOD="$2"; shift 2 ;; --resource_hash) RES_HASH="$2"; shift 2 ;; --resource_script) RES_SCRIPT="$2"; shift 2 ;; --resource_log) RES_LOG="$2"; shift 2 ;; *) exit 1 ;; esac; done
readonly SOFTWARE_DIR=$(readlink -m "${BASE_SOFT}/mfc/v5.7.0/${SCRIPT_HASH}"); readonly MODULE_FILE=$(readlink -m "${BASE_MOD}/mfc/v5.7.0/${SCRIPT_HASH}.lua")
mkdir -p "$SOFTWARE_DIR" "$(dirname "$MODULE_FILE")"
# ==========================================
# [可修改區塊：軟體編譯邏輯與 Lmod 生成]
# ==========================================
echo "[INFO] Executing compilation logic..."
readonly MFC_VERSION="v5.7.0"
readonly MFC_REPO="https://github.com/MFlowCode/MFC.git"
readonly BUILD_CORES="8"

if ! command -v mpifort &> /dev/null || ! command -v gcc &> /dev/null; then echo "[FATAL] Compilers missing. Load environment modules before execution."; exit 1; fi

echo "[INFO] Cloning and building MFC..."
rm -rf "$SOFTWARE_DIR"; mkdir -p "$SOFTWARE_DIR"
git clone --depth 1 --branch "$MFC_VERSION" "$MFC_REPO" "$SOFTWARE_DIR"
cd "$SOFTWARE_DIR" && bash ./mfc.sh build -j"${BUILD_CORES}"

echo "[INFO] Formatting and generating Lua modulefile..."
LUA_DEPENDS=""
[[ -n "$ACTIVE_MODULES" ]] && LUA_DEPENDS="depends_on(\"$(echo "$ACTIVE_MODULES" | sed 's/:/", "/g')\")"

cat <<EOF > "$MODULE_FILE"
${LUA_DEPENDS}
local mfc_root = "${SOFTWARE_DIR}"
setenv("MFC_ROOT", mfc_root)
prepend_path("PATH", mfc_root)
set_alias("mfc", "cd " .. mfc_root .. " && ./mfc.sh")
EOF

# ==========================================
# [底層機制：終極雙重歸檔與計時 (請勿修改)]
# ==========================================
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60)); sync; sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.sh"; cp "$LOG_FILE" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.log"; rm -f "$LOG_FILE"
[[ -f "$RES_SCRIPT" ]] && cp "$RES_SCRIPT" "${SOFTWARE_DIR}/compileresource_${RES_HASH}.sbatch"
[[ -f "$RES_LOG" ]] && cp "$RES_LOG" "${SOFTWARE_DIR}/compileresource_${RES_HASH}.log"
echo "[INFO] Artifacts safely pooled."
