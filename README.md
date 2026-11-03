# GitHub Actions 云端运行

本方案在 GitHub 托管的 `ubuntu-24.04` 虚拟机上完成，用户电脑不再执行 WSL 内核构建。它安装与虚拟机正在运行的内核匹配的 Ubuntu 头文件和符号表，然后只编译作业模块。

## 工作流行为

1. 检查 Bash 脚本语法，安装匹配的构建依赖。
2. 在 Xvfb 虚拟显示器中启动真正的 xterm 终端。
3. 依次运行编译、默认参数、自定义参数、计算与卸载、非法参数五组验证。
4. 每组运行后，使用 scrot 截取实际终端的显示画面，保存五张 PNG。
5. 上传源码、`p1_demo.ko`、PNG 截图和完整日志为 `p1-results-<run_id>` 工件，保留三天。

这五张图片是云端终端的实际屏幕捕获。模块加载、日志和截图均须在工作流实际执行后确认成功；当前文件本身不代表已经运行通过。

## 仓库放置方式

将工程文件放在专用仓库根目录，保留 `.github/workflows/p1-cloud.yml` 的路径。推送源码或工作流会触发运行，也可以在仓库的 Actions 页面选择此工作流，再点击 Run workflow。

使用标准 `ubuntu-24.04` runner，单次作业设为十五分钟超时。不使用个人电脑上的 runner，不调用 WSL 构建脚本。私有仓库运行使用该账号的 Actions 配额，费用及额度以该账号设置为准。

如果托管环境无法提供匹配的头文件、拒绝加载模块，或编译失败，工作流会报告失败并保留诊断日志；需要据此修复或更换支持内核模块的虚拟机。不能将失败画面当作实验成功的证据。

## 截图内容

| 文件 | 内容 |
| --- | --- |
| `01_build.png` | 三个 C 源文件编译链接为一个模块及参数信息 |
| `02_default.png` | 默认参数加载、模块列表、问候及卸载日志 |
| `03_parameters.png` | 自定义名字、重复两次及读取参数 |
| `04_calc_unload.png` | 加法、乘法结果和正常卸载验证 |
| `05_invalid.png` | 非法参数拒绝加载 |

截图中会显示 GitHub 托管 Ubuntu 环境和实际内核版本，以准确记录实验环境。源码中的作业要求没有写明必须使用学生个人电脑；若老师另有环境要求，请以补充要求为准。

## 官方依据

- [GitHub 托管的虚拟机 runner](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
- [Ubuntu 24.04 runner 镜像说明](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [Linux 外部模块构建要求](https://docs.kernel.org/kbuild/modules.html)
