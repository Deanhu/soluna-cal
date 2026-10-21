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
⚠️ 直接双击会被系统拦住，先看这里
=====================================

直接双击会跳「Apple 无法验证 SolunaCal…」，而且没有「打开」按钮，只能点「完成」。
这不是文件坏了——是这个软件没有 Apple 的付费签名（一年 99 美元）。
按下面走，两分钟装好。

一、怎么装（3 步，推荐：让 App 自己装）
---------------------------------------
1. 按 Command + 空格，输入「终端」，回车，打开「终端」。
   把下面这一行整行复制进去，回车（可能要输开机密码；输的时候屏幕上不显示字，输完回车）：

   xattr -cr /Volumes/SolunaCal/SolunaCal.app

   提示「No such file」就是磁盘名对不上：先在「访达」里打开 SolunaCal 这个磁盘，
   看窗口标题叫什么，把命令里的 SolunaCal 换成那个名字。

2. 回到安装包这个窗口，双击 SolunaCal。

3. 它会自己弹窗问「把 SolunaCal 装到「应用程序」？」→ 点「立即安装」。
   装好会自己重新打开，生日和设置都保留。

4. 装完后，在「访达」左边把 SolunaCal 这个磁盘点「推出」。
   ← 别省这一步：挂着安装包运行，磁盘一弹出 App 就没了，自动更新也用不了。

二、另一种装法（手动拖进「应用程序」）
--------------------------------------
不想让它自己装，就手动来：

1. 把 SolunaCal 图标，拖到右边的「Applications（应用程序）」文件夹。
2. 终端里执行：xattr -cr /Applications/SolunaCal.app
3. 打开「启动台」，找到 SolunaCal，双击它。

（如果你已经双击被拦了：点「完成」→ 回到第 1 步，不用重新下载。）

（有人会说去「系统设置 → 隐私与安全性 → 仍要打开」。
这个按钮对没签名的软件经常根本不出现，别在那上面耗时间，直接用上面两种办法。）

三、那行 xattr 命令在做什么
---------------------------
系统给「从网上下载的文件」打了一个隔离标记，所以不认它。
这行命令把标记清掉，等于告诉系统「这个软件我确认可以用」。
它不改任何系统设置，也不影响别的软件。

四、装好之后
------------
- 屏幕右上角菜单栏会多出一个小图标（或今天的日期），点一下展开整月日历。
- 第一次打开会弹几页说明；最后点「开始使用」时，右上角的图标会闪两下——
  那是它告诉你「我在这儿」。
- 它不出现在 Dock 里，这是正常的——菜单栏工具都这样，别以为没装上。
- 首次引导里也专门有一页讲这件事：图标在哪、被藏了怎么办。

五、它会问你要权限，都可以拒绝
------------------------------
- 日历：在日历上显示日程小圆点、双击日期新建事件。拒绝就没有小圆点。
- 通知：放假前、节日、生日提醒。默认全关，要自己在设置里开。
- 定位：只用于「真太阳时」校正，默认关闭。拒绝就按东八区时间算。

六、如果打开后还是看不到
------------------------
它没有 Dock 图标，平时不占窗口，只在屏幕右上角菜单栏显示。先往右上角看。

还是找不到，最可能是菜单栏太挤——刘海屏 Mac 上，放不下的项会被系统藏到刘海后面，
不显示也不提示。

三条路按顺序试：

  1）它会自己弹窗口。App 每次启动都会检查图标是不是被藏了；被藏就自动弹一个窗口，
     里面有一行说明 + 完整可用的日历。窗口关了想再打开：双击「应用程序」里的
     SolunaCal，或在菜单栏图标在的时候按快捷键 ⌥⌘C。
  2）腾位置。按住 ⌘ 把不用的菜单栏图标拖走（WPS、微信这类常驻的），图标会立刻露出来。
  3）强制切「仅图标」。宽度从约 120pt 降到约 22pt：

  · 能打开弹窗的话：点菜单栏日期 → 齿轮「设置」→「菜单栏形态」改成「仅图标」
  · 打不开弹窗（因为根本看不到图标）：终端里粘贴这三行

      defaults write com.soluna.cal statusItemStyle -int 2
      pkill -x SolunaCal; sleep 1
      open /Applications/SolunaCal.app

其他办法：退出几个别的菜单栏 App 腾位置，或把鼠标移到屏幕顶部再等一秒。

如果还是不行，把下面这行贴进「终端」回车，把输出截图发回给我：

/Applications/SolunaCal.app/Contents/MacOS/SolunaCal --selfcheck

它会把卡在哪一步直接写出来（没装到应用程序 / 还被系统拦着 / 菜单栏项建不出来），
不用猜。它同时会把每次启动的情况记在：~/Library/Logs/SolunaCal.log

七、更新到新版本（不用删旧版）
----------------------------------
先别退出 App。直接双击新的安装包（.dmg），挂载完成后：

  · 屏幕上会弹「发现新版本 x.y.z」→ 点「立即更新」
  · App 自己退出、替换、重新打开，约 5 秒
  · 生日和设置都保留

没弹窗的话：右键点菜单栏图标 → 「检查更新…」

为什么不能像普通软件那样「双击就装完」：这个软件没有 Apple 的付费开发者签名
（一年 99 美元），系统会拦住安装包里任何可执行的东西（安装器、脚本都会拦）。
所以更新的动作只能交给已经装好、你已经放行过的 App 自己完成。

八、不想要了 / 想卸载重装
--------------------------
它没有 Dock 图标，删之前必须先把程序退出，否则系统会提示「不能移到废纸篓，因为它已打开」。
两个退出办法，任选一个：

  1) 点菜单栏上的日期 → 设置（齿轮） → 拉到最下面 → 点「退出 SolunaCal」
  2) 右键点菜单栏上的 SolunaCal 图标 → 退出 SolunaCal
     （找不到菜单栏图标时：打开「活动监视器」，搜 SolunaCal，选中后点左上角 ⓧ 强制退出）

退出后，把「应用程序」里的 SolunaCal 拖进废纸篓即可，不留后台残留。
（想连日志一起清掉：删掉 ~/Library/Logs/SolunaCal.log）

九、系统要求
------------
macOS 14 Sonoma 或更新（15 Sequoia、26 都可以）。
Intel 芯片和 Apple 芯片（M1/M2/M3/M4）都能装，同一个安装包。
EOF

# 6. 打 DMG（UDZO 压缩，-ov 直接覆盖同名产物）+ 校验可挂载
mkdir -p "$DIST"
hdiutil create -volname "SolunaCal" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | tail -1
# 注意：不能写成 `hdiutil verify "$DMG" >/dev/null && echo OK`。
# `set -e` 不会因为 && 左边的命令失败而退出，校验失败会被静默跳过，
# 结果就是一个可能损坏的 DMG 被当成成功产物（2026-10-21 实测到 verify 报
# 「资源暂时不可用」但脚本照样打印「== 产物 ==」）。这里显式判定。
if ! hdiutil verify "$DMG" >/dev/null; then
    echo "!! DMG 校验失败：$DMG"
    exit 1
fi
echo "DMG 校验 OK"
echo "== 产物 =="
ls -lh "$DMG"
shasum -a 256 "$DMG"
