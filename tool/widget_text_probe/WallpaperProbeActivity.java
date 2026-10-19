package com.worknote.widgettextprobe;

import android.app.Activity;
import android.app.WallpaperManager;
import android.app.WallpaperColors;
import android.content.Intent;
import android.graphics.*;
import android.os.Bundle;
import android.os.Handler;
import java.io.*;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

/** Dedicated synthetic-device wallpaper fixture, not a product component. */
public class WallpaperProbeActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        String kind=getIntent().getStringExtra("wallpaper");
        WallpaperManager manager=WallpaperManager.getInstance(this);
        try {
            if("default".equals(kind)) manager.clear(WallpaperManager.FLAG_SYSTEM);
            else {
                Bitmap image=Bitmap.createBitmap(1440,1280,Bitmap.Config.ARGB_8888);
                Canvas canvas=new Canvas(image);
                canvas.drawColor("dark".equals(kind)?0xFF11151D:"gray".equals(kind)?0xFF808080:"dim".equals(kind)?0xFF6E6E6E:0xFFF7F4EC);
                if("mixed".equals(kind)) {
                    Paint paint=new Paint();
                    for(int y=0;y<1280;y+=160) for(int x=0;x<1440;x+=160) {
                        paint.setColor(new int[]{0xFFFAFAFA,0xFF151923,0xFF808080}[(x/160+y/160)%3]);
                        canvas.drawRect(x,y,x+160,y+160,paint);
                    }
                }
                manager.setBitmap(image,null,false,WallpaperManager.FLAG_SYSTEM);
                image.recycle();
            }
        } catch(Exception e) { throw new RuntimeException(e); }
        // Show the real launcher without resuming the product activity. This
        // lets the test detect whether existing widgets refresh themselves.
        startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME));
        new Handler().postDelayed(() -> {
            try {
                WallpaperColors colors=android.os.Build.VERSION.SDK_INT>=27?
                    manager.getWallpaperColors(WallpaperManager.FLAG_SYSTEM):null;
                JSONObject info=new JSONObject().put("wallpaper",kind)
                    .put("primary",colors==null?0:colors.getPrimaryColor().toArgb())
                    .put("hints",colors==null?0:colors.getColorHints());
                try(FileOutputStream file=new FileOutputStream(new File(getExternalFilesDir(null),"wallpaper-info.json"))) {
                    file.write(info.toString(2).getBytes(StandardCharsets.UTF_8));
                }
            } catch(Exception e) { throw new RuntimeException(e); }
            finish();
        },6000);
    }
}
