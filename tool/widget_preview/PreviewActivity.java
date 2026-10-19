package com.worknote.widgetpreview;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RemoteViews;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** Standalone development tool. Reads public resources only, never app data. */
public class PreviewActivity extends Activity {
    private static final String TARGET = "com.worknote.homework_radar";
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(24, 24, 24, 24);
        column.setBackgroundColor(0xffe7e9ef);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(column);
        setContentView(scroll);
        try {
            Context target = createPackageContext(TARGET, 0);
            File output = new File(getExternalFilesDir(null), "previews");
            output.mkdirs();
            JSONArray report = new JSONArray();
            for (String type : new String[]{"homework", "timetable"}) {
                int width = type.equals("homework") ? 320 : 180;
                int height = type.equals("homework") ? 160 : 180;
                int layout = target.getResources().getIdentifier(
                    type + "_widget_preview", "layout", TARGET);
                View view = new RemoteViews(TARGET, layout).apply(this, column);
                float density = getResources().getDisplayMetrics().density;
                int w = Math.round(width * density), h = Math.round(height * density);
                view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY));
                view.layout(0, 0, w, h);
                Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                view.draw(new Canvas(bitmap));
                try (FileOutputStream file = new FileOutputStream(new File(output, type + ".png"))) {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, file);
                }
                AppWidgetProviderInfo info = AppWidgetManager.getInstance(this)
                    .getInstalledProviders().stream().filter(p ->
                        p.provider.getPackageName().equals(TARGET) &&
                        p.provider.getClassName().endsWith(type.equals("homework") ?
                            "HomeworkWidgetProvider" : "TimetableWidgetProvider"))
                    .findFirst().orElseThrow();
                // Exercise the legacy host API even on a device supporting previewLayout.
                Drawable legacy = info.loadPreviewImage(this,
                    getResources().getDisplayMetrics().densityDpi);
                JSONObject item = new JSONObject().put("type", type)
                    .put("previewImage", info.previewImage).put("previewLayout", info.previewLayout)
                    .put("legacyLoaded", legacy != null).put("width", w).put("height", h);
                report.put(item);
                TextView title = new TextView(this);
                title.setText(type + " · legacy preview: " + (legacy != null ? "PASS" : "MISSING"));
                title.setTextColor(0xff151b2b);
                title.setTextSize(18);
                column.addView(title);
                ImageView image = new ImageView(this);
                if (getIntent().getBooleanExtra("legacy", false)) image.setImageDrawable(legacy);
                else image.setImageBitmap(bitmap);
                image.setAdjustViewBounds(true);
                column.addView(image, new LinearLayout.LayoutParams(w, h));
            }
            try (FileOutputStream file = new FileOutputStream(new File(output, "report.json"))) {
                file.write(report.toString(2).getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception error) {
            TextView text = new TextView(this);
            text.setText(error.toString());
            column.addView(text);
            throw new RuntimeException(error);
        }
    }
}
