import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repo = path.resolve(import.meta.dirname, '..');
const shell = process.env.TEST_SHELL || (process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : '/bin/sh');
const slash = p => p.replaceAll('\\', '/');
const quote = s => "'" + s.replaceAll("'", "'\\''") + "'";
const source = p => fs.readFileSync(path.join(repo, p), 'utf8').replaceAll('\r\n', '\n');
const runtime = [
  'usr/lib/singbox/common.sh', 'usr/libexec/singbox-run',
  'etc/sbox/sbox_tproxy_start.sh', 'etc/sbox/sbox_tproxy_stop.sh',
  'usr/sbin/singbox-install-config', 'usr/sbin/singbox-install-core',
  'usr/sbin/singbox-update-config'
];

function fixture(t, env = {}) {
  const root = slash(fs.mkdtempSync(path.join(os.tmpdir(), 'arthur-test-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const shellRoot = process.platform === 'win32' ? '/' + root[0].toLowerCase() + root.slice(2) : root;
  function write(p, content) {
    const dest = path.join(root, p);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, content, { mode: 0o755 });
    return slash(dest);
  }
  const replacements = [
    '/mnt/mmcblk0p27/sing-box', '/dev/mmcblk0p27', '/usr/share/singbox',
    '/usr/lib/singbox', '/usr/libexec', '/usr/bin/sing-box', '/etc/sbox',
    '/etc/init.d', '/var/run', '/var/lock', '/proc/mounts', '/tmp', '/lib/functions.sh'
  ];
  for (const p of runtime) {
    let text = source('files/' + p);
    // Redirect only filesystem dependencies into the fixture; real script logic runs.
    for (const old of replacements) text = text.replaceAll(old, '@ROOT@' + old);
    write(p, text.replaceAll('@ROOT@', shellRoot));
  }
  for (const dir of ['var/run', 'var/lock', 'tmp', 'bin', 'proc', 'dev', 'etc/init.d', 'mnt/mmcblk0p27/sing-box/bin', 'mnt/mmcblk0p27/sing-box/config', 'usr/share/singbox']) {
    fs.mkdirSync(path.join(root, dir), { recursive: true });
  }
  write('proc/mounts', `${shellRoot}/dev/mmcblk0p27 ${shellRoot}/mnt/mmcblk0p27 ext4 rw,relatime 0 0\n`);
  write('lib/functions.sh', `config_load() { :; }
config_get() {
    case "$3" in
        data_root) value="$TEST_ROOT/mnt/mmcblk0p27/sing-box" ;;
        data_mount) value="$TEST_ROOT/mnt/mmcblk0p27" ;;
        data_device) value="$TEST_ROOT/dev/mmcblk0p27" ;;
        bin_path) value="$TEST_ROOT/mnt/mmcblk0p27/sing-box/bin/sing-box" ;;
        packaged_bin) value="$TEST_ROOT/usr/bin/sing-box" ;;
        config_path) value="$TEST_ROOT/mnt/mmcblk0p27/sing-box/config/config.json" ;;
        direct_config)
            if [ "\${TEST_IPV6:-0}" = 1 ]; then
                value="$TEST_ROOT/usr/share/singbox/direct-dualstack.json"
            else
                value="$TEST_ROOT/usr/share/singbox/direct-ipv4.json"
            fi
            ;;
        sbox_dir) value="$TEST_ROOT/mnt/mmcblk0p27/sing-box/state" ;;
        enabled) value=1 ;;
        mode) value="\${TEST_MODE:-tproxy}" ;;
        client_ipv6) value="\${TEST_IPV6:-0}" ;;
        tproxy_port) value="\${TEST_PORT:-9898}" ;;
        tproxy_port6) value="\${TEST_PORT6:-9899}" ;;
        route_table) value="\${TEST_TABLE:-100}" ;;
        lan_ifnames) value="\${TEST_LAN:-br-lan}" ;;
        config_url) value="\${TEST_CONFIG_URL:-}" ;;
        *) value="$4" ;;
    esac
    export "$1=$value"
}
`);
  const core = `#!/bin/sh
if [ "$1" = version ]; then echo 'sing-box fixture'; exit 0; fi
if [ "$1" = check ]; then
    while [ "$#" -gt 0 ]; do
        if [ "$1" = -c ]; then shift; grep -q VALID "$1"; exit $?; fi
        shift
    done
    exit 1
fi
echo core-run >> "$TEST_ROOT/events"
echo $$ > "$TEST_ROOT/core-pid"
if [ "\${TEST_READY:-0}" = 1 ]; then
    attempts=0
    while [ ! -f "$TEST_ROOT/table" ] && [ "$attempts" -lt 100 ]; do
        /usr/bin/sleep 0.1
        attempts=$((attempts + 1))
    done
fi
/usr/bin/sleep 1
exit 3
`;
  write('usr/bin/sing-box', core);
  write('mnt/mmcblk0p27/sing-box/bin/sing-box', core);
  write('usr/share/singbox/direct-ipv4.json', 'VALID direct');
  write('usr/share/singbox/direct-dualstack.json', 'VALID direct dual');
  write('bin/ip', `#!/bin/sh
echo "ip $*" >> "$TEST_ROOT/events"
case "$*" in
    '-4 route show table '*) [ "\${TEST_CONFLICT:-0}" != 1 ] || echo 'default via 192.0.2.1'; exit 0 ;;
    '-4 rule show') exit 0 ;;
    '-4 rule add '*) [ "\${TEST_RULE_FAIL:-0}" != 1 ] ;;
esac
`);
  write('bin/nft', `#!/bin/sh
echo "nft $*" >> "$TEST_ROOT/events"
case "$1" in
    list) test -f "$TEST_ROOT/table" ;;
    delete) rm -f "$TEST_ROOT/table" ;;
    -c) cp "$3" "$TEST_ROOT/generated.nft"; [ "\${TEST_CHECK_FAIL:-0}" != 1 ] ;;
    -f) [ "\${TEST_APPLY_FAIL:-0}" != 1 ] || exit 1; touch "$TEST_ROOT/table" ;;
esac
`);
  write('bin/ss', '#!/bin/sh\n[ "${TEST_READY:-0}" = 1 ] && [ -f "$TEST_ROOT/core-pid" ] && echo "users: pid=$(cat "$TEST_ROOT/core-pid"),"\nexit 0\n');
  write('bin/curl', `#!/bin/sh
output=
while [ "$#" -gt 0 ]; do
    if [ "$1" = --output ]; then shift; output=$1; fi
    shift
done
[ "\${TEST_CURL_FAIL:-0}" != 1 ] || exit 22
cp "$TEST_DOWNLOAD" "$output"
`);
  write('bin/sleep', '#!/bin/sh\nexit 0\n');
  write('etc/init.d/sing-box', `#!/bin/sh
echo "service $*" >> "$TEST_ROOT/events"
case "$1" in
    restart)
        [ "\${TEST_RESTART_FAIL:-0}" != 1 ] || exit 1
        if [ "\${TEST_NO_RULES:-0}" != 1 ]; then
            printf '100 100 10000\n' > "$TEST_ROOT/var/run/singbox-tproxy.state"
            touch "$TEST_ROOT/table"
        fi
        ;;
    status) [ "\${TEST_STATUS_FAIL:-0}" != 1 ] ;;
    *) exit 0 ;;
esac
`);
  const vars = { ...process.env, TEST_ROOT: shellRoot, ...env };
  function run(p, args = []) {
    const command = 'export PATH=' + quote(shellRoot + '/bin') + ':' + quote(shellRoot + '/usr/sbin') + ':$PATH\nexec sh ' + quote(shellRoot + '/' + p) + ' ' + args.map(quote).join(' ');
    return spawnSync(shell, ['-c', command], { env: vars, encoding: 'utf8', timeout: 25000 });
  }
  return { root, write, run, vars, events: () => fs.existsSync(root + '/events') ? fs.readFileSync(root + '/events', 'utf8') : '' };
}

test('shell syntax parses for router and build scripts', () => {
  const list = [...runtime.map(p => 'files/' + p), 'files/etc/init.d/sing-box',
    'files/etc/init.d/sing-box-update', 'files/etc/uci-defaults/98-arthur-profile',
    'files/etc/uci-defaults/99-singbox', 'files/usr/sbin/arthur-diagnose',
    'scripts/prepare-arthur.sh', 'scripts/install-official-sing-box.sh',
    'scripts/check-arthur-config.sh'];
  for (const p of list) {
    const result = spawnSync(shell, ['-n'], { input: source(p), encoding: 'utf8' });
    assert.equal(result.status, 0, p + ': ' + result.stderr);
  }
});

test('public direct configurations are valid JSON with no remote nodes', () => {
  for (const name of ['direct-ipv4.json', 'direct-dualstack.json']) {
    const value = JSON.parse(source('files/usr/share/singbox/' + name));
    assert.equal(value.route.final, 'direct');
    assert.deepEqual(value.outbounds.map(item => item.type), ['direct']);
    assert.ok(value.inbounds.every(item => item.type === 'tproxy'));
  }
});

test('firmware profiles keep router IPv6 while controlling client IPv6', () => {
  const profile = source('files/etc/uci-defaults/98-arthur-profile');
  assert.match(profile, /base\)[\s\S]*network\.lan\.ip6assign='60'[\s\S]*dhcp\.wan\.ra='relay'/);
  assert.match(profile, /singbox-ipv4\)[\s\S]*delete network\.lan\.ip6assign[\s\S]*dhcp\.lan\.ra='disabled'/);
  assert.match(profile, /singbox-dualstack\)[\s\S]*client_ipv6='1'[\s\S]*network\.lan\.ip6assign='64'[\s\S]*dhcp\.wan\.ra='relay'/);
  assert.match(source('files/etc/config/network'), /config interface 'wan6'[\s\S]*option proto 'dhcpv6'/);
});

test('invalid candidate preserves active config and removes pending files', t => {
  const f = fixture(t);
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID original');
  const candidate = f.write('tmp/new.json', 'broken');
  const result = f.run('usr/sbin/singbox-install-config', [candidate]);
  assert.notEqual(result.status, 0);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID original');
  assert.deepEqual(fs.readdirSync(f.root + '/mnt/mmcblk0p27/sing-box/config').filter(n => n.startsWith('.singbox')), []);
  assert.equal(fs.existsSync(f.root + '/var/lock/singbox-config.lock'), false);
});

test('valid candidate is atomically installed without starting the service', t => {
  const f = fixture(t);
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID original');
  const candidate = f.write('tmp/new.json', 'VALID replacement');
  const result = f.run('usr/sbin/singbox-install-config', [candidate]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID replacement');
  assert.equal(f.events(), '');
  if (process.platform !== 'win32') assert.equal(fs.statSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json').mode & 0o777, 0o600);
});

test('HTTPS updater validates, installs and restarts atomically', t => {
  const f = fixture(t, { TEST_CONFIG_URL: 'https://config.example.invalid/private.json' });
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID original');
  f.write('tmp/download.json', 'VALID replacement');
  f.vars.TEST_DOWNLOAD = f.vars.TEST_ROOT + '/tmp/download.json';
  const result = f.run('usr/sbin/singbox-update-config');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID replacement');
  assert.match(f.events(), /service restart/);
  assert.match(f.events(), /service status/);
});

test('HTTPS updater restores the previous config when service health fails', t => {
  const f = fixture(t, {
    TEST_CONFIG_URL: 'https://config.example.invalid/private.json',
    TEST_NO_RULES: '1'
  });
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID original');
  f.write('tmp/download.json', 'VALID replacement');
  f.vars.TEST_DOWNLOAD = f.vars.TEST_ROOT + '/tmp/download.json';
  const result = f.run('usr/sbin/singbox-update-config');
  assert.notEqual(result.status, 0);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID original');
  assert.equal((f.events().match(/service restart/g) || []).length, 2);
});

test('missing data mount blocks writes to the mountpoint directory', t => {
  const f = fixture(t);
  fs.writeFileSync(f.root + '/proc/mounts', '');
  const candidate = f.write('tmp/new.json', 'VALID replacement');
  const active = f.root + '/mnt/mmcblk0p27/sing-box/config/config.json';
  fs.rmSync(active, { force: true });
  assert.notEqual(f.run('usr/sbin/singbox-install-config', [candidate]).status, 0);
  assert.equal(fs.existsSync(active), false);
});

test('profile change migrates only a bundled direct config', t => {
  const f = fixture(t, { TEST_IPV6: '1' });
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID direct');
  f.write('tmp/prepare.sh', `. "$TEST_ROOT/usr/lib/singbox/common.sh"
sbox_load
sbox_validate
sbox_prepare_storage
`);
  const result = f.run('tmp/prepare.sh');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID direct dual');

  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID private config');
  assert.equal(f.run('tmp/prepare.sh').status, 0);
  assert.equal(fs.readFileSync(f.root + '/mnt/mmcblk0p27/sing-box/config/config.json', 'utf8'), 'VALID private config');
});

test('invalid interface or reserved route table never changes networking', t => {
  for (const env of [{ TEST_LAN: 'br-lan;bad' }, { TEST_LAN: '*' }, { TEST_TABLE: '254' }]) {
    const f = fixture(t, env);
    assert.notEqual(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
    assert.equal(f.events(), '');
  }
});

test('occupied policy table is left untouched', t => {
  const f = fixture(t, { TEST_CONFLICT: '1' });
  assert.notEqual(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
  assert.doesNotMatch(f.events(), /ip -4 (route|rule) (add|del|flush)/);
  assert.equal(fs.existsSync(f.root + '/var/run/singbox-tproxy.state'), false);
});

test('failed nft validation leaves routing untouched', t => {
  const f = fixture(t, { TEST_CHECK_FAIL: '1' });
  assert.notEqual(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
  assert.doesNotMatch(f.events(), /ip -4 (route|rule) (add|del)/);
});

test('failed nft apply rolls back exactly its own route and rule', t => {
  const f = fixture(t, { TEST_APPLY_FAIL: '1' });
  assert.notEqual(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
  assert.match(f.events(), /rule del pref 10000 fwmark 100\/0xffffffff lookup 100/);
  assert.match(f.events(), /route del local default dev lo table 100/);
  assert.doesNotMatch(f.events(), /flush/);
  assert.equal(fs.existsSync(f.root + '/var/run/singbox-tproxy.state'), false);
});

test('stop uses saved ownership after UCI changes and is repeatable', t => {
  const f = fixture(t);
  assert.equal(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
  const rules = fs.readFileSync(f.root + '/generated.nft', 'utf8');
  assert.match(rules, /table inet singbox_tproxy/);
  assert.match(rules, /iifname != \{ "br-lan" \}/);
  f.vars.TEST_TABLE = '123';
  assert.equal(f.run('etc/sbox/sbox_tproxy_stop.sh').status, 0);
  assert.equal(f.run('etc/sbox/sbox_tproxy_stop.sh').status, 0);
  assert.match(f.events(), /route del local default dev lo table 100/);
  assert.doesNotMatch(f.events(), /route del .*table 123/);
  assert.equal(fs.existsSync(f.root + '/table'), false);
});

test('dual-stack mode creates and removes IPv4 and IPv6 policy routes', t => {
  const f = fixture(t, { TEST_IPV6: '1' });
  assert.equal(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
  const rules = fs.readFileSync(f.root + '/generated.nft', 'utf8');
  assert.match(rules, /tproxy ip6 to \[::1\]:9899/);
  assert.match(f.events(), /ip -6 route add local default dev lo table 100/);
  assert.match(f.events(), /ip -6 rule add pref 10000 fwmark 100\/0xffffffff lookup 100/);
  assert.equal(f.run('etc/sbox/sbox_tproxy_stop.sh').status, 0);
  assert.match(f.events(), /ip -6 route del local default dev lo table 100/);
  assert.match(f.events(), /ip -6 rule del pref 10000 fwmark 100\/0xffffffff lookup 100/);
});

test('missing JSON never launches the core or installs rules', t => {
  const f = fixture(t);
  fs.rmSync(f.root + '/usr/share/singbox/direct-ipv4.json');
  assert.notEqual(f.run('usr/libexec/singbox-run').status, 0);
  assert.doesNotMatch(f.events(), /core-run|nft -f|ip -4 (route|rule) add/);
});

test('core without listeners never intercepts traffic', t => {
  const f = fixture(t);
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID');
  assert.notEqual(f.run('usr/libexec/singbox-run').status, 0);
  assert.doesNotMatch(f.events(), /nft -f|ip -4 (route|rule) add/);
});

test('real Linux nftables accepts generated rules in an isolated namespace',
  { skip: process.env.TEST_REAL_NFT !== '1' }, t => {
  for (const TEST_IPV6 of ['0', '1']) {
    const f = fixture(t, { TEST_IPV6 });
    assert.equal(f.run('etc/sbox/sbox_tproxy_start.sh').status, 0);
    const result = spawnSync('nft', ['-c', '-f', f.root + '/generated.nft'], { encoding: 'utf8' });
    assert.equal(result.status, 0, `client_ipv6=${TEST_IPV6}: ${result.stderr}`);
  }
});

test('core exit after readiness removes interception before procd retry', t => {
  const f = fixture(t, { TEST_READY: '1' });
  f.write('mnt/mmcblk0p27/sing-box/config/config.json', 'VALID');
  const result = f.run('usr/libexec/singbox-run');
  assert.equal(result.status, 3, result.stderr);
  assert.match(f.events(), /nft -f/);
  assert.equal(fs.existsSync(f.root + '/table'), false);
  assert.equal(fs.existsSync(f.root + '/var/run/singbox-tproxy.state'), false);
});

test('overlay preparation permits public files and blocks private data', t => {
  const f = fixture(t);
  fs.cpSync(path.join(repo, 'files'), f.root + '/project/files', { recursive: true });
  f.write('project/scripts/prepare-arthur.sh', source('scripts/prepare-arthur.sh'));
  for (const item of fs.readdirSync(f.root + '/project/files/etc/config')) {
    const file = f.root + '/project/files/etc/config/' + item;
    fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n'));
  }
  f.write('build/include/toplevel.mk', '# fixture');
  const result = f.run('project/scripts/prepare-arthur.sh', [f.root + '/build', 'singbox-ipv4']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.existsSync(f.root + '/build/files/usr/libexec/singbox-run'), true);
  assert.equal(fs.readFileSync(f.root + '/build/files/etc/arthur-profile', 'utf8'), 'singbox-ipv4\n');
  // Existing destination must be inspected instead of merged.
  assert.notEqual(f.run('project/scripts/prepare-arthur.sh', [f.root + '/build', 'singbox-ipv4']).status, 0);
  f.write('other/include/toplevel.mk', '# fixture');
  f.write('project/files/etc/sbox/config.json', 'PRIVATE fixture only');
  assert.notEqual(f.run('project/scripts/prepare-arthur.sh', [f.root + '/other', 'singbox-ipv4']).status, 0);
  assert.equal(fs.existsSync(f.root + '/other/files'), false);
});

test('base overlay removes every sing-box runtime file', t => {
  const f = fixture(t);
  fs.cpSync(path.join(repo, 'files'), f.root + '/project/files', { recursive: true });
  f.write('project/scripts/prepare-arthur.sh', source('scripts/prepare-arthur.sh'));
  f.write('base/include/toplevel.mk', '# fixture');
  const result = f.run('project/scripts/prepare-arthur.sh', [f.root + '/base', 'base']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(f.root + '/base/files/etc/arthur-profile', 'utf8'), 'base\n');
  for (const item of [
    'etc/config/singbox', 'etc/init.d/sing-box', 'etc/init.d/sing-box-update',
    'usr/lib/singbox/common.sh', 'usr/libexec/singbox-run',
    'usr/sbin/singbox-install-config', 'usr/sbin/singbox-install-core',
    'usr/sbin/singbox-update-config', 'usr/share/singbox/direct-ipv4.json'
  ]) assert.equal(fs.existsSync(f.root + '/base/files/' + item), false, item);
  assert.equal(fs.existsSync(f.root + '/base/files/etc/config/fstab'), true);
});

test('required package checks distinguish base and proxy profiles', t => {
  const f = fixture(t);
  f.write('check.sh', source('scripts/check-arthur-config.sh'));
  const base = f.write('base.config', source('configs/0-jd1800.config'));
  assert.equal(f.run('check.sh', [base, 'base']).status, 0);
  const proxy = f.write('proxy.config', source('configs/0-jd1800-tproxy.config'));
  f.write('overlay/usr/bin/sing-box', 'official core fixture');
  f.write('overlay/usr/share/singbox/core-version.txt', `source=SagerNet/sing-box
release=v1.13.21
asset=sing-box_1.13.21_openwrt_aarch64_cortex-a53.ipk
asset_sha256=104e2541d4380e5bc97feae860cd2af9a1817eba2d75304c779b04a788047f6a
architecture=aarch64_cortex-a53
`);
  const overlay = f.root + '/overlay';
  const ipv4 = f.run('check.sh', [proxy, 'singbox-ipv4', overlay]);
  assert.equal(ipv4.status, 0, ipv4.stderr + ipv4.stdout);
  const dual = f.run('check.sh', [proxy, 'singbox-dualstack', overlay]);
  assert.equal(dual.status, 0, dual.stderr + dual.stdout);
  fs.rmSync(f.root + '/overlay/usr/bin/sing-box');
  assert.notEqual(f.run('check.sh', [proxy, 'singbox-ipv4', overlay]).status, 0);
});

test('proxy firmware pins the official SagerNet OpenWrt core', () => {
  const installer = source('scripts/install-official-sing-box.sh');
  assert.match(installer, /VERSION=1\.13\.21/);
  assert.match(installer, /ARCH=aarch64_cortex-a53/);
  assert.match(installer, /104e2541d4380e5bc97feae860cd2af9a1817eba2d75304c779b04a788047f6a/);
  assert.match(installer, /github\.com\/SagerNet\/sing-box\/releases\/download/);
  assert.doesNotMatch(source('configs/0-jd1800-tproxy.config'), /CONFIG_PACKAGE_sing-box=y/);
  const workflow = source('.github/workflows/0-JD1800-TPROXY.yml');
  assert.match(workflow, /install-official-sing-box\.sh/);
  assert.match(workflow, /sing-box-core\.txt/);
});
