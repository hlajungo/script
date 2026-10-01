#!/bin/bash
#SBATCH --job-name=Run
#SBATCH --partition=dev
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
set -euo pipefail
# ==========================================
# [請勿修改：參數解析、絕對路徑轉換與日誌攔截]
# ==========================================
while [[ "$#" -gt 0 ]]; do case $1 in --runtime_script) RUNTIME_SCRIPT=$(readlink -m "$2"); shift 2 ;; --compile_hash) COMPILE_HASH="$2"; shift 2 ;; --data_root) DATA_ROOT=$(readlink -m "$2"); shift 2 ;; *) echo "[FATAL] Arg: $1"; exit 1 ;; esac; done
readonly LOG_POOL_DIR="${HOME}/.log"; mkdir -p "$LOG_POOL_DIR"
RESOURCE_SCRIPT_PATH=$(readlink -m "$0"); RESOURCE_HASH=$(sha256sum "$RESOURCE_SCRIPT_PATH" | awk '{print $1}')
RESOURCE_LOG="${LOG_POOL_DIR}/runtimeresource_${SLURM_JOB_ID}.log"
RUNTIME_HASH=$(sha256sum "$RUNTIME_SCRIPT" | awk '{print $1}')
exec > >(tee -a "$RESOURCE_LOG") 2>&1
echo "COMPILE_HASH=${COMPILE_HASH}"
echo "RUNTIME_HASH=${RUNTIME_HASH}"
echo "RESOURCE_HASH=${RESOURCE_HASH}"
echo "RUNTIME_SCRIPT=${RUNTIME_SCRIPT}"
echo "RESOURCE_SCRIPT_PATH=${RESOURCE_SCRIPT_PATH}"
echo "DATA_ROOT=${DATA_ROOT}"
echo "RESOURCE_LOG=${RESOURCE_LOG}"
echo "[INFO] Task started. Live log at: $RESOURCE_LOG (Live log will be deleted if job successed.)"
# ==========================================
# [可修改區塊：Lmod 模組載入]
# ==========================================
ml use /home/hlajungo1/share/software/hpcx-v2.50-gcc-doca_ofed-ubuntu22.04-cuda12-x86_64/modulefiles
ml use /home/hlajungo1/share/module
ml load "mfc/v5.7.0/${COMPILE_HASH}"
# ==========================================
# [請勿修改：執行與自毀]
# ==========================================
bash "$RUNTIME_SCRIPT" --compile_hash "$COMPILE_HASH" --data_root "$DATA_ROOT" --resource_hash "$RESOURCE_HASH" --resource_script "$RESOURCE_SCRIPT_PATH" --resource_log "$RESOURCE_LOG"
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
rm -f "$RESOURCE_LOG"
echo "[INFO] Exit successfully."
