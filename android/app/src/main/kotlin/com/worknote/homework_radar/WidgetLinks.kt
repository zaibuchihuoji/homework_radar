package com.worknote.homework_radar

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/** Only the collection template is mutable; its component and action are fixed.
 * Leave data unset there so each fill-in can supply its own exact destination. */
internal object WidgetLinks {
    fun uri(page: String, id: String = ""): Uri = Uri.Builder()
        .scheme("homework-radar").authority("widget").appendPath(page)
        .apply { if (id.isNotEmpty()) appendQueryParameter("id", id) }.build()

    private fun intent(context: Context) = Intent(context, MainActivity::class.java)
        .setAction(HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION)
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    fun open(context: Context, request: Int, page: String): PendingIntent = PendingIntent.getActivity(
        context, request, intent(context).setData(uri(page)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun template(context: Context, request: Int): PendingIntent = PendingIntent.getActivity(
        context, request, intent(context), PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)

    fun row(page: String, id: String = ""): Intent = Intent().setData(uri(page, id))
}
