#!/bin/bash
# 双击本文件：把 dist/余民.app 复制到桌面，并去掉隔离属性。
# 也可以手动把 dist/余民.app 拖到桌面，效果一样。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/dist/余民.app"
DST_DIR="${1:-$HOME/Desktop}"
DST="$DST_DIR/余民.app"

if [ ! -d "$SRC" ]; then
	echo "找不到 $SRC"
	read -r -p "按回车关闭…" _
	exit 1
fi
mkdir -p "$DST_DIR" || exit 1
rm -rf "$DST"
if cp -R "$SRC" "$DST"; then
	xattr -dr com.apple.quarantine "$DST" 2>/dev/null
	echo "已安装到：$DST"
	open -R "$DST" 2>/dev/null
	osascript -e 'display notification "双击桌面上的「余民」即可开玩" with title "安装完成"' >/dev/null 2>&1
else
	echo "复制失败：可能需要在系统设置 → 隐私与安全性 → 文件中允许终端访问桌面。"
	echo "也可以手动把 dist/余民.app 拖到桌面。"
fi
read -r -p "按回车关闭…" _
