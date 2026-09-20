# sing-box：配置、更新、重启与恢复

本页只适用于 `singbox-ipv4` 和 `singbox-dualstack` 两个固件 profile。公开固件不含节点、订阅 URL、证书或私人 JSON。

## 1. 默认状态

刷机后服务已启用，使用可运行的直连配置：

| profile | 活动模板 | LAN 接管 |
| --- | --- | --- |
| `singbox-ipv4` | `/usr/share/singbox/direct-ipv4.json` | IPv4 TCP/UDP |
| `singbox-dualstack` | `/usr/share/singbox/direct-dualstack.json` | IPv4 和 IPv6 TCP/UDP |

运行文件位于数据分区：

| 内容 | 路径 |
| --- | --- |
| 运行核心 | `/mnt/mmcblk0p27/sing-box/bin/sing-box` |
| 活动 JSON | `/mnt/mmcblk0p27/sing-box/config/config.json` |
| 状态和缓存 | `/mnt/mmcblk0p27/sing-box/state` |

固件包含固定版本的 `/usr/bin/sing-box` 作为兼容种子；首次启动只复制一次，实际服务运行数据分区副本。该种子由 CI 从 SagerNet 官方 `v1.13.21` 的 `sing-box_1.13.21_openwrt_aarch64_cortex-a53.ipk` 中提取，下载附件必须匹配 SHA-256 `104e2541d4380e5bc97feae860cd2af9a1817eba2d75304c779b04a788047f6a`。构建不会安装 sing-box feeds 包，也不会在设备上通过 APK/IPK 包管理器安装核心。SagerNet 通用 Linux arm64 包依赖 glibc，不能用于本机 musl 系统。

本项目服务明确读取 `/etc/config/singbox`（没有连字符）以及上表的数据分区路径。官方附件只用于提取核心，其示例配置不会写入固件。

先检查：

```sh
df -h /mnt/mmcblk0p27
mount | grep ' /mnt/mmcblk0p27 '
/mnt/mmcblk0p27/sing-box/bin/sing-box version
/etc/init.d/sing-box check
/etc/init.d/sing-box status
```

数据盘必须是 `/dev/mmcblk0p27` 以可写 ext4 挂载到 `/mnt/mmcblk0p27`。检查失败时服务保持直连网络，不会向空挂载点写入 overlay。

## 2. 常用服务命令

```sh
/etc/init.d/sing-box start
/etc/init.d/sing-box stop
/etc/init.d/sing-box restart
/etc/init.d/sing-box status
/etc/init.d/sing-box check
logread -e sing-box
logread -e singbox
logread -e singbox-run
```

procd 管理前台包装程序。核心异常退出后，包装程序先清理本项目的 TProxy 规则，默认等待 30 秒再重试。正常停止期间流量恢复直连；当前设计没有 kill switch。

检查接管状态：

```sh
ss -4 -lntup | grep -E ':9898\\b'
nft list table inet singbox_tproxy
ip -4 rule show
ip -4 route show table 100
```

双栈版还要检查：

```sh
ss -6 -lntup | grep -E ':9899\\b'
ip -6 rule show
ip -6 route show table 100
```

包装程序只有在 IPv4 端口 9898（以及双栈版 IPv6 端口 9899）的 TCP、UDP 监听都属于当前 sing-box PID 后，才创建 nftables 和策略路由。mark 为 100，路由表为 100，优先级为 10000；发现与其他 PBR/代理冲突会拒绝启动。

## 3. 手工导入私人 JSON

配置必须与所选 profile 的监听匹配。IPv4 版至少提供 `0.0.0.0:9898` 的 TProxy TCP/UDP 入站；双栈版还需提供 `[::1]:9899`。不指定 inbound 的 `network` 可同时监听 TCP 和 UDP。

将文件上传到 RAM 临时目录，例如 `/tmp/singbox-upload.json`，然后运行：

```sh
singbox-install-config /tmp/singbox-upload.json
rm -f /tmp/singbox-upload.json
/etc/init.d/sing-box check
/etc/init.d/sing-box restart
/etc/init.d/sing-box status
```

`singbox-install-config` 用当前运行核心校验候选文件，再以 0600 权限原子替换活动 JSON。校验失败会保留旧配置，导入命令本身不会自动重启。

需要看详细解析错误时：

```sh
/mnt/mmcblk0p27/sing-box/bin/sing-box check \
  -D /mnt/mmcblk0p27/sing-box/state \
  -c /mnt/mmcblk0p27/sing-box/config/config.json
```

错误输出可能包含私人域名或节点信息，不要贴到公开 issue 或构建日志。

## 4. 通过 HTTPS URL 更新

推荐在 LuCI“服务 → Sing-box”填写 URL。CLI 等价操作：

```sh
uci set singbox.main.config_url='https://example.invalid/private/config.json'
uci set singbox.main.update_on_boot='1'
uci commit singbox
singbox-update-config
```

URL 只允许 HTTPS，可能含私人 token，只保存在路由器 UCI。开机服务默认尝试 6 次、间隔 30 秒；单次连接/下载超时 30 秒，最大文件 4 MiB。这些值可在 LuCI 或 `/etc/config/singbox` 修改。

更新流程：

1. 确认数据盘和当前核心可用。
2. HTTPS 下载到 `/tmp`，限制协议、时间和大小。
3. 用当前核心检查候选 JSON。
4. 备份旧配置、原子替换并重启服务。
5. 最多等待 20 秒确认服务运行；失败则恢复旧配置并再次启动。

校园网尚未网页认证、系统时间未同步或 DNS 不通时，下载会失败，旧配置继续使用。配置 URL 为空时，开机更新器直接退出，默认 direct 配置继续运行。

## 5. 安装已验证的新核心

常规升级应重新构建固件，使核心和配置功能匹配。确实需要单独更新时，先在电脑上获得**适用于当前 OpenWrt、aarch64、musl** 的可执行文件，上传到 `/tmp/sing-box.new`：

```sh
chmod 755 /tmp/sing-box.new
singbox-install-core /tmp/sing-box.new
rm -f /tmp/sing-box.new
```

安装器先执行候选核心的 `version`，备份旧核心、原子安装并重启；服务未能运行时恢复旧核心。不要仅凭文件名中的 “linux-arm64” 判断兼容性。

## 6. IPv4 与双栈边界

`singbox-ipv4` 关闭 LAN 的 RA、DHCPv6、NDP 和前缀分配，但保留路由器 WAN6。升级到该 profile 后，应让客户端断开重连，确认旧全局 IPv6 地址和默认路由已经消失。

`singbox-dualstack` 使用 odhcpd hybrid 模式：上游提供 PD 时在 LAN 服务；没有 PD 时尝试 RA/DHCPv6/NDP relay。TProxy 接管公网 IPv6 TCP/UDP，同时放行链路本地、ULA、多播、DHCPv6、邻居发现和其他 ICMPv6，避免破坏地址配置与 PMTU。

当前 TProxy 只处理从配置的 LAN bridge 进入的 TCP/UDP；路由器自身发起的流量、ICMP 和普通 AP 桥接流量不在接管范围。sing-box 访问代理节点不会再次进入 LAN TProxy，因此不会形成出口循环。

TUN 模式保留为高级运行选项，路由、DNS 和清理由私人 JSON 负责。切换前必须按当前核心版本配置 `auto_route`、`auto_redirect`、出口探测和排除项，并停用其他透明代理；本项目的两个默认 direct JSON 是 TProxy 配置，不能直接切到 TUN。

## 7. 故障恢复

立即停用透明代理并回到普通直连：

```sh
uci set singbox.main.enabled='0'
uci commit singbox
/etc/init.d/sing-box stop
/etc/sbox/sbox_tproxy_stop.sh
```

恢复默认 direct 配置：

```sh
profile=$(cat /etc/arthur-profile)
case "$profile" in
  singbox-ipv4) template=/usr/share/singbox/direct-ipv4.json ;;
  singbox-dualstack) template=/usr/share/singbox/direct-dualstack.json ;;
  *) exit 1 ;;
esac
singbox-install-config "$template"
uci set singbox.main.enabled='1'
uci commit singbox
/etc/init.d/sing-box restart
```

数据分区保留配置时，恢复出厂设置未必会删除它。需要彻底重置私人配置时，先停止服务并备份，再只删除 `/mnt/mmcblk0p27/sing-box/config/config.json`；下次启动会重新安装对应 direct 模板。

## 8. 当前实机调试记录（2026-09-20）

当前 JDCloud RE-SS-01 实机运行 SagerNet 官方 `v1.13.21` OpenWrt/musl `aarch64_cortex-a53` 核心，核心、活动配置和状态均位于 `/mnt/mmcblk0p27/sing-box`。通用 Linux arm64 包依赖 glibc，不适用于该 musl 系统；实机和固件构建均使用官方 OpenWrt 附件中提取的核心。

用户配置已从 TUN 改为双栈 TProxy，服务模式为主路由 `singbox-dualstack`。实际执行 `/etc/init.d/sing-box restart` 后，进程、IPv4/IPv6 监听、nftables 表和两套策略路由均能恢复。LAN 客户端的 IPv6 HTTPS 请求已确认经配置中的日本 IPv6 节点访问公网。

私人 JSON、节点、订阅 URL 和证书只保存在路由器数据分区及本地忽略目录，不写入源码、构建日志或公开固件。当前配置地址使用 HTTP，因此只做了手工导入；开机自动更新仍要求 HTTPS。

用于调试的 Windows 有线接口当时保留了旧静态地址 `192.168.1.10`，而当前路由器 LAN 是 `192.168.13.1/24`，所以尚未完成该客户端的 IPv4 TProxy 实测。将有线 IPv4 改回 DHCP 后再检查 IPv4 TCP、UDP 和 DNS 接管。

## 官方参考

- [sing-box TProxy 入站](https://sing-box.sagernet.org/configuration/inbound/tproxy/)
- [sing-box TUN 入站](https://sing-box.sagernet.org/configuration/inbound/tun/)
- [OpenWrt procd init scripts](https://openwrt.org/docs/guide-developer/procd-init-scripts)
- [OpenWrt odhcpd](https://openwrt.org/docs/techref/odhcpd)
