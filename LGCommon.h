//
//  LGCommon.h
//  LiquidGlassCC18 —— ControlCenter18 液态玻璃插件
//
//  独立插件，不依赖任何其它插件，也不读取其它插件的配置。
//  SpringBoard 侧 (LiquidGlassCC.dylib) 与 Settings 侧 (LiquidGlassPrefs.dylib)
//  共用的配置读写、默认值、Darwin 通知名与配色。
//
//  配置放在 NSHomeDirectory()/Library/Preferences/，
//  在 rootful / rootless / roothide 下都无需 jbroot 路径转换。
//

#ifndef LGCommon_h
#define LGCommon_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

#define LG_PREFS_DOMAIN   @"com.lgcc18.glass"
#define LG_N_PREFS        CFSTR("com.lgcc18.glass/changed")
#define LG_N_REFRESH      CFSTR("com.lgcc18.glass/refresh")

// PSSpecifier 上自定义 marker 键（只用于我们自己追加的项，不改系统任何一项）
#define LG_MARKER_KEY     @"LGKey"
#define LG_MARKER_ACTION  @"LGAction"

// 配置键（统一 lg 前缀）
#define kLGEnabled          @"lgEnabled"
#define kLGButtons          @"lgButtons"        // 圆形 / 强调按钮
#define kLGModules          @"lgModules"        // 模块底板
#define kLGSliders          @"lgSliders"        // 亮度 / 音量滑块
#define kLGExpanded         @"lgExpanded"       // 展开后的大面板
#define kLGPage             @"lgPage"           // 页面指示器
#define kLGMode             @"lgMode"           // 0 仅高光 / 1 系统模糊 / 2 背景放大折射
#define kLGBlurOpacity      @"lgBlurOpacity"
#define kLGLensZoom         @"lgLensZoom"
#define kLGTint             @"lgTint"
#define kLGHeight           @"lgHeight"         // refractionHeight (pt)
#define kLGAmount           @"lgAmount"         // refractionAmount (pt)
#define kLGDispersion       @"lgDispersion"     // chromaticAberration
#define kLGDepth            @"lgDepth"          // depthEffect
#define kLGHighlight        @"lgHighlight"
#define kLGEdgeWidth        @"lgEdgeWidth"
#define kLGCornerRadius     @"lgCornerRadius"   // 0 = 自动
#define kLGPalette          @"lgPalette"        // 0..3 内置配色
#define kLGSpin             @"lgSpin"           // 0 = 关闭流光旋转
#define kLGPress            @"lgPress"
#define kLGExtraClasses     @"lgExtraClasses"   // 逗号分隔的类名关键字
#define kLGMaxViews         @"lgMaxViews"       // 安全阀：最多挂多少个玻璃层
#define kLGRootEntry        @"lgRootEntry"      // 是否在设置首页追加独立入口

// 目标分组（用于按类别开关、以及自动圆角策略）
typedef NS_ENUM(NSInteger, LGGroup) {
    LGGroupNone     = 0,
    LGGroupButton   = 1,
    LGGroupModule   = 2,
    LGGroupSlider   = 3,
    LGGroupExpanded = 4,
    LGGroupPage     = 5
};

NS_INLINE NSString *LGPrefsPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Preferences/com.lgcc18.glass.plist"];
}

NS_INLINE NSDictionary *LGLoadSettings(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:LGPrefsPath()];
    return d ?: @{};
}

NS_INLINE void LGSaveSettings(NSDictionary *settings) {
    NSString *path = LGPrefsPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [settings writeToFile:path atomically:YES];
}

NS_INLINE NSDictionary *LGDefaults(void) {
    static NSDictionary *defaults = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            kLGEnabled:       @YES,
            kLGButtons:       @YES,
            kLGModules:       @YES,
            kLGSliders:       @YES,
            kLGExpanded:      @NO,
            kLGPage:          @NO,
            kLGMode:          @1,      // 叠加系统模糊
            kLGBlurOpacity:   @0.55,
            kLGLensZoom:      @0.045,
            kLGTint:          @0.16,
            kLGHeight:        @20.0,   // SDF 内折射带宽
            kLGAmount:        @16.0,   // 折射位移
            kLGDispersion:    @0.65,   // 逐通道色散强度
            kLGDepth:         @0.35,
            kLGHighlight:     @0.58,
            kLGEdgeWidth:     @2.0,
            kLGCornerRadius:  @0,      // 0 = 按宿主自动
            kLGPalette:       @0,      // Apple Intelligence
            kLGSpin:          @6.0,    // 秒/圈，0 = 静止
            kLGPress:         @YES,
            kLGExtraClasses:  @"",
            kLGMaxViews:      @48,
            kLGRootEntry:     @YES
        };
    });
    return defaults;
}

// 合并默认值 + 磁盘值，供渲染侧一次性读取
NS_INLINE NSDictionary *LGMergedSettings(void) {
    NSMutableDictionary *m = [LGDefaults() mutableCopy];
    NSDictionary *disk = LGLoadSettings();
    if (disk.count) [m addEntriesFromDictionary:disk];
    return [m copy];
}

NS_INLINE id LGValue(NSDictionary *settings, NSString *key) {
    id v = settings[key];
    return v ?: LGDefaults()[key];
}

NS_INLINE void LGPost(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         name, NULL, NULL, YES);
}

NS_INLINE CGFloat LGClampf(CGFloat v, CGFloat lo, CGFloat hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

#pragma mark - 内置配色（不依赖任何其它插件）

NS_INLINE UIColor *LGColorFromHex(NSString *hex) {
    if (hex.length < 6) return [UIColor whiteColor];
    unsigned int value = 0;
    NSString *h = [hex stringByTrimmingCharactersInSet:
                   [NSCharacterSet characterSetWithCharactersInString:@"#"]];
    NSScanner *scanner = [NSScanner scannerWithString:h];
    if (![scanner scanHexInt:&value]) return [UIColor whiteColor];
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
                           green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0
                           alpha:1.0];
}

NS_INLINE NSArray<UIColor *> *LGPaletteColors(NSInteger index) {
    NSArray *hexes;
    switch (index) {
        case 1:  // 极光蓝紫
            hexes = @[@"#00E5FF", @"#3B82F6", @"#8B5CF6", @"#22D3EE", @"#00E5FF"];
            break;
        case 2:  // 霓虹彩虹
            hexes = @[@"#FF2D55", @"#FF9500", @"#FFCC00", @"#34C759",
                      @"#00C7BE", @"#5E5CE6", @"#FF2D55"];
            break;
        case 3:  // 银白单色
            hexes = @[@"#FFFFFF", @"#AEAEB2", @"#F2F2F7", @"#8E8E93", @"#FFFFFF"];
            break;
        default: // Apple Intelligence 观感
            hexes = @[@"#BC82F3", @"#F5B9EA", @"#8D9FFF", @"#AA6EEE",
                      @"#FF6778", @"#FFBA71", @"#C686FF", @"#BC82F3"];
            break;
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:hexes.count];
    for (NSString *h in hexes) [out addObject:LGColorFromHex(h)];
    return out;
}

#endif /* LGCommon_h */
