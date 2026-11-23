# FP 期末报告：旧版 procfs 教程复现与 A-Tune 技术介绍

## 选题与环境

第一部分选择题目路线 **(1)：寻找兼容内核并调试教程示例**。使用 Linux 2.6.29，保留教程的 `create_proc_entry`、`create_proc_read_entry`、`read_proc`、`write_proc` 和 `data` 等接口。内核与外部模块由同一 GCC 4.9.4 工具链编译，实验在 GitHub Actions 的隔离 QEMU 虚拟机中执行。旧内核与网络隔离，实验后关闭。第二部分选择 openEuler 的 **A-Tune**，按题目要求介绍用途、架构与背后技术。

## 一、实验目标和实现

根据老师指定教程第 5 章的完整示例，建立 `/proc/procfs_example`，包含 `foo`、`bar`、`jiffies` 和指向 `jiffies` 的相对软链接 `jiffies_too`。`foo/bar` 共用读写回调，通过不同的私有数据指针访问各自的状态；`jiffies` 由回调读取内核计时值。卸载时按子项在前、目录在后的顺序清理。

用户态读取 proc 文件时，内核调用 `read_proc` 生成文本；写入时调用 `write_proc`，通过 `copy_from_user` 将数据复制到内核缓冲区。它们是内核状态的接口，数据无需保存在磁盘文件中。

## 二、调试与修正

- 使用教程对应年代且保留相应字段的 2.6.29 内核，避免把旧接口代码直接放进现代内核。
- 内核由 GCC 4.9.4 编译；宿主编译工具关闭默认 PIE 并使用兼容的 common 符号行为。旧 `kernel/timeconst.pl` 中现代 Perl 不支持的 `defined(@val)` 改为数组非空判断，补丁日志保留。
- 旧编译器依赖的 `libmpfr.so.4` 从 Ubuntu 官方归档提取到云端构建目录，通过库搜索路径供编译器使用，避免替换宿主系统库。
- 修复旧 vDSO Makefile 的链接参数传递，将 `-m elf_x86_64` 改为 `-Wl,-m,elf_x86_64`，由 GCC 正确转交链接器。
- 读取回调补齐偏移与 EOF 处理，使用有界格式化；用单字节读取测试确认文件读完能正确结束。
- 保留 8 字节值容量。原例对过长写入返回短长度，用户程序重试剩余部分时可能反复覆盖；修改版对超过容量的输入返回 `-E2BIG`，原值保持不变。
- 添加互斥锁保护读写共享状态，内核缓冲区显式终止字符串，初始化失败也清理已创建的条目。
- 使用能在旧内核上启动的静态 musl BusyBox，避免现代 glibc 的最低内核版本限制。

## 三、验证方法与截图对应

| 图号 | 内容 | 验证目标 |
| --- | --- | --- |
| 01 | 真实云端构建日志、版本、源码校验和 | 内核、编译器与模块匹配 |
| 02 | 调试说明 | 解释兼容性和代码修正 |
| 03 | 内核启动、模块加载、proc 条目 | 示例已在真实内核运行 |
| 04 | 初始值与两次 tick 采样 | 读回调、私有数据和动态内容 |
| 05 | 分别写入 foo/bar 后回读 | 写回调和独立状态 |
| 06 | 8 字节边界、过长输入、逐字节读取 | 长度、错误处理及 EOF |
| 07 | 目录、软链接、权限 | 教程管理 proc 条目的功能 |
| 08 | 卸载、清理、重新加载、恢复初始值 | 生命周期及资源释放 |
| 09 | A-Tune 架构研究 | openEuler 特色技术介绍 |
| 10 | 评估方法及实验结论 | 解释调优如何验证效果 |

第 03—08 图为运行中的虚拟机终端实测。第 02、09、10 图为报告说明页，其中 A-Tune 部分是官方文档研究；不将这些说明页作为 A-Tune 服务运行或性能提升的实测证据。

## 四、openEuler 特色技术：A-Tune

A-Tune 面向工作负载特征选择系统配置，减少逐个参数人工尝试的成本。不同服务对 CPU、内存、网络和存储的需求不同，单一配置难以适合全部场景。

官方架构分为三个层面：交互系统负责监测资源和执行配置策略；系统画像利用特征工程及两层分类模型识别业务特征；智能决策层根据识别结果形成调优决策。可以把这个过程理解为“采集指标—形成特征—识别业务—匹配配置—应用策略”，再通过测量判断效果。

例如 Web 服务常关注 CPU 与网络，而内存数据库具有不同的资源需求。官方还列出自定义配置/业务模型、自动参数优化等能力。这里选择 A-Tune 是因为它能用清楚的资源指标、模型分类和配置执行过程说明技术原理。

对一次调优的有效性，应固定硬件、软件及负载，先测基线，再应用策略，重复采样比较吞吐量、时延、资源占用和稳定性。能否提升必须依赖对应场景的测量，不能把某一业务的结果直接推广到所有业务。本文的第二部分介绍技术机制和评估方法，不报告未经运行的性能数字。

## 五、结论

兼容内核路线可以复现教程原有的 procfs 机制。完善偏移、EOF、长度检查、同步和清理后，示例更容易稳定使用。A-Tune 则展示了 openEuler 根据业务特征辅助选择系统配置的思路，两部分分别体现了内核接口实践与操作系统特色技术分析。

## 参考资料

1. Erik Mouw, [Linux Kernel Procfs Guide](https://kernelnewbies.org/Documents/Kernel-Docbooks?action=AttachFile&do=get&target=procfs-guide_2.6.29.pdf)，第 2—5 章；示例代码 GPL-2.0-or-later。
2. [Linux v2.6.29 proc_fs.h](https://github.com/torvalds/linux/blob/v2.6.29/include/linux/proc_fs.h)。
3. [Linux 2.6.29 官方源码归档](https://cdn.kernel.org/pub/linux/kernel/v2.6/linux-2.6.29.tar.xz)。
4. [kernel.org GCC 4.9.4 工具链](https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/4.9.4/)。
5. openEuler 22.03 LTS, [Getting to Know A-Tune](https://docs.openeuler.org/en/docs/22.03_LTS/docs/A-Tune/getting-to-know-a-tune.html)。
