# LiquidGlassCC18 —— ControlCenter18 液态玻璃（iOS 16 / roothide）
#
# 独立插件：不包含、不依赖 SiriAI16 / 跑马灯，也不修改系统 Siri 设置项。
# 构建：make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
# 需要 roothide/theos（不是官方 theos），见 README.md
#
# 两个 tweak 实例：
#   LiquidGlassCC    -> 只注入 SpringBoard，绘制玻璃
#   LiquidGlassPrefs -> 只注入 Preferences.app，追加设置入口与面板
# 拆开的原因：PSListController 只存在于 Settings 进程，编进 SpringBoard 会出问题。

TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidGlassCC LiquidGlassPrefs

LiquidGlassCC_FILES = LiquidGlassCC.x LGGlassRenderer.m
LiquidGlassPrefs_FILES = LiquidGlassEntry.x LiquidGlassPrefs.m

FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

ADDITIONAL_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-unused-function

# Preferences.framework 只存在于 Settings 进程，且 roothide 的 SDK
# 通常不带私有框架 stub，运行期动态解析即可。
LiquidGlassPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
