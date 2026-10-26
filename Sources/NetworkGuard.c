#include "NetworkGuard.h"
#include <sandbox.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

int soumao_deny_network(void) {
    char *error = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = sandbox_init("(version 1) (allow default) (deny network*)", 0, &error);
    if (result != 0) {
        fprintf(stderr, "搜猫五笔：无法启用离线网络限制，已停止启动：%s\n", error ? error : "unknown error");
        if (error) sandbox_free_error(error);
        return -1;
    }
    return 0;
#pragma clang diagnostic pop
}

static int test_outbound(int family, int type) {
    int fd = socket(family, type, 0);
    if (fd < 0) return errno == EPERM || errno == EACCES;
    int result;
    if (family == AF_INET) {
        struct sockaddr_in address = {0};
        address.sin_len = sizeof(address); address.sin_family = AF_INET;
        address.sin_port = htons(9); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        result = type == SOCK_STREAM ? connect(fd, (struct sockaddr *)&address, sizeof(address)) :
            (int)sendto(fd, "x", 1, 0, (struct sockaddr *)&address, sizeof(address));
    } else {
        struct sockaddr_in6 address = {0};
        address.sin6_len = sizeof(address); address.sin6_family = AF_INET6;
        address.sin6_port = htons(9); address.sin6_addr = in6addr_loopback;
        result = type == SOCK_STREAM ? connect(fd, (struct sockaddr *)&address, sizeof(address)) :
            (int)sendto(fd, "x", 1, 0, (struct sockaddr *)&address, sizeof(address));
    }
    int saved = errno;
    close(fd);
    return result == -1 && (saved == EPERM || saved == EACCES);
}

int soumao_test_network_denial(void) {
    int ok = test_outbound(AF_INET, SOCK_STREAM) && test_outbound(AF_INET6, SOCK_STREAM) &&
        test_outbound(AF_INET, SOCK_DGRAM) && test_outbound(AF_INET6, SOCK_DGRAM);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) {
        struct sockaddr_in address = {0};
        address.sin_len = sizeof(address); address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        int result = bind(fd, (struct sockaddr *)&address, sizeof(address));
        ok = ok && result == -1 && (errno == EPERM || errno == EACCES);
        close(fd);
    } else { ok = ok && (errno == EPERM || errno == EACCES); }
    printf("%s: IPv4/IPv6 TCP + UDP outbound and inbound bind denied by OS\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
