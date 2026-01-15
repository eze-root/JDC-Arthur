local sys = require "luci.sys"

m = Map("singbox", translate("Sing-box"), translate("Transparent proxy via TProxy for LAN clients."))

s = m:section(NamedSection, "main", "singbox", translate("Settings"))
s.addremove = false

enabled = s:option(Flag, "enabled", translate("Enable"))
enabled.rmempty = false

bin_path = s:option(Value, "bin_path", translate("Binary path"))
bin_path.datatype = "file"
bin_path.placeholder = "/etc/sbox/sing-box"

config_path = s:option(Value, "config_path", translate("Config path"))
config_path.datatype = "file"
config_path.placeholder = "/etc/sbox/config.json"

tproxy_port = s:option(Value, "tproxy_port", translate("TProxy port"))
tproxy_port.datatype = "port"
tproxy_port.placeholder = "9898"

fwmark = s:option(Value, "fwmark", translate("Firewall mark"))
fwmark.datatype = "uinteger"
fwmark.placeholder = "1"

route_table = s:option(Value, "route_table", translate("Policy route table"))
route_table.datatype = "uinteger"
route_table.placeholder = "100"

lan_ifnames = s:option(Value, "lan_ifnames", translate("LAN ifnames"))
lan_ifnames.placeholder = "br-lan"
lan_ifnames.description = translate("Space-separated interface names used for LAN ingress.")

proxy_router = s:option(Flag, "proxy_router", translate("Proxy router traffic"))
proxy_router.rmempty = false

bin_url = s:option(Value, "bin_url", translate("Binary URL"))
bin_url.placeholder = ""

config_url = s:option(Value, "config_url", translate("Config URL"))
config_url.placeholder = ""

check_url = s:option(Value, "check_url", translate("Network check URL"))
check_url.placeholder = "https://www.baidu.com"

restart = s:option(Button, "_restart", translate("Restart service"))
restart.inputstyle = "apply"
function restart.write()
	sys.call("/etc/init.d/sing-box restart >/dev/null")
end

return m
