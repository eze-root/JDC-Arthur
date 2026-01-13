<img width="768" src="https://github.com/openwrt/openwrt/blob/main/include/logo.png"/>

## 特别提示 [![](https://img.shields.io/badge/-个人免责声明-FFFFFF.svg)](#特别提示-)

- **⚠️ 硬件限制：本固件仅适用于京东云无线宝-亚瑟 (JDC-AX1800 Pro / JDCloud RE-SP-01B)，请勿尝试在其他型号（如鲁班、雅典娜等）或品牌上刷入，否则可能导致设备损坏（变砖）！**
- **本人不对任何人因使用本固件所遭受的任何理论或实际的损失承担责任！**
- **本固件主要用于 Lab 环境的网络拓扑实验与路由配置研究。**
- **本固件禁止用于任何商业用途，请务必严格遵守国家互联网使用相关法律规定！**

## 项目说明 [![](https://img.shields.io/badge/-项目基本介绍-FFFFFF.svg)](#项目说明-)
- **核心目标**：提供一个针对亚瑟硬件深度优化的 OpenWrt 固件，方便在实验室环境中进行透明代理测试、IPv6 网络实验以及高性能路由转发。
- **固件信息**：
    - 默认管理地址：`192.168.1.1`
    - 默认登录用户：`root`
    - 默认登录密码：`password`
- **源码参考**：
    - [LiBwrt](https://github.com/LiBwrt-op/openwrt-6.x) (内核 6.12 + NSS 加速支持)
    - [immortalwrt](https://github.com/immortalwrt/immortalwrt)

## 固件功能特点 [![](https://img.shields.io/badge/-特色功能-FFFFFF.svg)](#固件功能特点-)
- **WAN 口访问**：默认开启 WAN 口入站访问，方便从上级网络管理路由器。
- **IPv6 支持**：预装 `ipv6helper`，支持自动配置 IPv6 网络环境。
- **高性能转发**：基于 NSS 驱动，支持有线全双工线速转发。
- **实验环境友好**：集成自动化配置脚本框架，支持从本地持久化存储加载实验配置。

## 固件编译 [![](https://img.shields.io/badge/-GitHub_Actions-FFFFFF.svg)](#固件编译-)
| 平台+设备名称 | 固件编译状态 | 配置文件 | 固件下载 |
| :-------------: | :-------------: | :-------------: | :-------------: |
| [![](https://img.shields.io/badge/JDC--Arthur-JD1800-32C955.svg?logo=openwrt)](https://github.com/eze-root/JDC-Arthur/blob/main/.github/workflows/0-JD1800.yml) | [![](https://github.com/eze-root/JDC-Arthur/actions/workflows/0-JD1800.yml/badge.svg)](https://github.com/eze-root/JDC-Arthur/actions/workflows/0-JD1800.yml) | [![](https://img.shields.io/badge/编译-配置-orange.svg?logo=apache-spark)](https://github.com/eze-root/JDC-Arthur/blob/main/configs/0-jd1800.config) | [![](https://img.shields.io/badge/下载-链接-blueviolet.svg?logo=hack-the-box)](https://github.com/eze-root/JDC-Arthur/releases/IPQ60XX-JD1800-6.12-WIFI) |

## 快速上手指导 [![](https://img.shields.io/badge/-使用指南-FFFFFF.svg)](#快速上手指导-)
1. **Fork 本项目**：点击右上角 Fork 按钮。
2. **自定义脚本**：修改 `diy-jd1800.sh` 可在编译时自动集成特定的插件或配置。
3. **手动触发**：在仓库的 `Actions` 选项卡中选择 `JDC1800-6.12-WIFI` 并点击 `Run workflow`。
4. **获取固件**：编译完成后，在 [Releases](https://github.com/eze-root/JDC-Arthur/releases) 中下载生成的固件镜像。

<a href="#readme">
<img src="https://img.shields.io/badge/-返回顶部-FFFFFF.svg" title="返回顶部" align="right"/>
</a>
