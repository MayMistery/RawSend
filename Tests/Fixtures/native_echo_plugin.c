#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint32_t rawsend_plugin_api_version_v1(void) {
    return (1u << 16);
}

int32_t rawsend_plugin_handle_v1(
    const uint8_t *input_json,
    size_t input_length,
    uint8_t **output_json,
    size_t *output_length
) {
    (void)input_json;
    (void)input_length;
    static long id = 0;
    id += 1;
    const char *format =
        "{\"jsonrpc\":\"2.0\",\"id\":%ld,\"result\":{"
        "\"variants\":[],\"annotations\":[],\"findings\":[],"
        "\"status_message\":\"native-ok\"}}";
    int required = snprintf(NULL, 0, format, id);
    if (required < 0) {
        return 3;
    }
    uint8_t *buffer = (uint8_t *)malloc((size_t)required + 1);
    if (buffer == NULL) {
        return 4;
    }
    snprintf((char *)buffer, (size_t)required + 1, format, id);
    *output_json = buffer;
    *output_length = (size_t)required;
    return 0;
}

void rawsend_plugin_free_v1(uint8_t *buffer, size_t length) {
    (void)length;
    free(buffer);
}

void rawsend_plugin_shutdown_v1(void) {}
