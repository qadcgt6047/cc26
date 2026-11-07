//
//  LiquidGlassEntry.x
//  LiquidGlassCC18 —— Settings.app 侧入口注入
//
//  设计原则（重要）：
//    1. 只「追加」我们自己的分组与链接，绝不读取、修改、替换系统任何已有 PSSpecifier，
//       包括系统原生设置项 —— 全部保持系统原样，本插件连读都不读。
//    2. 主入口挂在 ControlCenter18 自带的设置面板里。CC18 的 PreferenceLoader plist
//       指向 C18PRootListController（定义在 ControlCenter18Prefs.bundle 中），
//       该 bundle 只在用户点开设置项时才加载，所以不能用 %hook C18PRootListController
//       （%ctor 时类还不存在，Logos 会静默跳过）。
//    3. 因此 hook 系统基类 UIViewController / PSListController，在运行时按类名判定，
//       天然规避 tweak 与 PreferenceBundle 的加载顺序问题。
//    4. 两处 hook 互为兜底：viewWillAppear（一定能拿到最终 specifiers 数组）+
//       PSListController -specifiers（子类若调 super 则更早命中）。用 marker 去重。
//

#import "LGCommon.h"
#import "PrefsShims.h"
#import "LiquidGlassPrefs.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char kLGEntryInCC18Key;
static char kLGEntryInRootKey;

#define LG_ENTRY_MARKER @"lgEntry"

#pragma mark - 控制器识别

static BOOL LGIsCC18Root(id controller) {
    NSString *n = NSStringFromClass([controller class]);
    // CC18 的 PreferenceLoader entry 里 detail 写死为 C18PRootListController
    return [n hasPrefix:@"C18PRoot"];
}

static BOOL LGIsSettingsRoot(id controller) {
    NSString *n = NSStringFromClass([controller class]);
    if ([n hasPrefix:@"C18"] || [n isEqualToString:@"LGSettingsListController"]) return NO;
    return [n isEqualToString:@"PSRootController"] ||
           [n isEqualToString:@"PSUIPrefsRootController"] ||
           [n isEqualToString:@"SettingsRootController"] ||
           [n isEqualToString:@"PreferencesRootController"] ||
           [n hasSuffix:@"PrefsRootListController"];
}

#pragma mark - 只追加，不改动任何已有项

static PSSpecifier *LGMakeGroupSpecifier(NSString *title, NSString *footer, id target) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:(title ?: @"")
                                                    target:target set:NULL get:NULL
                                                    detail:Nil
                                                      cell:NSClassFromString(@"PSGroupCell")
                                                      edit:Nil];
    if (footer) [s setProperty:footer forKey:@"footerText"];
    [s setProperty:LG_ENTRY_MARKER forKey:LG_MARKER_KEY];
    return s;
}

static PSSpecifier *LGMakeLinkSpecifier(NSString *title, id target) {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:target set:NULL get:NULL
                                                    detail:[LGSettingsListController class]
                                                      cell:NSClassFromString(@"PSLinkCell")
                                                      edit:Nil];
    [s setProperty:@YES forKey:@"isController"];
    [s setProperty:LG_ENTRY_MARKER forKey:LG_MARKER_KEY];
    return s;
}

static BOOL LGAppendToArray(id controller, NSMutableArray *arr, const void *key,
                            NSString *groupTitle, NSString *footer, NSString *linkTitle) {
    if (objc_getAssociatedObject(controller, key)) return NO;
    if (![arr isKindOfClass:[NSMutableArray class]]) return NO;

    // 数组级去重：换 controller 实例 / 多处 hook 命中时不会重复插入
    for (id obj in (NSArray *)arr) {
        if (![obj respondsToSelector:@selector(propertyForKey:)]) continue;
        id marker = [obj propertyForKey:LG_MARKER_KEY];
        if ([marker isEqualToString:LG_ENTRY_MARKER]) {
            objc_setAssociatedObject(controller, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return NO;
        }
    }

    [arr addObject:LGMakeGroupSpecifier(groupTitle, footer, controller)];
    [arr addObject:LGMakeLinkSpecifier(linkTitle, controller)];
    objc_setAssociatedObject(controller, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// 返回 YES 表示这次真的插入了新项，调用方据此刷新 tableView
static BOOL LGMaybeInject(id controller, NSArray *specifiers) {
    if (![controller isKindOfClass:[UIViewController class]]) return NO;
    NSMutableArray *arr = nil;
    if ([specifiers isKindOfClass:[NSMutableArray class]]) arr = (NSMutableArray *)specifiers;
    if (!arr) return NO;   // 不可变数组不强行改写，避免破坏系统控制器内部状态

    if (LGIsCC18Root(controller)) {
        return LGAppendToArray(controller, arr, &kLGEntryInCC18Key,
                               @"液态玻璃",
                               @"LiquidGlassCC18：给控制中心按钮与模块叠加 SDF 折射边缘、逐通道色散与旋转流光。系统原有设置项不受影响。",
                               @"液态玻璃设置");
    }

    if (LGIsSettingsRoot(controller) && [LGValue(LGLoadSettings(), kLGRootEntry) boolValue]) {
        return LGAppendToArray(controller, arr, &kLGEntryInRootKey,
                               nil, nil, @"控制中心液态玻璃");
    }
    return NO;
}

// 用类型化的 objc_msgSend 取 tableView / table，避开 ARC 下 performSelector: 的
// 「may cause a leak」警告；不同 iOS 版本 PSListController 暴露的属性名不同，两个都试。
static id LGSendNoArg(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id (*fn)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return fn(obj, sel);
}

static void LGReloadTable(id controller) {
    id tv = LGSendNoArg(controller, @selector(tableView));
    if (![tv isKindOfClass:[UITableView class]])
        tv = LGSendNoArg(controller, @selector(table));
    if ([tv isKindOfClass:[UITableView class]]) [(UITableView *)tv reloadData];
}

#pragma mark - Hooks

%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    BOOL changed = NO;
    @autoreleasepool {
        if ([self respondsToSelector:@selector(specifiers)]) {
            changed = LGMaybeInject(self, [(id)self specifiers]);
        }
    }
    %orig(animated);
    if (changed) LGReloadTable(self);
}

%end

%hook PSListController

- (NSArray *)specifiers {
    NSArray *specs = %orig;
    if (LGMaybeInject(self, specs)) {
        // 异步刷新，避免在 -specifiers 调用链里重入 tableView
        __weak id weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ LGReloadTable(weakSelf); });
    }
    return specs;
}

%end
