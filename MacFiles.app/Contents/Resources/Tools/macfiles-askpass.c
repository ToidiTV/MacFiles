#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>

int main(int argc, char **argv) {
    const char *path = getenv("MACFILES_ASKPASS_FILE");
    if (!path || argc < 2 || (!strcasestr(argv[1], "password") && !strcasestr(argv[1], "passphrase"))) return 1;
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return 1;
    struct stat info;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || (info.st_mode & 0777) != 0600 || info.st_size > 65536) { close(fd); return 1; }
    char buffer[4096]; ssize_t count;
    while ((count = read(fd, buffer, sizeof buffer)) > 0) {
        ssize_t offset = 0;
        while (offset < count) { ssize_t sent = write(STDOUT_FILENO, buffer + offset, count - offset); if (sent <= 0) { close(fd); return 1; }; offset += sent; }
    }
    memset(buffer, 0, sizeof buffer); close(fd); return count < 0;
}
