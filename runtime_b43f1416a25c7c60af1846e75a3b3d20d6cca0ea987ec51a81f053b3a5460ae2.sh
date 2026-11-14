#!/bin/bash
set -euo pipefail
############### [Do not modify] ###############
readonly ORIGINAL_SCRIPT_PATH=$(readlink -m "$0");readonly SCRIPT_HASH=$(sha256sum "$ORIGINAL_SCRIPT_PATH"|awk '{print $1}')
COMPILE_HASH="";BASE_DATA="";RES_HASH="none";SOFTWARE_ROOT="${HOME}/share/software/mfc/matrix"
while [[ "$#" -gt 0 ]];do case $1 in --software_root) SOFTWARE_ROOT=$(readlink -m "$2");shift 2;;--compile_hash) COMPILE_HASH="$2";shift 2;;--data_root) BASE_DATA="$2";shift 2;;--resource_hash) RES_HASH="$2";shift 2;;*) echo "[FATAL] Arg: $1";exit 1;;esac;done
readonly CONFIG_POOL_DIR=$(readlink -m "${BASE_DATA}/${COMPILE_HASH}_${SCRIPT_HASH}_${RES_HASH}")
readonly DATA_DIR="${CONFIG_POOL_DIR}/${SLURM_JOB_ID:-local_$(date +%s)}";mkdir -p "$DATA_DIR"
echo "[EXPORT_DATA_DIR] ${DATA_DIR}"
readonly LOG_POOL_DIR="${HOME}/.log";mkdir -p "$LOG_POOL_DIR"
readonly LOG_FILE="${LOG_POOL_DIR}/sbatch_${SLURM_JOB_ID:-manual}_runtime_${SCRIPT_HASH:0:8}.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "================================================================================"
echo "[INFO] Data Workspace : ${DATA_DIR}"
echo "[INFO] Software Root  : ${SOFTWARE_ROOT}"
echo "[INFO] Compile Hash   : ${COMPILE_HASH}"
echo "[INFO] Runtime Hash   : ${SCRIPT_HASH}"
echo "[INFO] Resource Hash  : ${RES_HASH}"
echo "================================================================================"
############################################
echo "[INFO] Verifying GPU execution environment..." 
if ! command -v srun &> /dev/null && ! command -v mpirun &> /dev/null; then 
    echo "[FATAL] MPI launcher (mpirun/srun) not found. Environment not ready."; exit 1
fi 
if [ -z "${MFC_ROOT:-}" ] || [ ! -d "${MFC_ROOT}" ]; then 
    echo "[FATAL] MFC_ROOT undefined or directory missing. Software environment not loaded."; exit 1
fi 
if ! command -v nvidia-smi &> /dev/null; then
    echo "[FATAL] nvidia-smi not available on execution node."; exit 1
fi

echo "[INFO] Generating case.py for NACA0012 (Re=200) in isolated workspace..."
cat << 'EOF_CASE' > "${DATA_DIR}/case.py"
#!/usr/bin/env python3
import json
import math

gamma_gas   = 1.4
R_gas       = 288.29438
T_inf       = 288.0
p_inf       = 101300.0
rho_inf     = 1.22
a_sound     = math.sqrt(gamma_gas * R_gas * T_inf)
Ma_inf      = 0.1
U_inf       = Ma_inf * a_sound
c_chord     = 0.5
t_thickness = 0.12
angle_deg   = 5.0
angle_rad   = angle_deg * math.pi / 180.0
Re_target   = 200.0

Nx = 399
Ny = 399
Tend = 1.0
Nt = 30000
mydt = Tend / Nt

print(
    json.dumps(
        {
            "num_fluids": 1,
            "fluid_pp(1)%gamma": 1.0 / (gamma_gas - 1.0),
            "fluid_pp(1)%eos": "ideal_gas",
            "fluid_pp(1)%Re(1)": Re_target,
            "viscous": "T",
            "num_patches": 1,
            "patch_icpp(1)%geometry": 3,
            "patch_icpp(1)%x_centroid": 0.0,
            "patch_icpp(1)%y_centroid": 0.0,
            "patch_icpp(1)%length_x": 10.0,
            "patch_icpp(1)%length_y": 10.0,
            "patch_icpp(1)%vel(1)": U_inf,
            "patch_icpp(1)%vel(2)": 0.0,
            "patch_icpp(1)%pres": p_inf,
            "patch_icpp(1)%alpha_rho(1)": rho_inf,
            "patch_icpp(1)%alpha(1)": 1.0,
            "bc_x%beg": -3,
            "bc_x%end": -3,
            "bc_y%beg": -3,
            "bc_y%end": -3,
            "ib": "T",
            "num_ibs": 1,
            "patch_ib(1)%geometry": 4,
            "patch_ib(1)%x_centroid": 0.0,
            "patch_ib(1)%y_centroid": 0.0,
            "patch_ib(1)%airfoil_id": 1,
            "patch_ib(1)%angles(3)": angle_rad,
            "patch_ib(1)%slip": "F",
            "ib_airfoil(1)%c": c_chord,
            "ib_airfoil(1)%t": t_thickness,
            "ib_airfoil(1)%p": 1.0e-8,
            "ib_airfoil(1)%m": 1.0e-8,
            "m": Nx,
            "n": Ny,
            "p": 0,
            "cyl_coord": "F",
            "x_domain%beg": -5.0,
            "x_domain%end":  5.0,
            "y_domain%beg": -5.0,
            "y_domain%end":  5.0,
            "dt": mydt,
            "t_step_start": 0,
            "t_step_stop": int(Nt),
            "time_stepper": 3,
            "model_eqns": 2,
            "weno_order": 5,
            "weno_eps": 1.0e-16,
            "riemann_solver": 2,
            "wave_speeds": 1,
            "avg_state": 2,
            "fd_order": 2,
            "run_time_info": "T",
            "t_step_save": int(Nt / 20),
            "format": "silo",
            "precision": 2,
            "prim_vars_wrt": "T",
            "ib_state_wrt": "T",
            "parallel_io": "F"
        }
    )
)
EOF_CASE
chmod +x "${DATA_DIR}/case.py"

echo "[INFO] Navigating to MFC root and initiating GPU simulation pipeline..." 
cd "$MFC_ROOT" 
export OMPI_MCA_hwloc_base_binding_policy=none

readonly GPU_TASKS=1

echo "[INFO] Stage 1/3: Running pre_process with GPU (Tasks: ${GPU_TASKS})..."
bash "${MFC_ROOT}/mfc.sh" run "${DATA_DIR}/case.py" -t pre_process -e interactive -n "$GPU_TASKS" --binary mpirun --gpu acc --case-optimization

echo "[INFO] Stage 2/3: Running simulation with GPU (Tasks: ${GPU_TASKS})..."
bash "${MFC_ROOT}/mfc.sh" run "${DATA_DIR}/case.py" -t simulation -e interactive -n "$GPU_TASKS" --binary mpirun --gpu acc --case-optimization

echo "[INFO] Stage 3/3: Running post_process..."
bash "${MFC_ROOT}/mfc.sh" run "${DATA_DIR}/case.py" -t post_process -e interactive -n 1 --binary mpirun

############### [Do not modify] ###############
printf "%s_runtime: %02dhr:%02dmin:%02dsec\n" "${0##*/}" $((SECONDS/3600)) $(( (SECONDS%3600)/60 )) $((SECONDS%60));sync;sleep 2
cp "$ORIGINAL_SCRIPT_PATH" "${DATA_DIR}/runtime_${SCRIPT_HASH}.sh"
cp "$LOG_FILE" "${DATA_DIR}/runtime_${SCRIPT_HASH}.log"
echo "=== BEGIN ENV DUMP ===";export -p;echo "=== END ENV DUMP ==="
echo "[INFO] Runtime Exit."
############################################
