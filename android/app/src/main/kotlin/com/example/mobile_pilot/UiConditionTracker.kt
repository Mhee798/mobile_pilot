package com.example.mobile_pilot

/** State-only evaluation. Android reads and time limits remain with WaitForUiController. */
class UiConditionTracker(private val condition: String) {
    data class Outcome(val code: String, val message: String)

    var matchSeen = false
        private set
    var beforeText: String? = null
        private set
    private var stableSince: Long? = null
    private var candidate: String? = null

    fun evaluate(now: Long, foreground: Boolean, element: Map<String, Any?>?, complete: Boolean, ambiguous: Boolean): Outcome? {
        if (!foreground || !complete) {
            reset()
            return null
        }
        if (condition == "textChanged" && ambiguous) {
            return Outcome("UI_AMBIGUOUS", "พบหลายรายการที่ตรงกัน เลือกรหัสหรือคำอธิบายที่ไม่ซ้ำ")
        }
        when (condition) {
            "disappeared" -> {
                if (element != null) {
                    matchSeen = true
                    reset()
                } else if (matchSeen && stable(now, "absent")) {
                    return Outcome("UI_DISAPPEARED", "พบรายการก่อนหน้า และไม่พบต่อเนื่อง 500 มิลลิวินาทีในแอปเป้าหมาย")
                }
            }
            "enabled" -> {
                if (element != null && element["enabled"] == true && element["clickable"] == true) {
                    if (stable(now, "ready")) {
                        return Outcome("UI_ENABLED", "พบปุ่มที่มองเห็น เปิดใช้งาน และแตะได้ต่อเนื่อง 500 มิลลิวินาที")
                    }
                } else {
                    reset()
                }
            }
            "textChanged" -> {
                if (element == null) {
                    reset()
                    return null
                }
                val text = element["text"] as String?
                if (!matchSeen) {
                    matchSeen = true
                    beforeText = text
                    reset()
                } else if (text != beforeText) {
                    if (stable(now, text)) {
                        return Outcome("UI_TEXT_CHANGED", "ข้อความของรายการเดิมเปลี่ยนและคงค่าใหม่ต่อเนื่อง 500 มิลลิวินาที")
                    }
                } else {
                    reset()
                }
            }
        }
        return null
    }

    private fun stable(now: Long, value: String?): Boolean {
        if (stableSince == null || candidate != value) {
            candidate = value
            stableSince = now
        }
        return now - stableSince!! >= 500
    }

    private fun reset() {
        stableSince = null
        candidate = null
    }
}
