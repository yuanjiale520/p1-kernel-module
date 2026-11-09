# Practice 2 云端实验

本目录在 GitHub Actions Ubuntu 虚拟机上执行 P2，生成实际运行截图。

- 从 Linux 6.6.30 官方源码编译精简 x86_64 内核，版本后缀为 `-p2`。
- 使用 Ubuntu 的 `busybox-static` 制作 gzip 压缩的 newc cpio 格式 `initramfs.img`。
- 使用 QEMU TCG 启动新内核，实际读取客户机版本，确认与宿主机不同。
- 选做项为编写并加载一个匹配客户机内核的模块 `p2_hello.ko`，验证加载与卸载。
- 在宿主云端 Linux 上启动 TigerVNC 的 X 服务和 XFCE 桌面，运行 neofetch 并展示会话配置。
- 使用 scrot 从真正的 TigerVNC 显示器截图。QEMU 相关截图在客户机实际运行时捕获。

工作流为 `.github/workflows/p2-cloud.yml`。提交 `p2/` 或工作流变动会触发，亦可手动运行。所有编译、启动和图形会话均在云端执行。

预期五张 PNG：构建文件信息、QEMU 内核版本、选做模块、XFCE neofetch、X 会话配置。工作流只有实际验证成功才报告成功；执行后的日志与元数据保留真实结果。

参考：

- https://docs.kernel.org/admin-guide/initrd.html
- https://docs.kernel.org/kbuild/modules.html
- https://www.qemu.org/docs/master/system/invocation.html
- https://tigervnc.org/doc/Xvnc.html
