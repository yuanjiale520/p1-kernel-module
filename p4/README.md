# Practice 4：从虚拟地址到物理地址

沿用老师给出的 `paging_lowmem.c`、`dram.c` 和 `fileview.cpp`，在 GitHub Actions 内编译 Linux 6.6.30 和匹配模块，再启动独立 QEMU 虚拟机运行。没有在本机加载模块，没有把预编译的旧 `dram.ko` 用于新内核。原始文件保存在 `supplied/`，修改版和新增验证程序均保留源码。

## 实验设计

1. 修复原示例 `vaddr` 的局部变量遮蔽问题，处理分配失败，并在卸载时正确释放。
2. 用 `__get_free_page` 分配一页，在页内偏移 `0x123` 处写入字符串。保留原直接映射地址，再用 `vmap` 建立指向同一页的 4KB 别名，以完整展示 PTE 层。原直接映射可能使用 2MB 大页，因此另外如实展示它的实际终止层。
3. 在模块初始化中读取 CR0/CR3，保留加载进程 mm 的引用，使根页表在实验结束前有效。用内核 `pgd_index/p4d_offset/pud_offset/pmd_offset/pte_offset_kernel` 逐级获取表项，导出只读实验数据。
4. `dram` 通过 `pfn_to_page -> kmap -> copy_to_user` 提供只读物理内存访问，改为动态主设备号、检查边界和有效 PFN，并要求 CAP_SYS_RAWIO。
5. 新增 `p4_probe` 从 CR3 根地址出发，独立通过 `/dev/dram` 读取每一级真实表项并换算地址，与内核 helper 结果和原地址的 `virt_to_phys` 交叉验证。修改版 FILEVIEW 新增 `--dump` 模式，原交互模式保留。

## 截图解释

| 截图 | 对应要求与结果 |
| --- | --- |
| 01_environment | 内核、两个模块、CR0/CR3、原地址和别名、各级 shift 和项数 |
| 02_PGD | VA[47:39] 得到 PGD 索引；CR3 根地址 + 索引×8 定位真实 64 位表项 |
| 03_P4D_folded | 该配置为四级硬件页表，P4D 在 Linux 中折叠；与 PGD 共用同一表项，无额外一次内存访问 |
| 04_PUD | VA[38:30]；屏蔽标志后取得下一级 PMD 表的物理基址 |
| 05_PMD | VA[29:21]；4KB 别名的 PS=0，因此继续访问 PTE 表 |
| 06_PTE | VA[20:12]；PTE 指向数据页帧，不再指向页表 |
| 07_physical_address_and_data | 页帧 + VA[11:0]，与内核换算和原直接映射地址的 virt_to_phys 相等，读出原字符串 |
| 08_original_address_comparison | 对老师原分配地址也实际逐级读取；如遇 PS=1 则在目录层停止，并按对应大页大小计算偏移 |
| 09_supplied_fileview | 用提供的工具查看物理页表的 QWORD 值，以及物理数据页的十六进制字节与 ASCII |
| 10_unload | 卸载模块、移除 proc、解除别名、释放原页和 mm 引用 |

## 如何理解和使用内存里的值

页表里的 8 字节并非单纯的物理地址：其中含地址位和标志位。`P=1` 表示存在，`RW` 表示写许可，`US` 表示用户访问许可，`A` 记录访问，叶子项的 `D` 记录写入，`NX` 表示禁止执行。实际权限受沿途各级共同限制。本四级配置的 PGD bit 7 是保留位；PUD/PMD 的 bit 7 是 PS；4KB PTE 的 bit 7 则是 PAT。非叶子项的 bits 6/8 不应作为数据页的 D/G 标志解释。截图中的标志均从真实值解码。

本实验是 x86-64 四级硬件页表，基页 4096 字节，每表 512 项，每项 8 字节。Linux 的软件接口依次为 PGD/P4D/PUD/PMD/PTE，但 P4D 只有一项并被折叠。各真实层索引为 `(VA >> shift) & 0x1ff`，表项地址为 `表物理基址 + 索引*8`。将原始表项与内核的物理地址掩码相与，排除 NX 和低位标志，才能取得下一级表基址或最终页帧。

4KB 页路径最终 `PA = (PTE & PTE_PFN_MASK) + (VA & 0xfff)`。如果在 PUD/PMD 遇到 PS=1，则对应 1GB/2MB 叶子，不继续解释为页表，分别使用 30/21 位偏移，并按相应边界屏蔽页帧基址。物理 RAM 的字节以小端序保存；FILEVIEW 的 QWORD 模式将 8 字节解码成数值，B 模式则逐字节显示字符串。

实验仅对模块自持有的稳定内核映射进行读取，不实现任意进程、可并发释放映射的通用页表遍历器。物理地址是 QEMU 客体物理地址；CR3 是加载时采样的根，而非声称为之后每个用户命令的当前 CR3。终端截图由运行时 Xvfb/xterm/scrot 实拍，日志同时保存。

参考：
- https://docs.kernel.org/mm/page_tables.html
- https://github.com/torvalds/linux/blob/v6.6/arch/x86/include/asm/pgtable_types.h
- https://github.com/torvalds/linux/blob/v6.6/arch/x86/include/asm/pgtable.h
- https://github.com/torvalds/linux/blob/v6.6/include/linux/sched/mm.h

工作流入口：`.github/workflows/p4-cloud.yml`；成功后下载 `P4-screenshots`，源码、配置、编译和串口日志另存于 `P4-evidence`。
