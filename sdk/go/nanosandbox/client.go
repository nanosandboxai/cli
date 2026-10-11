// client.go — the stateless protocol client. Each call dials and re-negotiates
// a fresh connection (mirroring the Python SDK), so the client holds only the
// socket path and the capabilities advertised by the helper's handshake.
package nanosandbox

// SandboxClient is a protocol client bound to one helper socket.
type SandboxClient struct {
	Socket string
	Caps   []string
}

// Connect dials the helper socket, performs the hello handshake, and returns
// a client.
func Connect(socketPath string) (*SandboxClient, error) {
	conn := NewConn(socketPath)
	err := conn.Open()
	if err != nil {
		return nil, err
	}
	caps := []string{}
	capsVal, ok := conn.Hello.GetArr("capabilities")
	if ok {
		for _, c := range capsVal {
			caps = append(caps, c.AsString())
		}
	}
	conn.Close()
	return &SandboxClient{Socket: socketPath, Caps: caps}, nil
}

// Capabilities returns the capabilities advertised by the helper.
func (c *SandboxClient) Capabilities() []string {
	return c.Caps
}

// Supports reports whether the helper advertises the given capability.
func (c *SandboxClient) Supports(cap string) bool {
	for _, x := range c.Caps {
		if x == cap {
			return true
		}
	}
	return false
}

// Call sends a request on a fresh connection and returns the response.
func (c *SandboxClient) Call(msg JsonValue) (JsonValue, error) {
	conn := NewConn(c.Socket)
	err := conn.Open()
	if err != nil {
		return JsonNullValue(), err
	}
	resp, rerr := conn.Call(msg)
	conn.Close()
	return resp, rerr
}

// Ping returns the helper's protocol version.
func (c *SandboxClient) Ping() (string, error) {
	resp, err := c.Call(JsonObjectValue().SetT("type", JsonStringValue("ping")))
	if err != nil {
		return "", err
	}
	v, _ := resp.Str("version")
	return v, nil
}

// List returns the sandbox handles, optionally including stopped ones.
func (c *SandboxClient) List(all bool) ([]JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("list"))
	req.Set("all", JsonBoolValue(all))
	resp, err := c.Call(req)
	if err != nil {
		return nil, err
	}
	arr, _ := resp.GetArr("sandboxes")
	return arr, nil
}

// ListWithLabel lists sandboxes filtered by a label.
func (c *SandboxClient) ListWithLabel(label string, all bool) ([]JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("list"))
	req.Set("all", JsonBoolValue(all))
	req.Set("label", JsonStringValue(label))
	resp, err := c.Call(req)
	if err != nil {
		return nil, err
	}
	arr, _ := resp.GetArr("sandboxes")
	return arr, nil
}

// ListPage returns one paginated page of sandbox handles.
func (c *SandboxClient) ListPage(limit int, cursor, label string) (JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("list"))
	req.Set("all", JsonBoolValue(true))
	if limit > 0 {
		req.Set("limit", JsonIntValue(int64(limit)))
	}
	if cursor != "" {
		req.Set("cursor", JsonStringValue(cursor))
	}
	if label != "" {
		req.Set("label", JsonStringValue(label))
	}
	return c.Call(req)
}

// Snapshots lists all snapshots.
func (c *SandboxClient) Snapshots() ([]JsonValue, error) {
	resp, err := c.Call(JsonObjectValue().SetT("type", JsonStringValue("snapshot_list")))
	if err != nil {
		return nil, err
	}
	arr, _ := resp.GetArr("snapshots")
	return arr, nil
}

// Get fetches a sandbox's info by name.
func (c *SandboxClient) Get(name string) (JsonValue, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("get"))
	req.Set("name", JsonStringValue(name))
	return c.Call(req)
}

// Create creates a sandbox from a spec and returns a handle.
func (c *SandboxClient) Create(spec JsonValue) (*Sandbox, error) {
	req := JsonObjectValue()
	req.Set("type", JsonStringValue("create"))
	req.Set("spec", spec)
	_, err := c.Call(req)
	if err != nil {
		return nil, err
	}
	name, _ := spec.Str("name")
	return &Sandbox{Client: c, Name: name}, nil
}

// CreateWith creates a sandbox from a builder.
func (c *SandboxClient) CreateWith(builder *SandboxBuilder) (*Sandbox, error) {
	spec := builder.Build()
	name, ok := spec.Str("name")
	if !ok || name == "" {
		return nil, &NanosbError{Code: "internal", Message: "spec.name is required to create"}
	}
	return c.Create(spec)
}

// Sandbox returns a handle bound to the named sandbox.
func (c *SandboxClient) Sandbox(name string) *Sandbox {
	return &Sandbox{Client: c, Name: name}
}