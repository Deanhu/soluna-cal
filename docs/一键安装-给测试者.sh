#!/bin/sh
# SolunaCal 一键安装 + 自检（给测试者用）
# 用法：整段贴进「终端」回车。默认装到 /Applications。
# 调试时可指定目标目录：sh 本脚本 <目标目录>

DEST="${1:-/Applications}"
APP="$DEST/SolunaCal.app"
VOL="/Volumes/SolunaCal"

say() { printf '\n=== %s ===\n' "$1"; }

say "0. 找安装包"
DMG=$(ls -t "$HOME/Downloads"/SolunaCal-*.dmg "$HOME/Desktop"/SolunaCal-*.dmg 2>/dev/null | head -1)
if [ -z "$DMG" ]; then
    echo "没在「下载」或「桌面」找到 SolunaCal-*.dmg"
    echo "请先把安装包下载到「下载」文件夹，再重跑这条命令。"
    exit 1
fi
echo "找到：$DMG"

say "1. 挂载"
hdiutil attach "$DMG" -nobrowse -readonly >/dev/null || { echo "挂载失败"; exit 1; }
[ -d "$VOL/SolunaCal.app" ] || { echo "挂载后没看到应用，中止"; exit 1; }
echo "已挂载到 $VOL"

say "2. 关掉可能在跑的旧版本"
if pkill -x SolunaCal 2>/dev/null; then echo "已退出旧进程"; else echo "没有旧进程在跑"; fi
sleep 1

say "3. 复制到 $DEST"
if [ ! -w "$DEST" ]; then
    echo "没有写入权限：$DEST"; hdiutil detach "$VOL" -quiet; exit 1
fi
# 旧版本不直接删，挪进废纸篓，误操作还能捞回来
if [ -d "$APP" ]; then
    STAMP=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$HOME/.Trash"
    if mv "$APP" "$HOME/.Trash/SolunaCal-旧版-$STAMP.app" 2>/dev/null; then
        echo "旧版本已移入废纸篓（SolunaCal-旧版-$STAMP.app）"
    else
        rm -rf "$APP" && echo "旧版本已删除"
    fi
fi
cp -R "$VOL/SolunaCal.app" "$DEST/" && echo "已复制"

say "4. 卸载映像"
hdiutil detach "$VOL" -quiet && echo "已卸载"

say "5. 清除隔离标记"
xattr -cr "$APP" && echo "完成"

say "6. 启动"
open "$APP" && echo "已启动，等 6 秒让菜单栏项建出来"
sleep 6

say "7. 自检"
"$APP/Contents/MacOS/SolunaCal" --selfcheck

say "8. 启动日志（最近 8 行）"
tail -8 "$HOME/Library/Logs/SolunaCal.log" 2>/dev/null || echo "（还没有日志）"

say "完成"
echo "右上角菜单栏应出现：月牙圆图标 + 今天的日期（例：10月20日 周二）"
echo "把以上内容整段复制发回即可。"
