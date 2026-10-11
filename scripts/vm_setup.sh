#!/bin/bash
# 在 GCP VM 上建立官方評測環境。所有輸出寫到 ~/audit/logs，版本資訊寫到 ~/audit/env/。
set -euo pipefail
REPO_SHA=2e9036e118464aa96a8bebaf9f5b9d091aa3585c
MATHLIB_SHA=2f65ba7f1a9144b20c8e7358513548e317d26de1
MODEL=Goedel-LM/Goedel-Prover-V2-8B
A=$HOME/audit; mkdir -p $A/logs $A/env $A/models
cd $A

# 1. Lean：elan，工具鏈由 mathlib4/lean-toolchain 決定（v4.9.0-rc1）
if [ ! -x $HOME/.elan/bin/lake ]; then
  curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
fi
export PATH=$HOME/.elan/bin:$PATH

# 2. 官方 repo，釘在 commit
if [ ! -d Goedel-Prover-V2 ]; then
  git clone --recurse-submodules https://github.com/Goedel-LM/Goedel-Prover-V2.git
fi
cd Goedel-Prover-V2
git checkout -q $REPO_SHA && git submodule update --init --recursive
test "$(git -C mathlib4 rev-parse HEAD)" = "$MATHLIB_SHA"
git rev-parse HEAD > $A/env/repo_sha.txt
git -C mathlib4 rev-parse HEAD > $A/env/mathlib_sha.txt
cat mathlib4/lean-toolchain > $A/env/lean_toolchain.txt

# 3. Mathlib：先試快取，失敗就完整建置；背景執行，記錄耗時
( cd mathlib4
  start=$(date +%s)
  if lake exe cache get > $A/logs/cache_get.log 2>&1; then echo "cache_get=ok" > $A/env/mathlib_build.txt
  else echo "cache_get=failed" > $A/env/mathlib_build.txt; fi
  lake build > $A/logs/lake_build.log 2>&1 && echo "lake_build=ok" >> $A/env/mathlib_build.txt || echo "lake_build=failed" >> $A/env/mathlib_build.txt
  lake build repl >> $A/logs/lake_build.log 2>&1 || true
  echo "seconds=$(( $(date +%s) - start ))" >> $A/env/mathlib_build.txt
) &
LEAN_PID=$!

# 4. Python：triton 執行期要編譯 C 擴充，需要 Python 標頭檔
sudo apt-get install -y -q python3.10-dev > $A/logs/apt.log 2>&1
# goedelv2.yml 的釘選版本（只裝跑 inference/compile 需要的子集）
if [ ! -x $A/venv/bin/python ]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH=$HOME/.local/bin:$PATH
  uv venv -p 3.10 $A/venv
  VIRTUAL_ENV=$A/venv uv pip install vllm==0.8.5.post1 torch==2.6.0 transformers==4.51.3 \
    numpy==1.26.4 pandas==1.4.3 pexpect==4.9.0 tqdm==4.67.1 jload==0.7.1 setuptools==78.1.1 wheel==0.45.1 triton==3.2.0 xformers==0.0.29.post2 huggingface_hub > $A/logs/pip.log 2>&1
fi
$A/venv/bin/pip freeze > $A/env/pip_freeze.txt 2>/dev/null || VIRTUAL_ENV=$A/venv $HOME/.local/bin/uv pip freeze > $A/env/pip_freeze.txt

# 5. 模型權重，記錄 HF revision
$A/venv/bin/python - <<EOF > $A/logs/hf_download.log 2>&1
from huggingface_hub import snapshot_download, HfApi
rev = HfApi().model_info("$MODEL").sha
p = snapshot_download("$MODEL", revision=rev, local_dir="$A/models/Goedel-Prover-V2-8B")
open("$A/env/model_revision.txt","w").write(rev + "\n")
print("downloaded", rev, p)
EOF

nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv > $A/env/gpu.txt
wait $LEAN_PID
echo SETUP_DONE > $A/env/setup_status.txt
