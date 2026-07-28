package rawsendplugin

import (
	"bufio"
	"bytes"
	"encoding/json"
	"testing"
)

func TestFramingRoundTrip(t *testing.T) {
	var output bytes.Buffer
	writer := bufio.NewWriter(&output)
	expected := Message{
		JSONRPC: "2.0",
		ID:      7,
		Method:  "host.info",
		Params:  json.RawMessage(`{"value":"测试"}`),
	}
	if err := writeMessage(writer, expected); err != nil {
		t.Fatal(err)
	}
	actual, err := readMessage(bufio.NewReader(&output))
	if err != nil {
		t.Fatal(err)
	}
	if actual.ID != expected.ID || actual.Method != expected.Method {
		t.Fatalf("unexpected message: %#v", actual)
	}
}
