package com.example.mobile_pilot

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Shares the existing Flutter conversation with the accessibility overlay. */
object FloatingChatBridge {
    private var channel: MethodChannel? = null
    var onUpdate: ((Map<*, *>) -> Unit)? = null
    var onProductionUpdate: ((Map<*, *>) -> Unit)? = null

    private fun publish(data: Map<*, *>) {
        onUpdate?.invoke(data)
        onProductionUpdate?.invoke(data)
    }

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "com.mobilepilot/floating_chat").also {
            it.setMethodCallHandler { call, result ->
                val data = call.arguments as? Map<*, *>
                if (call.method == "toolStarted") {
                    MobilePilotAccessibilityService.activeService?.collapseFloatingChat()
                    result.success(null)
                } else if (call.method == "update" && data != null) {
                    publish(data)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    fun snapshot() = request("snapshot", null) { value ->
        (value as? Map<*, *>)?.let(::publish)
    }

    fun send(text: String, accepted: (Boolean) -> Unit) =
        request("send", text) { accepted(it == true) }

    fun sendDraft(draft: Map<*, *>, accepted: (Boolean) -> Unit) =
        request("send", draft) { accepted(it == true) }

    fun pick(image: Boolean, done: (Any?) -> Unit) = request("pick", image, done)

    fun messageImage(message: Map<*, *>, done: (Any?) -> Unit) =
        request("messageImage", message, done)

    fun loadOlder(conversation: Any?, done: (Any?) -> Unit) =
        request("loadOlder", conversation, done)

    fun chooseApp(choice: Map<*, *>, done: (Any?) -> Unit) =
        request("chooseApp", choice, done)

    fun newChat(done: (Boolean) -> Unit) = request("newChat", null) { done(it == true) }

    fun retry(conversation: Any?, index: Any?, accepted: (Boolean) -> Unit) =
        request("retry", mapOf("conversation" to conversation, "index" to index)) {
            accepted(it == true)
        }

    fun read(text: String) = request("read", text) {}

    fun stop(fallback: () -> Unit) = request("stop", null) {
        if (it != true) fallback()
    }

    private fun request(method: String, argument: Any?, done: (Any?) -> Unit) {
        val connection = channel ?: run { done(null); return }
        connection.invokeMethod(method, argument, object : MethodChannel.Result {
            override fun success(result: Any?) = done(result)
            override fun error(code: String, message: String?, details: Any?) = done(null)
            override fun notImplemented() = done(null)
        })
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        publish(mapOf("messages" to emptyList<Any>(), "busy" to false))
    }
}
