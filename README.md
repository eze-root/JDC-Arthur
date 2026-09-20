# JDC-Arthur：京东云亚瑟 OpenWrt 固件

本项目为 **JDCloud RE-SS-01（亚瑟 / AX1800 Pro）** 定制 LiBwrt/OpenWrt。当前构建源为 `LiBwrt/LibWrt:25.12-nss`，目标为 `qualcommax/ipq60xx`、设备 `jdcloud_re-ss-01`，不适用于其他京东云型号。

共同默认值：LAN 管理地址 `192.168.1.1`，WAN 使用 DHCP，LuCI 保留 PPPoE 配置入口但不默认拨号。WAN 入站默认拒绝，管理入口只放在 LAN。全新、不保留配置的安装可直接从有线 LAN 获取 DHCP；无线驱动和配置页已包含，但不会发布一个人人都知道的默认 Wi-Fi 密码，首次登录后需自行设置 SSID/密码并启用无线。私人节点、订阅 URL、证书和 JSON 不进入源码或公开固件。

## 三套固件

| 固件 | 发布标签 | 客户端网络 | sing-box |
| --- | --- | --- | --- |
| 基础版 | `IPQ60XX-JD1800-6.12-WIFI` | DHCPv4 + IPv6；有前缀时下发前缀，否则尝试 RA/DHCPv6/NDP relay | 不包含 |
| sing-box IPv4 客户端版 | `IPQ60XX-JD1800-6.12-SINGBOX-IPV4` | 客户端只使用 IPv4；路由器自身仍保留 IPv4/IPv6，可连接 IPv6-only 节点 | IPv4 TCP/UDP TProxy |
| sing-box 双栈客户端版 | `IPQ60XX-JD1800-6.12-SINGBOX-DUALSTACK` | 客户端 IPv4/IPv6 | IPv4 和 IPv6 TCP/UDP TProxy |

两套代理固件默认启用一个**直连配置**。CI 固定下载并校验 SagerNet 官方 `v1.13.21` 的 OpenWrt 核心，首次启动后从 `/mnt/mmcblk0p27/sing-box/bin/sing-box` 运行；活动配置和状态也保存在该数据分区。

可在刷机后设置 HTTPS 配置 URL。开机更新器会等待网络、限时重试、用当前核心检查 JSON、原子替换并重启；启动失败会恢复旧配置。也可以通过 SCP 上传 JSON 后用 `singbox-install-config` 导入。具体命令见 [sing-box 配置与恢复](docs/devs/singbox-tproxy.md)。

## 编译入口

| GitHub Actions 工作流 | 配置 | 产物 |
| --- | --- | --- |
| `JDC1800-6.12-WIFI` | `configs/0-jd1800.config` | 基础版 |
| `JDC1800-6.12-WIFI-SINGBOX` | `configs/0-jd1800-tproxy.config` | matrix 同时构建 IPv4 客户端版和双栈客户端版 |

在 [Actions](https://github.com/eze-root/JDC-Arthur/actions) 手动运行对应工作流；默认从该次运行的 Artifacts 下载固件和 `sha256sums`。只有在手动运行时勾选 `publish_release`，构建才会同步发布到 [Releases](https://github.com/eze-root/JDC-Arthur/releases)。源码及 feeds 跟随上游分支，不同日期构建可能使用不同版本；产物中的 `source-commit.txt`、`build.config` 和 `sing-box-core.txt` 用于追溯。

本地回归检查：

```sh
node --test tests/singbox.test.mjs
```

Linux CI 还会在独立网络命名空间中检查真实 nftables 语法，并检查 Lua、构建选项和文档。完整固件编译及目标机转发仍需由工作流和实机验证。

## 文档

- [连接、存储、升级和实机验收](docs/devs/arthur-operations.md)
- [sing-box 配置、更新、重启和恢复](docs/devs/singbox-tproxy.md)
- [三个固件档位的设计记录](docs/devs/firmware-profiles-plan.md)
- [刷机前确认与旧教程说明](docs/devs/tutorial.md)

刷机前必须再次核对 `ubus call system board`、镜像类型和校验值。已经运行 OpenWrt 的设备通常只需要匹配的 sysupgrade 镜像，不需要重刷 U-Boot；优先对第一版做不保留旧配置的升级，避免旧网络、防火墙和代理规则覆盖新档位默认值。
