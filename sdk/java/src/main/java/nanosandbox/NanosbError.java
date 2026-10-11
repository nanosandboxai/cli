package nanosandbox;

/**
 * A structured error returned by the nanosandbox helper. The {@code code} is
 * one of the protocol error codes ({@code bad_request}, {@code not_found},
 * {@code invalid_state}, {@code unsupported}, {@code timeout}, ...); the
 * {@code message} is the helper's human-readable detail.
 */
public final class NanosbError extends RuntimeException {

    private final String code;
    private final String message;

    /** Creates an error with the given protocol code and message. */
    public NanosbError(String code, String message) {
        super(code + ": " + message);
        this.code = code;
        this.message = message;
    }

    /** Returns the protocol error code. */
    public String code() {
        return code;
    }

    /** Returns the helper's error message. */
    public String message() {
        return message;
    }

    /** Reports whether the error code is {@code not_found}. */
    public boolean isNotFound() {
        return "not_found".equals(code);
    }
}