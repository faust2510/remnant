#!/bin/bash
# 双击本文件：把 余民.app 复制到桌面（一次性安装）。
# 也可以手动把本目录里的 dist/余民.app 拖到桌面，效果完全一样。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/dist/余民.app"
DST_DIR="${1:-$HOME/Desktop}"
DST="$DST_DIR/余民.app"
mkdir -p "$DST_DIR" 2>/dev/null || true

if [ ! -d "$SRC" ]; then
	printf '找不到 %s\n' "$SRC"
	printf '按回车关闭…'; read -r _
	exit 1
fi

# 已有旧版就先清掉（.app 是整包替换，不做增量）
if [ -e "$DST" ]; then
	printf '发现桌面已有旧版，先移除…\n'
	rm -rf "$DST" 2>/dev/null || true
fi

if cp -R "$SRC" "$DST" 2>/dev/null; then
	xattr -cr "$DST" 2>/dev/null || true
	printf '已安装到：%s\n' "$DST"
	printf '双击桌面上的「余民」即可开玩；第一次打开若被拦，右键 → 打开。\n'
	open -R "$DST" 2>/dev/null || true
	osascript -e 'display notification "双击桌面上的「余民」即可开玩" with title "安装完成"' >/dev/null 2>&1 || true
else
	printf '\n复制被系统拦住了（终端没有桌面写入权限）。三种办法任选其一：\n'
	printf '  1) 系统设置 → 隐私与安全性 → 文件与文件夹 → 给「终端」勾上「桌面文件夹」，然后再双击本文件；\n'
	printf '  2) 打开 Finder，把 %s 直接拖到桌面；\n' "$SRC"
	printf '  3) 右键 dist/余民.app → 制作替身，把替身拖到桌面。\n'
	open -R "$SRC" 2>/dev/null || true
fi
printf '按回车关闭…'
read -r _