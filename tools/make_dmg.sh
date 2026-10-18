#!/bin/zsh
# SolunaCal 分发打包：Release 构建 → ad-hoc 深层签名 → DMG（含安装说明 + Applications 快捷方式）
# 用法：tools/make_dmg.sh
# 产物：dist/SolunaCal-<版本>.dmg（版本号取自 project.yml MARKETING_VERSION）
#
# 无付费开发者证书的现实约束（2026-10-15 盘点：钥匙串 0 张代码签名证书）：
#   - 无法公证（notarize），Gatekeeper 必拦首次双击 → 安装说明里给了右键打开 / xattr -cr 两条路
#   - ad-hoc 签名仍要做：保证二进制完整性自校验、Apple Silicon 上可运行（无签名 arm64 直接拒载）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.workbuddy-ai/scratch/dmg"          # 构建中间产物（不进 Git）
# 每次运行用独立 stage 目录：只新建、不删除。
# （本机宿主有批量删除保护，rm -rf 会被拦；消除删除动作比申请例外更可靠。）
STAMP=$(date +%Y%m%d-%H%M%S)
STAGE="$WORK/stage-$STAMP"
DIST="$ROOT/dist"
VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/project.yml" | sed 's/.*"\(.*\)".*/\1/')
DMG="$DIST/SolunaCal-$VERSION.dmg"

echo "== 版本 $VERSION =="

# 0. 前置检查：断言来源守卫 + 节气独立对账 + 单元测试（任一失败不出包）
#    赶时间可 SKIP_PREFLIGHT=1 跳过，但跳过就等于放弃这几道拦截。
if [ "${SKIP_PREFLIGHT:-0}" = "1" ]; then
    echo "!! 已按 SKIP_PREFLIGHT=1 跳前置检查"
else
    "$ROOT/tools/preflight.sh"
fi

# 1. 重新生成工程（project.yml 是唯一真源）并干净构建 Release
#    用 xcodebuild 自己的 clean 保证干净（不让脚本直接删目录，避开宿主批量删除保护）
command -v xcodegen >/dev/null && (cd "$ROOT" && xcodegen generate)
mkdir -p "$STAGE"
cd "$ROOT"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project SolunaCal.xcodeproj -scheme SolunaCal -configuration Release \
    -derivedDataPath "$WORK/derived" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
    clean build | grep -E "error|BUILD" | tail -2

APP="$WORK/derived/Build/Products/Release/SolunaCal.app"
[ -d "$APP" ] || { echo "构建产物不存在: $APP"; exit 1; }

# 2. 架构校验：必须双架构（Intel + Apple Silicon）
ARCHS=$(lipo -info "$APP/Contents/MacOS/SolunaCal" | sed 's/.*: //')
echo "架构: $ARCHS"
echo "$ARCHS" | grep -q x86_64 && echo "$ARCHS" | grep -q arm64 || { echo "非双架构，中止"; exit 1; }

# 3. ad-hoc 深层签名 + 校验
cp -R "$APP" "$STAGE/SolunaCal.app"
codesign --force --deep --sign - "$STAGE/SolunaCal.app"
codesign --verify --deep --strict "$STAGE/SolunaCal.app"
echo "签名校验 OK（ad-hoc）"

# 4. 冒烟：能起进程 4 秒不崩
"$STAGE/SolunaCal.app/Contents/MacOS/SolunaCal" --preview & SMOKE_PID=$!
sleep 4
if kill -0 $SMOKE_PID 2>/dev/null; then kill $SMOKE_PID; echo "冒烟 OK"; else echo "冒烟失败，中止"; exit 1; fi

# 5. 组装 DMG 内容：App + Applications 快捷方式 + 安装说明
ln -sf /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" << 'EOF'
SolunaCal 安装说明
==================

1. 把 SolunaCal 拖进右边的「应用程序」文件夹。
2. 首次打开：到「应用程序」里找到 SolunaCal → 右键点它 → 选「打开」→ 弹窗里再点「打开」。
   （直接双击可能被系统拦下，因为本应用没有 Apple 付费开发者签名，属正常现象。）
3. 如果提示「已损坏，无法打开」：打开「终端」App，粘贴下面这行后回车，再重新右键打开：
   xattr -cr /Applications/SolunaCal.app

系统要求
--------
macOS 14 Sonoma 或更新版本（支持 15 Sequoia / 26 Tahoe），Intel 和 Apple 芯片 Mac 均可。

它会在哪些地方要权限（都可以拒绝，拒绝也能用，只是对应功能没有）
--------------------------------------------------------------
- 日历：显示你的日程小圆点、双击日期创建事件。
- 通知：放假前一天 / 节日当天 / 生日提醒（在 App 设置里逐项开关，默认全关）。
- 定位：仅用于「干支时辰」的真太阳时校正（该功能默认关闭；拒绝则按东八区标准经线计算）。

卸载：把「应用程序」里的 SolunaCal 拖进废纸篓即可。
EOF

# 6. 打 DMG（UDZO 压缩，-ov 直接覆盖同名产物）+ 校验可挂载
mkdir -p "$DIST"
hdiutil create -volname "SolunaCal" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | tail -1
hdiutil verify "$DMG" >/dev/null && echo "DMG 校验 OK"
echo "== 产物 =="
ls -lh "$DMG"
shasum -a 256 "$DMG"
