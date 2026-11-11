#!/bin/bash
set -euo pipefail
############### [Do not modify] ###############
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0");readonly ACTIVE_MODULES="${LOADEDMODULES:-}"
readonly SCRIPT_HASH=$( (cat "$ORIGINAL_SCRIPT_PATH"; echo "$ACTIVE_MODULES") | sha256sum | awk '{print $1}' )
echo "[EXPORT_HASH] ${SCRIPT_HASH}"
BASE_SOFT="";BASE_MOD="";RES_HASH="none";FORCE_RECOMPILE=0
while [[ "$#" -gt 0 ]]; do case $1 in --software_root) BASE_SOFT="$2";shift 2;;--module_root) BASE_MOD="$2";shift 2;;--resource_hash) RES_HASH="$2";shift 2;;--recompile) FORCE_RECOMPILE=1;shift 1;;*) echo "[FATAL] Unknown argument: $1";exit 1;;esac;done
readonly SOFTWARE_DIR=$(readlink -m "${BASE_SOFT}/${SCRIPT_HASH}");readonly MODULE_FILE=$(readlink -m "${BASE_MOD}/${SCRIPT_HASH}.lua")
readonly LOG_POOL_DIR="${HOME}/.log";mkdir -p "$LOG_POOL_DIR"
readonly LOG_FILE="${LOG_POOL_DIR}/sbatch_${SLURM_JOB_ID:-manual}_compiletime_${SCRIPT_HASH:0:8}.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "================================================================================"
echo "[INFO] Software Target : ${SOFTWARE_DIR}"
echo "[INFO] Module Target   : ${MODULE_FILE}"
echo "[INFO] Script Hash     : ${SCRIPT_HASH}"
echo "[INFO] Resource Hash   : ${RES_HASH}"
echo "================================================================================"
if [[ -f "$MODULE_FILE" && -d "$SOFTWARE_DIR" && $FORCE_RECOMPILE -eq 0 ]]; then
echo "[WARN] Target build already exists at: ${SOFTWARE_DIR}"
echo "[WARN] Modulefile exists at: ${MODULE_FILE}"
echo "[WARN] Skipping compilation. Use --recompile to force rebuild."
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
rm -f "$LOG_FILE";echo "[INFO] Compiletime Exit (Cached).";exit 0
fi
mkdir -p "$BASE_SOFT" "$(dirname "$MODULE_FILE")"
############################################
if ! command -v gcc &> /dev/null && ! command -v nvfortran &> /dev/null; then 
    echo "[FATAL] Compilers missing."; exit 1
fi
if ! command -v mpifort &> /dev/null && ! command -v mpirun &> /dev/null; then 
    echo "[FATAL] MPI missing."; exit 1
fi

readonly MFC_VERSION="v5.7.0"
readonly MFC_REPO="https://github.com/MFlowCode/MFC.git"
readonly BUILD_CORES="12"

readonly TMP_BUILD_DIR="${BASE_SOFT}/bld_${SLURM_JOB_ID:-$$}"
echo "[INFO] Preparing temporary short build directory: ${TMP_BUILD_DIR}..."
rm -rf "$TMP_BUILD_DIR" "$SOFTWARE_DIR"
mkdir -p "$TMP_BUILD_DIR"

echo "[INFO] Cloning and building MFC [CPU Single Precision]..."
git clone --depth 1 --branch "$MFC_VERSION" "$MFC_REPO" "$TMP_BUILD_DIR"
cd "$TMP_BUILD_DIR"
bash ./mfc.sh build -j"${BUILD_CORES}" --single

echo "[INFO] Moving built software to target hash directory: ${SOFTWARE_DIR}..."
cd "$HOME"
mv "$TMP_BUILD_DIR" "$SOFTWARE_DIR"

echo "[INFO] Generate Lua modulefile at $MODULE_FILE"
LUA_DEPENDS=""
if [[ -n "$ACTIVE_MODULES" ]]; then
    IFS=':' read -r -a MOD_ARRAY <<< "$ACTIVE_MODULES"
    FORMATTED_MODS=""
    for MOD in "${MOD_ARRAY[@]}"; do
        [[ -z "$MOD" ]] && continue
        if [[ -z "$FORMATTED_MODS" ]]; then
            FORMATTED_MODS="\"${MOD}\""
        else
            FORMATTED_MODS="${FORMATTED_MODS}, \"${MOD}\""
        fi
    done
    if [[ -n "$FORMATTED_MODS" ]]; then
        LUA_DEPENDS="if is_loaded == nil or not is_loaded() then\n    depends_on(${FORMATTED_MODS})\nend"
    fi
fi

cat <<EOF > "$MODULE_FILE"
-- MFC Modulefile (Auto-generated)
$(echo -e "${LUA_DEPENDS}")

local mfc_root = "${SOFTWARE_DIR}"
setenv("MFC_ROOT", mfc_root)
prepend_path("PATH", mfc_root)
set_alias("mfc", "cd " .. mfc_root .. " && ./mfc.sh")
EOF
############### [Do not modify] ###############
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60));sync;sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.log"
echo "=== BEGIN ENV DUMP ===";export -p;echo "=== END ENV DUMP ==="
echo "[INFO] Compiletime Exit."
############################################
