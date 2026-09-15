# Anime / Blu-ray plugin fork

这是 [akFace/mpv.config](https://github.com/akFace/mpv.config) 的 uosc 配置 fork，基线提交为 `eb4da7343b98fced80082f93b8448b728f5e7565`。开发分支 `anime-bd-plugins`，继承的 `master` 用于跟踪上游。

| 独立 Git 子模块 | 功能 |
| --- | --- |
| [mpv-anime-xray](https://github.com/sdy623/mpv-anime-xray) | 片名识别、候选、作品 / 集数 / 声优资料、AniDB、AniSkip、可选 MCP |
| [mpv-bluray](https://github.com/sdy623/mpv-bluray) | 原盘 / ISO / 光驱、后端优先级与自动回退、Xreveal 接管时 disabled |

fork 组合右键菜单、快捷键和弹幕番名接口，并保留底部悬停显示、100% 原始像素模式。插件之间没有硬依赖。构建 uosc 三种菜单样式；保留上游 modernz 源码，但不生成带插件菜单的 modernz 包。

## 安装与构建

Release 的 `uosc_macos-dark.zip` 等是**配置与完整插件源码包**，不含 mpv 可执行文件、Java、libaacs、MakeMKV、密钥或用户数据。使用带 LuaJIT / libbluray 的 Windows x64 mpv，展开到 `portable_config`，运行 `Setup-Plugins.ps1` 初始化 Python 与公开动漫数据库。蓝光后端按插件说明配置。已有定制配置请先备份并合并，不要直接覆盖。

```powershell
git clone --recurse-submodules https://github.com/sdy623/mpv.config
cd mpv.config
npm ci
$env:RELEASE_VERSION = 'v1.9.19-anime-bd.1'
npm run build
```

`plugin-versions.json` 记录实际打包的子模块提交。构建只读取子模块已提交文件，排除依赖、数据库、缓存、影片和个人设置；发布包不含某台电脑的声卡、显卡和本地路径设置。

## 上游补丁

发布页提供相对上述基线的 `anime-bd-upstream.patch`，配合两个公开子模块可重现本 fork：

```powershell
git checkout -b anime-bd-plugins eb4da7343b98fced80082f93b8448b728f5e7565
git am /path/to/anime-bd-upstream.patch
git submodule update --init --recursive
```

上游更新需在本地合并或变基并处理冲突；插件更新需提交新的 gitlink。不要把整个便携播放器文件夹提交到 Git。

## 许可与验证

上游保留 `LICENSE.LGPL`（LGPL-2.1）及第三方声明。插件与本 fork 新集成代码为 GPL-3.0-or-later，见各插件 LICENSE、NOTICE 和 `LICENSE.integration`。不同组件保留各自许可，不把第三方脚本或数据重新声明为自己的代码。

验证见发布说明。自动测试不等于所有物理光盘、BD-J 菜单、声卡或 Linux/macOS 桌面体验都已验证。

English: uosc configuration fork integrating two independent, pinned Git submodules. ZIP releases include complete plugin source and configuration, not a player binary or decryption assets. The upstream patch targets the documented commit. Each plugin documents setup, provenance and limitations.


## 原有播放器适配

声卡恢复、100% 窗口模式、B 站 URL 协议解析及 MMT 启动桥保留在配置 fork 中，不放入两个功能插件。偏好声卡改为 `script-opts/audio-router.conf` 可配置项，公共默认不指定设备。B 站桥只接收指定 CDN 的 HTTPS 媒体地址和有限播放参数；不读取浏览器登录数据。

可选 Windows 启动器源码在 `windows/MpvAnimeLauncher.cs`，依赖 .NET Framework 的 Windows Forms / System.Web.Extensions。MMT 转换需另行安装 [mmt2ts](https://github.com/Till0196/mmt2ts) 到播放器的 `runtime/mmt2ts`；BD-J 使用自备的 `runtime/java8` 与 `runtime/bdj`。发行配置不附带这些程序，也不注册系统 URL 协议。已安装用户的启动器无需重编译。
