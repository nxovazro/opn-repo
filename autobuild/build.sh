#!/bin/sh
# os-nxova-xray 自动构建脚本
#
# 执行环境：FreeBSD 15.1（与 OPNsense 26.7 同基线），由 .github/workflows/build.yml
# 经 vmactions/freebsd-vm 调用；也可以在任意 FreeBSD 15.x 上手动执行：
#     sh autobuild/build.sh
#
# 产物：autobuild/dist/（os-nxova-xray-*.pkg + pkg repo 元数据 + index.html），
# workflow 会把它发布到 GitHub Pages。
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

echo ">>> [1/4] 安装构建依赖 (xray-core, 满足 PLUGIN_DEPENDS 检查)..."
pkg update -f
pkg install -y xray-core

echo ">>> [2/4] 构建 os-nxova-xray 包 (make -C net/nxova-xray package)..."
# PLUGIN_VERSION 必须每次递增，否则 pkg upgrade 会认为已是最新而不升级。
# 用 UTC 日期时间生成版本：1.YYYYMMDDHHMM
PKG_VERSION="1.$(date -u +%Y%m%d%H%M)"
echo ">>> 包版本: $PKG_VERSION"
make -C net/nxova-xray package PLUGIN_VERSION="$PKG_VERSION"

echo ">>> [3/4] 生成 pkg 仓库元数据..."
DIST="$REPO_ROOT/autobuild/dist"
rm -rf "$DIST"
mkdir -p "$DIST"
cp net/nxova-xray/work/pkg/*.pkg "$DIST/"
(cd "$DIST" && pkg repo .)

echo ">>> [4/4] 生成索引页..."
PKGFILE=$(ls "$DIST"/os-nxova-xray-*.pkg | head -n 1)
PKGBASE=$(basename "$PKGFILE")
BUILDDATE=$(date -u "+%Y-%m-%d %H:%M UTC")
cat > "$DIST/index.html" <<EOF
<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>os-nxova-xray pkg 仓库</title></head>
<body style="font-family:sans-serif;max-width:720px;margin:2em auto;">
<h2>os-nxova-xray pkg 仓库（nxova-opn）</h2>
<p>构建时间：$BUILDDATE ｜ 包：<a href="$PKGBASE">$PKGBASE</a></p>
<h3>在 OPNsense 上使用</h3>
<p>新建 <code>/usr/local/etc/pkg/repos/nxova-opn.conf</code>：</p>
<pre>nxova-opn: {
  url: "https://nxovazro.github.io/opn-repo",
  enabled: yes
}</pre>
<p>然后执行：<code>pkg update -r nxova-opn &amp;&amp; pkg install -y os-nxova-xray</code></p>
<p style="color:#666"><small>仓库未签名；包依赖的 xray-core 由 OPNsense 官方源提供。</small></p>
</body></html>
EOF

echo ">>> 完成，产物在 $DIST:"
ls -la "$DIST"
