//
//  LiquidGlassCC.x
//  LiquidGlassCC18 —— ControlCenter18 液态玻璃注入层
//
//  目标进程：com.apple.springboard（与 ControlCenter18.dylib 相同）
//
//  为什么 hook UIView 而不是逐个 hook C18* 类：
//  ControlCenter18 的自定义类是在它自己的 dylib 加载时才注册到 ObjC runtime 的，
//  tweak 的加载顺序不确定，Logos 的 %hook C18RoundButton 在 %ctor 执行时若类还不存在
//  会静默跳过，导致完全不生效。这里改为 hook 系统类 UIView 的 didMoveToWindow，
//  在视图真正进入 window 时按类名动态判定并挂载，天然规避加载顺序问题。
//
//  性能优化：Class -> 分组 的判定结果缓存在 Class 对象的关联对象上（O(1)），
//  不匹配的类第一次判定后就是一次指针查询；玻璃贴图按尺寸/参数全局缓存。
//

#import "LGCommon.h"
#import "LGGlassRenderer.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static char kLGClassGroupKey;
static char kLGGlassKey;
static char kLGBlurKey;

static NSDictionary *s_settings = nil;
static BOOL s_ready = NO;
static NSInteger const kLGBlurTag = 0x4C474244;   // 'LGBD'

static NSHashTable *LGGlassTable(void) {
    static NSHashTable *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

#pragma mark - 类名分组

static LGGroup LGClassifyName(NSString *n) {
    if (![n hasPrefix:@"C18"]) return LGGroupNone;

    // 页面指示器 / 小圆点
    if ([n containsString:@"PageIndicator"] || [n isEqualToString:@"C18PageControl"])
        return LGGroupPage;

    // 亮度 / 音量滑块
    if ([n containsString:@"Brightness"] || [n containsString:@"Volume"] ||
        [n containsString:@"Slider"] || [n containsString:@"AVControls"])
        return LGGroupSlider;

    // 展开后的大面板 / 背景容器
    if ([n containsString:@"Expandable"] || [n containsString:@"FocusView"] ||
        [n containsString:@"ConnectivityView"] || [n containsString:@"NowPlayingView"] ||
        [n containsString:@"Shell"] || [n containsString:@"PageView"] ||
        [n containsString:@"BackgroundHolder"] || [n containsString:@"ResizeBackdropView"] ||
        [n containsString:@"MicModeView"] || [n containsString:@"VideoEffectsView"])
        return LGGroupExpanded;

    // 模块底板（含 C18ButtonModuleView，它是模块不是按钮）
    if ([n containsString:@"ModuleView"] || [n containsString:@"Tile"] ||
        [n containsString:@"GalleryTileView"] || [n containsString:@"HomeView"] ||
        [n containsString:@"PassThroughView"])
        return LGGroupModule;

    // 圆形 / 强调按钮
    if ([n containsString:@"Button"] || [n containsString:@"EffectControl"] ||
        [n containsString:@"PowerGlyphView"])
        return LGGroupButton;

    // 用户自定义类名关键字，逗号分隔
    NSString *extra = [LGValue(s_settings, kLGExtraClasses) description] ?: @"";
    for (NSString *kw in [extra componentsSeparatedByString:@","]) {
        NSString *t = [kw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length >= 2 && [n containsString:t]) return LGGroupButton;
    }
    return LGGroupNone;
}

static LGGroup LGGroupForClass(Class cls) {
    id cached = objc_getAssociatedObject((id)cls, &kLGClassGroupKey);
    if (cached) return (LGGroup)[cached integerValue];
    LGGroup group = LGClassifyName(NSStringFromClass(cls));
    objc_setAssociatedObject((id)cls, &kLGClassGroupKey, @(group),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return group;
}

static BOOL LGGroupEnabled(LGGroup group) {
    if (![LGValue(s_settings, kLGEnabled) boolValue]) return NO;
    switch (group) {
        case LGGroupButton:   return [LGValue(s_settings, kLGButtons) boolValue];
        case LGGroupModule:   return [LGValue(s_settings, kLGModules) boolValue];
        case LGGroupSlider:   return [LGValue(s_settings, kLGSliders) boolValue];
        case LGGroupExpanded: return [LGValue(s_settings, kLGExpanded) boolValue];
        case LGGroupPage:     return [LGValue(s_settings, kLGPage) boolValue];
        default: return NO;
    }
}

#pragma mark - 背景模糊层

static void LGEnsureBackdrop(UIView *host, LGGroup group, NSDictionary *s) {
    NSInteger mode = [LGValue(s, kLGMode) integerValue];
    UIVisualEffectView *blur = objc_getAssociatedObject(host, &kLGBlurKey);

    if (mode < 1) {
        if (blur) {
            [blur removeFromSuperview];
            objc_setAssociatedObject(host, &kLGBlurKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    if (!blur) {
        UIBlurEffectStyle style = UIBlurEffectStyleLight;
        if (host.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
            style = UIBlurEffectStyleDark;
        blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
        blur.userInteractionEnabled = NO;
        blur.tag = kLGBlurTag;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // 插到最底层：在宿主自身背景之上、图标/文字之下，不会糊掉内容
        [host insertSubview:blur atIndex:0];
        objc_setAssociatedObject(host, &kLGBlurKey, blur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    blur.frame = host.bounds;
    CGFloat r = [LGValue(s, kLGCornerRadius) doubleValue];
    if (r <= 0.0) r = LGAutoCornerRadius(host.bounds.size, group);
    blur.layer.cornerRadius = LGClampf(r, 2.0, MIN(host.bounds.size.width, host.bounds.size.height) * 0.5);
    blur.clipsToBounds = YES;
    blur.alpha = LGClampf([LGValue(s, kLGBlurOpacity) doubleValue], 0.0, 1.0) * 0.55;
    blur.hidden = ![LGValue(s, kLGEnabled) boolValue];

    // mode 2：把模糊层轻微放大，模拟 AndroidLiquidGlass 材质配方里的 zoom 折射感
    if (mode >= 2) {
        CGFloat zoom = 1.0 + LGClampf([LGValue(s, kLGLensZoom) doubleValue], 0.0, 0.25);
        blur.transform = CGAffineTransformMakeScale(zoom, zoom);
    } else {
        blur.transform = CGAffineTransformIdentity;
    }
}

#pragma mark - 挂载

static void LGAttach(UIView *host, LGGroup group) {
    if (objc_getAssociatedObject(host, &kLGGlassKey)) return;
    NSInteger limit = MAX(4, [LGValue(s_settings, kLGMaxViews) integerValue]);
    if ((NSInteger)[LGGlassTable() count] >= limit) return;
    if (host.bounds.size.width < 8.0 || host.bounds.size.height < 8.0) return;

    LGGlassView *glass = [[LGGlassView alloc] initWithFrame:host.bounds];
    glass.group = group;
    glass.hostView = host;
    [glass applySettings:s_settings];
    // 最上层、不吃触摸；SDF 贴图中心全透明，只画圆角边缘，不会遮住图标与文字
    [host addSubview:glass];
    objc_setAssociatedObject(host, &kLGGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [LGGlassTable() addObject:glass];

    LGEnsureBackdrop(host, group, s_settings);
}

static void LGAttachIfNeeded(UIView *view) {
    if (!view || [view isKindOfClass:[LGGlassView class]]) return;
    if (view.tag == kLGBlurTag) return;
    LGGroup group = LGGroupForClass(object_getClass(view));
    if (group == LGGroupNone) return;
    if (!LGGroupEnabled(group)) return;
    LGAttach(view, group);
}

static void LGScanView(UIView *root, NSInteger depth) {
    if (!root || depth > 12) return;
    LGAttachIfNeeded(root);
    for (UIView *sub in root.subviews) LGScanView(sub, depth + 1);
}

static void LGRescanWindows(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;
    for (UIWindow *window in app.windows) LGScanView(window, 0);
}

#pragma mark - 通知

static void LGOnNotify(CFNotificationCenterRef center, void *observer, CFStringRef name,
                       const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        s_settings = LGMergedSettings();
        for (LGGlassView *g in [[LGGlassTable() allObjects] copy]) {
            [g applySettings:s_settings];
            g.hidden = !LGGroupEnabled(g.group);
            UIView *host = g.hostView;
            if (host) LGEnsureBackdrop(host, g.group, s_settings);
        }
        if (name && CFStringCompare(name, LG_N_REFRESH, 0) == kCFCompareEqualTo) {
            LGRescanWindows();
        }
    });
}

#pragma mark - Hooks

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (!s_ready || !self.window) return;
    LGAttachIfNeeded(self);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    if (![LGValue(s_settings, kLGPress) boolValue]) return;
    LGGlassView *g = objc_getAssociatedObject(self, &kLGGlassKey);
    if (g) [g setPressed:YES];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    LGGlassView *g = objc_getAssociatedObject(self, &kLGGlassKey);
    if (g) [g setPressed:NO];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    LGGlassView *g = objc_getAssociatedObject(self, &kLGGlassKey);
    if (g) [g setPressed:NO];
}

%end

%ctor {
    @autoreleasepool {
        %init;
        s_settings = LGMergedSettings();
        s_ready = YES;

        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, LGOnNotify, LG_N_PREFS, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(darwin, NULL, LGOnNotify, LG_N_REFRESH, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);

        // 控制中心视图可能在 tweak 加载前就已进 window，补一次全量扫描
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ LGRescanWindows(); });
    }
}
