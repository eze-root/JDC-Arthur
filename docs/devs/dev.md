# 固件覆盖目录与开发检查

`files/` 是编译时直接进入固件的根目录覆盖层，只放通用脚本与公开默认设置。私人 JSON、节点、订阅 URL、证书、磁盘备份和日志不得放入这里，也不能通过 Actions secrets 写进镜像。

两个亚瑟工作流现在使用：

```sh
sh scripts/prepare-arthur.sh "$OPENWRT_PATH" "$FIRMWARE_PROFILE"
cp "$CONFIG_FILE" "$OPENWRT_PATH/.config"
```

prepare 脚本会检查文件白名单、拒绝符号链接、确认公开配置 URL 为空，再按 `base`、`singbox-ipv4` 或 `singbox-dualstack` 准备干净覆盖目录。基础版会移除全部 sing-box 文件；两个代理版保留直连默认配置。新增公开文件时同步更新白名单；不要绕开检查直接合并 `files/`。

feeds 和 DIY 完成后执行 `make defconfig`，再运行：

```sh
sh "$GITHUB_WORKSPACE/scripts/check-arthur-config.sh" .config "$FIRMWARE_PROFILE"
```

这能及时发现上游删除/重命名选项导致必要包没有真正选中的问题。

## 回归检查

```sh
node --test tests/singbox.test.mjs
```

Node.js 22+，Windows 需要 Git Bash；用 `TEST_SHELL` 可指定 shell 路径。测试在系统临时目录复制脚本，将依赖替换为受控的命令，不操作真实网卡或路由器。

覆盖配置校验与原子替换、配置缺失、接口参数校验、路由冲突、nft 失败回滚、UCI 修改后的精确清理、核心退出清理、固件覆盖目录拒绝私人文件、必要包检查。默认跳过真实内核 nft 检查，Linux CI 在隔离网络命名空间额外执行，并检查 Lua 语法。

进程生命周期的模拟不能验证真实核心、fw4、NSS 或设备 watchdog。实机验收见[运维文档](arthur-operations.md)。
