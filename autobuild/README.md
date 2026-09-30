# autobuild —— os-nxova-xray 自动构建

push 到 `main`（改动 `net/nxova-xray/`、`autobuild/` 或 workflow 本身）或在 Actions 页手动
触发后，`.github/workflows/build.yml` 会：

1. 在 `vmactions/freebsd-vm`（FreeBSD 15.1，与 OPNsense 26.7 同基线）里执行
   `autobuild/build.sh`：装 `xray-core` → `make -C net/nxova-xray package` →
   `pkg repo` 生成仓库元数据 → 产物进 `autobuild/dist/`；
2. 把 `autobuild/dist/` 发布到 `gh-pages` 分支（GitHub Pages），形成可直接用的
   pkg 源：`https://nxovazro.github.io/opn-repo`。

## 首次启用（手动一次）

仓库 Settings → Pages → Build and deployment → Source 选 **Deploy from a branch**，
Branch 选 `gh-pages` / `/(root)`。之后每次构建自动更新。

## 在 OPNsense 上使用

新建 `/usr/local/etc/pkg/repos/nxova-opn.conf`：

```
nxova-opn: {
  url: "https://nxovazro.github.io/opn-repo",
  enabled: yes
}
```

然后 `pkg update -r nxova-opn && pkg install -y os-nxova-xray`。
包依赖的 `xray-core` 由 OPNsense 官方源提供。

## 本地构建

在 FreeBSD 15.x 上直接跑：

```
sh autobuild/build.sh
```

产物在 `autobuild/dist/`。发新版时改 `net/nxova-xray/Makefile` 的 `PLUGIN_VERSION`
再 push，Pages 上的包会自动更新。
