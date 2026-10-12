package app.loudcaption.loud_caption

/** Returns a session ID only when the channel argument is an integer. */
internal fun sessionIdArgument(value: Any?): Int? = value as? Int
