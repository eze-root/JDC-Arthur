local sys = require "luci.sys"

local m = Map("singbox", translate("Sing-box"),
    translate("The core, active JSON and state live on the mounted data volume. A validated direct configuration is used until a private configuration is installed."))
local s = m:section(NamedSection, "main", "singbox", translate("Settings"))
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("Enable"))
enabled.rmempty = false

local mode = s:option(ListValue, "mode", translate("Mode"))
mode:value("tproxy", translate("TProxy: LAN TCP/UDP"))
mode:value("tun", translate("TUN: routing managed by private JSON"))
mode.default = "tproxy"
mode.rmempty = false

local client_ipv6 = s:option(Flag, "client_ipv6", translate("Proxy client IPv6"))
client_ipv6.rmempty = false
client_ipv6:depends("mode", "tproxy")
client_ipv6.description = translate("Requires the dual-stack firmware profile and a matching IPv6 TProxy inbound. The router keeps WAN IPv6 in both proxy profiles.")

local function path_option(key, title, default)
    local o = s:option(Value, key, translate(title))
    o.default = default
    o.rmempty = false
    function o.validate(self, value)
        if value and value:sub(1, 1) == "/" and not value:find("[\r\n]") then
            return value
        end
        return nil, translate("Use an absolute path.")
    end
    return o
end

path_option("data_mount", "Data mount point", "/mnt/mmcblk0p27")
path_option("data_root", "Data directory", "/mnt/mmcblk0p27/sing-box")
path_option("data_device", "Data device", "/dev/mmcblk0p27")
path_option("bin_path", "Binary path", "/mnt/mmcblk0p27/sing-box/bin/sing-box")
path_option("packaged_bin", "Packaged core path", "/usr/bin/sing-box")
path_option("config_path", "Active config path", "/mnt/mmcblk0p27/sing-box/config/config.json")
path_option("direct_config", "Fallback direct config", "/usr/share/singbox/direct-ipv4.json")
local work = path_option("sbox_dir", "Working directory / cache", "/mnt/mmcblk0p27/sing-box/state")
work.description = translate("The service refuses to write when the expected ext4 data volume is not mounted.")

local function number_option(key, title, default, datatype)
    local o = s:option(Value, key, translate(title))
    o.default = default
    o.datatype = datatype
    o.rmempty = false
    return o
end

number_option("tproxy_port", "IPv4 TProxy port", "9898", "range(1024,65535)"):depends("mode", "tproxy")
number_option("tproxy_port6", "IPv6 TProxy port", "9899", "range(1024,65535)"):depends("client_ipv6", "1")
number_option("fwmark", "Firewall mark", "100", "range(1,65535)"):depends("mode", "tproxy")
number_option("route_table", "Policy route table", "100", "range(1,252)"):depends("mode", "tproxy")
number_option("rule_priority", "Policy rule priority", "10000", "range(1,32765)"):depends("mode", "tproxy")
number_option("respawn_timeout", "Restart delay (seconds)", "30", "range(5,3600)")

local lan = s:option(Value, "lan_ifnames", translate("LAN ifnames"))
lan.default = "br-lan"
lan.rmempty = false
lan:depends("mode", "tproxy")
function lan.validate(self, value)
    if not value or not value:find("%S") then return nil, translate("LAN interface required.") end
    for iface in value:gmatch("%S+") do
        if #iface > 15 or iface:find("[^%w_.:%-]") or iface == "lo" or iface == "wan" or iface == "wan6" then
            return nil, translate("Invalid LAN interface.")
        end
    end
    return value
end
lan.description = translate("Space-separated LAN bridges. Router-originated traffic is not intercepted by TProxy.")

local url = s:option(Value, "config_url", translate("HTTPS configuration URL"))
url.password = true
url.rmempty = true
function url.validate(self, value)
    if not value or value == "" or (value:match("^https://") and not value:find("[\r\n]")) then return value end
    return nil, translate("Use an HTTPS URL or leave it empty.")
end
url.description = translate("The URL may contain a private token. It is stored only on the router and is not embedded in public firmware.")

local update_on_boot = s:option(Flag, "update_on_boot", translate("Update configuration on boot"))
update_on_boot.rmempty = false
number_option("update_retries", "Boot update attempts", "6", "range(1,60)")
number_option("update_retry_delay", "Retry delay (seconds)", "30", "range(5,3600)")
number_option("download_timeout", "Download timeout (seconds)", "30", "range(5,600)")
number_option("max_config_bytes", "Maximum config bytes", "4194304", "range(1024,16777216)")

local check = s:option(Button, "_check", translate("Check saved configuration"))
check.inputstyle = "apply"
function check.write()
    if sys.call("/etc/init.d/sing-box check >/dev/null 2>&1") == 0 then
        m.message = translate("Configuration is valid.")
    else
        m.errmessage = translate("Check failed. Verify the data mount and paths, then run sing-box check locally for details.")
    end
end

local update = s:option(Button, "_update", translate("Download, validate and activate now"))
update.inputstyle = "apply"
function update.write()
    if sys.call("/usr/sbin/singbox-update-config >/dev/null 2>&1") == 0 then
        m.message = translate("Configuration updated successfully.")
    else
        m.errmessage = translate("Update failed; the previous configuration remains active. Check logs, time and upstream authentication.")
    end
end

local restart = s:option(Button, "_restart", translate("Restart using saved settings"))
restart.inputstyle = "reload"
function restart.write()
    if sys.call("/etc/init.d/sing-box check >/dev/null 2>&1") == 0 then
        sys.call("/etc/init.d/sing-box restart >/dev/null 2>&1")
        m.message = translate("Restart requested. Check system logs and service status.")
    else
        m.errmessage = translate("Invalid configuration; restart was not requested.")
    end
end

return m
