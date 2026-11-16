#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>

static void control(const char *name, const char *value)
{
    char path[256];
    snprintf(path, sizeof(path), "/tracing/%s", name);
    int fd = open(path, O_WRONLY | O_TRUNC);
    if (fd < 0 || write(fd, value, strlen(value)) != (ssize_t)strlen(value)) {
        perror(path); exit(1);
    }
    close(fd);
}

static void start_trace(void)
{
    char filters[8192], pid[32];
    int fd = open("/etc/ftrace-filter", O_RDONLY);
    ssize_t n = read(fd, filters, sizeof(filters) - 1);
    if (fd < 0 || n <= 0) { perror("ftrace filter"); exit(1); }
    close(fd); filters[n] = 0;
    control("tracing_on", "0");
    control("current_tracer", "nop");
    control("set_ftrace_filter", filters);
    snprintf(pid, sizeof(pid), "%d", getpid());
    control("set_ftrace_pid", pid);
    control("trace", "");
    control("current_tracer", "function");
    control("tracing_on", "1");
}

int main(int argc, char **argv)
{
    if (argc != 3) return 2;
    const char *op = argv[1], *path = argv[2];
    int fd = -1, rc = 0, saved;
    ssize_t written = 0;
    const char payload[] = "P3 real buffered write on a Btrfs filesystem.\n";
    if (!strcmp(op, "write")) {
        fd = open(path, O_CREAT | O_RDWR, 0644);
        if (fd < 0) { perror("prepare btrfs file"); return 1; }
    }
    start_trace();
    if (!strcmp(op, "open")) {
        fd = open(path, O_RDONLY);
        rc = fd < 0 ? -1 : 0;
    } else if (!strcmp(op, "write")) {
        written = write(fd, payload, sizeof(payload) - 1);
        rc = written == sizeof(payload) - 1 ? fsync(fd) : -1;
    } else if (!strcmp(op, "mkdir")) {
        rc = mkdir(path, 0755);
    } else { rc = -1; errno = EINVAL; }
    saved = errno;
    control("tracing_on", "0");
    if (rc < 0) { errno = saved; perror(op); return 1; }
    if (!strcmp(op, "open")) printf("REAL libc open(\"%s\", O_RDONLY) = fd %d\n", path, fd);
    if (!strcmp(op, "write")) printf("REAL write(\"%s\") = %zd bytes; fsync = 0\n", path, written);
    if (!strcmp(op, "mkdir")) printf("REAL mkdir(\"%s\", 0755) = 0\n", path);
    if (fd >= 0) close(fd);
    return 0;
}
