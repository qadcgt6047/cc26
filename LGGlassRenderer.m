//
//  LGGlassRenderer.m
//  ControlCenter18 液态玻璃渲染器（iOS 16 / Objective-C / 纯 CPU 光栅化）
//
//  算法来源：Kyant0/AndroidLiquidGlass 2.0.0-alpha03
//    backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt
//    backdrop/src/commonMain/kotlin/com/kyant/backdrop/effects/Lens.kt
//
//    Copyright 2025 Kyant
//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at
//        http://www.apache.org/licenses/LICENSE-2.0
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//
//  本文件直译了上游的 sdRoundedRect / gradSdRoundedRect / circleMap，
//  以及 RoundedRectRefractionWithDispersionShaderString 的 7 次采样逐通道色散
//  和 DefaultHighlightShaderString 的法线高光项。
//
//  差异说明（重要）：AGSL 的 content.eval() 采样的是真实背景纹理；iOS 16 的
//  SpringBoard 进程里没有等价物。这里用「调色板角向渐变 + 亮度梯度」构造一张
//  虚拟背景纹理来参与同样的采样数学，因此得到的是视觉近似的折射/色散边缘，
//  而不是物理正确的实时背景折射。真实背景模糊交给 UIVisualEffectView。
//  贴图按 (尺寸, 圆角, 参数) 全局缓存，只在尺寸或设置变化时重算一次。
//

#import "LGGlassRenderer.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#pragma mark - SDF 数学（直译自 Shaders.kt）

typedef struct { CGFloat x, y; } LGVec2;
typedef struct { CGFloat r, g, b; } LGRGB;

static inline LGVec2 LGVec(CGFloat x, CGFloat y) { LGVec2 v; v.x = x; v.y = y; return v; }
static inline CGFloat LGMax(CGFloat a, CGFloat b) { return a > b ? a : b; }
static inline CGFloat LGMin(CGFloat a, CGFloat b) { return a < b ? a : b; }

// float sdRoundedRect(float2 coord, float2 halfSize, float radius)
static CGFloat LGSdRoundedRect(LGVec2 coord, LGVec2 halfSize, CGFloat radius) {
    CGFloat qx = fabs(coord.x) - (halfSize.x - radius);
    CGFloat qy = fabs(coord.y) - (halfSize.y - radius);
    CGFloat mx = LGMax(qx, 0.0), my = LGMax(qy, 0.0);
    CGFloat outside = sqrtf(mx * mx + my * my) - radius;
    CGFloat inside = LGMin(LGMax(qx, qy), 0.0);
    return outside + inside;
}

// float2 gradSdRoundedRect(float2 coord, float2 halfSize, float radius)
static LGVec2 LGGradSdRoundedRect(LGVec2 coord, LGVec2 halfSize, CGFloat radius) {
    CGFloat qx = fabs(coord.x) - (halfSize.x - radius);
    CGFloat qy = fabs(coord.y) - (halfSize.y - radius);
    CGFloat sx = coord.x >= 0.0 ? 1.0 : -1.0;
    CGFloat sy = coord.y >= 0.0 ? 1.0 : -1.0;
    if (qx >= 0.0 || qy >= 0.0) {
        CGFloat nx = LGMax(qx, 0.0), ny = LGMax(qy, 0.0);
        CGFloat len = sqrtf(nx * nx + ny * ny);
        if (len < 1e-6) return LGVec(0.0, 0.0);
        return LGVec(sx * nx / len, sy * ny / len);
    }
    CGFloat gradX = (qy <= qx) ? 1.0 : 0.0;   // step(cornerCoord.y, cornerCoord.x)
    return LGVec(sx * gradX, sy * (1.0 - gradX));
}

// float circleMap(float x) { return 1.0 - sqrt(1.0 - x * x); }
static inline CGFloat LGCircleMap(CGFloat x) {
    x = LGClampf(x, -1.0, 1.0);
    return 1.0 - sqrtf(1.0 - x * x);
}

static inline LGVec2 LGNormalize(LGVec2 v) {
    CGFloat len = sqrtf(v.x * v.x + v.y * v.y);
    if (len < 1e-6) return LGVec(0.0, 0.0);
    return LGVec(v.x / len, v.y / len);
}

#pragma mark - 虚拟背景纹理

typedef struct {
    CGFloat w, h, halfW, halfH;
    CGFloat radius, gradRadius;
    CGFloat height, amount, dispersion, depth;
    CGFloat highlight, tint, falloff, lightAngle;
    const CGFloat *palette;       // RGB 三元组数组
    NSInteger paletteCount;
} LGShaderParams;

// 代替 AGSL 的 content.eval(coord)：角向调色板 + 亮度梯度。
// 7 次采样落在不同的角度/亮度位置，因此能产生真实的通道分离。
static LGRGB LGContentAt(CGFloat x, CGFloat y, const LGShaderParams *p) {
    CGFloat cx = x - p->halfW, cy = y - p->halfH;
    CGFloat t = (atan2f(cy, cx) + M_PI) / (2.0 * M_PI);
    t = t - floorf(t);
    CGFloat fi = t * (CGFloat)(p->paletteCount - 1);
    NSInteger i = (NSInteger)fi;
    if (i < 0) i = 0;
    if (i > p->paletteCount - 2) i = p->paletteCount - 2;
    CGFloat f = fi - (CGFloat)i;
    const CGFloat *a = p->palette + i * 3;
    const CGFloat *b = p->palette + (i + 1) * 3;
    LGRGB c;
    c.r = a[0] + (b[0] - a[0]) * f;
    c.g = a[1] + (b[1] - a[1]) * f;
    c.b = a[2] + (b[2] - a[2]) * f;

    CGFloat pos = LGClampf((x / p->w + y / p->h) * 0.5, 0.0, 1.0);
    CGFloat lum = 0.55 + 0.45 * (1.0 - pos);
    c.r = LGClampf(c.r * lum + (1.0 - c.r) * p->tint * lum, 0.0, 1.0);
    c.g = LGClampf(c.g * lum + (1.0 - c.g) * p->tint * lum, 0.0, 1.0);
    c.b = LGClampf(c.b * lum + (1.0 - c.b) * p->tint * lum, 0.0, 1.0);
    return c;
}

#pragma mark - CPU 光栅化：只画玻璃边缘那一圈

static CGImageRef LGCreateEdgeImage(const LGShaderParams *p) {
    // 按点 1x 光栅化并限制最大边长；玻璃边缘本来就是糊的，放大不损失观感
    CGFloat side = LGMax(p->w, p->h);
    CGFloat scale = side > 220.0 ? 220.0 / side : 1.0;
    NSInteger W = (NSInteger)LGMax(8.0, floorf(p->w * scale));
    NSInteger H = (NSInteger)LGMax(8.0, floorf(p->h * scale));
    CGFloat sx = p->w / (CGFloat)W;
    CGFloat sy = p->h / (CGFloat)H;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)W, (size_t)H, 8, 0, cs,
                        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) return NULL;
    UInt8 *data = (UInt8 *)CGBitmapContextGetData(ctx);
    size_t stride = CGBitmapContextGetBytesPerRow(ctx);
    if (!data) { CGContextRelease(ctx); return NULL; }

    LGVec2 halfSize = LGVec(p->halfW, p->halfH);
    CGFloat height = LGMax(p->height, 1.0);
    CGFloat nrmX = cosf(p->lightAngle), nrmY = sinf(p->lightAngle);

    for (NSInteger py = 0; py < H; py++) {
        CGFloat y = ((CGFloat)py + 0.5) * sy;
        UInt8 *row = data + py * stride;
        for (NSInteger px = 0; px < W; px++) {
            CGFloat x = ((CGFloat)px + 0.5) * sx;
            UInt8 *pixel = row + px * 4;

            LGVec2 coord = LGVec(x - p->halfW, y - p->halfH);
            CGFloat sd = LGSdRoundedRect(coord, halfSize, p->radius);
            // sd > 0 在圆角外；-sd >= height 是玻璃内部，两者都不画
            if (sd > 0.0 || -sd >= height) {
                pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;
                continue;
            }
            sd = LGMin(sd, 0.0);

            // t: 0 = 折射带内缘，1 = 最外侧边缘
            CGFloat t = LGClampf(1.0 - (-sd) / height, 0.0, 1.0);
            CGFloat d = LGCircleMap(t) * p->amount;

            LGVec2 g = LGGradSdRoundedRect(coord, halfSize, p->gradRadius);
            LGVec2 radial = LGNormalize(coord);
            LGVec2 grad = LGNormalize(LGVec(g.x + p->depth * radial.x,
                                            g.y + p->depth * radial.y));

            CGFloat dispIntensity = p->dispersion *
                                    ((coord.x * coord.y) / (p->halfW * p->halfH));
            CGFloat dx = d * grad.x, dy = d * grad.y;
            CGFloat ddx = dx * dispIntensity, ddy = dy * dispIntensity;
            CGFloat rx = x + dx, ry = y + dy;

            // RoundedRectRefractionWithDispersionShaderString 的 7 次采样
            LGRGB red    = LGContentAt(rx + ddx,        ry + ddy,        p);
            LGRGB orange = LGContentAt(rx + ddx*2.0/3.0, ry + ddy*2.0/3.0, p);
            LGRGB yellow = LGContentAt(rx + ddx/3.0,    ry + ddy/3.0,    p);
            LGRGB green  = LGContentAt(rx,              ry,              p);
            LGRGB cyan   = LGContentAt(rx - ddx/3.0,    ry - ddy/3.0,    p);
            LGRGB blue   = LGContentAt(rx - ddx*2.0/3.0, ry - ddy*2.0/3.0, p);
            LGRGB purple = LGContentAt(rx - ddx,        ry - ddy,        p);

            CGFloat r = red.r/3.5 + orange.r/3.5 + yellow.r/3.5 + purple.r/7.0;
            CGFloat gch = orange.g/7.0 + yellow.g/3.5 + green.g/3.5 + cyan.g/3.5;
            CGFloat b = cyan.b/3.0 + blue.b/3.0 + purple.b/3.0;

            // DefaultHighlightShaderString: pow(abs(dot(grad, normal)), falloff)
            CGFloat dot = fabsf(grad.x * nrmX + grad.y * nrmY);
            CGFloat intensity = powf(dot, p->falloff);
            CGFloat spec = p->highlight * intensity;

            // 边缘权重：越靠外越亮，内部平滑淡出
            CGFloat band = 0.25 + 0.75 * t;
            CGFloat a = LGClampf(band * (0.42 + 0.32 * intensity + 0.26 * spec), 0.0, 1.0);
            r = LGClampf(r * 0.72 + spec * 0.85 + 0.10, 0.0, 1.0);
            gch = LGClampf(gch * 0.72 + spec * 0.85 + 0.10, 0.0, 1.0);
            b = LGClampf(b * 0.72 + spec * 0.85 + 0.10, 0.0, 1.0);

            // premultiplied BGRA (little endian, alpha first)
            pixel[2] = (UInt8)(r * a * 255.0);
            pixel[1] = (UInt8)(gch * a * 255.0);
            pixel[0] = (UInt8)(b * a * 255.0);
            pixel[3] = (UInt8)(a * 255.0);
        }
    }
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

#pragma mark - 贴图缓存

static NSCache *LGEdgeCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 80;
    });
    return cache;
}

// 缓存 UIImage 而不是 CGImageRef：CGImage 不是 toll-free bridged 类型，
// 直接塞进 NSCache 依赖 CF 对象响应 retain/release，属于未定义行为。
static UIImage *LGCachedEdgeImage(const LGShaderParams *p, NSInteger paletteIndex) {
    NSString *key = [NSString stringWithFormat:
        @"%.0fx%.0f|r%.1f|%.1f_%.1f_%.2f_%.2f_%.2f_%.2f|p%ld|f%.2f",
        p->w, p->h, p->radius, p->height, p->amount, p->dispersion,
        p->depth, p->highlight, p->tint, (long)paletteIndex, p->falloff];
    UIImage *cached = [LGEdgeCache() objectForKey:key];
    if (cached) return cached;
    CGImageRef image = LGCreateEdgeImage(p);
    if (!image) return nil;
    UIImage *ui = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    [LGEdgeCache() setObject:ui forKey:key];
    return ui;
}

CGFloat LGAutoCornerRadius(CGSize size, LGGroup group) {
    CGFloat m = MIN(size.width, size.height);
    switch (group) {
        case LGGroupButton:   return m * 0.5;
        case LGGroupSlider:   return m * 0.5;
        case LGGroupPage:     return m * 0.5;
        case LGGroupModule:   return MIN(m * 0.26, 26.0);
        case LGGroupExpanded: return MIN(m * 0.18, 34.0);
        default:              return MIN(m * 0.24, 22.0);
    }
}

#pragma mark - 调色板展开

static void LGFillPaletteComponents(NSArray<UIColor *> *colors, CGFloat *out, NSInteger *count) {
    NSInteger n = (NSInteger)colors.count;
    if (n < 2) n = 2;
    if (n > 16) n = 16;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat r = 0.75, g = 0.55, b = 0.95, a = 1.0;
        UIColor *c = colors[i];
        if ([c respondsToSelector:@selector(getRed:green:blue:alpha:)]) {
            [c getRed:&r green:&g blue:&b alpha:&a];
        }
        out[i*3+0] = r; out[i*3+1] = g; out[i*3+2] = b;
    }
    *count = n;
}

#pragma mark - LGGlassView

@interface LGGlassView () {
    NSDictionary      *_settings;
    CALayer           *_spinHost;    // 不旋转，承载固定描边遮罩
    CALayer           *_spinLayer;   // 旋转，内部放圆锥渐变
    CAGradientLayer   *_conic;
    CAShapeLayer      *_edgeMask;
    CALayer           *_edgeLayer;   // SDF 折射 / 色散 / 高光贴图
    CAShapeLayer      *_rim;         // 细白边
    BOOL               _pressed;
}
@end

@implementation LGGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.clipsToBounds = NO;

    _spinHost = [CALayer layer];
    _spinHost.frame = self.bounds;
    _spinHost.masksToBounds = NO;
    [self.layer addSublayer:_spinHost];

    _spinLayer = [CALayer layer];
    _spinLayer.frame = self.bounds;
    [_spinHost addSublayer:_spinLayer];

    _conic = [CAGradientLayer layer];
    _conic.frame = self.bounds;
    // 用 KVC 设置 conic：部分 patched SDK 头文件未声明 type 属性 / kCAGradientLayerConic 常量
    [_conic setValue:@"conic" forKey:@"type"];   // iOS 12+
    _conic.startPoint = CGPointMake(0.5, 0.5);
    _conic.endPoint   = CGPointMake(0.5, 0.0);
    [_spinLayer addSublayer:_conic];

    // 遮罩挂在「不旋转」的 _spinHost 上，渐变层在内部旋转：
    // 圆角描边不会跟着一起转歪。
    _edgeMask = [CAShapeLayer layer];
    _edgeMask.fillColor = [UIColor clearColor].CGColor;
    _edgeMask.strokeColor = [UIColor whiteColor].CGColor;
    _edgeMask.lineWidth = 3.0;
    _spinHost.mask = _edgeMask;

    _edgeLayer = [CALayer layer];
    _edgeLayer.frame = self.bounds;
    _edgeLayer.contentsGravity = kCAGravityResize;
    [self.layer addSublayer:_edgeLayer];

    _rim = [CAShapeLayer layer];
    _rim.fillColor = [UIColor clearColor].CGColor;
    _rim.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _rim.lineWidth = 0.8;
    [self.layer addSublayer:_rim];

    return self;
}

- (void)applySettings:(NSDictionary *)settings {
    _settings = [settings copy];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self rebuild];
}

- (void)rebuild {
    CGRect bounds = self.bounds;
    if (bounds.size.width < 2.0 || bounds.size.height < 2.0) return;
    NSDictionary *s = _settings ?: LGMergedSettings();

    BOOL enabled = [LGValue(s, kLGEnabled) boolValue];
    self.hidden = !enabled;
    if (!enabled) { [_spinLayer removeAllAnimations]; return; }

    _spinHost.frame = bounds;
    _spinLayer.frame = bounds;
    _conic.frame = bounds;
    _edgeLayer.frame = bounds;
    _edgeMask.frame = bounds;
    _rim.frame = bounds;

    CGFloat radius = [LGValue(s, kLGCornerRadius) doubleValue];
    if (radius <= 0.0) radius = LGAutoCornerRadius(bounds.size, self.group);
    radius = LGClampf(radius, 2.0, MIN(bounds.size.width, bounds.size.height) * 0.5);

    CGFloat edgeW = LGClampf([LGValue(s, kLGEdgeWidth) doubleValue], 0.5, 8.0);
    CGRect inset = CGRectInset(bounds, edgeW * 0.5, edgeW * 0.5);
    CGFloat innerRadius = MAX(0.5, radius - edgeW * 0.5);
    CGPathRef path = CGPathCreateWithRoundedRect(inset, innerRadius, innerRadius, NULL);
    _edgeMask.lineWidth = edgeW * 1.6;
    _edgeMask.path = path;
    _rim.path = path;
    CGPathRelease(path);

    NSInteger paletteIndex = [LGValue(s, kLGPalette) integerValue];
    NSArray<UIColor *> *colors = LGPaletteColors(paletteIndex);
    CGFloat components[16 * 3] = {0};
    NSInteger colorCount = 0;
    LGFillPaletteComponents(colors, components, &colorCount);

    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colorCount];
    for (NSInteger i = 0; i < colorCount; i++) {
        [cgColors addObject:(__bridge id)[UIColor colorWithRed:components[i*3]
                                                         green:components[i*3+1]
                                                          blue:components[i*3+2]
                                                         alpha:1.0].CGColor];
    }
    _conic.colors = cgColors;
    _spinHost.opacity = LGClampf([LGValue(s, kLGHighlight) doubleValue], 0.0, 1.0);

    LGShaderParams p;
    memset(&p, 0, sizeof(p));
    p.w = bounds.size.width;  p.h = bounds.size.height;
    p.halfW = p.w * 0.5;     p.halfH = p.h * 0.5;
    p.radius = radius;
    p.gradRadius = MIN(radius * 1.5, MIN(p.halfW, p.halfH));
    p.height = MAX(2.0, [LGValue(s, kLGHeight) doubleValue]);
    p.amount = [LGValue(s, kLGAmount) doubleValue];
    p.dispersion = LGClampf([LGValue(s, kLGDispersion) doubleValue], 0.0, 3.0);
    p.depth = LGClampf([LGValue(s, kLGDepth) doubleValue], 0.0, 1.5);
    p.highlight = LGClampf([LGValue(s, kLGHighlight) doubleValue], 0.0, 1.0);
    p.tint = LGClampf([LGValue(s, kLGTint) doubleValue], 0.0, 1.0);
    p.falloff = 2.4;
    p.lightAngle = -M_PI / 4.0;
    p.palette = components;
    p.paletteCount = colorCount;

    UIImage *edgeImage = LGCachedEdgeImage(&p, paletteIndex);
    _edgeLayer.contents = edgeImage ? (__bridge id)edgeImage.CGImage : nil;
    _edgeLayer.opacity = LGClampf(0.55 + p.highlight * 0.45, 0.0, 1.0);

    // 圆锥渐变匀速旋转，让玻璃边缘有流动的彩色高光
    [_spinLayer removeAnimationForKey:@"lgSpin"];
    CGFloat spin = [LGValue(s, kLGSpin) doubleValue];
    if (spin > 0.05) {
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        anim.fromValue = @0;
        anim.toValue = @(2.0 * M_PI);
        anim.duration = spin;
        anim.repeatCount = HUGE_VALF;
        anim.removedOnCompletion = NO;
        [_spinLayer addAnimation:anim forKey:@"lgSpin"];
    }
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.alpha = pressed ? 1.0 : 0.88;
        _edgeLayer.opacity = pressed ? 1.0 : 0.72;
        self.transform = pressed ? CGAffineTransformMakeScale(1.035, 1.035)
                                 : CGAffineTransformIdentity;
    } completion:nil];
}

@end
