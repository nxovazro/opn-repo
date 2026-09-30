# os-xray —— OPNsense 26.7 的 xray-core Web 管理插件

[![build](https://github.com/nxovazro/opn-repo/actions/workflows/build.yml/badge.svg)](https://github.com/nxovazro/opn-repo/actions/workflows/build.yml)

为 OPNsense 26.7 适配的 `os-xray` 插件：提供 xray-core 的 Web 管理界面。
配置存 OPNsense 标准 `config.xml`（经 MVC 模型 `OPNsense/Xray`），支持入站编辑、
出站管理（含订阅与分享链接导入）、带优先级的路由编辑器、DNS 分流、
geosite.dat 分类提取 + 常用分类下拉多选。

## 架构

```
config.xml  (//OPNsense/xray)          派生数据（不进备份）
  general / inbounds / outbounds /       /usr/local/etc/xray/ui/sub/<uuid>.json
  subscriptions / routing / dns            订阅节点缓存，一订一文件，原子替换
        │ apply (configd: xray reconfigure) │
        ▼
/usr/local/etc/xray/conf.d/
  00-base.json  10-inbounds.json  20-outbounds.json  30-routing.json  40-dns.json
        │ xray run -test 校验后重启服务
```

- **存储**：`settings` / `streamSettings` / `sniffing` 等协议专属嵌套配置存为
  转义 JSON 文本（config.xml 里人类可读）；字符串列表（domain / ip / …）存为 JSON 数组文本。
- **订阅节点**是派生数据：`subscription.py` 同步后写 `ui/sub/<uuid>.json`，
  apply 时与手工出站合并（手工优先，tag 冲突自动改名并提示）。
- **DNS**：启用后自动生成 `dns-in`（dokodemo-door）入站 + `dns` 出站 + 首条路由规则。
- 固定路径：xray `/usr/local/bin/xray`，confdir `/usr/local/etc/xray/conf.d`，
  dat 资源 `/usr/local/etc/xray/`。

## 依赖

- OPNsense 26.7，`PLUGIN_DEPENDS=xray-core`（官方源自带 `xray-core-26.7.28_1`）。

## 页面

VPN → Xray：General / Inbound / Outbound（含订阅）/ Routing / DNS / Geosite。

## 设计文档

详见 `~/workspace/your_files/os-xray-config.xml-存储设计.md`（含 config.xml 完整结构、
字段表、实现备注）。
