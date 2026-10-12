package app.loudcaption.loud_caption

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionGateTest {
    @Test
    fun beginMonotonicallyIncreasesSessionIds() {
        val gate = SessionGate()

        val first = gate.begin()
        gate.invalidate()
        val second = gate.begin()

        assertTrue(second > first)
    }

    @Test
    fun invalidateRejectsQueuedHealthReply() {
        val gate = SessionGate()
        val sessionId = gate.begin()
        val queuedHealthReply = { gate.accepts(sessionId) }

        gate.invalidate()

        assertFalse(queuedHealthReply())
    }

    @Test
    fun oldCallbackCannotReplaceNewLanguage() {
        val gate = SessionGate()
        val english = gate.begin()
        gate.invalidate()
        val chinese = gate.begin()

        assertFalse(gate.accepts(english))
        assertTrue(gate.accepts(chinese))
    }
}
