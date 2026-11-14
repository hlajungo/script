#!/bin/bash
# Nano4, 12 cpu, 1 gpu (Required by NCHC)
#SBATCH --job-name=Run
#SBATCH --partition=dev
#SBATCH --nodes=1
#SBATCH --ntasks=12
#SBATCH --gpus-per-node=1
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
set -euo pipefail
############### [Do not modify] ###############
RUNTIME_SCRIPT="";COMPILE_HASH="";DATA_ROOT=""
while [[ "$#" -gt 0 ]];do case $1 in --runtime_script) RUNTIME_SCRIPT=$(readlink -m "$2");shift 2;;--compile_hash) COMPILE_HASH="$2";shift 2;;--data_root) DATA_ROOT=$(readlink -m "$2");shift 2;;*) echo "[FATAL] Arg: $1";exit 1;;esac;done
if [[ -z "$RUNTIME_SCRIPT" || -z "$COMPILE_HASH" || -z "$DATA_ROOT" ]]; then echo "[FATAL] Missing mandatory arguments.";exit 1;fi
readonly LOG_POOL_DIR="${HOME}/.log";mkdir -p "$LOG_POOL_DIR"
RESOURCE_SCRIPT_PATH=$(readlink -m "$0");RESOURCE_HASH=$(sha256sum "$RESOURCE_SCRIPT_PATH"|awk '{print $1}')
RESOURCE_LOG="${LOG_POOL_DIR}/sbatch_${SLURM_JOB_ID:-manual}_runtimeresource_${RESOURCE_HASH:0:8}.log"
exec > >(tee -a "$RESOURCE_LOG") 2>&1
echo "[INFO] Live resource log at: $RESOURCE_LOG"
############################################
ml use /home/hlajungo1/share/software/nvhpc/25.11/modulefiles
ml load nvhpc-hpcx-cuda13/25.11
ml use /home/hlajungo1/share/module/mfc/matrix
ml load "${COMPILE_HASH}"
############### [Do not modify] ###############
TMP_PIPE=$(mktemp -u);mkfifo "$TMP_PIPE";trap 'rm -f "$TMP_PIPE"' EXIT
bash "$RUNTIME_SCRIPT" --compile_hash "$COMPILE_HASH" --data_root "$DATA_ROOT" --resource_hash "$RESOURCE_HASH" 2>&1|tee "$TMP_PIPE" &
EXEC_PID=$!;TARGET_DATA_DIR=""
while IFS= read -r line;do if [[ "$line" =~ ^\[EXPORT_DATA_DIR\]\ (.*)$ ]];then TARGET_DATA_DIR="${BASH_REMATCH[1]}";fi;done < "$TMP_PIPE"
wait "$EXEC_PID"
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
if [[ -n "$TARGET_DATA_DIR" && -d "$TARGET_DATA_DIR" ]]; then
    F_RUN_RES="runtimeresource_${RESOURCE_HASH}.sbatch"
    RUN_TIME_FILE=$(find "$TARGET_DATA_DIR" -maxdepth 1 -name "runtime_*.sh" | head -n 1)
    F_RUN_TIME=$(basename "$RUN_TIME_FILE")
    RUNTIME_HASH=$(echo "$F_RUN_TIME" | sed 's/runtime_//;s/\.sh//')
    cp "$RESOURCE_SCRIPT_PATH" "${TARGET_DATA_DIR}/${F_RUN_RES}"
    cp "$RESOURCE_LOG" "${TARGET_DATA_DIR}/runtimeresource_${RESOURCE_HASH}.log"
    GITHUB_USER="hlajungo"
    GITHUB_REPO="script"
    BRANCH="main"
    REPO_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"
    DEPLOY_TMP=$(mktemp -d)
    echo "[INFO] Syncing runtime scripts to GitHub (${REPO_URL})..."
    if git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$DEPLOY_TMP/repo"; then
        cp "${TARGET_DATA_DIR}/${F_RUN_RES}" "${TARGET_DATA_DIR}/${F_RUN_TIME}" "$DEPLOY_TMP/repo/"
        sed -i "s|/home/hlajungo1/|${HOME}/|g" "$DEPLOY_TMP/repo/${F_RUN_RES}" "$DEPLOY_TMP/repo/${F_RUN_TIME}"
        cd "$DEPLOY_TMP/repo"
        git add "${F_RUN_RES}" "${F_RUN_TIME}"
        if git status --porcelain | grep -qE "^(A|M)  "; then
            git commit -m "Auto-deploy runtime suite: ${RUNTIME_HASH:0:8}"
            PUSH_SUCCESS=0
            for RETRY in {1..5}; do
                git pull --rebase origin "$BRANCH" || true
                if git push origin "$BRANCH"; then
                    echo "[INFO] GitHub push succeeded (attempt: ${RETRY})."
                    PUSH_SUCCESS=1
                    break
                fi
                echo "[WARN] Push collision detected. Retrying with backoff..."
                sleep $(( (RANDOM % 5) + 2 ))
            done
            [[ $PUSH_SUCCESS -eq 0 ]] && echo "[ERROR] Exceeded max retries. GitHub push failed."
        else
            echo "[INFO] No changes detected. Skipping GitHub push."
        fi
        cd - >/dev/null
    else
        echo "[ERROR] Git clone failed. Skipping deployment."
    fi
    rm -rf "$DEPLOY_TMP"
    REPRODUCE_FILE="${TARGET_DATA_DIR}/reproduce_runtime.txt"
    cat <<EOF > "$REPRODUCE_FILE"
# Reproduce runtime simulation
mkdir -p /home/hlajungo1/.tmp && cd /home/hlajungo1/.tmp && \\
wget -q "${RAW_BASE}/${F_RUN_TIME}" && \\
wget -q "${RAW_BASE}/${F_RUN_RES}" && \\
JOB_ID=\$(sbatch --parsable "${F_RUN_RES}" --runtime_script "${F_RUN_TIME}" --compile_hash "${COMPILE_HASH}" --data_root "${DATA_ROOT}") && \\
echo "Run Job \${JOB_ID} submitted. Waiting for completion..." && \\
while squeue -h -j "\${JOB_ID}" -o "%i" 2>/dev/null | grep -E -q "^\${JOB_ID}\$"; do sleep 10; done && \\
rm -f "${F_RUN_TIME}" "${F_RUN_RES}" && \\
echo "[INFO] Simulation completed and temporary scripts in /home/hlajungo1/.tmp cleaned up."
EOF
    echo "========================================================================="
    echo "[SUCCESS] Reproduce instructions written to: $REPRODUCE_FILE"
    echo "========================================================================="
    cat "$REPRODUCE_FILE"
    echo "========================================================================="
fi
echo "[INFO] Runtime Resource Exit."
############################################
