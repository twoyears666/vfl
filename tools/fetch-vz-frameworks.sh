#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 twoyears666
#
# 从 nfzerox/VirtualMacOniPad（MIT）的发布包里取现成的 iOS 版 VZ 运行时，
# 放进 vendor/app，由 Makefile 打进 VFL.app。省掉在本机下载 IPSW、uncache、
# stamp_ios 那一整套流程；需要自己从头提取时用 tools/build-vz-frameworks.sh。
#
# 用法：
#   tools/fetch-vz-frameworks.sh
#   VZ_DEB_VERSION=1.2.4 VZ_DEB_SHA256=<sha> tools/fetch-vz-frameworks.sh

set -euo pipefail

VERSION="${VZ_DEB_VERSION:-1.2.4}"
SHA256="${VZ_DEB_SHA256:-d8765adda6257fa7712aeae126c7992c952f151519375b0224520ecfea50a078}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="${VENDOR:-$REPO_ROOT/vendor/app}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/nfzerox/VirtualMacOniPad/releases/download/${VERSION}/VirtualMac_${VERSION}.deb"

echo "==> 下载 VirtualMac ${VERSION}"
curl -fsSL "$URL" -o "$TMP/vmoi.deb"

if [[ -n "$SHA256" ]]; then
	actual="$(shasum -a 256 "$TMP/vmoi.deb" | awk '{print $1}')"
	[[ "$actual" == "$SHA256" ]] || {
		echo "error: 校验和不匹配：$actual" >&2
		exit 1
	}
fi

echo "==> 解包"
( cd "$TMP" && ar x vmoi.deb )
tar -xf "$TMP/data.tar.xz" -C "$TMP"
PAYLOAD="$TMP/var/root/VirtualMac/payload"
APP="$TMP/var/jb/Applications/VirtualMac.app"
[[ -d "$PAYLOAD/Frameworks" && -f "$APP/VZHostCompat.dylib" ]] || {
	echo "error: 发布包结构与预期不符" >&2
	exit 1
}

echo "==> 组装 $VENDOR"
rm -rf "$VENDOR"
mkdir -p "$VENDOR"

# 1. 框架全部带上：VMM 子进程通过 @loader_path/../../../Frameworks 找它们。
cp -R "$PAYLOAD/Frameworks" "$VENDOR/Frameworks"

# 2. host hook：把 VZ 的方法调用重绑到 iPadOS 实现，并负责拉起 VMM 子进程。
cp "$APP/VZHostCompat.dylib" "$VENDOR/VZHostCompat.dylib"
chmod 755 "$VENDOR/VZHostCompat.dylib"

# 3. VMM 子进程：iOS 16 用 ipados16 变体（本包最低 iOS 16）。
VMM_DIR="$PAYLOAD/VirtualMachine.xpc/Contents/MacOS"
VMM_OUT="$VENDOR/VirtualMachine.xpc/Contents/MacOS"
cp -R "$PAYLOAD/VirtualMachine.xpc" "$VENDOR/VirtualMachine.xpc"
cp "$VMM_DIR/com.apple.Virtualization.VirtualMachine.ipados16" \
	"$VMM_OUT/com.apple.Virtualization.VirtualMachine"
rm -f "$VMM_OUT"/com.apple.Virtualization.VirtualMachine.ipados*
chmod 755 "$VMM_OUT/com.apple.Virtualization.VirtualMachine"

# 4. 运行时校验。
for probe in \
	"$VENDOR/Frameworks/Virtualization.framework/Virtualization" \
	"$VENDOR/Frameworks/Hypervisor.framework/Hypervisor" \
	"$VENDOR/Frameworks/ParavirtualizedGraphics.framework/ParavirtualizedGraphics" \
	"$VENDOR/Frameworks/MetalSerializer.framework/MetalSerializer" \
	"$VENDOR/VZHostCompat.dylib" \
	"$VMM_OUT/com.apple.Virtualization.VirtualMachine"; do
	[[ -e "$probe" ]] || {
		echo "error: 缺少 $probe" >&2
		exit 1
	}
done

echo "==> 完成"
du -sh "$VENDOR"
