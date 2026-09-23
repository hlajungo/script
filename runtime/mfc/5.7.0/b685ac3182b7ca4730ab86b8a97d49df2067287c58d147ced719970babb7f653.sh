#!/bin/bash
set -euo pipefail

# 1. 絕對路徑鎖定
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0")
readonly ORIGINAL_SCRIPT_DIR=$(dirname "$ORIGINAL_SCRIPT_PATH")

# 2. 純粹邏輯綁定：只計算腳本本身內容，徹底拔除環境干擾！
SCRIPT_HASH=$(sha256sum "$ORIGINAL_SCRIPT_PATH" | awk '{print $1}')

# 3. 綁定哈希的日誌攔截
readonly LOG_FILE="${ORIGINAL_SCRIPT_DIR}/${SCRIPT_HASH}.log.$(date +%Y%m%d_%H%M%S)"
exec > >(tee -a "$LOG_FILE") 2>&1

# ==========================================
# 實驗邏輯區塊 (這些改變會產生新的 Runtime Hash)
# ==========================================
readonly MFC_VERSION="5.7.0"
readonly TARGET_CASE="1D_sodshocktube"
readonly MPI_RESOURCES="" # 未來可在此擴充如 -n 16 等 MPI 參數

# 4. 嚴格參數解析
BASE_DATA=""
COMPILE_HASH=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --data_root) BASE_DATA="$2"; shift ;;
        --compile_hash) COMPILE_HASH="$2"; shift ;;
        *) echo "[FATAL] Unsupported argument: $1" ; exit 1 ;;
    esac
    shift
done

if [ -z "$BASE_DATA" ] || [ -z "$COMPILE_HASH" ]; then
    echo "[FATAL] Missing required arguments."
    echo "Usage: $0 --data_root /path/to/data --compile_hash <hash_string>"
    exit 1
fi

# 5. 極簡環境探測 (只確認是否存在，不管內容)
echo "[INFO] Verifying execution environment..."
if ! command -v mpirun &> /dev/null; then
    echo "[FATAL] Missing mpirun. Environment not ready."
    exit 1
fi

if [ -z "${MFC_ROOT:-}" ]; then
    echo "[FATAL] MFC_ROOT undefined. Software environment not loaded."
    exit 1
fi

# 6. 組裝絕對路徑資料區 (Compile_Hash + Runtime_Hash)
readonly DATA_DIR=$(readlink -m "${BASE_DATA}/mfc/${MFC_VERSION}/${COMPILE_HASH}_${SCRIPT_HASH}")

echo "[INFO] Establishing isolated data workspace..."
mkdir -p "$DATA_DIR"

echo "[INFO] Copying configuration to isolated workspace..."
cp "${MFC_ROOT}/examples/${TARGET_CASE}/case.py" "${DATA_DIR}/"

# 7. 進入環境執行運算 (絕對禁止在這裡拷貝日誌！)
echo "[INFO] Navigating to MFC root to satisfy execution constraints..."
cd "$MFC_ROOT"

echo "[INFO] Initiating MFC simulation..."
bash ./mfc.sh run "${DATA_DIR}/case.py" --binary mpirun

# 8. 運算結束與管線緩衝沖刷 (等待 tee 寫入硬碟)
echo "[INFO] Simulation completed successfully."
echo "[INFO] Data archived at: $DATA_DIR"
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))

sync
sleep 2

# 9. 終極雙重歸檔與自體改名 (生命週期的最後一刻)
echo "[INFO] Archiving script and execution log into data workspace..."
cp "$ORIGINAL_SCRIPT_PATH" "${DATA_DIR}/script_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${DATA_DIR}/"


echo "[INFO] Renaming script to match hash..."
mv "$ORIGINAL_SCRIPT_PATH" "${ORIGINAL_SCRIPT_DIR}/${SCRIPT_HASH}.sh"
