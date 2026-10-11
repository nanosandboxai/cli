// conn.go — connection, handshake, and NDJSON framing for the nanosandbox
// helper. The helper speaks NDJSON over a Unix stream socket. Every connection
// begins with a `hello` handshake; each request yields one response frame, and
// streaming verbs then emit additional `guest`/`event` frames terminated by an
// exit/done frame. This module owns the wire: dialing, line framing, and the
// typed error surface. It is stdlib-only (`net`).
package nanosandbox

import (
	"encoding/base64"
	"net"
	"time"
)

// PROTOCOL_VERSION is the protocol version this SDK speaks.
const PROTOCOL_VERSION = "1.0.0"

// CLIENT_NAME identifies this SDK in the hello handshake.
const CLIENT_NAME = "nanosandbox-go"

// NanosbError is a structured error returned by the helper.
type NanosbError struct {
	Code    string
	Message string
}

// Error formats the error as "code: message".
func (e *NanosbError) Error() string {
	return e.Code + ": " + e.Message
}

// IsNotFound reports whether the error code is "not_found".
func (e *NanosbError) IsNotFound() bool {
	return e.Code == "not_found"
}

// LineReader assembles newline-delimited lines from a stream socket.
type LineReader struct {
	Sock net.Conn
	Buf  []byte
	Eof  bool
}

// NewLineReader returns a line reader over a stream connection.
func NewLineReader(sock net.Conn) *LineReader {
	return &LineReader{Sock: sock}
}

// ReadLine returns the next line (without the trailing newline), or the empty
// string at EOF. A transport error is returned as an error.
func (r *LineReader) ReadLine() (string, error) {
	for {
		idx := indexByte(r.Buf, byte('\n'))
		if idx >= 0 {
			line := string(r.Buf[0:idx])
			r.Buf = r.Buf[idx+1:]
			return line, nil
		}
		if r.Eof {
			if len(r.Buf) == 0 {
				return "", nil
			}
			line := string(r.Buf)
			r.Buf = []byte{}
			return line, nil
		}
		var chunk [4096]byte
		n, err := r.Sock.Read(chunk[0:])
		if err != nil {
			return "", err
		}
		if n == 0 {
			r.Eof = true
		} else {
			for i := 0; i < n; i++ {
				r.Buf = append(r.Buf, chunk[i])
			}
		}
	}
}

func indexByte(b []byte, c byte) int {
	for i := 0; i < len(b); i++ {
		if b[i] == c {
			return i
		}
	}
	return -1
}

// Conn is one negotiated connection: dial -> hello -> request -> response.
type Conn struct {
	Path       string
	ClientName string
	Sock       net.Conn
	Reader     *LineReader
	Hello      JsonValue
	Closed     bool
}

// NewConn returns a connection handle for the given socket path.
func NewConn(path string) *Conn {
	return &Conn{Path: path, ClientName: CLIENT_NAME}
}

// Open dials the socket and performs the hello handshake.
func (c *Conn) Open() error {
	sock, err := net.Dial("unix", c.Path)
	if err != nil {
		return err
	}
	c.Sock = sock
	c.Reader = NewLineReader(sock)
	hello, herr := c.Handshake()
	if herr != nil {
		c.Sock.Close()
		return herr
	}
	c.Hello = hello
	return nil
}

// Handshake sends the hello frame and validates the hello_ok response.
func (c *Conn) Handshake() (JsonValue, error) {
	hello := JsonObjectValue()
	hello.Set("type", JsonStringValue("hello"))
	hello.Set("client", JsonStringValue(c.ClientName))
	hello.Set("sdk_version", JsonStringValue(PROTOCOL_VERSION))
	hello.Set("protocol_min", JsonStringValue(PROTOCOL_VERSION))
	hello.Set("protocol_max", JsonStringValue(PROTOCOL_VERSION))
	err := c.Send(hello)
	if err != nil {
		return JsonNullValue(), err
	}
	resp, err := c.Recv()
	if err != nil {
		return JsonNullValue(), err
	}
	rtype, _ := resp.Str("type")
	if rtype != "hello_ok" {
		code, _ := resp.Str("code")
		msg, _ := resp.Str("message")
		if code == "" {
			code = "internal"
		}
		if msg == "" {
			msg = "bad handshake"
		}
		return JsonNullValue(), &NanosbError{Code: code, Message: msg}
	}
	proto, _ := resp.Str("protocol")
	if proto != PROTOCOL_VERSION {
		return JsonNullValue(), &NanosbError{
			Code:    "incompatible_version",
			Message: "helper speaks " + proto + ", client needs " + PROTOCOL_VERSION,
		}
	}
	return resp, nil
}

// Send writes one JSON frame followed by a newline.
func (c *Conn) Send(msg JsonValue) error {
	line := JsonStringify(msg) + "\n"
	b := []byte(line)
	off := 0
	for off < len(b) {
		n, err := c.Sock.Write(b[off:])
		if err != nil {
			return err
		}
		off += n
	}
	return nil
}

// Recv reads and parses the next response frame.
func (c *Conn) Recv() (JsonValue, error) {
	line, err := c.Reader.ReadLine()
	if err != nil {
		return JsonNullValue(), err
	}
	if line == "" {
		return JsonNullValue(), &NanosbError{Code: "transport", Message: "connection closed"}
	}
	v, perr := JsonParse(line)
	if perr != nil {
		return JsonNullValue(), perr
	}
	return v, nil
}

// Call sends a request and returns the response, raising a NanosbError for an
// error frame.
func (c *Conn) Call(msg JsonValue) (JsonValue, error) {
	err := c.Send(msg)
	if err != nil {
		return JsonNullValue(), err
	}
	resp, err := c.Recv()
	if err != nil {
		return JsonNullValue(), err
	}
	rtype, _ := resp.Str("type")
	if rtype == "error" {
		code, _ := resp.Str("code")
		msg2, _ := resp.Str("message")
		if code == "" {
			code = "internal"
		}
		return JsonNullValue(), &NanosbError{Code: code, Message: msg2}
	}
	return resp, nil
}

// Close closes the underlying socket (idempotent).
func (c *Conn) Close() {
	if c.Closed {
		return
	}
	c.Closed = true
	if c.Sock != nil {
		c.Sock.Close()
	}
}

// SetReadDeadline sets a read deadline on the connection's socket so a wedged
// peer cannot hang the caller indefinitely.
func (c *Conn) SetReadDeadline(t time.Time) error {
	return c.Sock.SetReadDeadline(t)
}

// B64 encodes bytes as standard base64 for the wire.
func B64(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// Unb64 decodes standard base64 from the wire.
func Unb64(text string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(text)
}

// IsTerminalFrame reports whether a response frame ends a stream: a guest
// exit/error event or an event done frame.
func IsTerminalFrame(v JsonValue) bool {
	rtype, _ := v.Str("type")
	if rtype == "guest" {
		ev, _ := v.Str("event")
		return ev == "exit" || ev == "error"
	}
	if rtype == "event" {
		ev, _ := v.Str("event")
		return ev == "done"
	}
	return false
}