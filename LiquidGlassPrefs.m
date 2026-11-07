//
//  LiquidGlassPrefs.m
//  ControlCenter18 液态玻璃 —— Settings.app 侧面板
//
//  编译进 LiquidGlassPrefs.dylib（只注入 Preferences.app），
//  因为 PSListController 只存在于 Settings 进程。
//

#import "LiquidGlassPrefs.h"
#import "LGCommon.h"
#import <objc/runtime.h>

static char kLGSpecsKey;

@interface LGSettingsListController ()
- (NSMutableArray *)buildSpecifiers;
- (PSSpecifier *)makeGroup:(NSString *)title footer:(NSString *)footer;
- (PSSpecifier *)makeCell:(NSString *)title
                cellClass:(NSString *)cellClass
              detailClass:(Class)detailClass
                      key:(NSString *)key
                    extra:(NSDictionary *)extra;
- (PSSpecifier *)makeAction:(NSString *)title selector:(SEL)selector;
- (void)refreshAction;
- (void)resetAction;
@end

@implementation LGSettingsListController

- (NSArray *)specifiers {
    NSMutableArray *specs = objc_getAssociatedObject(self, &kLGSpecsKey);
    if (!specs) {
        specs = [self buildSpecifiers];
        objc_setAssociatedObject(self, &kLGSpecsKey, specs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return specs;
}

- (PSSpecifier *)makeGroup:(NSString *)title footer:(NSString *)footer {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:(title ?: @"")
                                                    target:self set:NULL get:NULL
                                                    detail:Nil
                                                      cell:NSClassFromString(@"PSGroupCell")
                                                      edit:Nil];
    if (footer) [s setProperty:footer forKey:@"footerText"];
    return s;
}

- (PSSpecifier *)makeCell:(NSString *)title
                cellClass:(NSString *)cellClass
              detailClass:(Class)detailClass
                      key:(NSString *)key
                    extra:(NSDictionary *)extra {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:detailClass
                                                      cell:NSClassFromString(cellClass)
                                                      edit:Nil];
    if (key) {
        [s setProperty:key forKey:LG_MARKER_KEY];
        [s setProperty:key forKey:@"key"];
        [s setProperty:LG_PREFS_DOMAIN forKey:@"defaults"];
        id def = LGDefaults()[key];
        if (def) [s setProperty:def forKey:@"default"];
    }
    for (NSString *k in extra) [s setProperty:extra[k] forKey:k];
    return s;
}

- (PSSpecifier *)makeAction:(NSString *)title selector:(SEL)selector {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self set:NULL get:NULL
                                                    detail:Nil
                                                      cell:NSClassFromString(@"PSButtonCell")
                                                      edit:Nil];
    NSString *selName = NSStringFromSelector(selector);
    [s setProperty:selName forKey:LG_MARKER_ACTION];
    // PSButtonCell 点击时读的是 action / buttonAction，不设这两个按钮不会响应
    [s setProperty:selName forKey:@"action"];
    [s setProperty:selName forKey:@"buttonAction"];
    [s setProperty:@YES forKey:@"enabled"];
    return s;
}

#pragma mark 面板内容

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *s = [NSMutableArray array];

    [s addObject:[self makeGroup:@"液态玻璃"
                          footer:@"给 ControlCenter18 的按钮、模块与滑块叠加一圈 SDF 折射边缘、逐通道色散与旋转流光。修改即时生效，无需 Respring。"]];
    [s addObject:[self makeCell:@"启用液态玻璃"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGEnabled extra:nil]];
    [s addObject:[self makeAction:@"立即刷新控制中心" selector:@selector(refreshAction)]];

    [s addObject:[self makeGroup:@"作用范围"
                          footer:@"只处理类名以 C18 开头的视图。展开大面板与页面指示器面积较大，默认关闭。"]];
    [s addObject:[self makeCell:@"圆形 / 强调按钮"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGButtons extra:nil]];
    [s addObject:[self makeCell:@"模块底板"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGModules extra:nil]];
    [s addObject:[self makeCell:@"亮度 / 音量滑块"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGSliders extra:nil]];
    [s addObject:[self makeCell:@"展开后的大面板"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGExpanded extra:nil]];
    [s addObject:[self makeCell:@"页面指示器"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGPage extra:nil]];

    [s addObject:[self makeGroup:@"材质"
                          footer:@"「仅流光」性能开销最低；「系统模糊」额外叠一层 UIVisualEffectView；「背景放大」再轻微缩放模糊层，近似材质配方里的 zoom 折射。真·实时背景折射在 iOS 16 上不可用。"]];
    [s addObject:[self makeCell:@"材质模式"
                      cellClass:@"PSLinkListCell"
                    detailClass:NSClassFromString(@"PSListItemsController")
                            key:kLGMode
                          extra:@{@"values": @[@0, @1, @2],
                                  @"titles": @[@"仅流光与折射", @"系统模糊 + 玻璃", @"模糊 + 背景放大"]}]];
    [s addObject:[self makeCell:@"配色方案"
                      cellClass:@"PSLinkListCell"
                    detailClass:NSClassFromString(@"PSListItemsController")
                            key:kLGPalette
                          extra:@{@"values": @[@0, @1, @2, @3],
                                  @"titles": @[@"Apple Intelligence", @"极光蓝紫", @"霓虹彩虹", @"银白单色"]}]];
    [s addObject:[self makeCell:@"流光速度（秒/圈，0 = 静止）"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGSpin
                          extra:@{@"min": @0.0, @"max": @12.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"模糊浓度"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGBlurOpacity
                          extra:@{@"min": @0.0, @"max": @1.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"背景放大"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGLensZoom
                          extra:@{@"min": @0.0, @"max": @0.2, @"showValue": @YES}]];

    [s addObject:[self makeGroup:@"折射与高光"
                          footer:@"这些参数直接对应 AndroidLiquidGlass 的 Lens 效果：refractionHeight / refractionAmount / chromaticAberration / depthEffect。带宽与位移越大，边缘越厚越亮，光栅化也越慢。"]];
    [s addObject:[self makeCell:@"折射带宽"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGHeight
                          extra:@{@"min": @4.0, @"max": @48.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"折射位移"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGAmount
                          extra:@{@"min": @0.0, @"max": @40.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"逐通道色散"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGDispersion
                          extra:@{@"min": @0.0, @"max": @2.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"深度效果"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGDepth
                          extra:@{@"min": @0.0, @"max": @1.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"高光强度"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGHighlight
                          extra:@{@"min": @0.0, @"max": @1.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"边缘光带宽度"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGEdgeWidth
                          extra:@{@"min": @0.5, @"max": @8.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"圆角半径（0 = 自动）"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGCornerRadius
                          extra:@{@"min": @0.0, @"max": @80.0, @"showValue": @YES}]];
    [s addObject:[self makeCell:@"白色调混合"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGTint
                          extra:@{@"min": @0.0, @"max": @0.6, @"showValue": @YES}]];

    [s addObject:[self makeGroup:@"高级"
                          footer:@"若某类控件没有玻璃效果，把它的类名关键字加进下面（英文逗号分隔）。「最大玻璃层数量」是安全阀，超出后不再挂载新层。"]];
    [s addObject:[self makeCell:@"按压反馈"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGPress extra:nil]];
    [s addObject:[self makeCell:@"在设置首页显示入口"
                      cellClass:@"PSSwitchCell" detailClass:Nil key:kLGRootEntry extra:nil]];
    [s addObject:[self makeCell:@"额外类名关键字"
                      cellClass:@"PSEditTextCell" detailClass:Nil key:kLGExtraClasses
                          extra:@{@"placeholder": @"例如 MyModule,MyButton"}]];
    [s addObject:[self makeCell:@"最大玻璃层数量"
                      cellClass:@"PSSliderCell" detailClass:Nil key:kLGMaxViews
                          extra:@{@"min": @8.0, @"max": @120.0, @"showValue": @YES}]];

    [s addObject:[self makeGroup:nil
                          footer:@"LiquidGlassCC18 1.0.0 · iOS 16 / roothide (arm64e)\nSDF 折射 / 色散数学移植自 Kyant0/AndroidLiquidGlass 2.0.0-alpha03（Apache-2.0, Copyright 2025 Kyant）。这是视觉近似，不是 iOS 26 的 UIGlassEffect，也不做实时背景折射。"]];
    [s addObject:[self makeAction:@"恢复默认设置" selector:@selector(resetAction)]];

    return s;
}

#pragma mark 读写配置（直接读写 plist，绕开 cfprefsd，跨进程立即可见）

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:LG_MARKER_KEY];
    if (!key) return nil;
    id v = LGLoadSettings()[key];
    return v ?: LGDefaults()[key];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:LG_MARKER_KEY];
    if (!key || !value) return;
    NSMutableDictionary *d = [LGLoadSettings() mutableCopy];
    d[key] = value;
    LGSaveSettings(d);
    LGPost(LG_N_PREFS);

    static NSSet *rescanKeys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rescanKeys = [NSSet setWithObjects:kLGEnabled, kLGButtons, kLGModules,
                      kLGSliders, kLGExpanded, kLGPage, kLGExtraClasses, kLGMaxViews, nil];
    });
    if ([rescanKeys containsObject:key]) LGPost(LG_N_REFRESH);
}

#pragma mark 动作

- (void)refreshAction {
    LGPost(LG_N_PREFS);
    LGPost(LG_N_REFRESH);
}

- (void)resetAction {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置"
                                                                  message:@"所有液态玻璃选项会重置为初始值。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[NSFileManager defaultManager] removeItemAtPath:LGPrefsPath() error:NULL];
        objc_setAssociatedObject(strongSelf, &kLGSpecsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LGPost(LG_N_PREFS);
        LGPost(LG_N_REFRESH);
        if ([strongSelf respondsToSelector:@selector(reloadSpecifiers)]) [strongSelf reloadSpecifiers];
        if ([strongSelf respondsToSelector:@selector(reload)]) [strongSelf reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
