#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 twoyears666
#
# 生成 vfl 自带的 Virtualization 运行时。提取 / uncache / stamp_ios 的全部逻辑
# 复用 nfzerox/VirtualMacOniPad（MIT License），这里只做「组装 + 重签 + 清单」。
#
# 用法：
#   VZ_REF=/tmp/vmoi \
#   VZ_BUILD_ROOT=/tmp/vmoi/VirtualMac/build \
#   tools/build-vz-frameworks.sh
#
# 前置条件（都在 Mac 上）：
#   1. VMOI 仓库已 clone，且按它的 README 准备了 IPSW 与 toolchain；
#   2. 已生成 frameworks/bundles/ios/{Virtualization,Hypervisor,
#      ParavirtualizedGraphics,MetalSerializer}.framework；
#   3. 已运行 VMOI 的 scripts/build-ipad-vm.sh 得到 ipad-vm/payload。
# 产物写到 vendor/app（不入库），Makefile 会自动打进 VFL.app。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VZ_REF="${VZ_REF:-/tmp/vmoi}"
VZ_BUILD_ROOT="${VZ_BUILD_ROOT:-$VZ_REF/VirtualMac/build}"
VENDOR="${VENDOR:-$REPO_ROOT/vendor/app}"
IOS_BUNDLES="$VZ_BUILD_ROOT/frameworks/bundles/ios"
PAYLOAD="$VZ_BUILD_ROOT/ipad-vm/payload"

die() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || die "只能在 macOS 上生成框架"
[[ -d "$VZ_REF/VirtualMac/scripts" ]] || die "找不到 VMOI：请先 git clone --depth 1 https://github.com/nfzerox/VirtualMacOniPad.git \"$VZ_REF\""

# === 一、提取并重签框架 —— 直接跑 VMOI 的管线 ===
if [[ ! -d "$IOS_BUNDLES/Virtualization.framework" ]]; then
	echo "==> 运行 VMOI build-frameworks.sh（需要 IPSW 的 DSC）"
	VZ_BUILD_ROOT="$VZ_BUILD_ROOT" "$VZ_REF/VirtualMac/scripts/build-frameworks.sh"
fi
for name in Virtualization Hypervisor ParavirtualizedGraphics MetalSerializer; do
	[[ -d "$IOS_BUNDLES/$name.framework" ]] || die "缺少 $name.framework（检查 VZ_BUILD_ROOT=$VZ_BUILD_ROOT）"
done

# === 二、host hook 与 VMM —— 由 VMOI build-ipad-vm.sh 产出 ===
[[ -f "$PAYLOAD/VZHostCompat.dylib" ]] ||
	die "缺少 VZHostCompat.dylib：先在 VMOI 里跑 scripts/build-ipad-vm.sh"
[[ -d "$PAYLOAD/VirtualMachine.xpc" ]] ||
	die "缺少 VirtualMachine.xpc：先在 VMOI 里跑 scripts/build-ipad-vm.sh"

# === 三、组装 vendor/app ===
rm -rf "$VENDOR"
mkdir -p "$VENDOR/Frameworks"
cp -R "$PAYLOAD/Frameworks/." "$VENDOR/Frameworks/"
for name in Virtualization Hypervisor ParavirtualizedGraphics MetalSerializer; do
	rm -rf "$VENDOR/Frameworks/$name.framework"
	cp -R "$IOS_BUNDLES/$name.framework" "$VENDOR/Frameworks/"
done
cp "$PAYLOAD/VZHostCompat.dylib" "$VENDOR/"
rm -rf "$VENDOR/VirtualMachine.xpc"
cp -R "$PAYLOAD/VirtualMachine.xpc" "$VENDOR/"

# === 四、重签 ===
# VMM 自带一整套特权 entitlements，必须原样保留；其余代码 ad-hoc 重签即可。
find "$VENDOR/Frameworks" -maxdepth 1 -name '*.framework' -type d -print0 |
	while IFS= read -r -d '' framework; do
		codesign --force --sign - "$framework"
		codesign --verify --strict "$framework"
	done
find "$VENDOR/Frameworks" -maxdepth 1 -name '*.dylib' -type f -print0 |
	while IFS= read -r -d '' dylib; do
		codesign --force --sign - "$dylib"
	done
codesign --force --sign - "$VENDOR/VZHostCompat.dylib"
codesign --verify --deep --strict "$VENDOR/VZHostCompat.dylib" || true
find "$VENDOR/VirtualMachine.xpc" -type f -perm -111 -print0 |
	while IFS= read -r -d '' binary; do
		codesign --force --sign - \
			--preserve-metadata=entitlements,flags,runtime "$binary"
	done

# === 五、清单 —— 便于核对版本与哈希 ===
{
	echo "VFL_VZ_MANIFEST 1"
	echo "generated_utc	$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "vmoi_commit	$(git -C "$VZ_REF" rev-parse HEAD 2>/dev/null || echo unknown)"
	for framework in "$VENDOR"/Frameworks/Virtualization.framework \
					 "$VENDOR"/Frameworks/Hypervisor.framework \
					 "$VENDOR"/Frameworks/ParavirtualizedGraphics.framework \
					 "$VENDOR"/Frameworks/MetalSerializer.framework; do
		binary="$(basename "$framework" .framework)"
		file="$framework/$binary"
		if [[ -f "$file" ]]; then
			printf '%s\t%s\t%s\n' "$binary" \
				"$(shasum -a 256 "$file" | awk '{print $1}')" \
				"$(dwarfdump --uuid "$file" | awk '{print $2}')"
		fi
	done
} > "$REPO_ROOT/vendor/MANIFEST.txt"

echo "done: $VENDOR"
echo "      $REPO_ROOT/vendor/MANIFEST.txt"
