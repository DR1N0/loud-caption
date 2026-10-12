package app.loudcaption.loud_caption

/** Guards asynchronously delivered callbacks so only the active capture session can emit. */
class SessionGate {
    private var nextId = 0
    private var activeId: Int? = null

    @Synchronized
    fun begin(): Int {
        val id = ++nextId
        activeId = id
        return id
    }

    @Synchronized
    fun invalidate() {
        activeId = null
    }

    @Synchronized
    fun accepts(id: Int): Boolean = activeId == id
}
