#!/bin/sh
# os-nxova-xray 手动打包脚本（不走 OPNsense make package 框架）
#
# 为什么手动打包：
# OPNsense 的 make package 框架会在 +MANIFEST 里写入大量 annotations
# （product_id、product_version 等），而 pkg 2.4.x 生成的这种 manifest
# 在 pkg 2.3.1（OPNsense 26.7 自带）上安装时会 segfault
# （FreeBSD bug #290959，崩在 sqlite3 写 manifestdigest 时）。
# 手写极简 manifest（参考 nxovaeng/opn-box 的做法）可避开此问题。
#
# 执行环境：FreeBSD 15.0（vmactions/freebsd-vm），由 .github/workflows/build.yml 调用。
# 产物：autobuild/dist/（os-nxova-xray-*.pkg + pkg repo 元数据 + index.html）
set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

echo ">>> [0/4] 安装 python3（用于生成 manifest）..."
pkg update -f
pkg install -y python3

PLUGIN_DIR="$REPO_ROOT/net/nxova-xray"
SRC_DIR="$PLUGIN_DIR/src"

# 版本号：1.YYYYMMDDHHMM（UTC），必须每次递增否则 pkg upgrade 不认
PKG_VERSION="1.$(date -u +%Y%m%d%H%M)"
echo ">>> 包版本: $PKG_VERSION"

echo ">>> [1/4]  staging 文件..."
STAGE=/tmp/nxova-xray-stage
rm -rf "$STAGE"
mkdir -p "$STAGE/usr/local"
cp -a "$SRC_DIR/etc" "$STAGE/usr/local/"
cp -a "$SRC_DIR/opnsense" "$STAGE/usr/local/"
# 注意：不要生成 /usr/local/opnsense/version/nxova-xray
# OPNsense 通过 pkg 数据库跟踪插件版本，手动生成 version 文件
# 会导致 firmware resync 报 "Ignoring invalid metadata"

# 脚本需要可执行权限（git 里可能是 660，cp -a 会原样保留）
chmod 755 "$STAGE/usr/local/opnsense/scripts/xray/"*.py

# 生成 plist（相对 /usr/local 的文件列表）
PLIST=/tmp/nxova-xray-plist
(cd "$STAGE/usr/local" && find . -type f | sed 's|^\./||' | sort) > "$PLIST"
echo ">>> 文件数: $(wc -l < "$PLIST")"

echo ">>> [2/4] 生成极简 manifest（无 annotations）..."
# 用 python 做转义，避免 shell 引号地狱
python3 - "$PLUGIN_DIR" "$PKG_VERSION" << 'PYEOF'
import sys

plugin_dir = sys.argv[1]
pkg_version = sys.argv[2]

def ucl_escape(s):
    # UCL 双引号字符串转义
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')

with open(f"{plugin_dir}/+POST_INSTALL") as f:
    post_install = f.read()
with open(f"{plugin_dir}/+PRE_DEINSTALL") as f:
    pre_deinstall = f.read()

manifest = f'''name: os-nxova-xray
version: "{pkg_version}"
origin: opnsense/os-nxova-xray
comment: "Xray-core web management interface"
desc: "Web management interface for xray-core on OPNsense."
maintainer: "nxovazro"
www: "https://opnsense.org/"
prefix: /usr/local
categories: [net]
abi: "FreeBSD:15:amd64"
arch: "freebsd:15:x86:64"
deps: {{
    xray-core: {{
        origin: "security/xray-core",
        version: "26.7.28_1"
    }}
}}
scripts: {{
    post-install: "{ucl_escape(post_install)}",
    pre-deinstall: "{ucl_escape(pre_deinstall)}"
}}
'''

with open('/tmp/nxova-xray-manifest.ucl', 'w') as f:
    f.write(manifest)
print("manifest written")
PYEOF

echo ">>> [3/4] pkg create 打包..."
DIST="$REPO_ROOT/autobuild/dist"
rm -rf "$DIST"
mkdir -p "$DIST"
pkg create -M /tmp/nxova-xray-manifest.ucl -p "$PLIST" -r "$STAGE" -o "$DIST"
ls -la "$DIST"

echo ">>> [4/4] 生成仓库元数据和索引页..."
(cd "$DIST" && pkg repo .)
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
