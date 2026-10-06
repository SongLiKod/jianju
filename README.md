# 简剧 Jianju

![Build Windows & Android](https://github.com/SongLiKod/jianju/actions/workflows/build.yml/badge.svg)

**简剧** 是基于 Flutter 的跨平台**纯净短剧客户端**，支持 **Android** 与 **Windows**。
所有去广告逻辑在客户端本地完成：不加载开屏/信息流/详情页广告，播放时自动剔除片头片尾广告分片，只播正片。

- 仓库：`SongLiKod/jianju`
- 当前版本：**2.1.0**（pubspec `version: 2.1.0`；Android versionCode 由版本号自动推导，本版为 `2001000`）
- 开发环境：Flutter **3.44.2** / Dart **3.12.2**

---

## 目录

1. [功能特性](#一功能特性)
2. [运行环境](#二运行环境)
3. [快速开始](#三快速开始)
4. [构建与打包](#四构建与打包)
5. [应用内检查更新](#五应用内检查更新)
6. [纯净播放：播放清单去广告机制](#六纯净播放播放清单去广告机制)
7. [数据源说明](#七数据源说明)
8. [项目结构](#八项目结构)
9. [测试与代码质量](#九测试与代码质量)
10. [开发约定](#十开发约定)
11. [常见问题](#十一常见问题)
12. [使用声明](#十二使用声明)
13. [相关文档](#十三相关文档)

---

## 一、功能特性

### 内容浏览
- 首页推荐信息流（下拉分页）、分类、排行榜、搜索
- 短剧详情页：封面、简介、全集列表、推荐位
- **信息流/详情页广告卡片全部过滤**，只渲染正规短剧
- 搜索历史（最多 20 条）、观看历史、本地收藏

### 播放核心
- 播放内核 `media_kit`（libmpv），HLS/m3u8 流媒体
- 倍速 **0.75x ~ 5x**，默认倍速在设置中全局配置、进播放器自动加载
- 播放进度本地记忆、**播放完毕自动跳下一集**
- 全屏播放、音量/进度手势
- Android **画中画（PiP）**、桌面端**悬浮小窗**、Esc 返回

### 跨集预缓存
- 起播预缓冲（`prebuffer_service`）：按清单顺序预取分片，减少卡顿
- 跨集预缓存：缓冲时长可选 **10 / 20 / 60 / 180 秒**，设置为 60s 或以上时自动预下载下一集
- 预缓存与播放共用同一套清单改写逻辑，预下载的片段不会是广告

### 主题与布局
- 浅色 / 深色 / 跟随系统
- 自定义主题主色（预设色板，切换实时生效、永久保存）
- 桌面端宽窄布局一键切换、窗口尺寸/位置记忆、系统托盘

### 本地数据（100% 本地，不上传）
- 观看历史、收藏、播放进度、搜索历史、全部配置项（主题/倍速/缓冲/数据源/设备信息）

### 应用内检查更新
- 检查 **GitHub Releases** 最新正式版（自动跳过 pre-release）
- **启动自动检查**（3 秒后，无新版本零打扰）+ **设置 → 关于 → 检查更新**手动检查
- **静默下载**（进度条、可取消）→ **应用内安装确认**，全程不离开软件
- 详见 [第五节](#五应用内检查更新)

### 桌面端（Windows）
- `window_manager` 窗口状态记忆、`tray_manager` 系统托盘
- 打包为独立运行目录（`flutter build windows --release`）

---

## 二、运行环境

| 平台 | 要求 |
| --- | --- |
| Android | 8.0（API 26）及以上 |
| Windows | Win10 / Win11（x64） |
| Flutter | 3.44.2（stable） |
| Dart | SDK ^3.12.2 |
| Android 构建 | JDK 17、compileSdk 36、NDK 26.3.11579264 |

主要依赖：`provider`、`dio`、`shared_preferences`、`cached_network_image`、`flutter_cache_manager`、`media_kit` / `media_kit_video` / `media_kit_libs_video`、`window_manager`、`tray_manager`、`package_info_plus`。

---

## 三、快速开始

```powershell
# 1. 获取代码
git clone git@github.com:SongLiKod/jianju.git
cd jianju

# 2. 拉取依赖
flutter pub get

# 3. 运行（连接 Android 设备，或加 -d windows 跑桌面端）
flutter run
```

> 本机 Flutter 路径若不在 `PATH`，可直接调用 `C:\software\flutter\bin\flutter.bat`（`build_apk.ps1` 即按此路径写死）。

---

## 四、构建与打包

### Android

```powershell
# 方式一：直接构建，产物 build\app\outputs\flutter-apk\app-release.apk
flutter build apk --release

# 方式二：一键脚本，额外复制为 dist\简剧<版本>.apk
powershell -ExecutionPolicy Bypass -File build_apk.ps1
```

### Windows

```powershell
flutter build windows --release
# 产物 build\windows\x64\runner\Release\
```

### Android 签名

- 仓库内**不保存** `android/key.properties` / keystore。CI 检测到 secrets 时自动注入正式签名，本地缺省则使用 **debug 签名**。
- 需要正式签名时，创建 `android/key.properties`：

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=jianju-keystore.jks
```

> ⚠️ **签名不一致的包无法覆盖安装**（会提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`），只能卸载重装（会丢失本地历史/收藏）。

### 版本号约定

```yaml
# pubspec.yaml —— 只写版本号，不写 build-number
version: 2.1.0
```

- `versionName` 用于界面展示与更新比对，界面上显示的就是 `2.1.0`。
- **Android versionCode 由 versionName 自动推导**，见 [`android/app/build.gradle.kts`](android/app/build.gradle.kts)：每段占 3 位 → `2.1.0` = `2_001_000`。
- 版本号递增（`2.1.0` → `2.1.1`）则 versionCode 必然递增，无需手工维护 `+N`；**每次发版只改 `pubspec.yaml` 的 `version`**。
- versionCode 不递增时系统会拒绝覆盖安装并报 `INSTALL_FAILED_VERSION_DOWNGRADE`（应用内更新会提示「新包版本号低于当前已安装版本」）。

### CI / 发布（GitHub Actions）

工作流：[`.github/workflows/build.yml`](.github/workflows/build.yml)，触发条件：

| 触发 | 行为 |
| --- | --- |
| push 到 `main` / PR | 分析 + 构建 Windows / Android，上传 artifact（不发 Release） |
| push tag `v*`（如 `v2.1.0`） | 构建并发布 GitHub Release |
| 手动 `workflow_dispatch` | 填 `version`（如 `v2.1.0`）即按该 tag 发布，`prerelease` 可勾选预发布 |

Release 资产命名：

- `Jianju-<版本>.apk`（Android release）
- `Jianju-<版本>-debug.apk`（debug 构建）
- `Jianju-<版本>-windows.zip`（Windows 打包）

签名 secrets（可选）：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`。

---

## 五、应用内检查更新

实现代码：`lib/core/services/update_service.dart`（网络/解析/下载/安装通道）、`lib/widgets/update_flow.dart`（弹窗流程）、`lib/app.dart`（启动自动检查）。

**流程**

1. **检查**：请求 `https://api.github.com/repos/SongLiKod/jianju/releases/latest`，该接口自动排除 prerelease；解析 `tag_name`、`body`、`assets`，与 `package_info_plus` 的当前版本做语义化比对。
2. **确认**：有新版才弹窗，展示版本号与更新说明，用户点「立即更新」。
3. **静默下载**：后台下载 APK 资产，展示进度、可取消；下载完成后校验 APK 魔数（`PK\x03\x04`）防止拿到 HTML/404 页面。
4. **安装（不离开软件）**：Android 端通过原生 `jianju/updater` MethodChannel 调用 `PackageInstaller` 会话安装，**安装确认框浮在本应用上方**，确认即完成。
   - 首次需授权一次「允许来自此来源 / 安装未知应用」，跳设置返回后会自动继续安装。
   - Windows 端无自动安装，改为打开发布页 `https://github.com/SongLiKod/jianju/releases` 供手动下载。

**使用要求**：发布时 Release 需包含资产 `Jianju-<版本>.apk`；`tag` 需形如 `v<版本>`（含 `-beta` 等会按 prerelease 处理，不会提示更新）。

---

## 六、纯净播放：播放清单去广告机制

实现位置：`lib/core/services/prebuffer_service.dart`（`rewritePlaylist` / `_downloadHls`），启动播放与预缓存均先过这套规则。

**第一层：目录判据**
广告分片与正片不同目录时，直接剔除（含 `#EXT-X-DISCONTINUITY` 标记后的块）。

**第二层：同目录码率判据**
短剧站常把片尾广告分片放在与正片同一目录，靠目录无法区分，因此：

1. 用 `Range: bytes=0-0` 请求分片头，从 `Content-Range` 取分片总字节数（该 CDN 对 `HEAD` 返回 502，故不用 HEAD）；
2. 结合 `EXTINF` 时长算出码率，采样不超过 8 片并行探测，取**中位码率**作为正片基准；
3. 与基准偏离 **≥ 1.8 倍**（双向）的非首块判定为广告，剔除；
4. 单片探测 5 秒超时则按「保留」处理（宁可漏删也不错杀），判定结果按播放源缓存，不重复探测；
5. 清单不含 `DISCONTINUITY` 时直接零探测返回。

改写成功后日志可见：`[PBF] 起播清单已改写：剔除广告 N 片（…码率判据 M 块）`。

> 修复背景：广告块与正片同目录时，老规则会把广告段交给播放器 → 播放器重启流回到 00:00 → 结尾检测不到片尾 → 不自动跳集、反复回跳、爆音。

---

## 七、数据源说明

设置 → 数据源 可查看/切换/管理数据源（含自定义站点、线路测速）。

| 数据源 | 说明 | 代码 |
| --- | --- | --- |
| 官方网页源 | 抓取短剧站页面接口（`webBase` 等地址） | `services/maccms_source.dart` / `api_service.dart` |
| 52api 聚合源 | 需填 `apikey` 的聚合接口 | `services/api52_source.dart` |
| 整站数据源 | `type=maccms` 站点：首页、搜索、详情、播放全走其公开线路 | `services/play_lines.dart` |

- 所有接口地址、路径、分类/榜单映射集中在 `lib/core/constants/api_constants.dart`，改地址只需改这一处。
- 请求统一经 `lib/core/network/http_client.dart` + `request_throttler.dart`（节流重试、防风控），播放请求附带防盗链请求头（`play_headers.dart`）。

**已知限制**：数据源站点改版会导致接口失效需重新适配；DRM 加密视频无法解密；高频请求仍有小概率触发风控。

---

## 八、项目结构

```
jianju/
├─ lib/
│  ├─ app.dart                       # 应用入口、启动自动检查更新
│  ├─ core/
│  │  ├─ constants/
│  │  │  ├─ api_constants.dart       # 接口地址/路径集中管理
│  │  │  └─ app_constants.dart       # 使用声明、各类上限常量
│  │  ├─ models/                     # drama / episode / history_entry
│  │  ├─ network/                    # dio 封装、请求节流
│  │  ├─ services/                   # 数据源、播放头、预缓存、收藏、历史、
│  │  │                              # 设置、设备、Token、托盘、窗口、更新…
│  │  ├─ state/                      # settings / theme provider
│  │  ├─ theme/                      # 主题与色板
│  │  └─ utils/
│  ├─ pages/                         # home search category rank detail
│  │                                  # player favorites history settings mine
│  └─ widgets/                       # update_flow 等通用组件
├─ android/                          # 原生壳、Manifest、PackageInstaller 通道
├─ windows/                          # 桌面壳
├─ test/                             # 单元/端到端用例 + 联网诊断探针
├─ tool/                             # 图标生成脚本
├─ docs/                             # 需求文档 / 技术文档
├─ build_apk.ps1                     # 一键打包脚本
└─ .github/workflows/build.yml       # CI：构建 + 发布 Release
```

---

## 九、测试与代码质量

```powershell
flutter analyze --no-pub   # 静态检查（CI 也跑这个）
flutter test               # 离线用例（无需网络，可随时跑）
```

- `test/*_test.dart` 中不带 `live`/`probe` 的为**离线用例**（含 `playlist_ad_block_test.dart`，用本地 HttpServer 验证去广告改写）。
- `test/probe_*.dart`、`test/*_live_test.dart` 为**联网诊断用例**，需网络，用于复现真实站点清单/码率问题：

```powershell
flutter test test/probe_bhvod7_test.dart
```

- 诊断真机播放问题时可配合 `adb logcat` 抓取 `media_kit` / `com.jianju.jianju` 日志。

---

## 十、开发约定

- **不要对源码执行 `dart format`**（仓库有自己的格式约定，全量格式化会产生巨大无意义 diff）。
- 源码文件使用 **UTF-8 无 BOM**；含中文的 `.ps1` 脚本使用 **UTF-8 带 BOM**。
- 修改发布相关逻辑后，记得同步 `pubspec.yaml` 的 `version`（versionCode 随之自动变化，无需写 `+N`）。
- 本地缺少 Android release keystore 时只能出 debug 签名包，验证更新/覆盖安装流程前先确认签名一致。

---

## 十一、常见问题

**1. 安装提示 `INSTALL_FAILED_VERSION_DOWNGRADE`**
目标设备上已装的 versionCode 更高。确认 `pubspec.yaml` 的 `version` 比已装版本大（versionCode 随之变大），或该包是旧代码构建的（未含自动推导逻辑）→ 用当前代码重新构建。

**2. 安装提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`（签名不匹配）**
本机包与目标包 keystore 不同，只能卸载重装（本地历史/收藏会丢）。

**3. 应用内更新下载/安装没反应**
- 未授权安装未知应用：设置 → 应用 → 简剧 → 安装未知应用 → 允许，返回后会自动继续。
- Release 必须包含 `Jianju-<版本>.apk` 资产，且 tag 为 `v<版本>`。
- 预发布（tag 含 `-beta` 等）不会触发更新提示，属预期行为。

**4. 播放报 `Failed to recognize file format` / 拉流失败**
多为防盗链或线路失效：在设置中换数据源/线路，或刷新 Token（设置 → 重置设备 ID / 退出登录后重取）。

**5. 不自动跳下一集、进度来回跳、爆音**
大概率是清单里含同目录广告分片，确认版本 ≥ 2.0.0（含码率判据修复），并看日志 `[PBF] 起播清单已改写` 是否出现。

**6. Windows 打开即闪退 / 无法运行**
使用 `flutter build windows --release` 产物整体分发（`jianju-windows.zip`），不要只拷 `.exe`，需与 `data/` 目录同级。

---

## 十二、使用声明

> 以下全文与应用内设置 → 关于 →「使用声明」一致（`lib/core/constants/app_constants.dart` 中 `usageStatement`）。

本软件为个人兴趣爱好开发产物，仅供个人学习、娱乐、非商业性质免费使用。

本人对本软件享有全部合法知识产权，未经作者本人书面许可，任何单位及个人不得对本软件进行二次开发、修改、复刻、衍生创作，不得将本软件及相关资源用于商业盈利、引流变现、付费售卖等一切牟利行为，严禁任何违规商用、二次开发及非法传播行为。

本软件无任何商业用途及商业服务属性，使用者在使用本软件的过程中，需自觉遵守当地法律法规及网络使用规范。因违规使用、私自篡改软件内容、非法商用、不当操作软件所造成的一切直接或间接损失、法律责任、纠纷风险等，均由使用者本人自行承担，软件作者不承担任何连带法律责任与相关后果。

凡下载、安装、使用本软件，即代表本人已完整阅读、理解并自愿接受本声明全部条款。

---
