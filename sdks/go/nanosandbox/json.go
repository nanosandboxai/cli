// json.go — a minimal JSON value type, parser, and serializer for the
// nanosandbox protocol. The Go 1.27 standard library has no `json` package,
// so this module owns the wire encoding: requests are serialized compactly
// (no insignificant whitespace) and responses are parsed into a typed value
// tree. It implements RFC 8259: objects, arrays, strings (with escapes),
// numbers, booleans, and null.
//
// allow: SIZE_OK — a self-contained JSON codec; the parser and serializer
// share the value type, escape logic, and UTF-8 helpers, so splitting them
// would create artificial seams.
package nanosandbox

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// JsonValue kinds.
const (
	JsonNull   = 0
	JsonBool   = 1
	JsonNumber = 2
	JsonString = 3
	JsonArray  = 4
	JsonObject = 5
)

// JsonValue is a tagged variant holding one JSON value.
type JsonValue struct {
	Kind int
	B    bool
	N    float64
	S    string
	Arr  []JsonValue
	Obj  []JsonPair
}

// JsonPair is one key/value entry of a JSON object (insertion-ordered).
type JsonPair struct {
	Key string
	Val JsonValue
}

// JsonNullValue returns the JSON null value.
func JsonNullValue() JsonValue {
	return JsonValue{Kind: JsonNull}
}

// JsonBoolValue returns a JSON boolean.
func JsonBoolValue(b bool) JsonValue {
	return JsonValue{Kind: JsonBool, B: b}
}

// JsonNumberValue returns a JSON number.
func JsonNumberValue(n float64) JsonValue {
	return JsonValue{Kind: JsonNumber, N: n}
}

// JsonIntValue returns a JSON number from an integer.
func JsonIntValue(n int64) JsonValue {
	return JsonValue{Kind: JsonNumber, N: float64(n)}
}

// JsonStringValue returns a JSON string.
func JsonStringValue(s string) JsonValue {
	return JsonValue{Kind: JsonString, S: s}
}

// JsonArrayValue returns an empty JSON array.
func JsonArrayValue() JsonValue {
	return JsonValue{Kind: JsonArray}
}

// JsonObjectValue returns an empty JSON object.
func JsonObjectValue() JsonValue {
	return JsonValue{Kind: JsonObject}
}

// Set inserts or replaces the value for key in a JSON object.
func (o *JsonValue) Set(key string, v JsonValue) {
	for i := 0; i < len(o.Obj); i++ {
		if o.Obj[i].Key == key {
			o.Obj[i].Val = v
			return
		}
	}
	o.Obj = append(o.Obj, JsonPair{Key: key, Val: v})
}

// SetT inserts or replaces the value for key and returns the object, enabling
// chained construction: JsonObjectValue().SetT("type", "ping").
func (o JsonValue) SetT(key string, v JsonValue) JsonValue {
	o.Set(key, v)
	return o
}

// Append adds a value to a JSON array.
func (a *JsonValue) Append(v JsonValue) {
	a.Arr = append(a.Arr, v)
}

// Get returns the value for key in a JSON object, or false if absent.
func (v *JsonValue) Get(key string) (JsonValue, bool) {
	for i := 0; i < len(v.Obj); i++ {
		if v.Obj[i].Key == key {
			return v.Obj[i].Val, true
		}
	}
	return JsonNullValue(), false
}

// Has reports whether key is present in a JSON object.
func (v *JsonValue) Has(key string) bool {
	_, ok := v.Get(key)
	return ok
}

// Str returns the string value for key, or false if absent/not a string.
func (v *JsonValue) Str(key string) (string, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonString {
		return "", false
	}
	return val.S, true
}

// Num returns the number value for key, or false if absent/not a number.
func (v *JsonValue) Num(key string) (float64, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonNumber {
		return 0, false
	}
	return val.N, true
}

// Int returns the number value for key as an integer, or false if absent.
func (v *JsonValue) Int(key string) (int64, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonNumber {
		return 0, false
	}
	return int64(val.N), true
}

// Bool returns the boolean value for key, or false if absent/not a bool.
func (v *JsonValue) Bool(key string) (bool, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonBool {
		return false, false
	}
	return val.B, true
}

// GetArr returns the array value for key, or false if absent/not an array.
func (v *JsonValue) GetArr(key string) ([]JsonValue, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonArray {
		return nil, false
	}
	return val.Arr, true
}

// GetObj returns the object pairs for key, or false if absent/not an object.
func (v *JsonValue) GetObj(key string) ([]JsonPair, bool) {
	val, ok := v.Get(key)
	if !ok || val.Kind != JsonObject {
		return nil, false
	}
	return val.Obj, true
}

// AsString returns the string value of a JSON string value.
func (v *JsonValue) AsString() string {
	if v.Kind != JsonString {
		return ""
	}
	return v.S
}

// AsInt returns the integer value of a JSON number value.
func (v *JsonValue) AsInt() int64 {
	if v.Kind != JsonNumber {
		return 0
	}
	return int64(v.N)
}

// AsBool returns the boolean value of a JSON boolean value.
func (v *JsonValue) AsBool() bool {
	if v.Kind != JsonBool {
		return false
	}
	return v.B
}

// AsArray returns the elements of a JSON array value.
func (v *JsonValue) AsArray() []JsonValue {
	if v.Kind != JsonArray {
		return nil
	}
	return v.Arr
}

// AsObj returns the pairs of a JSON object value.
func (v *JsonValue) AsObj() []JsonPair {
	if v.Kind != JsonObject {
		return nil
	}
	return v.Obj
}

// IsNull reports whether the value is JSON null.
func (v *JsonValue) IsNull() bool {
	return v.Kind == JsonNull
}

// jsonParser is the recursive-descent parser state.
type jsonParser struct {
	s string
	i int
}

// JsonParse parses a complete JSON document.
func JsonParse(s string) (JsonValue, error) {
	p := &jsonParser{s: s, i: 0}
	p.skipWs()
	v, err := p.parseValue()
	if err != nil {
		return JsonNullValue(), err
	}
	p.skipWs()
	if p.i < len(p.s) {
		return JsonNullValue(), errors.New("trailing characters in JSON document")
	}
	return v, nil
}

// JsonParseOr parses a JSON document, returning a null value on error.
func JsonParseOr(s string) JsonValue {
	v, _ := JsonParse(s)
	return v
}

func (p *jsonParser) skipWs() {
	for p.i < len(p.s) {
		c := p.s[p.i]
		if c != byte(' ') && c != byte('\t') && c != byte('\n') && c != byte('\r') {
			break
		}
		p.i++
	}
}

func (p *jsonParser) parseValue() (JsonValue, error) {
	if p.i >= len(p.s) {
		return JsonNullValue(), errors.New("unexpected end of JSON input")
	}
	c := p.s[p.i]
	switch c {
	case byte('{'):
		return p.parseObject()
	case byte('['):
		return p.parseArray()
	case byte('"'):
		s, err := p.parseString()
		if err != nil {
			return JsonNullValue(), err
		}
		return JsonStringValue(s), nil
	case byte('t'):
		return p.parseLiteral("true", JsonBoolValue(true))
	case byte('f'):
		return p.parseLiteral("false", JsonBoolValue(false))
	case byte('n'):
		return p.parseLiteral("null", JsonNullValue())
	default:
		if c == byte('-') || (c >= byte('0') && c <= byte('9')) {
			return p.parseNumber()
		}
		return JsonNullValue(), errors.New("unexpected character in JSON input")
	}
}

func (p *jsonParser) parseLiteral(lit string, v JsonValue) (JsonValue, error) {
	if p.i + len(lit) > len(p.s) || p.s[p.i:p.i+len(lit)] != lit {
		return JsonNullValue(), errors.New("invalid JSON literal")
	}
	p.i += len(lit)
	return v, nil
}

func (p *jsonParser) parseObject() (JsonValue, error) {
	p.i++ // consume '{'
	out := JsonObjectValue()
	p.skipWs()
	if p.i < len(p.s) && p.s[p.i] == byte('}') {
		p.i++
		return out, nil
	}
	for {
		p.skipWs()
		if p.i >= len(p.s) || p.s[p.i] != byte('"') {
			return JsonNullValue(), errors.New("expected string key in JSON object")
		}
		key, err := p.parseString()
		if err != nil {
			return JsonNullValue(), err
		}
		p.skipWs()
		if p.i >= len(p.s) || p.s[p.i] != byte(':') {
			return JsonNullValue(), errors.New("expected ':' in JSON object")
		}
		p.i++
		p.skipWs()
		val, verr := p.parseValue()
		if verr != nil {
			return JsonNullValue(), verr
		}
		out.Set(key, val)
		p.skipWs()
		if p.i >= len(p.s) {
			return JsonNullValue(), errors.New("unterminated JSON object")
		}
		c := p.s[p.i]
		p.i++
		if c == byte('}') {
			return out, nil
		}
		if c != byte(',') {
			return JsonNullValue(), errors.New("expected ',' or '}' in JSON object")
		}
	}
}

func (p *jsonParser) parseArray() (JsonValue, error) {
	p.i++ // consume '['
	out := JsonArrayValue()
	p.skipWs()
	if p.i < len(p.s) && p.s[p.i] == byte(']') {
		p.i++
		return out, nil
	}
	for {
		p.skipWs()
		val, err := p.parseValue()
		if err != nil {
			return JsonNullValue(), err
		}
		out.Append(val)
		p.skipWs()
		if p.i >= len(p.s) {
			return JsonNullValue(), errors.New("unterminated JSON array")
		}
		c := p.s[p.i]
		p.i++
		if c == byte(']') {
			return out, nil
		}
		if c != byte(',') {
			return JsonNullValue(), errors.New("expected ',' or ']' in JSON array")
		}
	}
}

func (p *jsonParser) parseString() (string, error) {
	p.i++ // consume opening quote
	bb := &strings.Builder{}
	for p.i < len(p.s) {
		c := p.s[p.i]
		if c == byte('"') {
			p.i++
			return bb.String(), nil
		}
		if c == byte('\\') {
			p.i++
			if p.i >= len(p.s) {
				return "", errors.New("unterminated escape in JSON string")
			}
			e := p.s[p.i]
			p.i++
			switch e {
			case byte('"'):
				bb.WriteString("\"")
			case byte('\\'):
				bb.WriteString("\\")
			case byte('/'):
				bb.WriteString("/")
			case byte('b'):
				bb.WriteString("\b")
			case byte('f'):
				bb.WriteString("\f")
			case byte('n'):
				bb.WriteString("\n")
			case byte('r'):
				bb.WriteString("\r")
			case byte('t'):
				bb.WriteString("\t")
			case byte('u'):
				cp, err := p.parseHex4()
				if err != nil {
					return "", err
				}
				// Handle surrogate pairs.
				if cp >= 0xD800 && cp <= 0xDBFF && p.i + 1 < len(p.s) && p.s[p.i] == byte('\\') && p.s[p.i+1] == byte('u') {
					save := p.i
					p.i += 2
					lo, lerr := p.parseHex4()
					if lerr == nil && lo >= 0xDC00 && lo <= 0xDFFF {
						cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
					} else {
						p.i = save
					}
				}
				bb.WriteString(string(rune(cp)))
			default:
				return "", errors.New("invalid escape in JSON string")
			}
			continue
		}
		// Copy one UTF-8 rune verbatim.
		r, n := utf8RuneAt(p.s, p.i)
		bb.WriteString(string(r))
		p.i += n
	}
	return "", errors.New("unterminated JSON string")
}

func (p *jsonParser) parseHex4() (int, error) {
	if p.i + 4 > len(p.s) {
		return 0, errors.New("truncated \\u escape in JSON string")
	}
	cp := 0
	for k := 0; k < 4; k++ {
		c := p.s[p.i+k]
		var d int
		if c >= byte('0') && c <= byte('9') {
			d = int(c - byte('0'))
		} else if c >= byte('a') && c <= byte('f') {
			d = int(c - byte('a')) + 10
		} else if c >= byte('A') && c <= byte('F') {
			d = int(c - byte('A')) + 10
		} else {
			return 0, errors.New("invalid hex digit in \\u escape")
		}
		cp = cp * 16 + d
	}
	p.i += 4
	return cp, nil
}

func (p *jsonParser) parseNumber() (JsonValue, error) {
	start := p.i
	if p.i < len(p.s) && p.s[p.i] == byte('-') {
		p.i++
	}
	// Integer part.
	if p.i < len(p.s) && p.s[p.i] == byte('0') {
		p.i++
	} else {
		digits := 0
		for p.i < len(p.s) && p.s[p.i] >= byte('0') && p.s[p.i] <= byte('9') {
			p.i++
			digits++
		}
		if digits == 0 {
			return JsonNullValue(), errors.New("invalid number in JSON input")
		}
	}
	// Fraction.
	if p.i < len(p.s) && p.s[p.i] == byte('.') {
		p.i++
		digits := 0
		for p.i < len(p.s) && p.s[p.i] >= byte('0') && p.s[p.i] <= byte('9') {
			p.i++
			digits++
		}
		if digits == 0 {
			return JsonNullValue(), errors.New("invalid fraction in JSON number")
		}
	}
	// Exponent.
	if p.i < len(p.s) && (p.s[p.i] == byte('e') || p.s[p.i] == byte('E')) {
		p.i++
		if p.i < len(p.s) && (p.s[p.i] == byte('+') || p.s[p.i] == byte('-')) {
			p.i++
		}
		digits := 0
		for p.i < len(p.s) && p.s[p.i] >= byte('0') && p.s[p.i] <= byte('9') {
			p.i++
			digits++
		}
		if digits == 0 {
			return JsonNullValue(), errors.New("invalid exponent in JSON number")
		}
	}
	text := p.s[start:p.i]
	n, err := strconv.ParseFloat(text, 64)
	if err != nil {
		return JsonNullValue(), errors.New("number out of range in JSON input")
	}
	return JsonNumberValue(n), nil
}

// utf8RuneAt decodes the UTF-8 rune starting at byte offset i of s,
// returning the rune and its byte length.
func utf8RuneAt(s string, i int) (rune, int) {
	b0 := byte(s[i])
	if b0 < 0x80 {
		return rune(b0), 1
	}
	if b0 >= 0xC0 && b0 < 0xE0 && i + 1 < len(s) {
		cp := (int(b0 & 0x1F) << 6) | int(byte(s[i+1]) & 0x3F)
		return rune(cp), 2
	}
	if b0 >= 0xE0 && b0 < 0xF0 && i + 2 < len(s) {
		cp := (int(b0 & 0x0F) << 12) | (int(byte(s[i+1]) & 0x3F) << 6) | int(byte(s[i+2]) & 0x3F)
		return rune(cp), 3
	}
	if b0 >= 0xF0 && b0 < 0xF8 && i + 3 < len(s) {
		cp := (int(b0 & 0x07) << 18) | (int(byte(s[i+1]) & 0x3F) << 12) | (int(byte(s[i+2]) & 0x3F) << 6) | int(byte(s[i+3]) & 0x3F)
		return rune(cp), 4
	}
	// Invalid byte: pass through as a replacement rune.
	return rune(0xFFFD), 1
}

// JsonStringify serializes a JSON value compactly.
func JsonStringify(v JsonValue) string {
	bb := &strings.Builder{}
	writeValue(bb, v)
	return bb.String()
}

func writeValue(bb *strings.Builder, v JsonValue) {
	switch v.Kind {
	case JsonNull:
		bb.WriteString("null")
	case JsonBool:
		if v.B {
			bb.WriteString("true")
		} else {
			bb.WriteString("false")
		}
	case JsonNumber:
		bb.WriteString(formatNumber(v.N))
	case JsonString:
		writeString(bb, v.S)
	case JsonArray:
		bb.WriteString("[")
		for i := 0; i < len(v.Arr); i++ {
			if i > 0 {
				bb.WriteString(",")
			}
			writeValue(bb, v.Arr[i])
		}
		bb.WriteString("]")
	case JsonObject:
		bb.WriteString("{")
		for i := 0; i < len(v.Obj); i++ {
			if i > 0 {
				bb.WriteString(",")
			}
			writeString(bb, v.Obj[i].Key)
			bb.WriteString(":")
			writeValue(bb, v.Obj[i].Val)
		}
		bb.WriteString("}")
	}
}

func writeString(bb *strings.Builder, s string) {
	bb.WriteString("\"")
	for i := 0; i < len(s); {
		c := byte(s[i])
		switch c {
		case byte('"'):
			bb.WriteString("\\\"")
			i++
		case byte('\\'):
			bb.WriteString("\\\\")
			i++
		case byte('\n'):
			bb.WriteString("\\n")
			i++
		case byte('\r'):
			bb.WriteString("\\r")
			i++
		case byte('\t'):
			bb.WriteString("\\t")
			i++
		case byte('\b'):
			bb.WriteString("\\b")
			i++
		case byte('\f'):
			bb.WriteString("\\f")
			i++
		default:
			if c < 0x20 {
				bb.WriteString(fmt.Sprintf("\\u%04x", int(c)))
				i++
			} else {
				r, n := utf8RuneAt(s, i)
				bb.WriteString(string(r))
				i += n
			}
		}
	}
	bb.WriteString("\"")
}

// formatNumber renders a float64 as a JSON number: integers without a
// decimal point, everything else with minimal precision.
func formatNumber(n float64) string {
	if n == float64(int64(n)) && n >= -9.007199254740992e15 && n <= 9.007199254740992e15 {
		return fmt.Sprintf("%d", int64(n))
	}
	return fmt.Sprintf("%g", n)
}