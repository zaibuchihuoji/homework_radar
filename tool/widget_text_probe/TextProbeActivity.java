package com.worknote.widgettextprobe;

import android.app.Activity;
import android.appwidget.*;
import android.content.*;
import android.graphics.Rect;
import android.graphics.drawable.BitmapDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.text.Layout;
import android.text.Spanned;
import android.text.style.TextAppearanceSpan;
import android.text.style.BackgroundColorSpan;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Development-only public widget host. Uses synthetic-device widget output,
 * never reads/writes the product's preferences or database. */
public class TextProbeActivity extends Activity {
    private static final String TARGET = "com.worknote.homework_radar";
    private AppWidgetHost host;
    private final List<AppWidgetHostView> views = new ArrayList<>();
    private final String[] types = {"homework", "homework", "homework", "timetable", "homework", "homework", "timetable"};
    private final int[][] sizes = {{124,67},{124,151},{260,318},{124,151},{124,40},{110,40},{110,110}};
    private final Handler handler = new Handler();
    private Context target;
    private static class SavedHost {
        final AppWidgetHost host; final Context target; final List<AppWidgetHostView> views;
        SavedHost(AppWidgetHost host,Context target,List<AppWidgetHostView> views) {
            this.host=host;this.target=target;this.views=new ArrayList<>(views);
        }
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (getIntent().getBooleanExtra("cleanup", false)) {
            new AppWidgetHost(getApplicationContext(),61924).deleteHost();finish();return;
        }
        SavedHost saved=(SavedHost)getLastNonConfigurationInstance();
        if(saved!=null) {
            // Material You may recreate this activity after a wallpaper change.
            // Retain the exact native views/IDs: rebinding could hide a missing
            // wallpaper refresh in the product under test.
            host=saved.host;target=saved.target;views.addAll(saved.views);
            LinearLayout column=new LinearLayout(this);column.setOrientation(LinearLayout.VERTICAL);
            for(int i=0;i<views.size();i++) {
                AppWidgetHostView view=views.get(i);
                if(view.getParent() instanceof ViewGroup)((ViewGroup)view.getParent()).removeView(view);
                column.addView(view,new LinearLayout.LayoutParams(dp(sizes[i][0]),dp(sizes[i][1])));
            }
            ScrollView scroll=new ScrollView(this);scroll.addView(column);setContentView(scroll);
            handler.postDelayed(this::report,1000);return;
        }
        host = new AppWidgetHost(getApplicationContext(), 61924);
        host.deleteHost();
        try { target = createPackageContext(TARGET, 0); } catch(Exception e) { throw new RuntimeException(e); }
        LinearLayout column = new LinearLayout(this); column.setOrientation(LinearLayout.VERTICAL);
        ScrollView scroll = new ScrollView(this); scroll.addView(column); setContentView(scroll);
        AppWidgetManager manager = AppWidgetManager.getInstance(this);
        host.startListening();
        for (int i=0; i<types.length; i++) {
            String suffix = types[i].equals("homework") ? "HomeworkWidgetProvider" : "TimetableWidgetProvider";
            AppWidgetProviderInfo info = manager.getInstalledProviders().stream().filter(p ->
                p.provider.getPackageName().equals(TARGET) && p.provider.getClassName().endsWith(suffix)).findFirst()
                .orElseThrow(() -> new IllegalStateException("Missing product widget provider"));
            int id = host.allocateAppWidgetId();
            Bundle options = new Bundle();
            options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,sizes[i][0]);
            options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH,sizes[i][0]);
            options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,sizes[i][1]);
            options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,sizes[i][1]);
            if (!manager.bindAppWidgetIdIfAllowed(id, info.provider, options)) throw new IllegalStateException("Grant test host binding permission first");
            AppWidgetHostView view = host.createView(this,id,info);
            view.setPadding(0,0,0,0);
            column.addView(view,new LinearLayout.LayoutParams(dp(sizes[i][0]),dp(sizes[i][1])));
            views.add(view);
        }
        handler.postDelayed(() -> {
            int position=getIntent().getIntExtra("position",0);
            if(position>0) for(int i=0;i<views.size();i++) {
                View list=views.get(i).findViewById(id(types[i].equals("homework")?"w_list":"tt_list"));
                if(list instanceof ListView)((ListView)list).setSelection(position);
            }
        },3500);
        handler.postDelayed(this::report,7000);
    }
    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        // Capture the existing host without rebinding or opening the product.
        // Wallpaper-change tests use this to detect automatic color refresh.
        if(intent.getBooleanExtra("capture",false))handler.postDelayed(this::report,1000);
    }
    private int dp(float value) { return Math.round(value*getResources().getDisplayMetrics().density); }
    private int id(String name) { return target.getResources().getIdentifier(name,"id",TARGET); }
    private List<TextView> texts(View parent,int id) {
        List<TextView> out = new ArrayList<>();
        if (parent.getId()==id && parent instanceof TextView) out.add((TextView)parent);
        if(parent instanceof ViewGroup) for(int i=0;i<((ViewGroup)parent).getChildCount();i++) out.addAll(texts(((ViewGroup)parent).getChildAt(i),id));
        return out;
    }
    private int ellipses(TextView text) {
        Layout layout=text.getLayout(); if(layout==null)return -1;
        int count=0; for(int i=0;i<layout.getLineCount();i++) count+=layout.getEllipsisCount(i);return count;
    }
    private int halos(TextView text) {
        if(text==null || !(text.getText() instanceof Spanned))return 0;
        Spanned value=(Spanned)text.getText();int count=0;
        for(TextAppearanceSpan span:value.getSpans(0,value.length(),TextAppearanceSpan.class))
            if(android.os.Build.VERSION.SDK_INT>=29 && span.getShadowRadius()>0 && span.getShadowColor()!=0)count++;
        return count;
    }
    private int backing(TextView text) {
        if(text==null || !(text.getText() instanceof Spanned))return 0;
        Spanned value=(Spanned)text.getText();
        BackgroundColorSpan[] spans=value.getSpans(0,value.length(),BackgroundColorSpan.class);
        return spans.length==0?0:spans[0].getBackgroundColor();
    }
    private boolean haloOnlyDraws(TextView text) {
        if(text==null || !(text.getText() instanceof Spanned))return true;
        Spanned value=(Spanned)text.getText();
        for(TextAppearanceSpan span:value.getSpans(0,value.length(),TextAppearanceSpan.class)) {
            if(span.getTextSize()>0 || span.getTextStyle()!=0 || span.getFamily()!=null || span.getTextColor()!=null)return false;
        }
        return true;
    }
    private int tint(View view) {
        if(view==null || view.getBackground()==null || view.getBackground().getConstantState()==null)return 0;
        android.graphics.drawable.Drawable drawable=view.getBackground().getConstantState().newDrawable().mutate();
        android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(64,64,android.graphics.Bitmap.Config.ARGB_8888);
        drawable.setBounds(0,0,64,64);drawable.draw(new android.graphics.Canvas(bitmap));
        int color=bitmap.getPixel(32,32);bitmap.recycle();return color;
    }
    private View rowFor(TextView text,int rowId) {
        View view=text;
        while(view!=null) {
            // Collection host wrappers can repeat the root ID without having
            // its background. Follow the visible title's actual ancestry.
            if(view.getId()==rowId && view.getBackground()!=null)return view;
            view=view.getParent() instanceof View?(View)view.getParent():null;
        }
        return null;
    }
    private boolean inside(TextView text,View viewport,AppWidgetHostView root) {
        Layout layout=text.getLayout(); if(layout==null)return false;
        Rect box=new Rect(0,0,text.getWidth(),text.getHeight());root.offsetDescendantRectToMyCoords(text,box);
        Rect port=new Rect(0,0,viewport.getWidth(),viewport.getHeight());root.offsetDescendantRectToMyCoords(viewport,port);
        int inkBottom=box.top+text.getCompoundPaddingTop()+layout.getLineBottom(layout.getLineCount()-1);
        return inkBottom<=box.bottom-text.getCompoundPaddingBottom()+1 && inkBottom<=port.bottom+1 && box.top>=port.top-1;
    }
    private boolean fits(TextView text,View viewport,AppWidgetHostView root) {
        return ellipses(text)==0 && inside(text,viewport,root);
    }
    private int visibleTitles(List<TextView> texts,View viewport,AppWidgetHostView root) {
        Rect port=new Rect(0,0,viewport.getWidth(),viewport.getHeight());root.offsetDescendantRectToMyCoords(viewport,port);
        int count=0;
        for(TextView text:texts) {
            Rect box=new Rect(0,0,text.getWidth(),text.getHeight());root.offsetDescendantRectToMyCoords(text,box);
            if(text.getVisibility()==View.VISIBLE&&!text.getText().toString().isEmpty()&&box.intersect(port))count++;
        }
        return count;
    }
    private JSONObject headerReport(AppWidgetHostView root,boolean hw) throws org.json.JSONException {
        View header=root.findViewById(id(hw?"w_header":"tt_header"));
        TextView title=root.findViewById(id(hw?"w_title":"tt_title"));
        TextView mark=root.findViewById(id(hw?"w_mark":"tt_mark"));
        boolean visible=header!=null&&header.getVisibility()==View.VISIBLE;
        Rect a=new Rect(),b=new Rect();
        if(visible) {title.getDrawingRect(a);root.offsetDescendantRectToMyCoords(title,a);
            mark.getDrawingRect(b);root.offsetDescendantRectToMyCoords(mark,b);}
        return new JSONObject().put("visible",visible).put("title",title.getText().toString()).put("mark",mark.getText().toString())
            .put("titleFits",visible&&fits(title,header,root)).put("markFits",visible&&fits(mark,header,root))
            .put("titleEllipsis",ellipses(title)).put("markEllipsis",ellipses(mark)).put("gapPx",visible?b.left-a.right:0)
            .put("heightPx",header.getHeight()).put("titleLines",title.getLineCount())
            .put("titleLayoutHeight",title.getLayout()==null?0:title.getLayout().getHeight()).put("titleViewHeight",title.getHeight())
            .put("titleWidth",title.getWidth()).put("titlePixels",title.getTextSize()).put("markPixels",mark.getTextSize())
            .put("titleScrollY",title.getScrollY()).put("titleLineBottom",title.getLayout()==null?0:title.getLayout().getLineBottom(title.getLineCount()-1)).put("titleRelativeTop",title.getTop()).put("titleTopPadding",title.getCompoundPaddingTop()).put("titleBottomPadding",title.getCompoundPaddingBottom())
            .put("hostPaddingLeft",root.getPaddingLeft()).put("hostPaddingTop",root.getPaddingTop());
    }
    private void report() {
        try {
            JSONArray report=new JSONArray();
            for(int i=0;i<views.size();i++) {
                AppWidgetHostView root=views.get(i);boolean hw=types[i].equals("homework");
                List<TextView> titles=texts(root,id(hw?"w_item":"tt_name"));
                List<TextView> details=texts(root,id(hw?"w_due":"tt_time"));
                if(hw && details.stream().noneMatch(v->v.getVisibility()==View.VISIBLE)) details=texts(root,id("w_meta"));
                View port=root.findViewById(id(hw?"w_list":"tt_list"));
                TextView title=titles.stream().filter(v->v.getVisibility()==View.VISIBLE&&!v.getText().toString().isEmpty()).findFirst().orElse(null);
                TextView detail=details.stream().filter(v->v.getVisibility()==View.VISIBLE&&!v.getText().toString().isEmpty()).findFirst().orElse(null);
                TextView empty=root.findViewById(id(hw?"w_empty":"tt_empty"));
                boolean emptyVisible=empty!=null&&empty.getVisibility()==View.VISIBLE;
                boolean ready=title!=null&&detail!=null&&port!=null;
                JSONObject item=new JSONObject().put("type",types[i]).put("width",sizes[i][0]).put("height",sizes[i][1]).put("itemCount",port instanceof ListView&&((ListView)port).getAdapter()!=null?((ListView)port).getAdapter().getCount():-1).put("firstPosition",port instanceof ListView?((ListView)port).getFirstVisiblePosition():-1).put("fontScale",getResources().getConfiguration().fontScale).put("ready",ready);
                item.put("widgetId",root.getAppWidgetId());
                item.put("sdk",android.os.Build.VERSION.SDK_INT);
                item.put("header",headerReport(root,hw));
                item.put("rowTintColor",tint(rowFor(title,id(hw?"hw_row":"tt_row"))));
                item.put("empty",emptyVisible).put("emptyFits",emptyVisible&&fits(empty,empty,root));
                item.put("titleColor",title==null?0:title.getCurrentTextColor())
                    .put("detailColor",detail==null?0:detail.getCurrentTextColor())
                    .put("titleBacking",backing(title)).put("detailBacking",backing(detail)).put("emptyBacking",backing(empty))
                    .put("titleHalos",halos(title)).put("detailHalos",halos(detail)).put("emptyHalos",halos(empty))
                    .put("haloPreservesMetricsAndColors",haloOnlyDraws(title)&&haloOnlyDraws(detail));
                ImageView panel=root.findViewById(id(hw?"w_glass":"tt_glass"));
                if(panel!=null && panel.getDrawable() instanceof BitmapDrawable) {
                    android.graphics.Bitmap bitmap=((BitmapDrawable)panel.getDrawable()).getBitmap();
                    int center=bitmap.getPixel(bitmap.getWidth()/2,bitmap.getHeight()/2);
                    item.put("panelCenterColor",center).put("panelCenterAlpha",center>>>24);
                }
                item.put("visibleTitleCount",ready?visibleTitles(titles,port,root):0).put("titleInside",ready&&inside(title,port,root)).put("titleFits",ready&&fits(title,port,root)).put("detailFits",ready&&fits(detail,port,root));
                if(ready) item.put("title",title.getText().toString()).put("detail",detail.getText().toString()).put("titleEllipsis",ellipses(title)).put("detailEllipsis",ellipses(detail)).put("titleLines",title.getLineCount()).put("detailLines",detail.getLineCount()).put("titleLayoutHeight",title.getLayout().getHeight()).put("detailLayoutHeight",detail.getLayout().getHeight()).put("titleViewHeight",title.getHeight()).put("detailViewHeight",detail.getHeight()).put("titleSizePx",title.getTextSize()).put("detailSizePx",detail.getTextSize()).put("viewportHeight",port.getHeight());
                report.put(item);
            }
            File out=new File(getExternalFilesDir(null),"text-fit");out.mkdirs();
            try(FileOutputStream file=new FileOutputStream(new File(out,"report.json"))) { file.write(report.toString(2).getBytes(StandardCharsets.UTF_8)); }
        } catch(Exception e) { throw new RuntimeException(e); }
    }
    @Override public Object onRetainNonConfigurationInstance() {return new SavedHost(host,target,views);}
    @Override public void onDestroy() {handler.removeCallbacksAndMessages(null); if(host!=null&&!isChangingConfigurations()){host.stopListening();host.deleteHost();} super.onDestroy();}
}
