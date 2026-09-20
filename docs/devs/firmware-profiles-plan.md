# 三套固件设计与实机记录

更新：2026-09-20。

## 已确定的设计

三套固件均面向 `jdcloud,re-ss-01`。WAN 默认是 DHCP 客户端；`luci-proto-ppp` 保留 PPPoE 配置入口，但不会自动拨号。LAN 保留 DHCPv4、DNS、Wi-Fi AP 支持和防火墙，默认管理地址是 `192.168.1.1`。全新安装从有线 LAN 配置 Wi-Fi；项目不嵌入公开通用的无线密码。

| profile | 用途 | LAN IPv6 | 路由器自身 IPv6 | 透明代理 |
| --- | --- | --- | --- | --- |
| `base` | 普通主路由 | 开启；有 PD 时下发前缀，没有 PD 时使用 odhcpd hybrid relay | 开启 | 无 |
| `singbox-ipv4` | 只让客户端使用 IPv4 的代理主路由 | 关闭 RA、DHCPv6、NDP 和 LAN 前缀分配 | 开启，可连接 IPv6-only 节点 | IPv4 TCP/UDP 与 53 端口 |
| `singbox-dualstack` | IPv4/IPv6 都进入代理的主路由 | 开启 hybrid server/relay | 开启 | IPv4、IPv6 TCP/UDP 与 53 端口 |

“客户端 IPv4”只限制 LAN 客户端。WAN6 始终保留，避免 IPv6-only 代理节点不可达。关闭客户端 IPv6 不能只关 DHCPv6，因此 IPv4 profile 同时关闭 RA、NDP relay 和 `ip6assign`；客户端升级后还需重新连接网络或等待旧地址失效。

第三套最终采用双栈代理主路由，不采用普通 AP/旁路由。普通 AP 中客户端网关是上级路由器，三层流量不会自动经过亚瑟，当前 TProxy 方案无法保证接管。

## sing-box 启动模型

两个 sing-box profile 使用相同的软件包配置和不同的首次启动参数：

1. `/dev/mmcblk0p27` 自动挂载到 `/mnt/mmcblk0p27`。
2. CI 从 SagerNet 官方 `v1.13.21` OpenWrt `aarch64_cortex-a53` 附件提取并校验核心；固件中的 `/usr/bin/sing-box` 首次复制到 `/mnt/mmcblk0p27/sing-box/bin/sing-box`。
3. IPv4 profile 安装 `direct-ipv4.json`；双栈 profile 安装 `direct-dualstack.json`。
4. 包装程序确认对应 TCP、UDP 监听属于当前核心之后，才安装 nftables 和策略路由。
5. 核心退出或服务停止时，先删除本项目的 nftables 表，再精确删除自己创建的 IPv4/IPv6 rule 和 route。
6. procd 在异常退出后延迟 30 秒重试；数据盘未挂载、配置无效或监听缺失时不接管 LAN 流量。

默认 direct 配置用于安全启动和调试，不包含节点。设置 HTTPS `config_url` 后，开机更新器限时下载、限制文件大小、校验、原子替换并重启；新配置起不来时恢复旧配置。

## 已确认的硬件与网络

- board：`jdcloud,re-ss-01`；架构 aarch64；当前内核 6.12.35。
- 当前系统：LibWrt SNAPSHOT `r0-1839348`，当前 LAN 地址 `192.168.13.1`。
- LAN 链路本地管理地址：`fe80::ded8:7cff:fe5a:606f%19`。旧的 `...:6070` 是 WAN 侧地址，接线调整后不再作为 LAN SSH 地址。
- `/dev/mmcblk0p27` 为可写 ext4，挂载点 `/mnt/mmcblk0p27`，约 54.9 GiB，总空闲约 52 GiB；overlay 约 36 MiB。
- 硬件 watchdog 正在运行，超时 30 秒。
- WAN 接校园/单位网络，已获得 `10.132.40.16/22`、网关 `10.132.40.1`、DNS `192.0.0.33/34` 和全局 IPv6；上游需要网页认证，认证前不能把 DNS/公网失败归因于固件。
- 官方通用 Linux arm64 二进制依赖 glibc，在 OpenWrt/musl 上不能执行。实机已验证 SagerNet 官方 `v1.13.21` 的 OpenWrt/musl `aarch64_cortex-a53` 核心；固件固定使用同一附件和 SHA-256，不依赖 feeds sing-box 版本。

## 仍需完成的实机验收

CI 和本地测试只能验证配置、回滚和规则生成。固件构建完成后仍要在设备上依次验证：

1. 基础版 DHCP、校园认证、IPv4、IPv6 PD/relay、Wi-Fi 和 PPPoE 配置入口。
2. 两个代理版的数据盘自动挂载、核心复制、direct 配置、重启和断电重启。
3. IPv4 profile 的客户端没有可绕过代理的 IPv6 默认路径。
4. 双栈 profile 的 IPv4/IPv6 TCP、UDP、DNS 都被接管，ICMPv6/邻居发现/PMTU 正常。
5. 配置 URL 在未认证、时钟未同步、下载失败、JSON 无效及新服务失败时保持旧配置。
6. 最后再导入用户真实配置，测试 IPv6-only 节点、分流、吞吐、温度和内存。
