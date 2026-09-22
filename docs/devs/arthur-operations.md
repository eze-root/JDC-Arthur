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

## 9. 2026-09-22：LAN IPv6 回程故障

实机仍运行 `odhcpd-ipv6only 2024.05.08~a2988231`。WAN 获得全局 `/64`，
但 `ubus call network.interface.wan6 status` 的 `ipv6-prefix` 为空：上游没有 PD，
LAN 依靠 RA/NDP relay 共享 WAN 网段。

本次复现时，`byr.pt` 的 A 查询无地址，AAAA 查询正常。路由器自身访问 IPv6
返回 HTTP 302 到登录页；LAN 电脑访问相同地址超时。电脑的两个全局 IPv6
地址出现在 **WAN** 邻居表的 FAILED/INCOMPLETE 项中，而主路由表缺少指向
`br-lan` 的 `/128` 回程。临时添加精确的 LAN 主机路由后，电脑访问 byr.pt
和微信 IPv6 服务立即得到 HTTP 响应。去掉临时路由后，已学习地址继续工作，
尚未学习的地址仍超时，说明只重启 odhcpd 或修改 DNS 不足以根治。

旧 odhcpd 会忽略自己从 master/WAN 发出的邻居请求，不能据此去 LAN
发现客户端。上游 `f0d855358b86` 修复该问题；`d402cdae4316` 将中继探测改为
链路本地源地址，改善 macOS 邻居发现。`diy-jd1800.sh` 固定 odhcpd 到包含
两项修复的 `5d7be43f8b9dec0eb47e245cfab81108bb131273`，并校验源码包哈希。

固件首次启动配置把 relay master 放在 `dhcp.wan6`，移除旧的 `dhcp.wan`
中继选项，明确启用 LAN 的 `ndproxy_routing` 与 `ndp_from_link_local`。
基础版和双栈版都使用该配置；IPv4 客户端版会清理两个 WAN 节上的中继选项。
固件产物附带 `config-commit.txt` 与 `odhcpd-source.txt`，便于核对实际源码。

升级前的临时主机路由只用于验证，不能写死到公共固件：IPv6 隐私地址、
上游前缀和设备都会变化。新固件验收需要在清空测试邻居状态或客户端重新
入网后，再验证自动生成 `客户端IPv6/128 dev br-lan`，以及重启和 WAN 重连。
`arthur-diagnose` 已加入 IPv6 地址、主路由、邻居和中继选项输出。

微信部分 IPv4 端点在本次测试中从路由器直接连接也超时，但其他 IPv4
网站正常。此项不能仅凭 IPv6 修复判定解决；网页 HTTP 响应也不能替代微信
客户端登录、消息和图片传输验收。私人节点配置、密码和运行备份不进入固件。

上游修复：

- [NDP master 自发请求的邻居发现](https://github.com/openwrt/odhcpd/commit/f0d855358b86)
- [使用链路本地源地址的 macOS 兼容修复](https://github.com/openwrt/odhcpd/commit/d402cdae4316)

### 手机微信图片的独立 DNS 问题

同日继续排查手机，控制接口确认 `mmbiz.qpic.cn`、`wx.qlogo.cn` 和
`res.wx.qq.com` 走 direct，却在部分 IPv4 节点持续超时或无下行数据。
活动 DNS 解析曾返回 `43.171.80.40` 等节点；路由器向校园 DNS 和
`223.5.5.5` 查询时，图片节点为 `183.66.105.224`，头像节点为
`219.153.154.32/30` 范围中的地址。后者在 IPv4 直连下约 0.14 秒得到响应。
从路由器对同一域名发送 A 查询已复核：原 IPv6 DNS `2400:3200::1`
返回上述 `43.*` 节点，IPv4 DNS `223.5.5.5` 返回 `183.66.105.224`。
图片域名的 IPv6 解析和连接也恢复可用。根路径返回 HTTP 400 是 CDN
对缺少图片路径的正常响应，只证明连接可用，仍需手机实际图片加载验收。

实机给 `qpic.cn`、`qlogo.cn`、`res.wx.qq.com` 增加优先 DNS 规则，
最初使用 UDP `223.5.5.5`，后续改为同地址的 TCP（见下面 B 站排查）。
用户随后选择「IPv4 为主，byr.pt 等纯 IPv6 站点
保留例外」，最终配置采用下面的策略；用户已确认公众号文章图片恢复。
旧节点不可达的上游原因尚未确定，不能简单归因于 IPv6。

- DNS 全局及原有 `prefer_ipv6` 规则改为 `prefer_ipv4`。
- 国内直连 DNS `dns_direct` 从 `2400:3200::1` 改为 `223.5.5.5`，
  与微信专用解析器统一；国外域名仍使用经代理访问的 `1.1.1.1` DoH。
  WAN 下发的 `192.0.0.33/34` 保留在上游状态，但 dnsmasq 已设
  `noresolv=1`，不会用它们处理局域网 DNS 请求。
- 对来自客户端入站的 AAAA、HTTPS、SVCB 查询返回 NOERROR 空答案；
  `byr.pt`、`lan`、`local`、`ip6.arpa` 除外。HTTPS/SVCB 也可能携带
  IPv6 地址提示，因此一并处理。规则限定客户端入站，不限制私人代理
  服务器的内部 IPv6 解析，也不关闭 RA、IPv6 转发和 NDP 中继。
- 在 sniff 之后，只对 `mmbiz.qpic.cn`、`wx.qlogo.cn`、`res.wx.qq.com`、
  `mp.weixin.qq.com`
  将目的地址恢复为同一个域名，经专用直连出口重新解析为 IPv4，保留端口
  和 TLS 域名，避免手机旧 IP 缓存继续连不可达节点。未修改私人代理节点。
- dnsmasq 的上游设置为 `127.0.0.1#1053`，`noresolv=1`，将发往路由器
  IPv6 链路本地地址的 DNS 也交给 sing-box。原先这条路径绕过了 TProxy。
  直接接管链路本地 UDP 会发生回包失败，故保留原有本地流量绕过规则。

`prefer_ipv4` 只是解析/拨号优先级，不会阻止手机对 AAAA 单独查询并选择
IPv6。上述客户端 DNS 过滤才使普通网站明确使用 IPv4。此策略不拦截应用
自带的加密 DNS、硬编码 IPv6 或仍未失效的缓存；新遇到纯 IPv6 站点需增加
例外。`tjupt.org` 本次查询有 A 记录，未列为纯 IPv6 例外。

私人 JSON 保存在设备数据分区，不能复制到公共固件覆盖目录。仓库提供
可重复生成同样修复的工具（Python 3，在电脑运行）：

```sh
python3 scripts/patch-wechat-dns.py /private/path/config.json /private/path/candidate.json \
  --ipv4-first --refresh-cdn-addresses --direct-dns-tag dns_direct --dns-transport tcp
# 增加例外时，附加 --ipv6-domain example.org，可重复指定。
```

工具不覆盖输入文件，输出权限为 0600，不输出凭据。把候选文件私下上传到
路由器后，使用 `singbox-install-config /tmp/candidate.json` 校验安装，再
重启 sing-box。然后将 `scripts/configure-singbox-dns-forwarding.sh` 上传到
路由器并用 `sh` 执行，它先检查服务和 1053 监听，再备份并修改 dnsmasq。
若已有其他自定义 DNS 上游，脚本会停止，须人工合并。

此后路由器 DNS 依赖 sing-box；永久停用 sing-box 前，必须恢复脚本打印的
DHCP 配置备份并重启 dnsmasq。2026-09-22 实机的回滚文件为数据分区的
`sing-box/backup-20260922/config-before-ipv4-first.json` 和
`sing-box/backup-20260922/dhcp-before-dns-forwarding`。

固件更新不会自动改写已有私人配置；订阅覆盖配置时应在
订阅生成端加入相同规则，或再次生成并验证候选文件。客户端旧 DNS 缓存
可能需要重新连接 Wi-Fi 后才刷新。当前没有启用开机订阅覆盖。

实测普通 IPv4 DNS 和 IPv6 链路本地 DNS 均不再返回微信图片 AAAA，
仍返回有效 A；两种入口均保留 byr.pt 的 AAAA。指定旧故障 IPv4
`43.171.80.40` 的 HTTPS 请求经域名重新解析后约 0.10 秒收到 HTTP 400；
byr.pt 通过 IPv6 约 0.23 秒返回登录跳转。用户随后确认手机图片正常。

随后针对「仍偏慢」反馈统一了国内 DNS。路由器直测 `223.5.5.5` 的四个
查询耗时约 25–30 毫秒；原 IPv6 DNS 耗时约 37–106 毫秒，并对公众号域名
返回另一组节点。校园 DNS 同次约 25–30 毫秒，不能据此判定其必然不可用。
修改后局域网电脑的公众号首页约 0.28 秒返回 HTTP 200，图片域名约 0.13 秒
返回 HTTP 400，byr.pt 约 0.27 秒返回 HTTP 302；这些只衡量相应请求，
不能替代手机文章全部图片的吞吐或加载速度测试。对公众号首页的同次
直连比较中，原解析节点 `43.137.130.213` 首响应约 2.86 秒、完整响应约
5.46 秒，新节点 `101.91.40.80` 首响应约 0.35 秒、完整响应约 0.38 秒。
这说明节点选择比 DNS 查询时间本身更影响本次等待；单次结果不代表长期
平均延迟。因此将 `mp.weixin.qq.com` 也加入精确域名的旧地址修正规则。

策略脚本和私人配置不打包进公共固件；保留配置刷机时须保留 DHCP 配置及
数据分区，不保留配置刷机后需重新导入私人 JSON 并运行 DNS 转发脚本。
本次编译中的固件提交为 `a2ac1ff`，包括 odhcpd 修复和 nftables 包选择修复；
后续策略工具与运维说明不改变该固件镜像。

### B 站间歇性 DNS 失败

2026-09-22 晚间继续排查 `bilibili.com`。初次局域网请求复现了多个 B 站
域名解析 15 秒超时，紧接着对路由器的单次 DNS 查询也超时；因此不能仅以
首页在另一设备能打开否定客户端报错。现有 B 站图片、视频和 API 连接均为
IPv4 direct，路由器负载约 0.18，无线链路没有明显拥塞证据。

故障随后自行恢复：调整前 80 次 TCP/UDP 客户端 DNS 查询全部成功，
最慢约 71 毫秒，Chrome 原有 B 站标签页的主页和封面也已显示。上游 UDP
查询约 24–31 毫秒，同一 `223.5.5.5:53` 的 TCP 查询约 18–29 毫秒。
普通 512 字节 DNS 查询也得到完整有效回答，未复现大答案截断问题。

为降低 UDP 丢包对解析的影响，将 `dns_direct` 与 `dns-wechat-local` 的
`type` 从 `udp` 改为 `tcp`，其余配置不变。此项是可回滚的稳定性调整，
**尚未证明刚才超时一定由上游 UDP 丢包造成**，也不能把一次恢复视为根治。
未将 B 站改走代理，未修改浏览器插件或安全 DNS 设置。

候选配置已由实机 sing-box 1.13.21 校验；应用后重新加载 Chrome 中的 B 站
主页，页面和资源成功显示。B 站主页/API/图片域名复测约 2–23 毫秒，微信
解析成功，byr.pt 的 AAAA 例外保留。回滚文件为数据分区中的
`sing-box/backup-20260922/config-before-bili-dns-tcp.json`。

首次构建还发现上游只有 `nftables-json` 和 `nftables-nojson` 实际包，
`nftables` 是虚拟名称。已改选 `nftables-json`，构建检查接受两种实际实现。

## 官方依据

- [RE-SS-01 设备树](https://github.com/openwrt/openwrt/blob/main/target/linux/qualcommax/dts/ipq6000-re-ss-01.dts)
- [OpenWrt 挂载配置](https://openwrt.org/docs/guide-user/storage/fstab)
- [OpenWrt hardware watchdog](https://openwrt.org/docs/guide-user/hardware/watchdog)
- [OpenWrt odhcpd](https://openwrt.org/docs/techref/odhcpd)
