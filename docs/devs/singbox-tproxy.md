# JD1800 Wi-Fi Uplink + Sing-box TProxy

This profile is for a "Wi-Fi in, Wi-Fi out" routing setup. The router joins an upstream Wi-Fi as STA, runs its own AP for clients, and sends all LAN client traffic to sing-box via TProxy.

## Build

Use the new profile:

- Config: `configs/0-jd1800-tproxy.config`
- Workflow: `JDC1800-6.12-WIFI-TPROXY`
- Tag: `IPQ60XX-JD1800-6.12-WIFI-TPROXY`

## Post-flash setup (LuCI)

### 1) Wi-Fi uplink (STA)

- Go to **Network -> Wireless**.
- Pick one radio and set it to **Client** mode, then join the upstream Wi-Fi.
- LuCI will ask to create a new interface, name it `wwan` (or reuse `wan`), protocol **DHCP client**.
- Put that interface into the **wan** firewall zone.

Keep your AP on LAN (`br-lan`) as usual.

### 2) Sing-box TProxy

- Copy the binary to `/etc/sbox/sing-box` and config to `/etc/sbox/config.json`, or set URLs in LuCI.
- Open **Services -> Sing-box**, enable it, and adjust:
  - `TProxy port` (default `9898`)
  - `Firewall mark` (default `1`)
  - `Policy route table` (default `100`)
  - `LAN ifnames` (default `br-lan`)
  - `Proxy router traffic` (enable if you want the router itself to be proxied)

### 3) sing-box inbound requirement

Your config must include a TProxy inbound that matches the port above (default 9898). Example:

```json
{
  "inbounds": [
    {
      "type": "tproxy",
      "tag": "tproxy-in",
      "listen": "0.0.0.0",
      "listen_port": 9898,
      "sniff": true
    }
  ]
}
```

## Notes

- Only LAN traffic is proxied by default. If you have multiple LAN bridges, set `LAN ifnames` to a space-separated list (e.g. `br-lan br-guest`).
- DNS port 53 is also handled by TProxy, so DNS requests will go through sing-box as well.
