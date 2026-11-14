#!/bin/bash
# SC26 Single-Node (H100 NVL), 32 cpu, 1 gpu
#SBATCH --gpus-per-node=1
#SBATCH --job-name=Compile_Base
#SBATCH --partition=normal
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
set -euo pipefail
############### [Do not modify] ###############
readonly LOG_POOL_DIR="${HOME}/.log";mkdir -p "$LOG_POOL_DIR"
RESOURCE_SCRIPT_PATH=$(readlink -m "$0");RESOURCE_HASH=$(sha256sum "$RESOURCE_SCRIPT_PATH"|awk '{print $1}')
RESOURCE_LOG="${LOG_POOL_DIR}/sbatch_${SLURM_JOB_ID:-manual}_compiletimeresource_${RESOURCE_HASH:0:8}.log"
exec > >(tee -a "$RESOURCE_LOG") 2>&1
echo "[INFO] Live resource log at: $RESOURCE_LOG"
############################################
if [[ -f /etc/profile.d/lmod.sh ]]; then
    source /etc/profile.d/lmod.sh
elif [[ -f /usr/share/lmod/lmod/init/bash ]]; then
    source /usr/share/lmod/lmod/init/bash
fi

ml use /opt/nvidia/hpc_sdk/modulefiles
ml load nvhpc-hpcx-cuda13

# 導向大型高速儲存陣列 /data，避免寫爆 1.7TB 根目錄
export TMPDIR="/data/${USER}/.tmp"
export UV_CACHE_DIR="/data/${USER}/.cache/uv"
mkdir -p "$TMPDIR" "$UV_CACHE_DIR"
############### [Do not modify] ###############
COMPILETIME_SCRIPT="";SOFTWARE_ROOT="";MODULE_ROOT="";RECOMPILE_FLAG=""
while [[ "$#" -gt 0 ]];do case $1 in --compiletime_script) COMPILETIME_SCRIPT="$2";shift 2;;--software_root) SOFTWARE_ROOT="$2";shift 2;;--module_root) MODULE_ROOT="$2";shift 2;;--recompile) RECOMPILE_FLAG="--recompile";shift 1;;*) echo "[FATAL] Unknown arg: $1";exit 1;;esac;done
if [[ -z "$COMPILETIME_SCRIPT"||-z "$SOFTWARE_ROOT"||-z "$MODULE_ROOT" ]];then echo "[FATAL] Missing mandatory arguments.";exit 1;fi
TMP_PIPE=$(mktemp -u);mkfifo "$TMP_PIPE";trap 'rm -f "$TMP_PIPE"' EXIT
bash "$COMPILETIME_SCRIPT" --software_root "$SOFTWARE_ROOT" --module_root "$MODULE_ROOT" --resource_hash "$RESOURCE_HASH" ${RECOMPILE_FLAG} 2>&1|tee "$TMP_PIPE" &
EXEC_PID=$!;COMPILE_SCRIPT_HASH=""
while IFS= read -r line;do if [[ "$line" =~ ^\[EXPORT_HASH\]\ (.*)$ ]];then COMPILE_SCRIPT_HASH="${BASH_REMATCH[1]}";fi;done < "$TMP_PIPE"
wait "$EXEC_PID"
TARGET_SOFTWARE_DIR=$(readlink -m "${SOFTWARE_ROOT}/${COMPILE_SCRIPT_HASH}")
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60))
if [[ -n "$COMPILE_SCRIPT_HASH"&&-e "$TARGET_SOFTWARE_DIR" ]];then
    F_COMP_RES="compiletimeresource_${RESOURCE_HASH}.sbatch"
    F_COMP_TIME="compiletime_${COMPILE_SCRIPT_HASH}.sh"
    cp "$RESOURCE_SCRIPT_PATH" "${TARGET_SOFTWARE_DIR}/${F_COMP_RES}"
    cp "$RESOURCE_LOG" "${TARGET_SOFTWARE_DIR}/compiletimeresource_${RESOURCE_HASH}.log"
    # Deploy to GitHub
    GITHUB_USER="hlajungo"
    GITHUB_REPO="script"
    BRANCH="main"
    REPO_URL="git@github.com:${GITHUB_USER}/${GITHUB_REPO}.git"
    RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"
    DEPLOY_TMP=$(mktemp -d)
    echo "[INFO] Syncing scripts to GitHub (${REPO_URL})..."
    if git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$DEPLOY_TMP/repo"; then
        cp "${TARGET_SOFTWARE_DIR}/${F_COMP_RES}" "${TARGET_SOFTWARE_DIR}/${F_COMP_TIME}" "$DEPLOY_TMP/repo/"
        sed -i "s|/home/hlajungo/|${HOME}/|g" "$DEPLOY_TMP/repo/${F_COMP_RES}" "$DEPLOY_TMP/repo/${F_COMP_TIME}"
        cd "$DEPLOY_TMP/repo"
        git add "${F_COMP_RES}" "${F_COMP_TIME}"
        if git status --porcelain | grep -qE "^(A|M)  "; then
            git commit -m "Auto-deploy SC26 baseline compile suite: ${COMPILE_SCRIPT_HASH:0:8}"
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
    REPRODUCE_FILE="${TARGET_SOFTWARE_DIR}/reproduce_compile.txt"
    cat <<EOF > "$REPRODUCE_FILE"
# Reproduce compilation (SC26 Baseline commit 4e96e0d)
mkdir -p "/data/\${USER}/.tmp" && cd "/data/\${USER}/.tmp" && \\
wget -q "${RAW_BASE}/${F_COMP_TIME}" && \\
wget -q "${RAW_BASE}/${F_COMP_RES}" && \\
JOB_ID=\$(sbatch --parsable "${F_COMP_RES}" --compiletime_script "${F_COMP_TIME}" --software_root ${SOFTWARE_ROOT} --module_root ${MODULE_ROOT}) && \\
echo "Compile Job \${JOB_ID} submitted. Waiting for completion..." && \\
while squeue -j "\${JOB_ID}" 2>/dev/null | grep -q "\${JOB_ID}"; do sleep 5; done && \\
rm -f "${F_COMP_TIME}" "${F_COMP_RES}" && \\
echo "[INFO] Compilation done."
EOF
    echo "========================================================================="
    echo "[SUCCESS] Reproduce instructions written to: $REPRODUCE_FILE"
    echo "========================================================================="
    cat "$REPRODUCE_FILE"
    echo "========================================================================="
fi
echo "[INFO] Compiletime Resource Exit."
############################################
