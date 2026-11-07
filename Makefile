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

# Theos 默认会给 FINALPACKAGE 加 -Werror（common.mk 里的 GO_EASY_ON_ME 判断），
# 同时让 Logos 把警告当错误。CI 用的是 Xcode 的 iOS 18.5 SDK，
# 一些 iOS 15 起废弃的 API 会直接把构建打断，这里统一降级为普通警告。
GO_EASY_ON_ME = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidGlassCC LiquidGlassPrefs

LiquidGlassCC_FILES = LiquidGlassCC.x LGGlassRenderer.m
LiquidGlassPrefs_FILES = LiquidGlassEntry.x LiquidGlassPrefs.m

FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

# 双保险：ADDITIONAL_CFLAGS 位于 Theos 内部 CFLAGS 之后，
# 即使上游 Theos 再追加 -Werror，-Wno-error 也能把警告降级。
ADDITIONAL_CFLAGS = -fobjc-arc -Wno-error -Wno-unused-variable -Wno-unused-function

# Preferences.framework 只存在于 Settings 进程，且 roothide 的 SDK
# 通常不带私有框架 stub，运行期动态解析即可。
LiquidGlassPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
