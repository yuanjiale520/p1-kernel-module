# P5：自定义 slab 缓存与跨模块分配

## 作业要做什么

用内核模块创建一个自定义 slab cache，从中分配对象，在 `/proc/slabinfo` 中找到对应条目；进一步验证能否由另一个模块分配。这些步骤展示了“按固定对象大小复用内存”的机制。

## 实现

- `p5_cache_owner.ko` 用 `kmem_cache_create` 创建 `p5_lab_cache`，对象结构大小为 128 字节，通过 `kmem_cache_alloc` 分配并持有 4 个对象，然后使用 `EXPORT_SYMBOL_GPL(p5_cache)` 导出缓存指针。
- `p5_cache_client.ko` 引用导出符号，从同一个缓存分配 96 个对象。为每个对象写入编号、归属、文本和 64 字节测试数据，验证内容与地址唯一性；并真实执行一次释放后重分配，重新初始化和验证内容。
- 两个模块分别输出只读 `/proc/p5_owner` 和 `/proc/p5_client` 诊断信息，可直接核对缓存指针是否相同。共享数据结构由头文件统一定义。
- 由于客户端引用了创建模块的导出符号，模块加载器记录依赖。客户端未卸载时，普通 `rmmod p5_cache_owner` 应失败，避免缓存提前销毁。
- 客户端卸载时释放其全部对象；创建模块最后释放自己的对象，再调用 `kmem_cache_destroy`。初始化失败也清理已分配的资源。

构造函数非空，并使用 `slab_nomerge` 启动参数，避免缓存合并使自定义名称变成其他缓存的别名。每次分配仍显式初始化对象：构造函数不保证在每次复用对象时重新执行。释放后再分配是否得到相同地址是观察结果，不是 API 保证。

## 实验环境与验证

在 GitHub Actions 中编译 Linux 6.6.30 与匹配模块，再启动隔离 QEMU 客体（x86-64、单 CPU、512MB）。启用 `CONFIG_SLUB`、`CONFIG_SLUB_DEBUG`、`CONFIG_PROC_FS`、`CONFIG_SYSFS` 和模块卸载支持。实验不会在用户本机编译或加载内核模块。

| 截图 | 内容与作业对应 |
| --- | --- |
| 01 | 任务说明、真实内核版本与配置，加载前缓存不存在 |
| 02 | 创建自定义缓存、分配 4 个对象并找到 slabinfo 条目 |
| 03 | 第二个模块分配 96 个对象；内容、地址唯一性及同一缓存指针验证 |
| 04 | 查找 `/proc/slabinfo`，解析对象统计、槽位大小与 slab 几何信息 |
| 05 | 展示模块依赖，确认缓存创建模块不能过早卸载 |
| 06 | 释放客户端的 96 个对象，缓存仍存在且创建模块的 4 个对象有效 |
| 07 | 释放剩余对象并销毁缓存，确认 slabinfo 与 sysfs 中都已消失 |
| 08 | 改用 16 个客户端对象，重复完整生命周期并再次清理 |

所有截图均为 GitHub 云端运行时的 Xvfb/xterm/scrot 实拍。源码、内核配置、编译日志和 QEMU 串口日志同时归档。

## 如何理解结果

**可以跨模块分配。** 创建模块导出缓存指针，客户端使用同一指针调用分配接口；需统一对象布局，并保持缓存生命周期覆盖所有对象和使用者。每个对象都必须释放到原来的缓存。

`/proc/slabinfo` 的重要字段包括名称、`active_objs`、`num_objs`、`objsize`、`objperslab`、`pagesperslab`，以及 `slabdata` 中的 slab 数。这里的 `objsize` 是分配器槽位大小，可能因元数据和对齐大于结构体的 128 字节。sysfs 的 `object_size` 与 `slab_size` 可以辅助区分请求大小和槽位大小。

SLUB 的活动对象统计可能包含 CPU 缓存预留，不能强行要求它与模块持有的 100 个对象完全相等。因此脚本核对缓存身份和容量是否合理，并用模块自己的持有计数与内容验证确定对象使用情况。释放对象后缓存可能保留空闲内存供复用；只有销毁缓存后才要求其条目消失。

参考：[Linux 内存管理 API](https://docs.kernel.org/core-api/mm-api.html)、[Linux v6.6 slab.h](https://github.com/torvalds/linux/blob/v6.6/include/linux/slab.h)、[SLUB slabinfo 实现](https://github.com/torvalds/linux/blob/v6.6/mm/slub.c)、[缓存创建与销毁实现](https://github.com/torvalds/linux/blob/v6.6/mm/slab_common.c)。
