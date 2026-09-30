# opn-repo

个人 OPNsense 插件仓库（多插件结构），兼容 OPNsense 26.7。

构建框架（`Makefile`、`Mk/`、`Scripts/`、`Templates/`、`Keywords/`）取自
[mimugmail/opn-repo](https://github.com/mimugmail/opn-repo)（BSD 2-Clause），
插件目录布局遵循官方 [opnsense/plugins](https://github.com/opnsense/plugins) 规范：
每个插件位于 `<分类>/<插件名>/`，包含 `Makefile`、`pkg-descr` 与 `src/`。

## 插件列表

| 目录 | 包名 | 说明 |
|---|---|---|
| `net/xray` | `os-xray` | xray-core Web 管理：JSON 配置、入站编辑、出站订阅、带优先级的路由编辑器、geosite 分类提取 |

## 构建

在 OPNsense（或 FreeBSD）上：

```sh
git clone https://github.com/nxovazro/opn-repo.git
cd opn-repo

# 查看所有插件
make list

# 打包单个插件
make -C net/xray package
# 产物在 net/xray/work/pkg/*.pkg

# 安装
pkg add net/xray/work/pkg/os-xray-*.pkg
```

## 新增插件

1. 在对应分类下建目录，如 `net/myplugin/`（分类目录小写，如 `net`、`sysutils`、`security`、`www`、`dns`）。
2. 放入 `Makefile`（参考 `net/xray/Makefile`，以 `.include "../../Mk/plugins.mk"` 结尾）、`pkg-descr`、`src/`。
3. 根目录 `make list` 会自动发现新插件。
