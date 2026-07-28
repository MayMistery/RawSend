package rawsendplugin

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const maxMessageBytes = 16 * 1024 * 1024

type Message struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      int             `json:"id"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type Handler func(method string, params json.RawMessage, host *Host) (any, error)
type SimpleHandler func(method string, params json.RawMessage) (any, error)

type Host struct {
	reader *bufio.Reader
	writer *bufio.Writer
	nextID int
}

func (host *Host) Call(method string, params any, result any) error {
	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return err
	}
	id := host.nextID
	host.nextID++
	request := Message{
		JSONRPC: "2.0",
		ID:      id,
		Method:  method,
		Params:  paramsJSON,
	}
	if err := writeMessage(host.writer, request); err != nil {
		return err
	}
	response, err := readMessage(host.reader)
	if err != nil {
		return err
	}
	if response.ID != id || response.Method != "" {
		return fmt.Errorf("unexpected Host API response")
	}
	if response.Error != nil {
		return fmt.Errorf("Host API %s failed: %s", method, response.Error.Message)
	}
	if result == nil {
		return nil
	}
	encoded, err := json.Marshal(response.Result)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, result)
}

func Serve(handler Handler) error {
	reader := bufio.NewReader(os.Stdin)
	writer := bufio.NewWriter(os.Stdout)
	host := &Host{reader: reader, writer: writer, nextID: 1_000_000}
	for {
		message, err := readMessage(reader)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		result, callErr := handler(message.Method, message.Params, host)
		response := Message{JSONRPC: "2.0", ID: message.ID, Result: result}
		if callErr != nil {
			response.Result = nil
			response.Error = &RPCError{Code: -32000, Message: callErr.Error()}
		}
		if err := writeMessage(writer, response); err != nil {
			return err
		}
	}
}

func ServeSimple(handler SimpleHandler) error {
	return Serve(func(method string, params json.RawMessage, _ *Host) (any, error) {
		return handler(method, params)
	})
}

func readMessage(reader *bufio.Reader) (Message, error) {
	length := -1
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			return Message{}, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			return Message{}, fmt.Errorf("malformed RPC header")
		}
		if strings.EqualFold(strings.TrimSpace(parts[0]), "Content-Length") {
			length, err = strconv.Atoi(strings.TrimSpace(parts[1]))
			if err != nil {
				return Message{}, err
			}
		}
	}
	if length < 0 || length > maxMessageBytes {
		return Message{}, fmt.Errorf("invalid Content-Length")
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(reader, body); err != nil {
		return Message{}, err
	}
	var message Message
	if err := json.Unmarshal(body, &message); err != nil {
		return Message{}, err
	}
	return message, nil
}

func writeMessage(writer *bufio.Writer, message Message) error {
	body, err := json.Marshal(message)
	if err != nil {
		return err
	}
	if len(body) > maxMessageBytes {
		return fmt.Errorf("RPC message too large")
	}
	if _, err := fmt.Fprintf(writer, "Content-Length: %d\r\n\r\n", len(body)); err != nil {
		return err
	}
	if _, err := writer.Write(body); err != nil {
		return err
	}
	return writer.Flush()
}
