package com.loomsolutions.campaign_sms

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.TextUtils
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * The card that floats over an incoming call: who this is, and what you know
 * about them — "wants 3 bedroom, max 8M" while the phone is still ringing.
 *
 * Built as a plain Android view, not Flutter: the app's engine may not be
 * running when a call arrives, and starting one just to draw a card would lose
 * the race against the second ring. Colours are the app's own palette,
 * hand-copied from theme.dart — the one place they are duplicated, for the one
 * view that cannot import them.
 *
 * Needs SYSTEM_ALERT_WINDOW ("display over other apps"), which has its own
 * switch in Settings. Everything here is defensive: an overlay that crashes
 * during a ringing phone would be unforgivable.
 *
 * The card can be dragged up and down — it may land on top of the caller's
 * face or the answer button, and where that is depends on the dialer. The
 * spot it is left in is remembered, so it only needs moving once.
 */
object CallOverlay {

    // theme.dart, by hand.
    private const val INK = 0xFF33475B.toInt()
    private const val INK_MUTED = 0xFF516F90.toInt()
    private const val CARD = 0xFFFFFFFF.toInt()
    private const val ACCENT = 0xFF00A4BD.toInt()
    private const val ACCENT_DARK = 0xFF0091AE.toInt()

    private var shown: View? = null

    /// Kept beside the view so the jot line can flip the window focusable when
    /// it is tapped — a window born FLAG_NOT_FOCUSABLE cannot open a keyboard.
    private var shownWm: WindowManager? = null
    private var shownParams: WindowManager.LayoutParams? = null

    /** Where the user last left the card, in window pixels from the top. */
    private var savedY = Int.MIN_VALUE
    private var restoredY = false

    fun hasPermission(ctx: Context): Boolean =
        android.provider.Settings.canDrawOverlays(ctx)

    /**
     * Background thread, with the DB already open (the ring handler has one):
     * recall where the card was left before the process last died. In-memory
     * wins after the first call — it is always at least as fresh.
     */
    fun restoreY(db: SQLiteDatabase) {
        if (restoredY) return
        restoredY = true
        val stored = CampaignDb.setting(db, Const.S_OVERLAY_Y, "").toIntOrNull()
        if (stored != null && savedY == Int.MIN_VALUE) savedY = stored
    }

    /** Main thread only. Idempotent — the second RINGING broadcast is a no-op. */
    fun show(
        ctx: Context,
        contactId: Long,
        name: String,
        phone: String,
        notes: List<String>
    ) {
        if (shown != null) return
        if (!hasPermission(ctx)) return
        try {
            val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val view = build(ctx, contactId, name, phone, notes)
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                android.graphics.PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP
                // If the card sits low, typing must not bury it under the
                // keyboard — pan the window instead.
                softInputMode =
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
                y = if (savedY != Int.MIN_VALUE) {
                    // Never restore to somewhere off-screen: displays change.
                    val max = (ctx.resources.displayMetrics.heightPixels - dp(ctx, 160))
                        .coerceAtLeast(0)
                    savedY.coerceIn(0, max)
                } else {
                    dp(ctx, 96)
                }
            }
            makeDraggable(ctx, wm, view, params)
            wm.addView(view, params)
            shown = view
            shownWm = wm
            shownParams = params
        } catch (e: Exception) {
            // Permission revoked mid-flight, or an OEM with opinions. The call
            // itself must never be disturbed.
            Log.w(Const.TAG, "call overlay failed", e)
            shown = null
        }
    }

    /**
     * Vertical drag anywhere on the card. Horizontal is pointless — the card
     * is full-width — and the ✕ still closes because a clickable child eats
     * its own touches before they reach this listener.
     */
    @Suppress("ClickableViewAccessibility")
    private fun makeDraggable(
        ctx: Context,
        wm: WindowManager,
        view: View,
        params: WindowManager.LayoutParams
    ) {
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var downRawY = 0f
        var downParamY = 0
        var dragging = false
        view.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawY = e.rawY
                    downParamY = params.y
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val delta = (e.rawY - downRawY).toInt()
                    if (!dragging && abs(delta) > slop) dragging = true
                    if (dragging) {
                        val max = (ctx.resources.displayMetrics.heightPixels - v.height)
                            .coerceAtLeast(0)
                        params.y = (downParamY + delta).coerceIn(0, max)
                        try {
                            wm.updateViewLayout(v, params)
                        } catch (_: Exception) {
                            // The window went away mid-drag (call ended). Fine.
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) rememberY(ctx, params.y)
                    true
                }
                else -> false
            }
        }
    }

    /** The new resting spot, kept in memory and written behind for next boot. */
    private fun rememberY(ctx: Context, y: Int) {
        savedY = y
        val app = ctx.applicationContext
        Thread {
            try {
                CampaignDb.use(app) { db ->
                    CampaignDb.putSetting(db, Const.S_OVERLAY_Y, y.toString())
                }
            } catch (e: Exception) {
                Log.w(Const.TAG, "overlay position not saved", e)
            }
        }.start()
    }

    fun hide(ctx: Context) {
        val view = shown ?: return
        shown = null
        shownWm = null
        shownParams = null
        try {
            (ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .removeView(view)
        } catch (_: Exception) {
        }
    }

    /**
     * The window starts FLAG_NOT_FOCUSABLE so the call screen keeps working
     * underneath; the moment the jot line is tapped, the flag comes off so a
     * keyboard can attach. Put back by [releaseTyping] once the note is saved,
     * so stray taps stop being swallowed.
     */
    private fun focusForTyping(input: View) {
        val wm = shownWm ?: return
        val view = shown ?: return
        val params = shownParams ?: return
        if (params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0) {
            params.flags =
                params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            try {
                wm.updateViewLayout(view, params)
            } catch (_: Exception) {
                return
            }
        }
        input.requestFocus()
        val imm = input.context
            .getSystemService(Context.INPUT_METHOD_SERVICE)
                as android.view.inputmethod.InputMethodManager
        imm.showSoftInput(input, 0)
    }

    private fun releaseTyping(input: View) {
        val imm = input.context
            .getSystemService(Context.INPUT_METHOD_SERVICE)
                as android.view.inputmethod.InputMethodManager
        imm.hideSoftInputFromWindow(input.windowToken, 0)
        input.clearFocus()
        val wm = shownWm ?: return
        val view = shown ?: return
        val params = shownParams ?: return
        params.flags =
            params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        try {
            wm.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    /**
     * The jot itself: a bare body straight into the note table, attached to
     * the caller. No editor, no title — "3.4 last price, call back Thursday"
     * typed with the phone still at the ear.
     */
    private fun saveJot(
        ctx: Context,
        contactId: Long,
        input: android.widget.EditText
    ) {
        val text = input.text.toString().trim()
        if (text.isEmpty()) return
        input.isEnabled = false
        val app = ctx.applicationContext
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        Thread {
            try {
                CampaignDb.use(app) { db ->
                    val now = System.currentTimeMillis()
                    val cv = android.content.ContentValues().apply {
                        put("title", "")
                        put("body", text)
                        put("tint", 0)
                        put("pinned", 0)
                        put("contact_id", contactId)
                        put("created_at", now)
                        put("updated_at", now)
                    }
                    db.insert("note", null, cv)
                }
                main.post {
                    input.setText("")
                    input.hint = "Saved — jot another?"
                    input.isEnabled = true
                    releaseTyping(input)
                }
            } catch (e: Exception) {
                Log.w(Const.TAG, "overlay note save failed", e)
                main.post { input.isEnabled = true }
            }
        }.start()
    }

    /**
     * "Note" opens the app's note editor for this caller, mid-call. Holding
     * the overlay permission is what lets an activity start from the
     * background here; the overlay hides itself first, because it floats over
     * everything — including the editor it just opened.
     */
    private fun openNoteEditor(ctx: Context, contactId: Long) {
        try {
            val app = ctx.applicationContext
            val time = android.text.format.DateFormat.getTimeFormat(app)
                .format(java.util.Date())
            hide(app)
            app.startActivity(
                android.content.Intent(app, MainActivity::class.java)
                    .addFlags(
                        android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                            android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
                    )
                    .putExtra(Notifications.EXTRA_CALL_NOTE_CONTACT, contactId)
                    .putExtra(
                        Notifications.EXTRA_CALL_NOTE_PREFILL,
                        "Call · $time\n"
                    )
            )
        } catch (e: Exception) {
            // An OEM that still blocks the launch: the after-call nudge will
            // offer the same editor in a moment. The call goes on.
            Log.w(Const.TAG, "note from overlay failed", e)
        }
    }

    private fun build(
        ctx: Context,
        contactId: Long,
        name: String,
        phone: String,
        notes: List<String>
    ): View {
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 18), dp(ctx, 14), dp(ctx, 14), dp(ctx, 16))
            background = GradientDrawable().apply {
                setColor(CARD)
                cornerRadius = dp(ctx, 22).toFloat()
                setStroke(dp(ctx, 1), 0x22000000)
            }
        }

        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        // The accent dot: this card is LeadForce speaking, and the palette says so.
        header.addView(
            View(ctx).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(ACCENT)
                }
            },
            LinearLayout.LayoutParams(dp(ctx, 10), dp(ctx, 10)).apply {
                marginEnd = dp(ctx, 9)
            }
        )
        header.addView(
            TextView(ctx).apply {
                text = name
                setTextColor(INK)
                textSize = 17f
                typeface = Typeface.create(typeface, Typeface.BOLD)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        )
        header.addView(
            TextView(ctx).apply {
                text = "Note"
                setTextColor(ACCENT_DARK)
                textSize = 13.5f
                typeface = Typeface.create(typeface, Typeface.BOLD)
                setPadding(dp(ctx, 10), dp(ctx, 4), dp(ctx, 10), dp(ctx, 4))
                setOnClickListener { openNoteEditor(ctx, contactId) }
            }
        )
        header.addView(
            TextView(ctx).apply {
                text = "✕"
                setTextColor(INK_MUTED)
                textSize = 16f
                setPadding(dp(ctx, 12), dp(ctx, 4), dp(ctx, 6), dp(ctx, 4))
                setOnClickListener { hide(ctx.applicationContext) }
            }
        )
        card.addView(header)

        card.addView(
            TextView(ctx).apply {
                text = phone
                setTextColor(INK_MUTED)
                textSize = 12.5f
                setPadding(dp(ctx, 19), 0, 0, dp(ctx, 6))
            }
        )

        if (notes.isEmpty()) {
            card.addView(
                TextView(ctx).apply {
                    text = "No notes about them yet."
                    setTextColor(INK_MUTED)
                    textSize = 13f
                    setPadding(dp(ctx, 19), dp(ctx, 2), 0, 0)
                }
            )
        } else {
            for (line in notes) {
                card.addView(
                    TextView(ctx).apply {
                        text = "•  $line"
                        setTextColor(INK)
                        textSize = 13.5f
                        maxLines = 2
                        ellipsize = TextUtils.TruncateAt.END
                        setPadding(dp(ctx, 19), dp(ctx, 3), 0, dp(ctx, 1))
                    }
                )
            }
        }

        // The line to write on, without leaving the call. Tapping it makes the
        // window focusable so the keyboard can come up; Save writes the body
        // straight to the note table under this caller and gives the call
        // screen its taps back.
        val jotRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val input = android.widget.EditText(ctx).apply {
            hint = "Jot a note…"
            setHintTextColor(INK_MUTED)
            setTextColor(INK)
            textSize = 13.5f
            maxLines = 3
            background = GradientDrawable().apply {
                setColor(0xFFF5F8FA.toInt()) // canvas, by hand like the rest
                cornerRadius = dp(ctx, 8).toFloat()
            }
            setPadding(dp(ctx, 12), dp(ctx, 8), dp(ctx, 12), dp(ctx, 8))
            imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI
            setOnTouchListener { v, e ->
                if (e.actionMasked == MotionEvent.ACTION_UP) focusForTyping(v)
                false
            }
        }
        jotRow.addView(
            input,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        )
        jotRow.addView(
            TextView(ctx).apply {
                text = "Save"
                setTextColor(ACCENT_DARK)
                textSize = 13.5f
                typeface = Typeface.create(typeface, Typeface.BOLD)
                setPadding(dp(ctx, 12), dp(ctx, 8), dp(ctx, 4), dp(ctx, 8))
                setOnClickListener { saveJot(ctx, contactId, input) }
            }
        )
        card.addView(
            jotRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dp(ctx, 10)
                marginStart = dp(ctx, 19)
            }
        )

        // The margin lives on an outer frame: window params have no margins,
        // and a full-width white slab against the screen edges reads as a bug.
        return FrameLayout(ctx).apply {
            setPadding(dp(ctx, 12), 0, dp(ctx, 12), 0)
            addView(card)
        }
    }

    private fun dp(ctx: Context, v: Int): Int =
        (v * ctx.resources.displayMetrics.density).toInt()
}
