# 控制中心液态玻璃 · LiquidGlassCC18

给 **ControlCenter18** 的控制中心按钮、模块、滑块叠加液态玻璃效果：
SDF 圆角折射边缘 + 逐通道色散 + 旋转彩色流光 + 可选系统模糊。

> 目标环境：iOS 16.x + roothide（arm64e），需已安装 ControlCenter18。

**这个版本和 Siri AI 跑马灯已经彻底分开：**

| | 说明 |
| --- | --- |
| 独立工程 | 单独的目录、单独的 `control`、单独的 `.deb`（`com.lgcc18.glass`），不合并、不依赖、不读取 SiriAI16 的任何文件与配置 |
| 不动系统设置项 | **没有**任何替换 / 改写「Siri 与搜索」控制项的代码。设置里那一项保持系统原样，本插件连读都不读它 |
| 只做控制中心 | 不画屏幕边缘流光、不做跑马灯文字、不注入 Siri、不改语音识别 |
| 设置入口 | 挂在 **ControlCenter18 自带的设置面板**里（它自己就有控制项），不在系统项上做文章 |

---

## 一、设置入口在哪

1. **主入口**：`设置 → ControlCenter18` → 拉到最底部「液态玻璃」分组 → 「液态玻璃设置」
2. **备用入口**：`设置` 首页最底部「控制中心液态玻璃」（可在面板「高级 → 在设置首页显示入口」关掉，关掉后重启一次「设置」生效）

两处都只是**在列表末尾追加**本插件自己的分组和链接，不修改任何已有 specifier。
系统「Siri 与搜索」仍指向原生面板，点击行为完全不变。

> 实现上之所以不直接 `%hook C18PRootListController`：CC18 的控制器类定义在
> `ControlCenter18Prefs.bundle` 里，只有用户点开设置项时才加载，tweak 的 `%ctor`
> 执行时该类还不存在，Logos 会静默跳过。因此改为 hook 系统基类
> `UIViewController -viewWillAppear:` + `PSListController -specifiers`，运行时按类名判断，
> 并用 marker 去重、只接受可变数组。

---

## 二、工程结构

```
LiquidGlassCC18/
├── Makefile                      # 两个 tweak 实例，共用一个 .deb
├── control                       # com.lgcc18.glass / 1.0.0 / iphoneos-arm64e
├── LiquidGlassCC.plist           # Filter: com.apple.springboard
├── LiquidGlassPrefs.plist        # Filter: com.apple.Preferences
├── LGCommon.h                    # 配置默认值 / plist 读写 / 内置配色 / 通知名
├── LGGlassRenderer.h / .m        # CPU 光栅化：SDF 折射 / 色散 / 高光贴图
├── LiquidGlassCC.x               # SpringBoard：按类名给 C18* 视图挂玻璃层
├── PrefsShims.h                  # Preferences.framework 私有类最小声明
├── LiquidGlassPrefs.h / .m       # 设置面板（代码构造，无 PreferenceBundle）
├── LiquidGlassEntry.x            # Settings：只追加入口，不改系统项
├── build.sh                      # 自动下载 roothide/theos + SDK 并编译
├── .github/workflows/build.yml   # macOS CI，推送后自动产出 .deb
└── README.md
```

**两个 dylib**：`PSListController` 只存在于 Settings 进程，编进 SpringBoard 会出问题，所以拆开；
私有类用 `-Wl,-undefined,dynamic_lookup` 在运行时解析，不需要私有框架 stub。

---

## 三、构建（Windows 只要浏览器）

编译跑在 **GitHub 云端的 macOS 主机**（`macos-15`，自带 Xcode），你的电脑只负责上传源码、下载成品。

### 方式 A：复用你已有的仓库（最省事，推荐）

你之前的仓库 `qadcgt6047/Siriai` 里 `.github/workflows/build.yml` 已经放好且能正常触发构建，
**不用再碰隐藏目录**：

1. 打开工作区的 `upload-LiquidGlassCC18` 文件夹，**双击进去**，`Ctrl+A` 全选里面的**全部文件**
   （注意：选的是文件夹里的内容，不是文件夹本身；目录里的 `.github` 网页上传时可能被丢掉，
    没关系 —— 你这个仓库里已经有能用的 workflow 了）。
2. 仓库 `Code` 页 → `Add file` → `Upload files` → 拖进去 → `Commit changes`。
3. 同名文件会覆盖。旧的 `SiriAI.x` 等文件留在仓库里**不影响编译**（Makefile 只引用新文件），
   想干净可以在网页上顺手删掉。
4. 这次 push 自动触发构建 → `Actions` 页等 5–15 分钟 → 右侧 **Releases** 下载 `.deb`。

> 建议把 workflow 也更新一下（文件名不变，只改产物名）：用 `粘贴用-build.yml` 全文覆盖
> `.github/workflows/build.yml`，否则 Release 名还带旧工程字样，功能上没区别。

### 方式 B：新建一个干净仓库

1. `github.com` → `+` → `New repository` → 名字 `LiquidGlassCC18`，选 **Public** → Create。
2. 打开工作区根目录的 `一键创建workflow.html`，填入 `你的用户名/仓库名`，点「打开 GitHub 创建页」，
   文件名会自动填成 `.github/workflows/build.yml` → 拉到底 `Commit changes`。
   （⚠️ 网页「上传文件」会丢掉点开头的 `.github` 目录，所以 workflow 一定要用「Create new file」建。）
3. 再按方式 A 第 1 步把源码传上去 → 自动构建。

### 本机有 macOS / Linux

```bash
cd LiquidGlassCC18
chmod +x build.sh && ./build.sh
```

脚本自动装 roothide Theos + patched SDK + ldid，产物在
`packages/com.lgcc18.glass_1.0.0_iphoneos-arm64e.deb`。
必须用 **roothide 分支的 Theos**，官方 Theos 不认识 `THEOS_PACKAGE_SCHEME=roothide`。

---

## 四、安装与使用

```bash
dpkg -i com.lgcc18.glass_1.0.0_iphoneos-arm64e.deb
killall -9 SpringBoard
```

用 Filza 把 deb 交给 Sileo / Zebra 安装也可以。装好后：

1. `设置 → ControlCenter18 → 液态玻璃设置`（或设置首页的独立入口）
2. 打开「启用液态玻璃」，点一次「立即刷新控制中心」
3. 收起再下拉控制中心看效果；改参数即时生效，**不需要 Respring**

---

## 五、设置项一览

| 分类 | 项目 |
| --- | --- |
| 基本 | 启用液态玻璃、立即刷新控制中心、恢复默认设置 |
| 作用范围 | 圆形/强调按钮、模块底板、亮度/音量滑块、展开大面板、页面指示器 |
| 材质 | 材质模式（仅流光 / 系统模糊 / 模糊+背景放大）、配色（4 套内置）、流光速度、模糊浓度、背景放大 |
| 折射与高光 | 折射带宽、折射位移、逐通道色散、深度效果、高光强度、边缘光带宽度、圆角半径、白色调混合 |
| 高级 | 按压反馈、额外类名关键字、最大玻璃层数量、在设置首页显示入口 |

配置写在 `NSHomeDirectory()/Library/Preferences/com.lgcc18.glass.plist`，
改动通过 Darwin 通知即时推送到 SpringBoard，不受 roothide 随机 jbroot 路径影响。

---

## 六、实现要点

- **不 hook `C18*` 类**：这些类在 CC18 的 dylib 加载时才注册，tweak 加载顺序不定。
  改为 hook 系统 `UIView -didMoveToWindow`，视图进 window 时按类名前缀 `C18` 分组挂载，
  Class→分组结果缓存到关联对象；另有 2 秒后全量扫 window 树兜底。
- **`LGGlassRenderer.m` 纯 CPU 光栅化**：直译上游 `sdRoundedRect` / `gradSdRoundedRect` /
  `circleMap` 与 7 次采样逐通道色散，加 `pow(abs(dot(grad,normal)), falloff)` 高光，
  只生成「圆角边缘那一圈」的半透明贴图（中心 alpha=0，不挡图标文字），按尺寸/参数全局缓存、边长上限 220pt。
- **流光不转歪**：conic 渐变层在内部旋转，圆角描边遮罩挂在不旋转的容器层上。
- 安全阀：`最大玻璃层数量` 默认 48，超出不再挂载；视图小于 8pt 跳过。

---

## 七、排错

| 现象 | 处理 |
| --- | --- |
| 设置里找不到入口 | 先去 `设置 → ControlCenter18` 面板底部找；确认 `LiquidGlassPrefs.dylib` + `LiquidGlassPrefs.plist` 都在；杀掉「设置」重开。设置首页入口可在面板「高级」里重新打开 |
| 下拉控制中心没效果 | 面板里点「立即刷新控制中心」；确认「启用液态玻璃」与作用范围开关是开的；确认已安装 ControlCenter18；收起再下拉一次 |
| 只有部分控件有玻璃 | 在「额外类名关键字」里加对应类名片段（英文逗号分隔）；适当调大「最大玻璃层数量」 |
| 卡顿 / 掉帧 | 材质改成「仅流光与折射」，调小「折射带宽」「折射位移」，关闭「展开后的大面板」 |
| Actions 页停在「开始使用 GitHub Actions」引导页 | 说明仓库里没有 `.github/workflows/`。用 `一键创建workflow.html` 的 Create new file 方式补上，别用拖拽上传（网页会丢隐藏目录） |
| 构建秒失败 / runner 分配被拒 | `runs-on` 必须是 `macos-15`（`macos-14` 已于 2026-11-02 退役）；别点「重跑任务」，重跑用旧 commit |
| 网页上传后文件套了一层目录 | 上传时选的是**文件夹里面的内容**，不是文件夹本身；仓库根目录要能直接看到 `Makefile`、`build.sh` |

---

## 八、已知限制

- 这是**视觉近似**：AGSL 的 `content.eval()` 采真实背景纹理，iOS 16 的 SpringBoard 没有等价物，
  这里用「调色板角向渐变 + 亮度梯度」构造虚拟背景参与同一套折射数学；真实背景模糊交给
  `UIVisualEffectView`。不是 iOS 26 的 `UIGlassEffect`，**没有**实时背景折射。
- 不引入 Kotlin / Compose / Skia，也不带 AndroidLiquidGlass 的二进制依赖。
- 未做实机验证：本机 Windows 无 clang / make / iOS SDK，只做了源码级静态校验，
  第一次 CI 或真机若报错，把日志贴回来即可修。

## 九、许可与来源

SDF 折射 / 色散数学移植自
[Kyant0/AndroidLiquidGlass 2.0.0-alpha03](https://github.com/Kyant0/AndroidLiquidGlass/releases/tag/2.0.0-alpha03)
的 `Shaders.kt` / `Lens.kt`，**Apache-2.0，Copyright 2025 Kyant**。
版权与许可证声明保留在 `LGGlassRenderer.m` 文件头。
