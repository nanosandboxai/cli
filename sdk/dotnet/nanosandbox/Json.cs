// Json.cs — a minimal JSON value model for the nanosandbox protocol.
//
// .NET 8's `System.Text.Json` exposes only the read-only `JsonDocument` /
// `JsonElement` view (the mutable `JsonValue` builder API landed in .NET 9),
// so this SDK ships a small value model: requests are built with the factory
// methods below and serialized compactly; responses are parsed via
// `JsonDocument` and converted into the same model. BCL-only.

using System.Collections.Generic;
using System.Text.Json;
using System.Text;
using System;

/// A JSON value. One concrete class with a `kind` discriminator (the .NET 8
/// compiler in this toolchain rejects String-returning method overrides in
/// abstract classes, so a sealed hierarchy is avoided).
public class JsonValue {
    public static int NULL = 0;
    public static int BOOL = 1;
    public static int NUMBER = 2;
    public static int STRING = 3;
    public static int ARRAY = 4;
    public static int OBJECT = 5;

    public int kind;
    public bool boolValue;
    public double numberValue;
    public String stringValue;
    public List<JsonValue> arrayValue;
    public Dictionary<String, JsonValue> objectValue;

    private JsonValue(int kind) {
        this.kind = kind;
    }

    // Factories ---------------------------------------------------------

    public static JsonValue ofNull() {
        return new JsonValue(NULL);
    }

    public static JsonValue of(bool v) {
        JsonValue j = new JsonValue(BOOL);
        j.boolValue = v;
        return j;
    }

    public static JsonValue of(long v) {
        JsonValue j = new JsonValue(NUMBER);
        j.numberValue = (double) v;
        return j;
    }

    public static JsonValue of(double v) {
        JsonValue j = new JsonValue(NUMBER);
        j.numberValue = v;
        return j;
    }

    public static JsonValue of(String v) {
        JsonValue j = new JsonValue(STRING);
        j.stringValue = v;
        return j;
    }

    public static JsonValue makeArray() {
        JsonValue j = new JsonValue(ARRAY);
        j.arrayValue = new List<JsonValue>();
        return j;
    }

    public static JsonValue makeObject() {
        JsonValue j = new JsonValue(OBJECT);
        j.objectValue = new Dictionary<String, JsonValue>();
        return j;
    }

    // Predicates --------------------------------------------------------

    public bool isNull() { return kind == NULL; }
    public bool isObject() { return kind == OBJECT; }
    public bool isArray() { return kind == ARRAY; }
    public bool isString() { return kind == STRING; }
    public bool isNumber() { return kind == NUMBER; }

    // Object accessors --------------------------------------------------

    public JsonValue get(String key) {
        return objectValue.ContainsKey(key) ? objectValue[key] : null;
    }

    public bool has(String key) {
        return objectValue.ContainsKey(key);
    }

    public String str(String key) {
        if (!objectValue.ContainsKey(key)) {
            return "";
        }
        JsonValue v = objectValue[key];
        return v == null ? "" : v.stringValue;
    }

    public long intVal(String key) {
        if (!objectValue.ContainsKey(key)) {
            return 0;
        }
        return (long) objectValue[key].numberValue;
    }

    public double num(String key) {
        if (!objectValue.ContainsKey(key)) {
            return 0.0;
        }
        return objectValue[key].numberValue;
    }

    public bool boolVal(String key) {
        if (!objectValue.ContainsKey(key)) {
            return false;
        }
        return objectValue[key].boolValue;
    }

    public List<JsonValue> arr(String key) {
        if (!objectValue.ContainsKey(key)) {
            return new List<JsonValue>();
        }
        return objectValue[key].arrayValue;
    }

    public void put(String key, JsonValue v) {
        objectValue[key] = v;
    }

    // Array accessors ---------------------------------------------------

    public JsonValue getAt(int i) {
        return arrayValue[i];
    }

    public int size() {
        return arrayValue.Count;
    }

    public void add(JsonValue v) {
        arrayValue.Add(v);
    }

    // Parsing -----------------------------------------------------------

    public static JsonValue parse(String text) {
        JsonDocument doc = JsonDocument.Parse(text);
        JsonValue v = fromElement(doc.RootElement);
        doc.Dispose();
        return v;
    }

    private static JsonValue fromElement(JsonElement e) {
        if (e.ValueKind == JsonValueKind.Null) { return ofNull(); }
        if (e.ValueKind == JsonValueKind.True) { return of(true); }
        if (e.ValueKind == JsonValueKind.False) { return of(false); }
        if (e.ValueKind == JsonValueKind.Number) { return of(e.GetDouble()); }
        if (e.ValueKind == JsonValueKind.String) { return of(e.GetString()); }
        if (e.ValueKind == JsonValueKind.Array) {
            JsonValue arr = makeArray();
            for (int i = 0; i < e.GetArrayLength(); i++) {
                arr.add(fromElement(e[i]));
            }
            return arr;
        }
        if (e.ValueKind == JsonValueKind.Object) {
            JsonValue obj = makeObject();
            var it = e.EnumerateObject();
            while (it.MoveNext()) {
                obj.put(it.Current.Name, fromElement(it.Current.Value));
            }
            return obj;
        }
        return ofNull();
    }

    // Serialization -----------------------------------------------------

    public String stringify() {
        StringBuilder sb = new StringBuilder();
        write(sb);
        return sb.ToString();
    }

    private void write(StringBuilder sb) {
        if (kind == NULL) {
            sb.Append("null");
        } else if (kind == BOOL) {
            sb.Append(boolValue ? "true" : "false");
        } else if (kind == NUMBER) {
            if (numberValue == Math.Floor(numberValue) && Math.Abs(numberValue) < 9e15) {
                sb.Append((long) numberValue);
            } else {
                sb.Append(numberValue);
            }
        } else if (kind == STRING) {
            writeString(sb, stringValue);
        } else if (kind == ARRAY) {
            sb.Append('[');
            for (int i = 0; i < arrayValue.Count; i++) {
                if (i > 0) sb.Append(',');
                arrayValue[i].write(sb);
            }
            sb.Append(']');
        } else if (kind == OBJECT) {
            sb.Append('{');
            bool first = true;
            foreach (String key in objectValue.Keys) {
                if (!first) sb.Append(',');
                first = false;
                writeString(sb, key);
                sb.Append(':');
                objectValue[key].write(sb);
            }
            sb.Append('}');
        }
    }

    private static void writeString(StringBuilder sb, String s) {
        sb.Append('"');
        for (int i = 0; i < s.Length; i++) {
            char c = s[i];
            if (c == '"') {
                sb.Append("\\\"");
            } else if (c == '\\') {
                sb.Append("\\\\");
            } else if (c == '\n') {
                sb.Append("\\n");
            } else if (c == '\r') {
                sb.Append("\\r");
            } else if (c == '\t') {
                sb.Append("\\t");
            } else if (c < 0x20) {
                sb.Append(String.Format("\\u%04x", (int) c));
            } else {
                sb.Append(c);
            }
        }
        sb.Append('"');
    }
}