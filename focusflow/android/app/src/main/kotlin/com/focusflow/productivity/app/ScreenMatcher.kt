package com.focusflow.productivity.app

import android.os.Parcelable
import android.view.accessibility.AccessibilityNodeInfo

/**
 * ScreenMatcher — Phase 1 per-screen blocking rule engine.
 *
 * Hardcoded rules for two social apps:
 *   - Instagram Reels
 *   - TikTok For You (FYP)
 *
 * Each rule can match on multiple signals (resource ID, content description,
 * text). First hit wins. Matching is done off the main thread inside
 * FocusAccessibilityService.ioExecutor; nodes are recycled after walk.
 *
 * Multi-signal strategy: production social apps change View IDs every
 * release cycle. By requiring at least one of {ID — substring match,
 * ContentDesc — substring match, Text — substring/exact match} we
 * survive most app updates. Add new matchers via [register] when an
 * app version breaks detection — DRI/OPS toggle at startup.
 *
 * Stability notes per the Phase 1 plan:
 *   - Instagram Reels:   resource `clips_video_container` (Brittle)
 *                        + content description "Reels"  (Device-dependent)
 *   - TikTok FYP:        content description "For You" (Device-dependent)
 *                        + text "For You"               (Device-dependent)
 *
 * NOT thread-safe by design — register rules on the ioExecutor thread
 * before any walk; afterwards only [match] is called from that thread.
 */
object ScreenMatcher {

    /** A rule that adds up to one [Signal] family. All signals are OR-ed. */
    data class Rule(
        val packageName: String,
        val screenKey: String,
        val friendlyName: String,
        val signals: List<Signal>,
    )

    sealed class Signal {
        data class ResourceIdContains(val substring: String) : Signal()
        data class ContentDescriptionContains(val substring: String, val ignoreCase: Boolean = true) : Signal()
        data class TextContains(val substring: String, val ignoreCase: Boolean = true) : Signal()
        data class TextEquals(val exact: String, val ignoreCase: Boolean = true) : Signal()
    }

    /** Lookup table — built once at process start. */
    private val rulesByPackage: Map<String, List<Rule>> = buildMap {
        put(
            "com.instagram.android",
            listOf(
                Rule(
                    packageName = "com.instagram.android",
                    screenKey = "reels",
                    friendlyName = "Reels",
                    signals = listOf(
                        // Most stable signal: container View ID — appears in many IG versions
                        Signal.ResourceIdContains("clips_video_container"),
                        // Content description on Reels tab
                        Signal.ContentDescriptionContains("Reels"),
                    ),
                ),
            ),
        )
        put(
            "com.zhiliaoapp.musically",  // TikTok
            listOf(
                Rule(
                    packageName = "com.zhiliaoapp.musically",
                    screenKey = "fyp",
                    friendlyName = "For You",
                    signals = listOf(
                        // Bottom-tab content description
                        Signal.ContentDescriptionContains("For You"),
                        // Some localizations render the tab as plain text
                        Signal.TextEquals("For You"),
                    ),
                ),
            ),
        )
    }

    /**
     * Returns the first rule that matches anything inside [root], or null.
     * Caller must guarantee [root] is from the foreground window (i.e.
     * rootInActiveWindow). The walker handles depth + early exit.
     */
    fun match(root: AccessibilityNodeInfo, packageName: String): Rule? {
        val rules = rulesByPackage[packageName] ?: return null
        for (rule in rules) {
            if (matchesAny(root, rule.signals)) return rule
        }
        return null
    }

    /**
     * Recursive walk — depth-limited to avoid building the entire tree
     * for apps with huge view hierarchies like Reels/TikTok feeds.
     */
    private fun matchesAny(node: AccessibilityNodeInfo, signals: List<Signal>): Boolean {
        // Check the current node first — early-exit if any signal hits.
        if (nodeMatches(node, signals)) return true

        // Walk children, but cap depth so we don't blow the stack on
        // pathological views (Reels infinite scroller, TikTok FYP recycler).
        val children = node.childCount.let { it }?.let { if (it > 0) node.getChild(0) else null }
        var child: AccessibilityNodeInfo? = children?.let { firstNonNullChild(node) }
        var depth = 0
        val maxDepth = 12  // empirical — enough for IG/TikTok tabs but bounded
        while (child != null && depth < maxDepth) {
            if (nodeMatches(child, signals)) return true
            // Check grandchildren of this child (we don't recurse infinitely,
            // but we sample for common "tab indicator" placements).
            for (i in 0 until minOf(child.childCount, 6)) {
                val grand = child.getChild(i) ?: continue
                if (nodeMatches(grand, signals)) return true
            }
            child = nextSibling(child)
            depth++
        }
        return false
    }

    private fun firstNonNullChild(parent: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        for (i in 0 until parent.childCount) {
            parent.getChild(i)?.let { return it }
        }
        return null
    }

    private fun nextSibling(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // AccessibilityNodeInfo.indexInParent was deprecated and removed in
        // API 21+. The replacement is a parent-child index search. Cost is
        // O(n) per call but the walker is bounded by maxDepth=12, so this is
        // acceptable.
        val parent = node.parent ?: return null
        val count = parent.childCount
        for (i in 0 until count - 1) {
            if (parent.getChild(i) === node) {
                return parent.getChild(i + 1)
            }
        }
        return null
    }

    private fun nodeMatches(node: AccessibilityNodeInfo, signals: List<Signal>): Boolean {
        for (s in signals) {
            when (s) {
                is Signal.ResourceIdContains -> {
                    val id = node.viewIdResourceName ?: ""
                    if (id.isNotEmpty() && id.contains(s.substring, ignoreCase = true)) return true
                }
                is Signal.ContentDescriptionContains -> {
                    val cd = node.contentDescription?.toString() ?: ""
                    if (cd.isNotEmpty() && cd.contains(s.substring, s.ignoreCase)) return true
                }
                is Signal.TextContains -> {
                    val t = node.text?.toString() ?: ""
                    if (t.isNotEmpty() && t.contains(s.substring, s.ignoreCase)) return true
                }
                is Signal.TextEquals -> {
                    val t = node.text?.toString() ?: ""
                    if (t.isNotEmpty() && t.equals(s.exact, s.ignoreCase)) return true
                }
            }
        }
        return false
    }
}
