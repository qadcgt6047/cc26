//
//  LGGlassRenderer.h
//  ControlCenter18 液态玻璃渲染器（iOS 16 / Objective-C / 纯 CPU 光栅化）
//
//  算法来源：Kyant0/AndroidLiquidGlass 2.0.0-alpha03
//    backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt
//  移植了其中的 sdRoundedRect / gradSdRoundedRect / circleMap 与
//  「7 次采样逐通道色散」的 RoundedRectRefractionWithDispersionShaderString
//  以及 DefaultHighlightShaderString 的高光项。
//  原工程为 Apache-2.0，Copyright 2025 Kyant，版权声明见文件末尾与 README。
//
//  与 Android 版的区别：AGSL 的 content.eval() 采样的是真实背景纹理，
//  iOS 16 的 SpringBoard 里没有等价物，因此这里：
//    - 真实背景模糊交给 UIVisualEffectView / CABackdropLayer（见 LGGlassView）；
//    - CPU 只对「玻璃边缘那一圈」按同一套 SDF 数学合成折射 / 色散 / 高光贴图。
//  结果是一张可缓存的半透明边缘贴图，不是全屏实时折射。
//

#ifndef LGGlassRenderer_h
#define LGGlassRenderer_h

#import <UIKit/UIKit.h>
#import "LGCommon.h"

@class UIColor;

// 按宿主分组自动推断圆角（按钮接近正圆，模块为 iOS 18 风格的大圆角矩形）
CGFloat LGAutoCornerRadius(CGSize size, LGGroup group);

@interface LGGlassView : UIView
@property (nonatomic, assign) LGGroup group;
@property (nonatomic, weak)   UIView  *hostView;
- (void)applySettings:(NSDictionary *)settings;
- (void)setPressed:(BOOL)pressed;
@end

#endif /* LGGlassRenderer_h */
