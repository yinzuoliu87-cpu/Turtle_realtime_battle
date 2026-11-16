#!/bin/bash
# 裁判机换 ARM · 新机装机（2026-11-16 · 方案书 docs/plans/20261116c-裁判机换ARM.md §4.2）
#
# 在【新机】上以 root 跑：
#   bash arm_provision.sh <旧机IP>           第一次：装包 + 建用户 + Godot(按本机架构) + ufw + 拉全部配置与数据
#   bash arm_provision.sh <旧机IP> --final   切换时：只增量同步配置与数据（旧机服务已停）
# 前提：新机 /root/.ssh/from_old 这把钥匙已加进旧机 root 的 authorized_keys（编排 tools/referee_arm_cutover.py keys 做，finish 时删）。
# ★只装不起：turtle-* 服务 / 计时器与 caddy 一律保持停止、不 enable —— 否则新机会和旧机同时领活、同时发龟投消息。
#   切换时由编排脚本照旧机的 enable 清单打开。
# ★属主按名字映射（不用 --numeric-ids）：新机 turtle-referee / caddy 的 uid 未必和旧机相同。
# ★密钥文件（/etc/turtle-referee/env*）只在两台服务器之间直接拷，不经过本机、不打印。
set -euo pipefail
OLD="${1:?用法: arm_provision.sh <旧机IP> [--final]}"
MODE="${2:-}"
SSH_OLD="ssh -i /root/.ssh/from_old -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
GODOT_VER="4.6.3"
GODOT_COMMIT="7d41c59c4"

pull() {   # pull <旧机路径> <本机路径>：增量、删掉旧机已没有的、保留属主权限 / 硬链接 / ACL
	rsync -aHAX --delete -e "$SSH_OLD" "root@$OLD:$1" "$2"
}
say() { echo "$(date -u +%H:%M:%S) $*"; }

if [ "$MODE" != "--final" ]; then
	say "① 系统包"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq rsync unzip fontconfig libfontconfig1 fail2ban sysstat nftables htop tmux git curl acl >/dev/null
	pull /etc/apt/sources.list.d/caddy-stable.list /etc/apt/sources.list.d/caddy-stable.list
	pull /usr/share/keyrings/caddy-stable-archive-keyring.gpg /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	apt-get update -qq
	apt-get install -y -qq caddy >/dev/null
	systemctl disable --now caddy >/dev/null 2>&1 || true

	say "② 用户 turtle-referee"
	getent group turtle-referee >/dev/null || groupadd --system turtle-referee
	id turtle-referee >/dev/null 2>&1 || useradd --system -g turtle-referee -d /var/lib/turtle-referee -s /usr/sbin/nologin turtle-referee

	say "③ Godot $GODOT_VER（本机架构 $(uname -m)）"
	case "$(uname -m)" in
		aarch64) GZ="Godot_v${GODOT_VER}-stable_linux.arm64" ;;
		x86_64) GZ="Godot_v${GODOT_VER}-stable_linux.x86_64" ;;
		*) echo "不认识的架构 $(uname -m)"; exit 1 ;;
	esac
	mkdir -p /opt/godot
	if ! /opt/godot/godot --headless --version 2>/dev/null | grep -q "$GODOT_COMMIT"; then
		rm -rf /tmp/godot_dl && mkdir -p /tmp/godot_dl
		curl -sSL -o /tmp/godot_dl/g.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/${GZ}.zip"
		python3 -m zipfile -e /tmp/godot_dl/g.zip /tmp/godot_dl/
		install -m 755 "/tmp/godot_dl/$GZ" /opt/godot/godot
		rm -rf /tmp/godot_dl
	fi
	/opt/godot/godot --headless --version 2>/dev/null | grep "$GODOT_COMMIT"

	say "④ 防火墙（同旧机）"
	ufw allow OpenSSH >/dev/null
	ufw allow 80/tcp comment 'caddy acme+redirect' >/dev/null
	ufw allow 443/tcp comment 'caddy https' >/dev/null
	ufw allow 443/udp comment 'caddy http3' >/dev/null
	ufw allow 8443/tcp comment 'turtle relay phase1' >/dev/null
	ufw --force enable >/dev/null
fi

say "⑤ 配置（旧机直拷）"
mkdir -p /etc/turtle-referee /etc/caddy
pull /etc/turtle-referee/ /etc/turtle-referee/
pull /etc/caddy/ /etc/caddy/
pull /etc/turtle-relay.nft /etc/turtle-relay.nft
rsync -aHAX -e "$SSH_OLD" "root@$OLD:/etc/systemd/system/turtle-*" /etc/systemd/system/
systemctl daemon-reload

say "⑥ 工程与数据"
## --final(停机窗口里)只同步会变的状态; 工程目录(/opt/*, 40 GB 左右、文件多, 光扫一遍就要几分钟)在停服务前已预同步, 两次之间不发版
DIRS="/var/lib/turtle-referee /var/lib/turtle-referee-beta /var/lib/turtle-bots-prod /var/lib/turtle-bots-beta /var/lib/caddy"
[ "$MODE" = "--final" ] || DIRS="/opt/turtle /opt/turtle-beta /opt/turtle-bots-prod /opt/turtle-bots-beta $DIRS"
for d in $DIRS; do
	mkdir -p "$d"
	pull "$d/" "$d/"
done
for d in /opt/turtle-prev /opt/turtle-stage /opt/turtle-staging; do mkdir -p "$d"; done
chown turtle-referee:turtle-referee /opt/turtle-staging
mkdir -p /root/old-root
rsync -aHAX -e "$SSH_OLD" --exclude .ssh --exclude .cache "root@$OLD:/root/" /root/old-root/

say "⑦ 自检（不起服务）"
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && echo "caddy 配置 OK" || echo "★caddy 配置不过"
nft -c -f /etc/turtle-relay.nft && echo "中转 nft 规则 OK" || echo "★中转 nft 规则不过"
for v in /opt/turtle /opt/turtle-beta; do
	echo "$v 版本: $(VERSIONS_DIR=$v python3 /opt/turtle/referee/referee_poller.py --versions | tr -d '\n ' )"
done
df -h / | tail -1
say "DONE"
