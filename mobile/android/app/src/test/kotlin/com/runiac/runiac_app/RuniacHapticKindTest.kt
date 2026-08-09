package com.runiac.runiac_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuniacHapticKindTest {
    @Test
    fun resolvesEveryWireNameSentByDart() {
        assertEquals(
            RuniacHapticKind.SELECTION,
            RuniacHapticKind.fromWireName("selection"),
        )
        assertEquals(
            RuniacHapticKind.LIGHT_IMPACT,
            RuniacHapticKind.fromWireName("lightImpact"),
        )
        assertEquals(
            RuniacHapticKind.MEDIUM_IMPACT,
            RuniacHapticKind.fromWireName("mediumImpact"),
        )
        assertEquals(
            RuniacHapticKind.HEAVY_IMPACT,
            RuniacHapticKind.fromWireName("heavyImpact"),
        )
        assertEquals(
            RuniacHapticKind.ERROR,
            RuniacHapticKind.fromWireName("error"),
        )
    }

    @Test
    fun coversEveryDeclaredKind() {
        // Guards the Dart/Kotlin contract: a new level added on one side
        // without the other stops here rather than silently going unfelt.
        assertEquals(5, RuniacHapticKind.entries.size)
    }

    @Test
    fun rejectsUnknownAndMissingWireNames() {
        assertNull(RuniacHapticKind.fromWireName("Selection"))
        assertNull(RuniacHapticKind.fromWireName("success"))
        assertNull(RuniacHapticKind.fromWireName(""))
        assertNull(RuniacHapticKind.fromWireName(null))
    }
}
