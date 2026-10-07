#!/bin/bash
#SBATCH --job-name=Compile
#SBATCH --partition=dev
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
set -euo pipefail
# ==========================================
# [請勿修改：路徑哈希與全域日誌攔截]
# ==========================================
readonly LOG_POOL_DIR="${HOME}/.log"; mkdir -p "$LOG_POOL_DIR"
RESOURCE_SCRIPT_PATH=$(readlink -m "$0"); RESOURCE_HASH=$(sha256sum "$RESOURCE_SCRIPT_PATH" | awk '{print $1}')
RESOURCE_LOG="${LOG_POOL_DIR}/compileresource_${SLURM_JOB_ID}.log"; exec > >(tee -a "$RESOURCE_LOG") 2>&1
echo "[INFO] Task started. Live log monitoring strictly at: $RESOURCE_LOG"
# ==========================================
# [可修改區塊：機器專屬環境耦合]
# ==========================================
ml use /home/hlajungo1/share/software/hpcx-v2.50-gcc-doca_ofed-ubuntu22.04-cuda12-x86_64/modulefiles
ml gcc/11.5 cuda/12.6 hpcx

# ==========================================
# [請勿修改：參數解析、執行與自毀]
# ==========================================
while [[ "$#" -gt 0 ]]; do case $1 in --compiletime_script) COMPILETIME_SCRIPT="$2"; shift 2 ;; --software_root) SOFTWARE_ROOT="$2"; shift 2 ;; --module_root) MODULE_ROOT="$2"; shift 2 ;; *) echo "[FATAL] Unknown arg: $1"; exit 1 ;; esac; done
bash "$COMPILETIME_SCRIPT" --software_root "$SOFTWARE_ROOT" --module_root "$MODULE_ROOT" --resource_hash "$RESOURCE_HASH" --resource_script "$RESOURCE_SCRIPT_PATH" --resource_log "$RESOURCE_LOG"
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
rm -f "$RESOURCE_LOG"
echo "[INFO] Exit successfully."
