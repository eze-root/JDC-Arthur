<img width="768" src="https://github.com/openwrt/openwrt/blob/main/include/logo.png"/>

## 特别提示 [![](https://img.shields.io/badge/-个人免责声明-FFFFFF.svg)](#特别提示-)

- **本人不对任何人因使用本固件所遭受的任何理论或实际的损失承担责任！**
- **本固件仅用于 Lab 环境的网络配置与路由实验。**
- **本固件禁止用于任何商业用途，请务必严格遵守国家互联网使用相关法律规定！**

## 项目说明 [![](https://img.shields.io/badge/-项目基本介绍-FFFFFF.svg)](#项目说明-)
- **本项目专注于京东云无线宝-亚瑟 (JDC-AX1800 Pro) 的定制化配置，旨在为 Lab 环境提供稳定的路由支持。**
- 固件默认管理地址：`192.168.1.1` 默认用户：`root` 默认密码：`password`
- 源码：[LiBwrt](https://github.com/LiBwrt-op/openwrt-6.x)
- 源码：[immortalwrt](https://github.com/immortalwrt/immortalwrt)

## 固件下载 [![](https://img.shields.io/badge/-编译状态及下载链接-FFFFFF.svg)](#固件下载-)
| 平台+设备名称 | 固件编译状态 | 配置文件 | 固件下载 |
| :-------------: | :-------------: | :-------------: | :-------------: |
| [![](https://img.shields.io/badge/JDC--Arthur-JD1800-32C955.svg?logo=openwrt)](https://github.com/eze-root/JDC-Arthur/blob/main/.github/workflows/0-JD1800.yml) | [![](https://github.com/eze-root/JDC-Arthur/actions/workflows/0-JD1800.yml/badge.svg)](https://github.com/eze-root/JDC-Arthur/actions/workflows/0-JD1800.yml) | [![](https://img.shields.io/badge/编译-配置-orange.svg?logo=apache-spark)](https://github.com/eze-root/JDC-Arthur/blob/main/configs/0-jd1800.config) | [![](https://img.shields.io/badge/下载-链接-blueviolet.svg?logo=hack-the-box)](https://github.com/eze-root/JDC-Arthur/releases/IPQ60XX-JD1800-6.12-WIFI) |

## 定制固件 [![](https://img.shields.io/badge/-项目基本编译教程-FFFFFF.svg)](#定制固件-)
1. 首先要登录 Gihub 账号，然后 Fork 此项目到你自己的 Github 仓库。
2. 修改 `configs` 目录对应文件添加或删除插件，或者上传自己的 `xx.config` 配置文件。
3. 修改 `diy-jd1800.sh` 文件内进行个性化脚本修改。
4. 在 `Actions` 页面手动运行 `JDC1800-6.12-WIFI` 即可开始编译。
5. 编译完成后在 [Releases](https://github.com/eze-root/JDC-Arthur/releases) 下载固件。

<a href="#readme">
<img src="https://img.shields.io/badge/-返回顶部-FFFFFF.svg" title="返回顶部" align="right"/>
</a>