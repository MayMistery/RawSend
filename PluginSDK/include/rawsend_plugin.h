#ifndef RAWSEND_PLUGIN_H
#define RAWSEND_PLUGIN_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define RAWSEND_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define RAWSEND_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// High 16 bits are ABI major; low 16 bits are ABI minor.
RAWSEND_PLUGIN_EXPORT uint32_t rawsend_plugin_api_version_v1(void);

// input_json is one JSON-RPC 2.0 request. The plugin allocates output_json and
// returns a JSON-RPC 2.0 response. Return 0 on success.
RAWSEND_PLUGIN_EXPORT int32_t rawsend_plugin_handle_v1(
    const uint8_t *input_json,
    size_t input_length,
    uint8_t **output_json,
    size_t *output_length
);

RAWSEND_PLUGIN_EXPORT void rawsend_plugin_free_v1(
    uint8_t *buffer,
    size_t length
);

// Optional. RawSend does not dlclose native plugins during the process lifetime.
RAWSEND_PLUGIN_EXPORT void rawsend_plugin_shutdown_v1(void);

#ifdef __cplusplus
}
#endif

#endif
