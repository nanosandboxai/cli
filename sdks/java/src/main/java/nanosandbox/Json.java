package nanosandbox;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A minimal RFC 8259 JSON value type with a recursive-descent parser and a
 * serializer. The JDK ships no JSON support, so the SDK carries a small
 * hand-written one (mirroring the Go SDK's {@code nanosandbox/json.go}).
 *
 * <p>Values are immutable in spirit but the object/array containers are
 * mutable ({@link #set}, {@link #add}) so request frames can be built
 * incrementally, exactly like the reference SDKs.
 */
public final class Json {

    /** The JSON value kinds this type can hold. */
    public enum Kind { NULL, BOOL, NUMBER, STRING, ARRAY, OBJECT }

    private final Kind kind;
    private final boolean boolValue;
    private final double numValue;
    private final String strValue;
    private final List<Json> arrValue;
    private final Map<String, Json> objValue;

    private Json(Kind kind, boolean boolValue, double numValue, String strValue,
                 List<Json> arrValue, Map<String, Json> objValue) {
        this.kind = kind;
        this.boolValue = boolValue;
        this.numValue = numValue;
        this.strValue = strValue;
        this.arrValue = arrValue;
        this.objValue = objValue;
    }

    // ---- factories -------------------------------------------------------

    /** Returns the JSON null value. */
    public static Json ofNull() {
        return new Json(Kind.NULL, false, 0, null, null, null);
    }

    /** Returns a JSON boolean value. */
    public static Json ofBool(boolean b) {
        return new Json(Kind.BOOL, b, 0, null, null, null);
    }

    /** Returns a JSON number value. */
    public static Json ofNumber(double n) {
        return new Json(Kind.NUMBER, false, n, null, null, null);
    }

    /** Returns a JSON string value. */
    public static Json ofString(String s) {
        return new Json(Kind.STRING, false, 0, s, null, null);
    }

    /** Returns a new empty JSON array. */
    public static Json array() {
        return new Json(Kind.ARRAY, false, 0, null, new ArrayList<>(), null);
    }

    /** Returns a new empty JSON object (insertion-ordered). */
    public static Json object() {
        return new Json(Kind.OBJECT, false, 0, null, null, new LinkedHashMap<>());
    }

    // ---- accessors -------------------------------------------------------

    /** Returns this value's kind. */
    public Kind kind() {
        return kind;
    }

    /** Reports whether this is the JSON null value. */
    public boolean isNull() {
        return kind == Kind.NULL;
    }

    /** Returns the boolean value (false for non-boolean kinds). */
    public boolean asBool() {
        return boolValue;
    }

    /** Returns the number value (0 for non-number kinds). */
    public double asNumber() {
        return numValue;
    }

    /** Returns the string value (null for non-string kinds). */
    public String asString() {
        return strValue;
    }

    /** Returns the array elements (empty for non-array kinds). */
    public List<Json> asArray() {
        return arrValue == null ? List.of() : arrValue;
    }

    /** Returns the object entries (empty for non-object kinds). */
    public Map<String, Json> asObject() {
        return objValue == null ? Map.of() : objValue;
    }

    // ---- object helpers --------------------------------------------------

    /** Reports whether this object has the given key. */
    public boolean has(String key) {
        return objValue != null && objValue.containsKey(key);
    }

    /** Returns the value for {@code key}, or JSON null if absent. */
    public Json get(String key) {
        if (objValue == null) {
            return ofNull();
        }
        Json v = objValue.get(key);
        return v == null ? ofNull() : v;
    }

    /** Sets {@code key} to {@code v} on this object. */
    public void set(String key, Json v) {
        if (objValue == null) {
            throw new IllegalStateException("not an object");
        }
        objValue.put(key, v);
    }

    /** Returns the string for {@code key}, or null if absent or not a string. */
    public String getStr(String key) {
        Json v = get(key);
        return v.kind == Kind.STRING ? v.strValue : null;
    }

    /** Returns the boolean for {@code key} (false if absent or not a bool). */
    public boolean getBool(String key) {
        Json v = get(key);
        return v.kind == Kind.BOOL && v.boolValue;
    }

    /** Returns the number for {@code key} (0 if absent or not a number). */
    public double getNum(String key) {
        Json v = get(key);
        return v.kind == Kind.NUMBER ? v.numValue : 0;
    }

    /** Returns the number for {@code key} truncated to a long. */
    public long getInt(String key) {
        return (long) getNum(key);
    }

    /** Returns the array for {@code key} (empty if absent or not an array). */
    public List<Json> getArr(String key) {
        Json v = get(key);
        return v.kind == Kind.ARRAY ? v.arrValue : List.of();
    }

    // ---- array helpers ---------------------------------------------------

    /** Appends {@code v} to this array. */
    public void add(Json v) {
        if (arrValue == null) {
            throw new IllegalStateException("not an array");
        }
        arrValue.add(v);
    }

    /** Returns the number of elements in this array. */
    public int size() {
        return arrValue == null ? 0 : arrValue.size();
    }

    /** Returns the element at {@code i}. */
    public Json at(int i) {
        return arrValue.get(i);
    }

    // ---- parsing ---------------------------------------------------------

    /** Parses a JSON document from {@code text}. */
    public static Json parse(String text) {
        return new JsonParser(text).parse();
    }

    // ---- serialization ---------------------------------------------------

    /** Serializes this value to a compact JSON string. */
    public String stringify() {
        StringBuilder sb = new StringBuilder();
        write(sb);
        return sb.toString();
    }

    private void write(StringBuilder sb) {
        switch (kind) {
            case NULL:
                sb.append("null");
                break;
            case BOOL:
                sb.append(boolValue ? "true" : "false");
                break;
            case NUMBER:
                if (numValue == Math.rint(numValue) && Math.abs(numValue) < 1e15) {
                    sb.append((long) numValue);
                } else {
                    sb.append(numValue);
                }
                break;
            case STRING:
                writeString(sb, strValue);
                break;
            case ARRAY:
                sb.append('[');
                for (int i = 0; i < arrValue.size(); i++) {
                    if (i > 0) {
                        sb.append(',');
                    }
                    arrValue.get(i).write(sb);
                }
                sb.append(']');
                break;
            case OBJECT:
                sb.append('{');
                boolean first = true;
                for (Map.Entry<String, Json> e : objValue.entrySet()) {
                    if (!first) {
                        sb.append(',');
                    }
                    first = false;
                    writeString(sb, e.getKey());
                    sb.append(':');
                    e.getValue().write(sb);
                }
                sb.append('}');
                break;
        }
    }

    private static void writeString(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':
                    sb.append("\\\"");
                    break;
                case '\\':
                    sb.append("\\\\");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append('"');
    }

    @Override
    public String toString() {
        return stringify();
    }
}