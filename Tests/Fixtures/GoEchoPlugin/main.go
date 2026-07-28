package main

import (
	"encoding/json"
	"fmt"
	"os"

	"rawsend-plugin-sdk/rawsendplugin"
)

func handle(method string, params json.RawMessage, host *rawsendplugin.Host) (any, error) {
	switch method {
	case "initialize":
		var info map[string]any
		if err := host.Call("host.info", map[string]any{}, &info); err != nil {
			return nil, err
		}
		if info["name"] != "RawSend" {
			return nil, fmt.Errorf("unexpected host")
		}
		var statusWritten bool
		if err := host.Call(
			"ui.status.set",
			map[string]any{"message": "go-process-ok"},
			&statusWritten,
		); err != nil {
			return nil, err
		}
		return map[string]any{"initialized": statusWritten}, nil
	case "exchange.completed":
		return map[string]any{
			"variants":       []any{},
			"annotations":    []any{},
			"findings":       []any{},
			"status_message": "go-process-ok",
		}, nil
	default:
		return nil, fmt.Errorf("unsupported method: %s", method)
	}
}

func main() {
	if err := rawsendplugin.Serve(handle); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
