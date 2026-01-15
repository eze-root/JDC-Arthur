module("luci.controller.singbox", package.seeall)

function index()
	local fs = require "nixio.fs"
	if not fs.access("/etc/config/singbox") then
		return
	end

	entry({"admin", "services", "singbox"}, cbi("singbox"), _("Sing-box"), 60).dependent = true
end
