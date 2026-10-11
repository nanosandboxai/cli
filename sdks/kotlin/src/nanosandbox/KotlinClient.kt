package nanosandbox.kt

import nanosandbox.Json
import nanosandbox.SandboxClient

/**
 * Kotlin facade over the Java nanosandbox SDK (`sdks/java`). A stateless
 * protocol client bound to one helper socket: each call dials and re-negotiates
 * a fresh connection, so the client holds only the socket path and the
 * capabilities advertised by the helper's handshake.
 *
 * The facade exposes the Java SDK's surface with Kotlin-idiomatic naming and
 * nullable parameters; every method delegates to the Java implementation, so
 * the protocol behaviour (NDJSON framing, hello handshake, streaming verbs)
 * is exactly the Java SDK's.
 */
class KotlinClient {

    private val delegate: SandboxClient
    private val socketPath: String
    private val caps: List<String>

    private constructor(delegate: SandboxClient, socketPath: String, caps: List<String>) {
        this.delegate = delegate
        this.socketPath = socketPath
        this.caps = caps
    }

    companion object {
        /** Dials the helper socket, performs the hello handshake, and returns a client. */
        fun connect(socketPath: String): KotlinClient {
            val jc = SandboxClient.connect(socketPath)
            return KotlinClient(jc, socketPath, jc.capabilities())
        }
    }

    /** Returns the capabilities advertised by the helper. */
    fun capabilities(): List<String> = caps

    /** Reports whether the helper advertises the given capability. */
    fun supports(cap: String?): Boolean = cap != null && caps.contains(cap)

    /** Returns the socket path this client is bound to. */
    fun socket(): String = socketPath

    /** Sends a request on a fresh connection and returns the response. */
    fun call(msg: Json): Json = delegate.call(msg)

    /** Returns the helper's protocol version. */
    fun ping(): String = delegate.ping()

    /** Lists sandbox handles, optionally including stopped ones. */
    fun list(all: Boolean): List<Json> = delegate.list(all)

    /** Lists all snapshots. */
    fun snapshots(): List<Json> = delegate.snapshots()

    /** Fetches a sandbox's info by name. */
    fun get(name: String?): Json = delegate.get(name)

    /** Creates a sandbox from a spec and returns a handle. */
    fun create(spec: Json): KotlinSandbox = KotlinSandbox(delegate.create(spec))

    /** Returns a handle bound to the named sandbox. */
    fun sandbox(name: String?): KotlinSandbox = KotlinSandbox(delegate.sandbox(name ?: ""))
}