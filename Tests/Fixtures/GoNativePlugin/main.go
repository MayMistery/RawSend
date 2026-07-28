package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"unsafe"
)

type request struct {
	JSONRPC string `json:"jsonrpc"`
	ID      int    `json:"id"`
	Method  string `json:"method"`
}

type response struct {
	JSONRPC string         `json:"jsonrpc"`
	ID      int            `json:"id"`
	Result  map[string]any `json:"result"`
}

//export rawsend_plugin_api_version_v1
func rawsend_plugin_api_version_v1() C.uint32_t {
	return C.uint32_t(1 << 16)
}

//export rawsend_plugin_handle_v1
func rawsend_plugin_handle_v1(
	input *C.uint8_t,
	inputLength C.size_t,
	output **C.uint8_t,
	outputLength *C.size_t,
) C.int32_t {
	var incoming request
	if err := json.Unmarshal(C.GoBytes(unsafe.Pointer(input), C.int(inputLength)), &incoming); err != nil {
		return 1
	}
	result := map[string]any{"initialized": true}
	if incoming.Method != "initialize" {
		result = map[string]any{
			"variants":       []any{},
			"annotations":    []any{},
			"findings":       []any{},
			"status_message": "go-native-ok",
		}
	}
	encoded, err := json.Marshal(response{
		JSONRPC: "2.0",
		ID:      incoming.ID,
		Result:  result,
	})
	if err != nil {
		return 2
	}
	buffer := C.CBytes(encoded)
	*output = (*C.uint8_t)(buffer)
	*outputLength = C.size_t(len(encoded))
	return 0
}

//export rawsend_plugin_free_v1
func rawsend_plugin_free_v1(pointer *C.uint8_t, _ C.size_t) {
	C.free(unsafe.Pointer(pointer))
}

//export rawsend_plugin_shutdown_v1
func rawsend_plugin_shutdown_v1() {}

func main() {}
