#!/bin/bash
set -e

# 記錄起始時間
START_TIME=$(date +%s)

# 參數解析
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --o_software) SOFTWARE_DIR="$2"; shift ;;
        --o_module) MODULE_FILE="$2"; shift ;;
        *) echo "致命錯誤：不支援的參數 $1" ; exit 1 ;;
    esac
    shift
done

# 防呆檢查
if [ -z "$SOFTWARE_DIR" ] || [ -z "$MODULE_FILE" ]; then
    echo "致命錯誤：必須同時提供 --o_software 與 --o_module 參數！"
    echo "用法: $0 --o_software /絕對路徑/mfc/5.7.0 --o_module /絕對路徑/modulefiles/mfc/5.7.0"
    exit 1
fi

# 轉換為絕對路徑，防止模組檔路徑錯亂
SOFTWARE_DIR=$(readlink -m "$SOFTWARE_DIR")
MODULE_FILE=$(readlink -m "$MODULE_FILE")

echo ">>> 1. 檢查前置環境..."
if ! command -v mpifort &> /dev/null; then
    echo "致命錯誤：找不到 MPI 編譯器！請先手動 module load 你的 compiler 與 mpi 模組！"
    exit 1
fi

echo ">>> 2. 清理並建立軟體目錄..."
if [ -d "$SOFTWARE_DIR" ]; then
    echo "警告：目標目錄已存在，正在強制清除..."
    rm -rf "$SOFTWARE_DIR"
fi
mkdir -p "$(dirname "$SOFTWARE_DIR")"

echo ">>> 3. 下載並編譯 MFC..."
git clone --depth 1 --branch v5.7.0 https://github.com/MFlowCode/MFC.git "$SOFTWARE_DIR"
cd "$SOFTWARE_DIR"
bash ./mfc.sh build -j4

echo ">>> 4. 生成 Modulefile..."
mkdir -p "$(dirname "$MODULE_FILE")"
cat <<EOF > "$MODULE_FILE"
#%Module1.0
set MFC_ROOT $SOFTWARE_DIR
prepend-path PATH \$MFC_ROOT
set-alias mfc "cd \$MFC_ROOT && ./mfc.sh"
EOF

# 計算並輸出執行時間
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ">>> 部署大功告成！"
echo ">>> 軟體路徑: $SOFTWARE_DIR"
echo ">>> 模組路徑: $MODULE_FILE"
echo ">>> 總耗時: ${MINUTES} 分 ${SECONDS} 秒"
