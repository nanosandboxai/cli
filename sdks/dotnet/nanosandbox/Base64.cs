// Base64.cs — RFC 4648 base64 for the protocol's `data_base64` fields.
// The .NET 8 `System.Buffers.Text.Base64` API is span/out-parameter based and
// awkward for whole-buffer round-trips, so this SDK ships a small codec.

using System.Text;
using System;

class Base64Codec {
    private static String ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    public static String encode(byte[] data) {
        StringBuilder sb = new StringBuilder();
        int i = 0;
        while (i + 3 <= data.Length) {
            int b0 = data[i] & 0xff;
            int b1 = data[i + 1] & 0xff;
            int b2 = data[i + 2] & 0xff;
            sb.Append(ALPHABET[b0 >> 2]);
            sb.Append(ALPHABET[((b0 & 0x03) << 4) | (b1 >> 4)]);
            sb.Append(ALPHABET[((b1 & 0x0f) << 2) | (b2 >> 6)]);
            sb.Append(ALPHABET[b2 & 0x3f]);
            i += 3;
        }
        int rem = data.Length - i;
        if (rem == 1) {
            int b0 = data[i] & 0xff;
            sb.Append(ALPHABET[b0 >> 2]);
            sb.Append(ALPHABET[(b0 & 0x03) << 4]);
            sb.Append("==");
        } else if (rem == 2) {
            int b0 = data[i] & 0xff;
            int b1 = data[i + 1] & 0xff;
            sb.Append(ALPHABET[b0 >> 2]);
            sb.Append(ALPHABET[((b0 & 0x03) << 4) | (b1 >> 4)]);
            sb.Append(ALPHABET[(b1 & 0x0f) << 2]);
            sb.Append('=');
        }
        return sb.ToString();
    }

    public static byte[] decode(String text) {
        int pad = 0;
        if (text.EndsWith("==")) {
            pad = 2;
        } else if (text.EndsWith("=")) {
            pad = 1;
        }
        int outLen = (text.Length / 4) * 3 - pad;
        byte[] result = new byte[outLen];
        int outPos = 0;
        int acc = 0;
        int bits = 0;
        for (int i = 0; i < text.Length; i++) {
            char c = text[i];
            if (c == '=') {
                break;
            }
            int v = decodeChar(c);
            if (v < 0) {
                continue;
            }
            acc = (acc << 6) | v;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                result[outPos] = (byte) ((acc >> bits) & 0xff);
                outPos++;
            }
        }
        return result;
    }

    private static int decodeChar(char c) {
        if (c >= 'A' && c <= 'Z') { return c - 'A'; }
        if (c >= 'a' && c <= 'z') { return c - 'a' + 26; }
        if (c >= '0' && c <= '9') { return c - '0' + 52; }
        if (c == '+') { return 62; }
        if (c == '/') { return 63; }
        return -1;
    }
}