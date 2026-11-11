#!/bin/bash
set -euo pipefail
############### [Do not modify] ###############
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0");readonly ACTIVE_MODULES="${LOADEDMODULES:-}"
readonly SCRIPT_HASH=$( (cat "$ORIGINAL_SCRIPT_PATH";echo "$ACTIVE_MODULES")|sha256sum|awk '{print $1}' )
echo "[EXPORT_HASH] ${SCRIPT_HASH}"
BASE_SOFT="";BASE_MOD="";RES_HASH="none";FORCE_RECOMPILE=0
while [[ "$#" -gt 0 ]];do case $1 in --software_root) BASE_SOFT="$2";shift 2;;--module_root) BASE_MOD="$2";shift 2;;--resource_hash) RES_HASH="$2";shift 2;;--recompile) FORCE_RECOMPILE=1;shift 1;;*) echo "[FATAL] Unknown argument: $1";exit 1;;esac;done
readonly SOFTWARE_DIR=$(readlink -m "${BASE_SOFT}/${SCRIPT_HASH}");readonly MODULE_FILE=$(readlink -m "${BASE_MOD}/${SCRIPT_HASH}.lua")
readonly LOG_POOL_DIR="${HOME}/.log";mkdir -p "$LOG_POOL_DIR"
readonly LOG_FILE="${LOG_POOL_DIR}/sbatch_${SLURM_JOB_ID:-manual}_compiletime_${SCRIPT_HASH:0:8}.log"
exec > >(tee -a "$LOG_FILE") 2>&1
if [[ -f "$MODULE_FILE"&&-d "$SOFTWARE_DIR"&&$FORCE_RECOMPILE -eq 0 ]];then
echo "[WARN] Target build already exists at: ${SOFTWARE_DIR}"
echo "[WARN] Modulefile exists at: ${MODULE_FILE}"
echo "[WARN] Skipping compilation. Use --recompile to force rebuild."
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
rm -f "$LOG_FILE";exit 0
fi
mkdir -p "$SOFTWARE_DIR" "$(dirname "$MODULE_FILE")"
############################################
if ! command -v nvfortran &> /dev/null; then echo "[FATAL] nvfortran compiler missing. NVHPC environment required."; exit 1; fi
readonly MFC_VERSION="v5.7.0"
readonly MFC_REPO="https://github.com/MFlowCode/MFC.git"
echo "[INFO] [Tag: CPU_Double_Default] Cloning and building MFC with args: -j 12..."
rm -rf "$SOFTWARE_DIR";mkdir -p "$SOFTWARE_DIR"
git clone --depth 1 --branch "$MFC_VERSION" "$MFC_REPO" "$SOFTWARE_DIR"
cd "$SOFTWARE_DIR"
bash ./mfc.sh build -j 12
echo "[INFO] Generating Lua modulefile at $MODULE_FILE"
LUA_DEPENDS=""
[[ -n "$ACTIVE_MODULES" ]] && LUA_DEPENDS="depends_on(\"$(echo "$ACTIVE_MODULES" | sed 's/:/", "/g')\")"
cat <<EOF > "$MODULE_FILE"
${LUA_DEPENDS}
local mfc_root = "${SOFTWARE_DIR}"
setenv("MFC_ROOT", mfc_root)
prepend_path("PATH", mfc_root)
set_alias("mfc", "cd " .. mfc_root .. " && ./mfc.sh")
EOF
############### [Do not modify] ###############
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60));sync;sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.log"
echo "[INFO] Compiletime Exit."
############################################
