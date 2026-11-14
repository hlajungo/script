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
echo "================================================================================"
echo "[INFO] Software Target : ${SOFTWARE_DIR}"
echo "[INFO] Module Target   : ${MODULE_FILE}"
echo "[INFO] Script Hash     : ${SCRIPT_HASH}"
echo "[INFO] Resource Hash   : ${RES_HASH}"
echo "================================================================================"
if [[ -f "$MODULE_FILE" && -e "$SOFTWARE_DIR" && $FORCE_RECOMPILE -eq 0 ]]; then
echo "[WARN] Target build already exists at: ${SOFTWARE_DIR}"
echo "[WARN] Modulefile exists at: ${MODULE_FILE}"
echo "[WARN] Skipping compilation. Use --recompile to force rebuild."
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
rm -f "$LOG_FILE";echo "[INFO] Compiletime Exit (Cached).";exit 0
fi
mkdir -p "$BASE_SOFT" "$(dirname "$MODULE_FILE")"
############################################
if ! command -v nvfortran &> /dev/null; then
    echo "[FATAL] nvfortran missing. Ensure nvhpc-hpcx-cuda13 is loaded."
    exit 1
fi
if ! command -v mpirun &> /dev/null; then
    echo "[FATAL] MPI missing."
    exit 1
fi

readonly MFC_COMMIT="4e96e0d"
readonly MFC_REPO="https://github.com/MFlowCode/MFC.git"
readonly BUILD_CORES="32"

HASH_LEN=12
REAL_SOFT_DIR=$(readlink -m "${BASE_SOFT}/${SCRIPT_HASH:0:${HASH_LEN}}")
while [[ -e "$REAL_SOFT_DIR" && "$(readlink -f "$SOFTWARE_DIR" 2>/dev/null)" != "$REAL_SOFT_DIR" ]]; do
    HASH_LEN=$((HASH_LEN + 1))
    REAL_SOFT_DIR=$(readlink -m "${BASE_SOFT}/${SCRIPT_HASH:0:${HASH_LEN}}")
done

echo "[INFO] Preparing physical short directory: ${REAL_SOFT_DIR}..."
rm -rf "$REAL_SOFT_DIR" "$SOFTWARE_DIR"
mkdir -p "$REAL_SOFT_DIR"

echo "[INFO] Cloning MFC and checking out official SC26 commit (${MFC_COMMIT})..."
git clone "$MFC_REPO" "$REAL_SOFT_DIR"
cd "$REAL_SOFT_DIR"
git checkout "$MFC_COMMIT"

echo "[INFO] Building MFC (Unoptimized GPU OpenACC Double-Precision Baseline)..."
bash ./mfc.sh build --gpu acc -j"${BUILD_CORES}"

echo "[INFO] Linking 64-char hash symlink -> physical short directory..."
ln -sfn "$REAL_SOFT_DIR" "$SOFTWARE_DIR"

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

cat <<EOF_LUA > "$MODULE_FILE"
-- MFC GPU OpenACC Baseline Modulefile (SC26 commit 4e96e0d)
$(echo -e "${LUA_DEPENDS}")

local mfc_root = "${REAL_SOFT_DIR}"
setenv("MFC_ROOT", mfc_root)
prepend_path("PATH", mfc_root)
set_alias("mfc", "cd " .. mfc_root .. " && ./mfc.sh")
EOF_LUA
############### [Do not modify] ###############
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60));sync;sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${SOFTWARE_DIR}/compiletime_${SCRIPT_HASH}.log"
echo "=== BEGIN ENV DUMP ===";export -p;echo "=== END ENV DUMP ==="
echo "[INFO] Compiletime Exit."
############################################
