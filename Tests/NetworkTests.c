#include "../Sources/NetworkGuard.h"
int main(void) { if (soumao_deny_network() != 0) return 1; return soumao_test_network_denial(); }
