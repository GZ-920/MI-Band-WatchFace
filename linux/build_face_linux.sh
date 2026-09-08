#!/usr/bin/env bash
# ============================================================================
# build_face_linux.sh — 在 x86_64 Linux 上把 FloatLayerDemo 编译成 .face
#
# 为什么需要这个脚本：
#   小米官方表盘编译器 Compiler.exe 是 .NET 程序，可在 Linux + mono 运行，
#   但它有 3 个 Windows 依赖，本脚本逐一处理（均已在本机验证原理）：
#     1) WPF(PresentationCore)：mono 无此程序集 -> 用随附的最小占位 dll
#        骗过 ImageMagick 类型签名解析（tools/PresentationCore.cs 现场编译）
#     2) ImageMagick native：Compiler 内嵌 Magick.NET-Q16-AnyCPU 7.1.0，
#        其 native 库仅提供 linux-x64 -> 从 NuGet 官方包解包 .so 放入工具目录
#     3) Windows 反斜杠路径：Compiler 硬编码 '\\' 拼接路径，Linux 下需
#        在工程根构造同名"字面路径"文件（见下方 prepare_literal_paths）
#
# 用法：
#   bash linux/build_face_linux.sh [输出文件名] [表盘ID]
#   产物：bin/<工程名>.face
# 说明：本脚本在 arm64(手机) 上无法完成（ImageMagick native 无 arm64 版），
#       请用 GitHub Actions 云端编译（见 .github/workflows/build-face.yml）。
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJ_NAME="FloatLayerDemo"
FACE_ID="${FACE_ID:-491552737}"
OUT_NAME="${1:-${PROJ_NAME}.face}"
TOOLS="watchface/tools"
FPRJ_DIR="watchface/fprj"

echo "== [1/6] 工具检查 =="
command -v mono  >/dev/null || { echo "缺少 mono, 请先: sudo apt install mono-runtime mono-mcs libgdiplus libmono-system-drawing4.0-cil"; exit 1; }
command -v mcs   >/dev/null || { echo "缺少 mcs, 请先: sudo apt install mono-mcs"; exit 1; }
command -v python3 >/dev/null || { echo "缺少 python3"; exit 1; }

echo "== [2/6] 伪 WPF(PresentationCore) 签名占位 =="
if [ ! -f "$TOOLS/PresentationCore.dll" ]; then
  # 仅用于让 mono 能解析 MagickImage 的方法表签名（编译器不走 WPF 渲染路径）
  mcs /target:library /out:"$TOOLS/PresentationCore.dll" "$TOOLS/PresentationCore.cs"
fi
echo "    PresentationCore.dll ready: $(ls -la "$TOOLS/PresentationCore.dll" | awk '{print $5}') bytes"

echo "== [3/6] ImageMagick native (linux-x64) 准备 =="
if ls "$TOOLS"/*Native.dll.so >/dev/null 2>&1; then
  echo "    native 已存在，跳过下载"
else
  echo "    从 NuGet 下载 Magick.NET-Q16-AnyCPU 7.1.0 (官方包)..."
  python3 - <<'PYEOF'
import urllib.request, zipfile, io, os, shutil, time
url = "https://api.nuget.org/v3-flatcontainer/magick.net-q16-anycpu/7.1.0/magick.net-q16-anycpu.7.1.0.nupkg"
for i in range(5):
    try:
        data = urllib.request.urlopen(url, timeout=60).read()
        break
    except Exception as e:
        print("    重试", i + 1, e)
        time.sleep(3)
else:
    raise SystemExit("下载 nupkg 失败")
z = zipfile.ZipFile(io.BytesIO(data))
dst = "watchface/tools"
n = 0
for name in z.namelist():
    if name.startswith("runtimes/linux-x64/native/"):
        base = os.path.basename(name)
        with open(os.path.join(dst, base), "wb") as f:
            f.write(z.read(name))
        n += 1
        print("    解出:", base)
if n == 0:
    raise SystemExit("nupkg 中未找到 linux-x64 native")
# 兼容 mono 的库名搜索习惯
for so in os.listdir(dst):
    if so.endswith("Native.dll.so"):
        link = "lib" + so
        if not os.path.exists(os.path.join(dst, link)):
            os.symlink(so, os.path.join(dst, link))
PYEOF
fi

echo "== [4/6] 布置 Windows 反斜杠字面路径（编译器硬编码 '\\' 拼接）=="
# Compiler 内部把 <fprj目录>\images\preview.png 拼成含反斜杠的串，
# 在 Linux 下它实际寻找的是 工程根/一个名为 "fprj\images\preview.png" 的文件。
if [ ! -f "$FPRJ_DIR/FloatLayerDemo.fprj" ]; then
  mv "$FPRJ_DIR"/LuaDevTemplate.fprj "$FPRJ_DIR/FloatLayerDemo.fprj" 2>/dev/null || true
fi
mkdir -p bin "watchface/fprj/output"
# 关键：在 watchface/ 下创建字面名文件（单引号保留反斜杠）
cp -f "watchface/fprj/images/preview.png" "watchface/fprj\\images\\preview.png"
echo "    字面路径文件已布置"

echo "== [5/6] 运行官方编译器 (mono) =="
LD_LIBRARY_PATH="$ROOT/$TOOLS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  mono "$TOOLS/Compiler.exe" -b "$FPRJ_DIR/FloatLayerDemo.fprj" bin "$OUT_NAME" "$FACE_ID"

echo "== [6/6] 修正 face 头部的表盘 ID =="
python3 - "$FACE_ID" "$OUT_NAME" <<'PYEOF'
import sys
face_id = sys.argv[1].encode("ascii")
name    = sys.argv[2]
path    = "bin/" + name
b = bytearray(open(path, "rb").read())
assert b[:4] == bytes([0x5A, 0xA5, 0x34, 0x12]), "face 头魔数不对: " + name
assert len(face_id) <= 10, "ID 超过 10 字节"
b[5] = 10
b[40:50] = b"\x00" * 10
b[40:40 + len(face_id)] = face_id
open(path, "wb").write(b)
print("已写 ID:", sys.argv[1])
PYEOF

echo ""
echo "========== 构建完成 =========="
ls -la "bin/$OUT_NAME"
echo "请用 表盘自定义工具 / Notify for Mi Band 等导入安装到设备"