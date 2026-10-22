# Windows 装机助手

Windows 装机助手，覆盖镜像下载、启动盘工具、文件与驱动备份、安装后配置、日常软件和开发环境。支持 Windows PowerShell 5.1 与 PowerShell 7。

## 启动

在 Windows PowerShell 中运行：

```powershell
irm https://setup.rustypiano.com | iex
```

运行命令后从同一域名下载并打开 Windows 装机助手，退出时清理临时文件。系统镜像、工具和备份保存在用户选择的位置，日志保存在 `%LOCALAPPDATA%\WindowsSetupHelper\logs\`。

也可以下载仓库 ZIP 并解压，双击 `Launch.cmd`。以管理员身份运行终端可备份和安装驱动、修改 WinGet 源。

```text
========== Windows 装机助手 ==========
1. 装机准备（系统镜像、启动盘、备份）
2. 安装后配置（驱动、更新、激活、系统设置）
3. 安装日常软件
4. 安装开发软件
5. 查看开发软件清单
6. 设置推荐的国内软件下载源
7. 自选工具和软件下载源
8. 恢复软件的官方下载源
0. 退出
```

软件和包管理器支持输入 `1,3,5-7` 多选，输入 `all` 全选。实际更改前显示选项并确认。

## 装机流程

1. 查看电脑型号、系统、架构和磁盘空间，将文件夹和第三方驱动备份到重装时保留的磁盘或 U 盘。
2. 下载 Windows 系统镜像，即安装 Windows 使用的 ISO 文件。微软媒体创建工具负责下载；采用 Arm 处理器的电脑会打开对应的官方下载页。已有文件可以通过选择窗口打开，再粘贴微软下载页的校验值，检查文件是否下载完整。
3. 选择启动盘工具。Rufus 将一个系统镜像写入 U 盘，Ventoy 支持在同一个启动 U 盘中保存多个系统镜像。在工具窗口中选择目标 U 盘并确认写入，写入会清除所选设备的数据。助手会校验下载的工具文件，微软媒体创建工具还会验证 Microsoft 数字签名。
4. 将安装后助手保存到 U 盘，重启电脑并从 U 盘进入 Windows 安装程序，按安装界面选择版本和分区。
5. 系统安装后运行 U 盘中 `WindowsSetupHelper\Launch.cmd`。保存在 U 盘中的助手可离线安装备份驱动，联网后可安装软件、检查更新和运行激活工具。

文件夹备份使用 Robocopy，保留目标目录中已有的其他文件。驱动备份使用 DISM 导出第三方驱动，安装使用 PnPUtil 匹配当前硬件。

备份、恢复驱动和保存 U 盘副本都通过窗口选择文件夹。点击“取消”返回菜单。

## 安装后配置

提供电脑信息、备份驱动安装、Windows 更新、激活状态、激活工具、文件扩展名显示，以及任务栏、启动应用、电源和默认应用设置入口。

激活入口使用以下命令，在独立 PowerShell 窗口中启动第三方 Microsoft Activation Scripts，由用户在其菜单中选择具体操作。退出后读取 Windows 激活状态。

```powershell
irm https://get.activated.win | iex
```

文件扩展名设置写入当前用户配置，重新登录后生效。其余 Windows 设置通过对应的系统设置页面调整。

## 软件清单

日常软件在 [`data/apps.json`](data/apps.json) 中维护：微信、QQ、WPS Office、Google Chrome、Mozilla Firefox、小狼毫输入法、SumatraPDF、ShareX、VLC 和 ToDesk。

开发软件在 [`data/packages.json`](data/packages.json) 中维护：Windows Terminal、PowerShell 7、Git、GitHub CLI、Visual Studio Code、Python 3.14、uv、Node.js LTS、Go、Rustup、.NET SDK 10、nvm for Windows、GitHub Copilot CLI、PowerToys、Oh My Posh、Coreutils for Windows、Windows App CLI、Docker Desktop 和 7-Zip。

软件通过 WinGet 的唯一软件编号安装，已安装的软件跳过。Node.js LTS 与 nvm for Windows 需要二选一。安装后更新当前窗口的程序搜索目录，可继续设置软件下载源；nvm 安装后仍需安装具体的 Node.js 版本。

## 软件下载源

| 工具 | 可选下载源 | 默认选择 | 修改范围 |
| --- | --- | --- | --- |
| WinGet | 中科大 USTC、官方 | 中科大 USTC | 用于查询软件的清单地址 |
| pip | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 当前用户 pip 配置 |
| uv | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 用户环境变量 `UV_DEFAULT_INDEX` |
| npm | npmmirror、腾讯云、官方 | npmmirror | 用户 registry |
| pnpm | npmmirror、腾讯云、官方 | npmmirror | 用户 registry |
| Yarn | npmmirror、腾讯云、官方 | npmmirror | 当前用户的 Yarn 下载源配置 |
| Go | Goproxy.cn、阿里云、官方 | Goproxy.cn | `go env -w GOPROXY` |
| Cargo | 清华 TUNA、中科大 USTC、官方 | 清华 TUNA | `$CARGO_HOME/config.toml` |

下载源是 WinGet 和开发工具查询软件、下载软件包时使用的地址，在 [`data/mirrors.json`](data/mirrors.json) 中维护。缺少工具或权限时显示原因并跳过对应项。Cargo 已有 `config` 或自定义 `config.toml` 时跳过，恢复官方源时只删除本工具生成的配置。

这些设置不用于下载 Windows 系统镜像。WinGet 下载源主要提供软件清单，软件安装包、组件和激活工具仍有各自的下载来源。恢复官方源表示恢复官方地址，原有私有地址需要自行保留。

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

`Prepare` 和 `System` 打开对应的交互菜单；`Apps` 不指定软件编号时打开日常软件选择。`Mirrors` 不指定工具时选择全部八项，`-Mirror Auto` 使用推荐下载源。终端限制脚本执行时，可在脚本路径前添加 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`。

## 开发与测试

先生成发布文件，再运行测试：

```shell
python3 scripts/build-hosting.py
```

```powershell
.\tests\Smoke.Tests.ps1
.\tests\Behavior.Tests.ps1
.\tests\Setup.Tests.ps1
.\tests\Dialogs.Tests.ps1
.\tests\Bootstrap.Tests.ps1
```

GitHub Actions 在 Windows PowerShell 5.1 与 PowerShell 7 上验证清单、预演、配置读写、日志、备份、窗口选择、发布压缩包和启动流程。`tests/Online.Tests.ps1` 验证公开启动命令，在 Actions 页面手动运行工作流时执行；域名和托管生效后可运行此项。`tests/Downloads.Tests.ps1` 实际下载三个官方工具并校验文件。测试使用独立目录和样例程序验证调用，真实激活和启动盘写入由用户在工具中操作。

装机准备在 `scripts/Preparation.ps1`，安装后配置在 `scripts/System.ps1`，软件安装和镜像配置在 `Start-DevSetup.ps1`。

## Vercel 托管

在 Vercel 导入 `RustyPiano/windows-setup-helper`，使用仓库根目录，生产分支选择 `main`。构建命令、发布目录、响应类型和缓存规则由根目录的 `vercel.json` 提供，控制台保留仓库配置即可。构建环境需要 Python 3，Vercel 已提供。

`scripts/build-hosting.py` 在 `public` 中生成 `bootstrap.ps1` 和 `windows-setup-helper.zip`。压缩包包含主程序、功能脚本、软件清单、启动文件、说明和许可。`public` 是生成目录，不提交到 Git。

在 Settings → Domains 添加 `setup.rustypiano.com`，到域名的 DNS 管理页面添加名称为 `setup` 的 CNAME 记录，目标填写 Vercel 显示的地址。等待域名和 HTTPS 验证通过，并确保正式域名允许匿名访问，无需登录或浏览器验证。

关联仓库后，每次推送到 `main` 都会自动构建并更新正式域名；其他分支生成预览部署。构建脚本和 Vercel 配置随代码提交，后续无需逐次调整控制台。启动脚本和助手压缩包均由 Vercel 提供，软件安装包、系统镜像和第三方工具仍使用各自的下载地址。

参考 [Vercel 仓库配置](https://vercel.com/docs/project-configuration/vercel-json)、[GitHub 自动部署](https://vercel.com/docs/git/vercel-for-github)和[域名配置](https://vercel.com/docs/domains/working-with-domains/add-a-domain)。

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
