# WinDevPicker

Windows 开发环境交互式安装与国内镜像配置工具。使用系统自带的 Windows PowerShell 5.1 即可运行，也支持 PowerShell 7。

可以选择软件、一次配置常见包管理器的镜像、单独挑选镜像、恢复官方地址。无需安装 Python、Node.js 或其他额外运行环境。

## 快速开始

在 Windows PowerShell 中粘贴以下命令：

```powershell
irm https://raw.githubusercontent.com/RustyPiano/win-dev-picker/main/bootstrap.ps1 | iex
```

启动脚本自动下载主脚本和两份清单，打开中文菜单。下载文件在退出后清理，运行日志保留在本机。

也可以下载仓库 ZIP 并解压，双击 `Launch.cmd`，或在 Windows PowerShell 中进入仓库目录，运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-DevSetup.ps1
```

交互菜单：

```text
========== Windows 开发环境安装助手 ==========
1. 选择安装软件
2. 一键配置推荐国内镜像
3. 自选包管理器和镜像
4. 恢复官方镜像（按包管理器选择）
5. 查看软件清单
0. 退出
```

选择软件和包管理器时，输入 `1,3,5-7` 可多选，输入 `all` 选择全部。实际更改前会显示选项并要求确认。

## 软件清单

提供 Windows Terminal、PowerShell 7、Git、GitHub CLI、Visual Studio Code、Python 3.14、uv、Node.js LTS、Go、Rustup、.NET SDK 10、nvm for Windows、GitHub Copilot CLI、PowerToys、Oh My Posh、Coreutils for Windows、Windows App CLI、Docker Desktop 和 7-Zip。

软件均通过 WinGet 的精确 ID 安装，用途说明、软件 ID 和分类在 [`data/packages.json`](data/packages.json) 中维护。安装前显示已安装和待安装的软件，已经安装的会跳过。Node.js LTS 与 nvm for Windows 需要二选一，冲突会在确认安装之前提示。

安装结束后，当前窗口会读取更新后的程序搜索目录，可直接返回菜单配置镜像。nvm for Windows 安装后还需要通过 `nvm` 安装具体的 Node.js 版本。

## 国内镜像

| 包管理器 | 可选镜像 | 一键配置时的默认选择 | 修改范围 |
| --- | --- | --- | --- |
| WinGet | 中科大 USTC、官方 | 中科大 USTC | `winget` 社区索引源 |
| pip | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 当前用户 pip 配置 |
| uv | 清华 TUNA、中科大 USTC、阿里云、官方 | 清华 TUNA | 当前用户 `UV_DEFAULT_INDEX` 环境变量 |
| npm | npmmirror、腾讯云、官方 | npmmirror | 当前用户 npm registry |
| pnpm | npmmirror、腾讯云、官方 | npmmirror | 当前用户 pnpm registry |
| Yarn | npmmirror、腾讯云、官方 | npmmirror | Yarn 1 的用户 registry / Yarn 2+ 的 home 配置 |
| Go | Goproxy.cn、阿里云、官方 | Goproxy.cn | `go env -w GOPROXY` |
| Cargo | 清华 TUNA、中科大 USTC、官方 | 清华 TUNA | `$CARGO_HOME/config.toml` |

镜像地址与默认选择均可在 [`data/mirrors.json`](data/mirrors.json) 中调整。

**下载范围说明**：WinGet 镜像主要加速软件清单/索引的访问，软件安装包仍可能下载自 GitHub、微软或软件作者的服务器。此工具不会设置系统代理、修改 DNS、关闭证书检查或绕过哈希校验。

修改 WinGet 源需要管理员权限，确认之前会提示权限要求。需要修改时，以管理员身份打开 Windows PowerShell 并运行启动命令。缺少权限时跳过 WinGet，继续配置其他包管理器。未安装的 pip、npm、pnpm、Yarn 或 Go 会跳过。

Cargo 仅会创建或更新由本工具生成的 `config.toml`。已有 `config` 或自定义 `config.toml` 时，工具会显示路径并跳过。恢复官方 Cargo 源时，只删除本工具创建的配置文件。Cargo 的 `search` / `info` 在使用镜像时可能需要添加 `--registry win-dev-picker`。

## 命令行模式

以下命令在本地仓库目录中执行；非交互模式使用 `-Yes` 表示同意执行，预演使用 `-DryRun -Yes`。如果当前终端限制执行脚本，可使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` 加上脚本路径和参数。

查看清单：

```powershell
.\Start-DevSetup.ps1 -Action List
```

按 WinGet ID 安装指定软件：

```powershell
.\Start-DevSetup.ps1 -Action Install -PackageIds Git.Git,Microsoft.VisualStudioCode,astral-sh.uv -Yes
```

一次设置全部推荐镜像：

```powershell
.\Start-DevSetup.ps1 -Action Mirrors -Mirror Auto -Yes
```

针对 Python 和 Rust 选择清华镜像：

```powershell
.\Start-DevSetup.ps1 -Action Mirrors -Managers pip,uv,cargo -Mirror TUNA -Yes
```

恢复指定包管理器的官方源：

```powershell
.\Start-DevSetup.ps1 -Action Restore -Managers winget,pip,uv,npm,pnpm,yarn,go,cargo -Yes
```

只查看将要执行的操作，不访问软件源、不安装软件、不更改配置：

```powershell
.\Start-DevSetup.ps1 -Action Mirrors -Managers pip,uv,go -DryRun -Yes
.\Start-DevSetup.ps1 -Action Install -PackageIds Git.Git,Microsoft.PowerShell -DryRun -Yes
```

`-Action Mirrors` 不指定 `-Managers` 时选择全部八个包管理器，`-Mirror Auto` 使用每个包管理器对应的推荐镜像。如果选定的镜像不支持某个包管理器，脚本会在修改前提示错误。

## 恢复与记录

菜单第 4 项恢复各包管理器的官方地址。恢复过程只修改本工具支持的设置，保留其他无关设置。pip 恢复为显式 PyPI 官方地址；其余工具移除相应的用户覆盖设置或恢复 WinGet 默认源。

每次操作结束后，按软件或包管理器统计成功、跳过和失败数量。实际命令、命令输出及操作结果保存在 `%LOCALAPPDATA%\WinDevPicker\logs\`，脚本异常退出时也保存已有记录。预演操作不写入日志。

## 运行范围

在线入口从本仓库下载并执行代码。启动器的 `-ExecutionPolicy Bypass` 仅作用于子进程，管理员确认和重启要求由软件安装程序决定。

镜像配置会修改选定包管理器的用户软件源。使用私有源时，请按需选择包管理器。恢复官方源表示使用官方地址，原有私有地址需要自行保留。

本工具负责软件安装和镜像配置。WinGet 软件安装包、软件自行下载的组件和依赖有各自的来源，国内镜像无法保证全部下载始终可用。

## 开发和测试

```powershell
.\tests\Smoke.Tests.ps1
.\tests\Behavior.Tests.ps1
.\tests\Bootstrap.Tests.ps1
```

GitHub Actions 在 Windows PowerShell 5.1 与 PowerShell 7 上执行语法、清单、预演、配置读写、错误记录和在线启动测试。测试使用独立目录和命令样例，不安装软件。修改软件清单时编辑 `data/packages.json`，修改镜像时编辑 `data/mirrors.json`。

## 镜像和命令参考

- [WinGet 官方 source 文档](https://learn.microsoft.com/windows/package-manager/winget/source)
- [中科大 WinGet](https://mirrors.ustc.edu.cn/help/winget-source.html)
- [清华 PyPI](https://mirrors.tuna.tsinghua.edu.cn/help/pypi/)
- [中科大 PyPI](https://mirrors.ustc.edu.cn/help/pypi.html)
- [阿里云 PyPI](https://developer.aliyun.com/mirror/pypi)
- [npmmirror](https://npmmirror.com/)
- [pnpm config](https://pnpm.io/cli/config)
- [Yarn config set](https://yarnpkg.com/cli/config/set)
- [uv 配置说明](https://docs.astral.sh/uv/configuration/files/)
- [Goproxy.cn](https://goproxy.cn/)
- [阿里云 Go](https://developer.aliyun.com/mirror/goproxy)
- [清华 Cargo](https://mirrors.tuna.tsinghua.edu.cn/help/crates.io-index/)
- [中科大 Cargo](https://mirrors.ustc.edu.cn/help/crates.io-index.html)
- [Cargo source replacement](https://doc.rust-lang.org/cargo/reference/source-replacement.html)

## 许可

MIT License。WindowsDeveloperConfig 和其他软件的名称均属于相应项目，WinDevPicker 是独立实现的社区工具。
