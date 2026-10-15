"""用官方 lean_compiler/repl_scheduler.py 的函式檢查單一證明，結果寫成 JSON。
等同官方 worker 的一次 send_command_and_wait(child, code, env=0)；env 0 永遠是 import 完成後的狀態，
所以每個證明開新的 REPL 與官方重複使用 REPL 在語意上相同。
用法（cwd 必須是 Goedel-Prover-V2 根目錄）：check_one.py <in.json> <out.json>
in.json 是 to_inference_codes.json 的一筆（需有 problem_id、full_code）。"""
import json, os, sys, time

sys.path.insert(0, os.getcwd())
from lean_compiler.repl_scheduler import initiate_child, send_command_and_wait  # noqa: E402


def handle(text):  # 與官方 src/compile.py 的 handle() 相同（Goedel-Prover-V2, Apache-2.0）
    lines = text.split('\n')
    filtered_lines = [line for line in lines if not (
            line.strip().startswith('import') or
            line.strip().startswith('set_option') or
            line.strip().startswith('open')
    )]
    return '\n'.join(filtered_lines)


item = json.load(open(sys.argv[1]))
code = handle(item["full_code"])  # 官方對 "None" 也照樣 handle，得到 "None"
t0 = time.time()
if len(code) == 0:
    resp = {"code": code, "compilation_result": {"pass": False, "complete": False, "system_errors": None}}
else:
    child, _ = initiate_child()
    t_import = time.time() - t0
    resp = send_command_and_wait(child, code, env=0)
    try:
        child.close()
    except Exception:
        child.terminate(force=True)
    resp["import_seconds"] = round(t_import, 2)
resp["name"] = item["problem_id"]
resp["verify_time"] = round(time.time() - t0, 2)
resp["proof_timeout_env"] = os.environ.get("PROOF_TIMEOUT")
json.dump(resp, open(sys.argv[2], "w"))
