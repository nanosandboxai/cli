package nanosandbox;

/**
 * Recursive-descent parser for the JSON subset produced by {@link Json}.
 * Extracted from {@link Json} so the value type stays focused; the parser is
 * the only consumer of the raw text.
 */
final class JsonParser {

    private final String text;
    private int pos;

    JsonParser(String text) {
        this.text = text;
    }

    /** Parses a complete JSON document. */
    Json parse() {
        Json v = parseValue();
        skipWs();
        if (pos < text.length()) {
            throw new IllegalArgumentException("trailing characters at offset " + pos);
        }
        return v;
    }

    private void skipWs() {
        while (pos < text.length()) {
            char c = text.charAt(pos);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                pos++;
            } else {
                break;
            }
        }
    }

    private Json parseValue() {
        skipWs();
        if (pos >= text.length()) {
            throw new IllegalArgumentException("unexpected end of input");
        }
        char c = text.charAt(pos);
        switch (c) {
            case '{':
                return parseObject();
            case '[':
                return parseArray();
            case '"':
                return Json.ofString(parseString());
            case 't':
                expect("true");
                return Json.ofBool(true);
            case 'f':
                expect("false");
                return Json.ofBool(false);
            case 'n':
                expect("null");
                return Json.ofNull();
            default:
                if (c == '-' || (c >= '0' && c <= '9')) {
                    return parseNumber();
                }
                throw new IllegalArgumentException("unexpected character '" + c + "' at offset " + pos);
        }
    }

    private Json parseObject() {
        pos++; // consume '{'
        Json obj = Json.object();
        skipWs();
        if (pos < text.length() && text.charAt(pos) == '}') {
            pos++;
            return obj;
        }
        while (true) {
            skipWs();
            String key = parseString();
            skipWs();
            if (pos >= text.length() || text.charAt(pos) != ':') {
                throw new IllegalArgumentException("expected ':' at offset " + pos);
            }
            pos++;
            obj.set(key, parseValue());
            skipWs();
            if (pos >= text.length()) {
                throw new IllegalArgumentException("unterminated object");
            }
            char c = text.charAt(pos);
            if (c == ',') {
                pos++;
            } else if (c == '}') {
                pos++;
                return obj;
            } else {
                throw new IllegalArgumentException("expected ',' or '}' at offset " + pos);
            }
        }
    }

    private Json parseArray() {
        pos++; // consume '['
        Json arr = Json.array();
        skipWs();
        if (pos < text.length() && text.charAt(pos) == ']') {
            pos++;
            return arr;
        }
        while (true) {
            arr.add(parseValue());
            skipWs();
            if (pos >= text.length()) {
                throw new IllegalArgumentException("unterminated array");
            }
            char c = text.charAt(pos);
            if (c == ',') {
                pos++;
            } else if (c == ']') {
                pos++;
                return arr;
            } else {
                throw new IllegalArgumentException("expected ',' or ']' at offset " + pos);
            }
        }
    }

    private String parseString() {
        if (pos >= text.length() || text.charAt(pos) != '"') {
            throw new IllegalArgumentException("expected string at offset " + pos);
        }
        pos++; // consume opening quote
        StringBuilder sb = new StringBuilder();
        while (true) {
            if (pos >= text.length()) {
                throw new IllegalArgumentException("unterminated string");
            }
            char c = text.charAt(pos);
            if (c == '"') {
                pos++;
                return sb.toString();
            }
            if (c == '\\') {
                pos++;
                if (pos >= text.length()) {
                    throw new IllegalArgumentException("unterminated escape");
                }
                char e = text.charAt(pos);
                switch (e) {
                    case '"':
                        sb.append('"');
                        break;
                    case '\\':
                        sb.append('\\');
                        break;
                    case '/':
                        sb.append('/');
                        break;
                    case 'b':
                        sb.append('\b');
                        break;
                    case 'f':
                        sb.append('\f');
                        break;
                    case 'n':
                        sb.append('\n');
                        break;
                    case 'r':
                        sb.append('\r');
                        break;
                    case 't':
                        sb.append('\t');
                        break;
                    case 'u':
                        if (pos + 4 >= text.length()) {
                            throw new IllegalArgumentException("bad unicode escape");
                        }
                        sb.append((char) Integer.parseInt(text.substring(pos + 1, pos + 5), 16));
                        pos += 4;
                        break;
                    default:
                        throw new IllegalArgumentException("bad escape '\\" + e + "'");
                }
                pos++;
            } else {
                sb.append(c);
                pos++;
            }
        }
    }

    private Json parseNumber() {
        int start = pos;
        if (pos < text.length() && text.charAt(pos) == '-') {
            pos++;
        }
        while (pos < text.length() && Character.isDigit(text.charAt(pos))) {
            pos++;
        }
        if (pos < text.length() && text.charAt(pos) == '.') {
            pos++;
            while (pos < text.length() && Character.isDigit(text.charAt(pos))) {
                pos++;
            }
        }
        if (pos < text.length() && (text.charAt(pos) == 'e' || text.charAt(pos) == 'E')) {
            pos++;
            if (pos < text.length() && (text.charAt(pos) == '+' || text.charAt(pos) == '-')) {
                pos++;
            }
            while (pos < text.length() && Character.isDigit(text.charAt(pos))) {
                pos++;
            }
        }
        return Json.ofNumber(Double.parseDouble(text.substring(start, pos)));
    }

    private void expect(String lit) {
        if (!text.startsWith(lit, pos)) {
            throw new IllegalArgumentException("expected " + lit + " at offset " + pos);
        }
        pos += lit.length();
    }
}