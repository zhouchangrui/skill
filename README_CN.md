# Skill CLI

这是一个命令行工具，用于从中央仓库拉取和管理 LLM (大语言模型) 的各项技能（Skills）。

## 安装

### Windows

```powershell
# 使用预编译好的二进制文件
# 或者通过以下命令在本地编译并添加到系统 PATH 环境变量中
```

### macOS / Linux

```bash
# 克隆仓库并构建
git clone <this-repo>
cd skill
zig build -Doptimize=ReleaseSafe
# 编译后的二进制文件将位于 zig-out/bin/skill
```

## 快速开始

在你的项目中初始化技能系统：

```bash
skill init --repo http://192.168.36.168:3002/trendy/skills.git
```

这会在当前目录下创建一个 `skills/` 文件夹，并将配置保存到 `~/.config/skills/skills.json`（在 Windows 上是 `%USERPROFILE%\.config\skills\skills.json`）。

## 使用指南

### 查看可用技能

查看已配置的远程仓库中所有可用的技能：

```bash
skill list
```

### 添加技能

将一个或多个技能添加到本地项目中。默认情况下，它们会被保存到当前项目的 `skills/` 目录下。

```bash
# 添加远程仓库中特定路径下的技能
skill add skills/pdf

# 一次性添加多个技能
skill add skills/pdf skills/pptx

# 使用 -o 参数将技能添加到自定义输出目录
skill add skills/pdf -o ./my_custom_folder
```

### 移除技能

从本地项目中移除已安装的技能。

```bash
# 通过相对路径移除（假设技能存在于 skills/ 目录下）
skill remove skills/pdf

# 移除多个技能
skill remove skills/pdf skills/pptx

# 通过绝对路径移除
skill remove C:\absolute\path\to\skills\pdf
```

### 更新技能

将本地技能更新为远程仓库中的最新版本。

```bash
# 更新特定的技能
skill update skills/pdf

# 更新所有已安装的技能
skill update --all
```

### 环境变量与配置

查看当前的配置信息和仓库路径：

```bash
skill env
```

### 接入指南 (Onboarding)

打印 `AGENTS.md` 的代码块。你可以将这些指令提供给 LLM 代理（Agent），帮助其理解并集成该技能系统：

```bash
skill onboard
```

## 配置文件

配置文件通常保存在 `~/.config/skills/skills.json`（Windows 下为 `%USERPROFILE%\.config\skills\skills.json`）。你可以在其中指定仓库地址和 Git 引用（如分支 branch、标签 tag 或哈希 sha）。

```json
{
  "repo": "http://192.168.36.168:3002/trendy/skills.git"
  // "branch": "main"
  // "tag": "v1.0.0"
  // "sha": "abc123def456"
}
```

## 源码构建

需要安装 [Zig](https://ziglang.org/)，版本至少为 0.15.1。

### 编译为本地平台
```bash
zig build -Doptimize=ReleaseSafe
```

### 交叉编译为 Linux 平台 (从 Windows/macOS)
```bash
zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux
```