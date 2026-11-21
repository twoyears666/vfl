export ARCHS = arm64
export TARGET = iphone:clang:latest:16.0
export THEOS_PACKAGE_SCHEME = rootless
export PACKAGE_VERSION = 0.2.0

include $(THEOS)/makefiles/common.mk

# 守护进程与 GUI/CLI 共用的核心：VZ 绑定、定义、会话、客户端。
VFL_SHARED_FILES = src/VFLVirtualization.m \
                   src/VFLVMDefinition.m \
                   src/VFLMachineSession.m \
                   src/VFLClient.m

# === GUI —— 列表 / 配置 / 串口控制台 ===
# 终端视图依赖 UIKit，只进 App；vfl 命令行只链 Foundation。
APPLICATION_NAME = VFL
VFL_FILES = $(wildcard app/*.m) \
            $(VFL_SHARED_FILES) \
            src/VFLTerminalEmulator.m \
            src/VFLTerminalView.m
VFL_FRAMEWORKS = UIKit Foundation
VFL_CFLAGS = -fobjc-arc -Wall -Isrc
VFL_CODESIGN_FLAGS = -Sentitlements.plist
VFL_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk

# === CLI —— vfl list/start/control/shut/kill，另带 daemon 子命令 ===
TOOL_NAME = vfl
vfl_FILES = cli/main.m \
            $(VFL_SHARED_FILES) \
            src/VFLServer.m
vfl_FRAMEWORKS = Foundation
vfl_CFLAGS = -fobjc-arc -Wall -Isrc
vfl_CODESIGN_FLAGS = -Sentitlements.plist
vfl_INSTALL_PATH = /usr/bin
include $(THEOS_MAKE_PATH)/tool.mk
