# 亚瑟：连接、存储、升级与验收

## 1. 当前实机基线

2026-09-20 已从电脑直连 LAN、路由器 WAN 接校园/单位网络的拓扑完成只读检查。

| 项目 | 已确认值 |
| --- | --- |
| board | `jdcloud,re-ss-01` |
| 架构 / 内核 | aarch64 / 6.12.35 |
| 当前系统 | LibWrt SNAPSHOT `r0-1839348` |
| 当前 LAN IPv4 | `192.168.13.1` |
| LAN link-local | `fe80::ded8:7cff:fe5a:606f%19` |
| WAN IPv4 | `10.132.40.16/22`，网关 `10.132.40.1` |
| WAN DNS | `192.0.0.33`、`192.0.0.34` |
| WAN IPv6 | 已获得全局 `/64` 地址，可直接访问 IPv6 公网 |
| 数据分区 | `/dev/mmcblk0p27`，ext4，挂载到 `/mnt/mmcblk0p27` |
| 容量 | 约 54.9 GiB，总空闲约 52 GiB；overlay 约 36 MiB |
| watchdog | 已运行，timeout 30 秒 |

校园 WAN 的 IPv4 需要网页认证，IPv6 不需要。IPv4 认证前，上游 DNS 和 IPv4 公网探测失败不代表路由器的 DHCP 或 IPv6 配置错误；IPv6-only 节点可直接连接。

新固件的默认 LAN 是 `192.168.1.1`，与当前系统不同。刷机后电脑改回自动 DHCP，不要继续固定在 `192.168.13.0/24`。

## 2. 登录

电脑接 LAN 后优先使用 DHCP 获取地址，再访问 `http://192.168.1.1/`。当前旧系统可访问 `http://192.168.13.1/`。

IPv4 未知时可从 Windows 有线接口的 IPv6 邻居定位：

```powershell
Get-NetAdapter
Get-NetNeighbor -InterfaceIndex 19 -AddressFamily IPv6
ssh root@fe80::ded8:7cff:fe5a:606f%19
```

`%19` 是这台电脑当时的接口编号，换电脑或重新枚举后可能变化。链路本地地址只在同一二层链路有效。首次 SSH 应核对主机指纹；接线变化后不要把 WAN 地址 `...:6070` 当作 LAN 管理地址。

新固件提供只读诊断：

```sh
arthur-diagnose
```

它显示 board、内存、挂载、watchdog、接口、监听、服务状态和近期内核健康信号，不读取完整 UCI 或私人 JSON。

## 3. 数据分区

`files/etc/config/fstab` 将现有 `/dev/mmcblk0p27` 以 ext4、`rw,noatime` 挂载到 `/mnt/mmcblk0p27`。项目不会格式化、调整分区或把它设置成 extroot。

刷机后检查：

```sh
block info /dev/mmcblk0p27
mount | grep ' /mnt/mmcblk0p27 '
df -h /mnt/mmcblk0p27 /overlay
```

如果设备、文件系统或挂载点不匹配，先停用 sing-box 并排查，不要向空的 `/mnt/mmcblk0p27` 目录复制大文件。服务会核对 `/proc/mounts` 中的设备、挂载点、ext4 和 rw 标志，失败时不会把核心或配置写进小容量 overlay。

## 4. 网络档位

- WAN 默认为 DHCP；在 LuCI“网络 → 接口 → WAN → 修改 → 协议”可切换 PPPoE 并填写运营商账号。固件不预置账号。
- 基础版和双栈代理版使用 odhcpd hybrid IPv6：有上游 PD 时在 LAN 提供服务，没有 PD 时尝试 relay。
- IPv4 客户端代理版只关闭 LAN 客户端 IPv6；路由器的 `wan6` 仍为 DHCPv6，以便连接 IPv6-only 节点。
- LAN 和 WAN 必须使用不同 IPv4 子网。当前校园 WAN 的 `10.132.40.0/22` 与默认 LAN `192.168.1.0/24` 不冲突。
- 普通 AP 模式下客户端绕过亚瑟三层路由，不能保证 TProxy 接管，因此三个交付档位都按主路由拓扑设计。

校园认证建议先停用私人代理，使用 direct 配置打开认证页；认证成功、DNS 和时间同步后再测试 URL 更新。

## 5. watchdog 与服务恢复

| 故障 | 自动处理 |
| --- | --- |
| sing-box 配置、核心或数据盘不可用 | 不安装 TProxy；procd 延时重试 |
| 核心退出 | 先清理接管规则，30 秒后重启 |
| 新 URL 配置不能启动 | 恢复旧配置并重启 |
| 整机卡死且 PID 1 不再喂狗 | 当前硬件 watchdog 应在约 30 秒后复位 |
| 上游断网或校园认证失效 | 不重启整机，保留当前配置 |

进程仍存在但节点逻辑卡顿不能靠 PID 检测解决。真实配置可另行设计代理出口健康检查，但不能因单一网站超时反复重启路由器。

不要让第二个 watchdog 进程与 procd 争抢设备。破坏性 watchdog 验证应在现场、可断电恢复并已有备份的维护窗口进行。

## 6. 编译

基础版工作流使用 `configs/0-jd1800.config` 和 profile `base`。sing-box 工作流使用 `configs/0-jd1800-tproxy.config`，matrix 分别传入 `singbox-ipv4` 与 `singbox-dualstack`。

本地或 CI 的关键顺序：

```sh
./scripts/feeds update -a
./scripts/feeds install -a
sh scripts/prepare-arthur.sh "$OPENWRT_PATH" "$FIRMWARE_PROFILE"
sh scripts/install-official-sing-box.sh "$OPENWRT_PATH/files" # 仅代理工作流
cp "$CONFIG_FILE" "$OPENWRT_PATH/.config"
# 运行 diy-jd1800.sh
cd "$OPENWRT_PATH"
make defconfig
sh "$GITHUB_WORKSPACE/scripts/check-arthur-config.sh" \
  .config "$FIRMWARE_PROFILE" "$OPENWRT_PATH/files"
make -j"$(nproc)"
```

prepare 使用显式覆盖文件白名单，拒绝符号链接、额外 JSON 和已存在的目标 `files/`；base 会移除全部 sing-box 运行文件。checker 在 `make defconfig` 后确认设备、IPv6、PPPoE、ext4 和相应代理包仍被选中。

构建产物保留 `sha256sums`、`build.config`、`source-commit.txt`、`sing-box-core.txt`、profile 标识和操作文档。代理工作流固定下载并校验 SagerNet 官方 `v1.13.21` OpenWrt `aarch64_cortex-a53` 核心。手动运行工作流默认只上传 Actions Artifact；只有明确勾选 `publish_release` 才创建 GitHub Release。构建入口已从失效的 `LiBwrt/openwrt-6.x:main-nss` 迁到当前 `LiBwrt/LibWrt:25.12-nss`；源码及其他 feeds 仍跟随上游分支，稳定版本验收后再固定具体提交。

## 7. 升级

先下载与 `jdcloud_re-ss-01` 匹配的 sysupgrade 镜像并核对 SHA-256：

```sh
ubus call system board
sha256sum /tmp/firmware.bin
sysupgrade -T /tmp/firmware.bin
```

不要在检查失败后直接使用 `-F`。当前设备已经运行 OpenWrt，通常不需要重刷 U-Boot，也不要混用其他京东云型号或 factory 镜像。

第一版建议**不保留旧配置**升级，因为当前系统 LAN 地址、防火墙、DHCP 和旧代理设置可能覆盖新 profile。升级前分别备份：

1. 当前系统配置：`sysupgrade -b /tmp/system-backup.tar.gz`。
2. `/mnt/mmcblk0p27` 中需要保留的数据和私人 JSON。
3. 当前分区与挂载信息：`block info`、`cat /proc/mounts`、`cat /proc/partitions`。

系统备份和 sing-box 配置含密钥，不要提交到仓库或上传为公开 Release。数据分区通常不属于 sysupgrade 根文件系统，但不能在未检查目标镜像分区脚本前承诺一定保留。

刷机后按以下顺序恢复：

1. 电脑改回自动 DHCP，从有线 LAN 登录 `192.168.1.1`。
2. 立刻设置新的 root 密码。
3. 设置自己的 Wi-Fi SSID/WPA2 密码并启用需要的无线电，再检查 board、数据盘、WAN DHCP、DNS、系统时间和校园认证。
4. 基础版先测普通 IPv4/IPv6；代理版先测默认 direct。
5. 最后单独导入私人 JSON 或填写 HTTPS URL，不整体恢复旧系统备份。

## 8. 实机验收

- 三个 profile 都能从 LAN 管理，WAN DHCP 默认生效，PPPoE 入口存在。
- 基础版 DHCPv4、DNS、配置后的 Wi-Fi、IPv4 和 IPv6 PD/relay 正常。
- 两个代理版启动后实际二进制、活动 JSON 和状态都在 p27。
- direct 配置下校园认证和普通网页正常，停止服务后规则完全撤销。
- IPv4 profile 的客户端没有全局 IPv6 默认路径，但路由器能访问 IPv6-only 节点。
- 双栈 profile 的客户端 IPv4/IPv6 TCP、UDP、DNS 均接管；ICMPv6、ND 和 PMTU 正常。
- URL 无法下载、JSON 无效、监听不匹配和核心退出时均不留下半套策略路由。
- 重启、WAN 重连、`fw4 reload` 后服务恢复；测试吞吐、温度、RAM 和日志量。

完成以上 direct 验收后再提供真实 sing-box 配置，这样节点问题和固件问题可以分开定位。

## 官方依据

- [RE-SS-01 设备树](https://github.com/openwrt/openwrt/blob/main/target/linux/qualcommax/dts/ipq6000-re-ss-01.dts)
- [OpenWrt 挂载配置](https://openwrt.org/docs/guide-user/storage/fstab)
- [OpenWrt hardware watchdog](https://openwrt.org/docs/guide-user/hardware/watchdog)
- [OpenWrt odhcpd](https://openwrt.org/docs/techref/odhcpd)
