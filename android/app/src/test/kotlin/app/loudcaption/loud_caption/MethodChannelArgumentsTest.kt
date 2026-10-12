package app.loudcaption.loud_caption

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MethodChannelArgumentsTest {
    @Test
    fun acceptsIntegerSessionId() {
        assertEquals(41, sessionIdArgument(41))
    }

    @Test
    fun rejectsMissingAndNonIntegerSessionIds() {
        assertNull(sessionIdArgument(null))
        assertNull(sessionIdArgument("41"))
        assertNull(sessionIdArgument(41.0))
    }
}
