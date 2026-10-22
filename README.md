# WinDevPicker

Windows 装机助手，覆盖镜像下载、启动盘工具、文件与驱动备份、安装后配置、日常软件和开发环境。支持 Windows PowerShell 5.1 与 PowerShell 7。

## 启动

在 Windows PowerShell 中运行：

```powershell
irm https://raw.githubusercontent.com/RustyPiano/win-dev-picker/main/bootstrap.ps1 | iex
```

启动器下载本仓库 ZIP，解压后打开菜单，退出时清理临时副本。镜像、工具和备份保存在用户选择的位置，日志保存在 `%LOCALAPPDATA%\WinDevPicker\logs\`。

也可以下载仓库 ZIP 并解压，双击 `Launch.cmd`。以管理员身份运行终端可备份和安装驱动、修改 WinGet 源。

```text
========== Windows 装机助手 ==========
1. 装机准备（镜像、启动盘、备份）
2. 安装后配置（驱动、更新、激活、系统设置）
3. 安装日常软件
4. 安装开发软件
5. 查看开发软件清单
6. 一键配置推荐国内镜像
7. 自选包管理器和镜像
8. 恢复官方镜像（按包管理器选择）
0. 退出
```

软件和包管理器支持输入 `1,3,5-7` 多选，输入 `all` 全选。实际更改前显示选项并确认。

## 装机流程

1. 查看电脑型号、系统、架构和磁盘空间，将文件夹和第三方驱动备份到重装时保留的磁盘或 U 盘。
2. 使用微软媒体创建工具下载 Windows 11 ISO，或打开微软官方下载页选择镜像。Arm64 设备使用对应的官方下载页。已有 ISO 可以输入微软公布的 SHA-256 进行校验。
3. 下载并启动 Rufus 或 Ventoy，在工具的原生界面中选择 U 盘并确认写入。写入会清除所选设备的数据。工具下载文件与 GitHub 官方发布的 SHA-256 比对，微软媒体创建工具验证 Microsoft 数字签名。
4. 将安装后助手保存到 U 盘，重启电脑并从 U 盘进入 Windows 安装程序，按安装界面选择版本和分区。
5. 系统安装后运行 U 盘中 `WinDevPicker\Launch.cmd`。该副本支持离线安装备份驱动，联网后可安装软件、检查更新和运行激活工具。

文件夹备份使用 Robocopy，保留目标目录中已有的其他文件。驱动备份使用 DISM 导出第三方驱动，安装使用 PnPUtil 匹配当前硬件。

## 安装后配置

提供电脑信息、备份驱动安装、Windows 更新、激活状态、激活工具、文件扩展名显示，以及任务栏、启动应用、电源和默认应用设置入口。

激活入口使用以下命令，在独立 PowerShell 窗口中启动第三方 Microsoft Activation Scripts，由用户在其菜单中选择具体操作。退出后读取 Windows 许可状态。

```powershell
irm https://get.activated.win | iex
```

文件扩展名设置写入当前用户配置，重新登录后生效。其余 Windows 设置通过对应的系统设置页面调整。

## 软件清单

日常软件在 [`data/apps.json`](data/apps.json) 中维护：微信、QQ、WPS Office、Google Chrome、Mozilla Firefox、小狼毫输入法、SumatraPDF、ShareX、VLC 和 ToDesk。

开发软件在 [`data/packages.json`](data/packages.json) 中维护：Windows Terminal、PowerShell 7、Git、GitHub CLI、Visual Studio Code、Python 3.14、uv、Node.js LTS、Go、Rustup、.NET SDK 10、nvm for Windows、GitHub Copilot CLI、PowerToys、Oh My Posh、Coreutils for Windows、Windows App CLI、Docker Desktop 和 7-Zip。

软件通过 WinGet 精确 ID 安装，已安装的软件跳过。Node.js LTS 与 nvm for Windows 需要二选一。安装后更新当前窗口的程序搜索目录，可继续配置镜像；nvm 安装后仍需安装具体的 Node.js 版本。

## 国内镜像

| 包管理器 | 可选镜像 | 推荐选择 | 修改范围 |
| --- | --- | --- | --- |
| WinGet | 中科大 USTC、官方 | 中科大 USTC | 社区索引源 |
| pip | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 当前用户 pip 配置 |
| uv | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 用户环境变量 `UV_DEFAULT_INDEX` |
| npm | npmmirror、腾讯云、官方 | npmmirror | 用户 registry |
| pnpm | npmmirror、腾讯云、官方 | npmmirror | 用户 registry |
| Yarn | npmmirror、腾讯云、官方 | npmmirror | Yarn 1 用户 registry / Yarn 2+ home 配置 |
| Go | Goproxy.cn、阿里云、官方 | Goproxy.cn | `go env -w GOPROXY` |
| Cargo | 清华 TUNA、中科大 USTC、官方 | 清华 TUNA | `$CARGO_HOME/config.toml` |

镜像地址在 [`data/mirrors.json`](data/mirrors.json) 中维护。缺少工具或权限时显示原因并跳过对应项。Cargo 已有 `config` 或自定义 `config.toml` 时跳过，恢复官方源时只删除本工具生成的配置。

恢复官方源表示恢复官方地址，原有私有地址需要自行保留。WinGet 镜像主要提供索引，软件安装包、组件、系统镜像和激活工具仍有各自的下载来源。

## 命令行

以下命令在本地仓库目录执行。非交互操作使用 `-Yes`，预演使用 `-DryRun -Yes`。

```powershell
.\Start-DevSetup.ps1 -Action Prepare
.\Start-DevSetup.ps1 -Action System
.\Start-DevSetup.ps1 -Action AppList
.\Start-DevSetup.ps1 -Action Apps -PackageIds Tencent.WeChat,VideoLAN.VLC -Yes
.\Start-DevSetup.ps1 -Action List
.\Start-DevSetup.ps1 -Action Install -PackageIds Git.Git,Microsoft.VisualStudioCode -Yes
.\Start-DevSetup.ps1 -Action Mirrors -Managers pip,uv,cargo -Mirror TUNA -Yes
.\Start-DevSetup.ps1 -Action Restore -Managers winget,pip,uv,npm,pnpm,yarn,go,cargo -Yes
.\Start-DevSetup.ps1 -Action Apps -PackageIds Tencent.WeChat -DryRun -Yes
```

`Prepare` 和 `System` 打开对应的交互菜单；`Apps` 不指定 ID 时打开日常软件选择。`Mirrors` 不指定包管理器时选择全部八项，`-Mirror Auto` 使用推荐镜像。终端限制脚本执行时，可在脚本路径前添加 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`。

## 开发与测试

```powershell
.\tests\Smoke.Tests.ps1
.\tests\Behavior.Tests.ps1
.\tests\Setup.Tests.ps1
.\tests\Bootstrap.Tests.ps1
```

GitHub Actions 在 Windows PowerShell 5.1 与 PowerShell 7 上验证清单、预演、配置读写、日志、备份和启动流程。公开下载地址另由 `tests/Online.Tests.ps1` 验证。测试使用独立目录与命令样例，激活工具和启动盘写入均由测试替身验证调用。

装机准备在 `scripts/Preparation.ps1`，安装后配置在 `scripts/System.ps1`，软件安装和镜像配置在 `Start-DevSetup.ps1`。

## 来源

- [微软 Windows 11 下载](https://www.microsoft.com/zh-cn/software-download/windows11)
- [Rufus](https://rufus.ie/zh/)、[Ventoy](https://www.ventoy.net/cn/doc_start.html)
- [Microsoft Activation Scripts](https://get.activated.win)
- [DISM 驱动备份](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-driver-servicing-command-line-options-s14)、[PnPUtil 驱动安装](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [Robocopy](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [WinGet 源](https://learn.microsoft.com/windows/package-manager/winget/source)、[中科大 WinGet 镜像](https://mirrors.ustc.edu.cn/help/winget-source.html)
- [清华 PyPI](https://mirrors.tuna.tsinghua.edu.cn/help/pypi/)、[清华 Cargo](https://mirrors.tuna.tsinghua.edu.cn/help/crates.io-index/)

## 许可

MIT License。下载和启动的第三方软件使用各自的许可。
