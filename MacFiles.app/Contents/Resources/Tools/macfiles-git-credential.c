#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "get") != 0) return 0;
    char line[8192], protocol[32] = "", host[256] = "";
    while (fgets(line, sizeof(line), stdin) && strcmp(line, "\n") != 0) {
        line[strcspn(line, "\r\n")] = 0;
        if (strncmp(line, "protocol=", 9) == 0) snprintf(protocol, sizeof(protocol), "%s", line + 9);
        if (strncmp(line, "host=", 5) == 0) snprintf(host, sizeof(host), "%s", line + 5);
    }
    if (strcmp(protocol, "https") || strcmp(host, "github.com")) return 0;
    const void *keys[] = {kSecClass, kSecAttrService, kSecAttrAccount, kSecReturnData, kSecMatchLimit};
    const void *values[] = {kSecClassGenericPassword, CFSTR("com.toidi.macfiles.github"), CFSTR("github.com"), kCFBooleanTrue, kSecMatchLimitOne};
    CFDictionaryRef query = CFDictionaryCreate(NULL, keys, values, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, &result); CFRelease(query);
    if (status != errSecSuccess || !result) return 0;
    if (CFGetTypeID(result) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)result; CFIndex length = CFDataGetLength(data);
        if (length > 0 && length < 8192) {
            char *value = calloc((size_t)length + 1, 1);
            if (value) {
                memcpy(value, CFDataGetBytePtr(data), (size_t)length);
                char *token = strchr(value, '\n');
                if (token) { *token++ = 0; if (!strpbrk(value, "\r\n=") && !strpbrk(token, "\r\n")) printf("username=%s\npassword=%s\n\n", value, token); }
                volatile char *wipe = value; for (CFIndex i = 0; i < length; ++i) wipe[i] = 0; free(value);
            }
        }
    }
    CFRelease(result); return 0;
}
