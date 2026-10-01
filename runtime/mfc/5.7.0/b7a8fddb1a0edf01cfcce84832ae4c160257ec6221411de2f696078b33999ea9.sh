#!/bin/bash
set -euo pipefail
# ==========================================
# [請勿修改：哈希綁定、日誌與階層式隔離區建立]
# ==========================================
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0"); readonly SCRIPT_HASH=$(sha256sum "$ORIGINAL_SCRIPT_PATH" | awk '{print $1}')
readonly LOG_POOL_DIR="${HOME}/.log"; mkdir -p "$LOG_POOL_DIR"
readonly LOG_FILE="${LOG_POOL_DIR}/runtime_${SCRIPT_HASH}_${SLURM_JOB_ID}.log"; exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== BEGIN ENV DUMP ==="; export -p; echo "=== END ENV DUMP ==="
while [[ "$#" -gt 0 ]]; do case $1 in --compile_hash) COMPILE_HASH="$2"; shift 2 ;; --data_root) BASE_DATA="$2"; shift 2 ;; --resource_hash) RES_HASH="$2"; shift 2 ;; --resource_script) RES_SCRIPT="$2"; shift 2 ;; --resource_log) RES_LOG="$2"; shift 2 ;; *) exit 1 ;; esac; done
readonly CONFIG_POOL_DIR=$(readlink -m "${BASE_DATA}/mfc/v5.7.0/${COMPILE_HASH}_${SCRIPT_HASH}_${RES_HASH}")
readonly DATA_DIR="${CONFIG_POOL_DIR}/${SLURM_JOB_ID:-local_$(date +%s)}"; mkdir -p "$DATA_DIR"
# ==========================================
# [可修改區塊：實驗運算邏輯]
# ==========================================
echo "[INFO] Executing simulation logic at: $DATA_DIR"

readonly TARGET_CASE="1D_sodshocktube"
readonly MPI_RESOURCES=""

echo "[INFO] Verifying execution environment..."
if ! command -v mpirun &> /dev/null; then echo "[FATAL] Missing mpirun. Environment not ready."; exit 1; fi
if [ -z "${MFC_ROOT:-}" ]; then echo "[FATAL] MFC_ROOT undefined. Software environment not loaded."; exit 1; fi

echo "[INFO] Copying configuration to isolated workspace..."
cp "${MFC_ROOT}/examples/${TARGET_CASE}/case.py" "${DATA_DIR}/"

echo "[INFO] Navigating to MFC root and initiating simulation..."
cd "$MFC_ROOT"
bash ./mfc.sh run "${DATA_DIR}/case.py" --binary srun

# ==========================================
# [請勿修改：終極雙重歸檔與計時]
# ==========================================
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60)); sync; sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${DATA_DIR}/runtime_${SCRIPT_HASH}.sh"; cp "$LOG_FILE" "${DATA_DIR}/runtime_${SCRIPT_HASH}.log"; rm -f "$LOG_FILE"
[[ -f "$RES_SCRIPT" ]] && cp "$RES_SCRIPT" "${DATA_DIR}/runtimeresource_${RES_HASH}.sbatch"
[[ -f "$RES_LOG" ]] && cp "$RES_LOG" "${DATA_DIR}/runtimeresource_${RES_HASH}.log"
echo "[INFO] Exit successfully."
