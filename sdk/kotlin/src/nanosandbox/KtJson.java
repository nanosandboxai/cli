package nanosandbox.kt;

import nanosandbox.Json;

/**
 * Kotlin-facing factories for the Java SDK's {@link Json} value type.
 *
 * <p>Kotlin cannot call {@code Json.object()} directly: a Java static method
 * named {@code object} breaks the Kotlin compiler's companion-object synthesis
 * for the whole class (kotlinc 2.4.21), so every static factory on {@code Json}
 * becomes unresolvable from Kotlin. This shim re-exposes the factories under
 * names Kotlin can resolve; the Kotlin facade and driver use these instead.
 */
public final class KtJson {

    private KtJson() {
    }

    /** Returns a new empty JSON object. */
    public static Json obj() {
        return Json.object();
    }

    /** Returns a new empty JSON array. */
    public static Json arr() {
        return Json.array();
    }

    /** Returns a JSON string value. */
    public static Json str(String s) {
        return Json.ofString(s);
    }

    /** Returns a JSON boolean value. */
    public static Json bool(boolean b) {
        return Json.ofBool(b);
    }

    /** Returns a JSON number value. */
    public static Json num(double n) {
        return Json.ofNumber(n);
    }

    /** Returns the JSON null value. */
    public static Json nul() {
        return Json.ofNull();
    }

    /** Parses a JSON document from {@code text}. */
    public static Json parse(String text) {
        return Json.parse(text);
    }
}