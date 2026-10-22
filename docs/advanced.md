# 技术说明

本页包含命令行用法、配置说明、测试和部署方法。图形界面的操作见 [README](../README.md)。脚本支持 Windows PowerShell 5.1 与 PowerShell 7。

## 命令行

以下命令在本地仓库目录执行。非交互操作使用 `-Yes`，预演使用 `-DryRun -Yes`。

```powershell
.\Start-DevSetup.ps1 -Action Desktop
.\Start-DevSetup.ps1 -Action Menu
.\Start-DevSetup.ps1 -Action Prepare
.\Start-DevSetup.ps1 -Action System
.\Start-DevSetup.ps1 -Action Optimize
.\Start-DevSetup.ps1 -Action Optimize -FullOptimization -DryRun -Yes
.\Start-DevSetup.ps1 -Action AppList
.\Start-DevSetup.ps1 -Action Apps -PackageIds Tencent.WeChat,VideoLAN.VLC -Yes
.\Start-DevSetup.ps1 -Action List
.\Start-DevSetup.ps1 -Action Install -PackageIds Git.Git,Microsoft.VisualStudioCode -Yes
.\Start-DevSetup.ps1 -Action Install -PackageIds Git.Git -InstallRoot D:\Applications -InteractiveInstall -Yes
.\Start-DevSetup.ps1 -Action Mirrors -Managers pip,uv,cargo -Mirror TUNA -Yes
.\Start-DevSetup.ps1 -Action Restore -Managers winget,pip,uv,npm,pnpm,yarn,go,cargo -Yes
.\Start-DevSetup.ps1 -Action Apps -PackageIds Tencent.WeChat -DryRun -Yes
```

默认使用 `Desktop` 打开图形界面，`Menu` 打开终端菜单。在线启动命令的标准输入被重定向时使用终端菜单，支持通过输入序列操作。

`Prepare` 和 `System` 打开对应的交互菜单；`Apps` 不指定软件编号时打开日常软件选择。`Mirrors` 不指定工具时选择全部八项，`-Mirror Auto` 使用推荐下载源。终端限制脚本执行时，可在脚本路径前添加 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`。

## 安装与备份

日常软件清单在 [`data/apps.json`](../data/apps.json)，开发软件清单在 [`data/packages.json`](../data/packages.json)。软件通过 WinGet 的唯一软件编号安装，已安装的软件跳过。自选安装目录下按软件编号建立子目录，并通过 `--location` 传给安装程序；是否接受该路径由软件自身决定。

Node.js LTS（Long-Term Support，长期支持版）与 nvm for Windows（Node Version Manager for Windows，Node.js 版本管理工具）二选一，选择 nvm 后还需安装具体的 Node.js 版本。安装后更新当前窗口的程序搜索目录，可继续设置软件下载源。

离线下载使用 `winget download`，按目标处理器下载安装包及 WinGet 声明的依赖。安装包是否支持离线使用需要单独核实。

准备目录用 `Images` 保存镜像、`Drivers` 保存目标电脑驱动、`Software` 保存安装包、`WindowsSetupHelper` 保存离线助手，`target.json` 记录目标信息。

文件夹备份使用 Robocopy，保留目标目录中已有的其他文件。驱动备份使用 Deployment Image Servicing and Management（DISM，Windows 自带的镜像与驱动管理工具）导出第三方驱动，安装使用 PnPUtil 匹配当前硬件。

在线启动从 `setup.rustypiano.com` 下载助手，退出时清理本次下载的临时文件。系统镜像、工具和备份保存在用户选择的位置，日志保存在 `%LOCALAPPDATA%\WindowsSetupHelper\logs\`。

## 系统配置

系统配置保存在 [`data/tweaks.json`](../data/tweaks.json)，共 23 项。图形界面的“应用推荐设置”应用其中 18 项，具体内容见操作窗口和 README。

小组件使用微软 LGPO 工具导入本地组策略，再执行计算机策略刷新并读取最终值。工具从 Microsoft Download Center 下载，压缩包和可执行文件均校验 SHA256，缓存在 `%LOCALAPPDATA%\WindowsSetupHelper\tools\lgpo\`。此操作保留现有注册表权限和 Windows 保护驱动。参见[微软本地组策略工具说明](https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/security-compliance-toolkit-10)和[小组件策略](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-newsandinterests#allownewsandinterests)。

`-Action Optimize -FullOptimization` 还会启用 Sudo、开发者模式、远程桌面、关闭全部弹出通知和隐藏蓝牙图标。Sudo 需要系统提供 Windows Sudo；家庭版无法作为远程桌面被控端，远程桌面防火墙需要单独允许连接。部分设置需要重新登录或重启 Windows 后生效。

“其他激活工具”在独立 PowerShell 窗口中执行以下命令，启动第三方 Microsoft Activation Scripts，由用户在其菜单中选择具体操作。退出后读取 Windows 激活状态。

```powershell
irm https://get.activated.win | iex
```

## 软件下载源

下载源是 WinGet 和开发工具查询软件、下载软件包时使用的地址，在 [`data/mirrors.json`](../data/mirrors.json) 中维护。

| 工具 | 可选下载源 | 推荐选择 | 修改范围 |
| --- | --- | --- | --- |
| WinGet | 中国科学技术大学、官方 | 中国科学技术大学 | 用于查询软件的清单地址 |
| pip | 清华大学、中国科学技术大学、阿里云、官方 | 清华大学 | 当前用户 pip 配置 |
| uv | 清华大学、中国科学技术大学、阿里云、官方 | 清华大学 | 用户环境变量 `UV_DEFAULT_INDEX` |
| npm | npmmirror、腾讯云、官方 | npmmirror | 当前用户的软件包下载地址 |
| pnpm | npmmirror、腾讯云、官方 | npmmirror | 当前用户的软件包下载地址 |
| Yarn | npmmirror、腾讯云、官方 | npmmirror | 当前用户的 Yarn 下载源配置 |
| Go | Goproxy.cn、阿里云、官方 | Goproxy.cn | `go env -w GOPROXY` |
| Cargo | 清华大学、中国科学技术大学、官方 | 清华大学 | `$CARGO_HOME/config.toml` |

缺少工具或权限时显示原因并跳过对应项。Cargo 已有 `config` 或自定义 `config.toml` 时跳过，恢复官方源时只删除本工具生成的配置。

这些设置不用于下载 Windows 系统镜像。WinGet 下载源主要提供软件清单，软件安装包、组件和激活工具仍有各自的下载来源。恢复官方源表示恢复官方地址，原有私有地址需要自行保留。

## 开发与测试

先生成发布文件，再运行测试：

```shell
python3 scripts/build-hosting.py
```

```powershell
.\tests\Smoke.Tests.ps1
.\tests\Behavior.Tests.ps1
.\tests\Setup.Tests.ps1
.\tests\Copy.Tests.ps1
.\tests\Dialogs.Tests.ps1
.\tests\Menu.Tests.ps1
.\tests\Desktop.Tests.ps1
.\tests\Optimization.Tests.ps1
.\tests\WidgetsPolicy.Tests.ps1
.\tests\Elevation.Tests.ps1
.\tests\Bootstrap.Tests.ps1
```

GitHub Actions 在 Windows PowerShell 5.1 与 PowerShell 7 上验证清单、预演、配置读写、日志、备份、窗口选择、发布压缩包和启动流程。`tests/Online.Tests.ps1` 验证公开启动命令，在 Actions 页面手动运行工作流时执行；域名和托管生效后可运行此项。`tests/Downloads.Tests.ps1` 实际下载三个官方工具并校验文件。测试使用独立目录和样例程序验证调用，真实激活和启动盘写入由用户在工具中操作。

图形界面在 `scripts/Desktop.ps1`，后台任务和目标电脑检查在 `scripts/DesktopTasks.ps1`，引导内容在 `data/guide.json`。装机准备在 `scripts/Preparation.ps1`，安装后设置和系统优化在 `scripts/System.ps1`，软件安装和镜像配置在 `Start-DevSetup.ps1`。桌面测试验证目标隔离、安装目录、软件互斥、步骤状态、取消操作和后台结果；窗口测试仅在 Windows 执行。系统优化测试逐项核对微软原脚本，并在独立测试注册表目录中验证写入。

## Vercel 托管

在 Vercel 导入 `RustyPiano/windows-setup-helper`，使用仓库根目录，生产分支选择 `main`。构建命令、发布目录、响应类型和缓存规则由根目录的 `vercel.json` 提供，控制台保留仓库配置即可。构建环境需要提供 Python 3。

`scripts/build-hosting.py` 在 `public` 中生成 `bootstrap.ps1` 和 `windows-setup-helper.zip`。压缩包包含主程序、功能脚本、软件清单、启动文件、README、技术说明和许可。离线助手也包含技术说明，可通过 README 中的相对链接打开。`public` 是生成目录，不提交到 Git。

在 Settings → Domains 添加 `setup.rustypiano.com`，到域名解析管理页面添加名称为 `setup` 的 CNAME（Canonical Name，别名）记录，目标填写 Vercel 显示的地址。等待域名验证和证书签发完成，并确保正式域名允许匿名访问，无需登录或浏览器验证。

关联仓库后，每次推送到 `main` 都会自动构建并更新正式域名；其他分支生成预览部署。构建脚本和 Vercel 配置随代码提交，后续无需逐次调整控制台。启动脚本和助手压缩包均由 Vercel 提供，软件安装包、系统镜像和第三方工具仍使用各自的下载地址。

参考 [Vercel 仓库配置](https://vercel.com/docs/project-configuration/vercel-json)、[GitHub 自动部署](https://vercel.com/docs/git/vercel-for-github)和[域名配置](https://vercel.com/docs/domains/working-with-domains/add-a-domain)。

## 来源

- [Microsoft WindowsDeveloperConfig 系统配置](https://github.com/microsoft/WindowsDeveloperConfig/tree/fe21c03a486a1076c425720c1ebe4e25404e0e6b/windows-dev-config/steps)：系统、文件管理器、任务栏与搜索、Edge 配置，MIT License。
- [微软 Windows 11 下载](https://www.microsoft.com/zh-cn/software-download/windows11)
- [Rufus](https://rufus.ie/zh/)、[Ventoy](https://www.ventoy.net/cn/doc_start.html)
- [Microsoft Activation Scripts](https://get.activated.win)
- [DISM 驱动备份](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-driver-servicing-command-line-options-s14)、[PnPUtil 驱动安装](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [Robocopy](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [WinGet 源](https://learn.microsoft.com/en-us/windows/package-manager/winget/source)、[中国科学技术大学 WinGet 镜像](https://mirrors.ustc.edu.cn/help/winget-source.html)
- [清华大学 Python 软件包镜像](https://mirrors.tuna.tsinghua.edu.cn/help/pypi/)、[清华大学 Cargo 镜像](https://mirrors.tuna.tsinghua.edu.cn/help/crates.io-index/)
