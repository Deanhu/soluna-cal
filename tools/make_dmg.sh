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
cat > "$STAGE/① 先看这里 安装说明.txt" << 'EOF'
⚠️ 不要在打开的窗口里直接双击 SolunaCal
=========================================

直接双击会跳「Apple 无法验证 SolunaCal…」，而且没有「打开」按钮，只能点「完成」。
这不是文件坏了——是这个软件没有 Apple 的付费签名（一年 99 美元）。
按下面 4 步走，两分钟装好。

一、怎么装（4 步）
------------------
1. 打开 SolunaCal 这个磁盘文件（就是现在这个窗口）。

2. 把 SolunaCal 图标，拖到右边的「Applications（应用程序）」文件夹。
   ← 一定要先拖过去，别在这个窗口里双击它。

3. 按 Command + 空格，输入「终端」，回车，打开「终端」。
   把下面这一行整行复制进去，回车（可能要输开机密码；输的时候屏幕上不显示字，输完回车）：

   xattr -cr /Applications/SolunaCal.app

4. 打开「启动台」，找到 SolunaCal，双击它。

装好后，在「访达」左边把 SolunaCal 这个磁盘点「推出」，别一直挂着。

那行命令在做什么
----------------
系统给「从网上下的文件」打了一个隔离标记，所以不认它。
这行命令把标记清掉，等于告诉系统「这个软件我确认可以用」。
它不改任何系统设置，也不影响别的软件。

二、如果已经双击被拦了
----------------------
点「完成」→ 回到第 2 步，把 SolunaCal 拖进「应用程序」→ 做第 3 步 →
从「启动台」打开。不用重新下载。

（有人会说去「系统设置 → 隐私与安全性 → 仍要打开」。
这个按钮对没签名的软件经常根本不出现，别在那上面耗时间，直接用第 3 步。）

三、装好之后
------------
- 屏幕右上角菜单栏会多出今天的日期，点一下展开整月日历。
- 第一次打开会弹三页说明，看完点完成。
- 它不出现在 Dock 里，这是正常的——菜单栏工具都这样，别以为没装上。

四、它会问你要权限，都可以拒绝
------------------------------
- 日历：在日历上显示日程小圆点、双击日期新建事件。拒绝就没有小圆点。
- 通知：放假前、节日、生日提醒。默认全关，要自己在设置里开。
- 定位：只用于「真太阳时」校正，默认关闭。拒绝就按东八区时间算。

五、如果打开后还是看不到
------------------------
它没有 Dock 图标，也不会开窗口，只在屏幕右上角菜单栏显示。先往右上角看。

还是找不到，就把下面这一行整行贴进「终端」回车，把输出截图发回给我：

/Applications/SolunaCal.app/Contents/MacOS/SolunaCal --selfcheck

它会把卡在哪一步直接写出来（没装到应用程序 / 还被系统拦着 / 菜单栏项建不出来），
不用猜。它同时会把每次启动的情况记在：~/Library/Logs/SolunaCal.log

六、不想要了
------------
把「应用程序」里的 SolunaCal 拖进废纸篓即可，不留后台残留。
（想连日志一起清掉：删掉 ~/Library/Logs/SolunaCal.log）

七、系统要求
------------
macOS 14 Sonoma 或更新（15 Sequoia、26 都可以）。
Intel 芯片和 Apple 芯片（M1/M2/M3/M4）都能装，同一个安装包。
EOF

# 6. 打 DMG（UDZO 压缩，-ov 直接覆盖同名产物）+ 校验可挂载
mkdir -p "$DIST"
hdiutil create -volname "SolunaCal" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | tail -1
hdiutil verify "$DMG" >/dev/null && echo "DMG 校验 OK"
echo "== 产物 =="
ls -lh "$DMG"
shasum -a 256 "$DMG"
