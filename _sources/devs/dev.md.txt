# Add Default configs

为了能自动的初始化一些配置，例如设置默认网关 `/etc/config/network`。

创建文件夹 `files/etc/config`。

由于在github action中有如下的命令，因此该配置应该是能被注入到默认的固件中的。


```
    - name: Load Custom Configuration(加载自定义配置)
      run: |
        [ -e files ] && mv files $OPENWRT_PATH/files
        [ -e $CONFIG_FILE ] && mv $CONFIG_FILE $OPENWRT_PATH/.config

```










