package com.dasungta.harmony.previewfixture;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.DisplayMetrics;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private long frames;
    private int clicks;
    private boolean running;
    private View animation;
    private TextView dimensions;
    private LinearLayout root;
    private EditText input;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!running) return;
            frames++;
            DisplayMetrics screen = new DisplayMetrics();
            getWindowManager().getDefaultDisplay().getRealMetrics(screen);
            dimensions.setText("TEST ONLY | screen " + screen.widthPixels + " x " + screen.heightPixels
                + " px | " + (screen.widthPixels > screen.heightPixels ? "LANDSCAPE" : "PORTRAIT")
                + "\ncontent " + root.getWidth() + " x " + root.getHeight() + " px | frame " + frames);
            animation.invalidate();
            handler.postDelayed(this, 33);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            frames = state.getLong("frames");
            clicks = state.getInt("clicks");
        }
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(8), dp(12), dp(8));
        root.setBackgroundColor(Color.WHITE);
        dimensions = new TextView(this);
        dimensions.setTextSize(16);
        dimensions.setTextColor(Color.BLACK);
        root.addView(dimensions);
        animation = new View(this) {
            private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            @Override protected void onDraw(Canvas canvas) {
                canvas.drawColor(Color.rgb(12, 34, 65));
                paint.setColor(Color.CYAN);
                float radius = dp(15);
                float travel = Math.max(0, getWidth() - 2 * radius);
                canvas.drawCircle(radius + (frames % 90) / 89f * travel, getHeight() / 2f, radius, paint);
                paint.setColor(Color.YELLOW);
                canvas.drawRect(getWidth() * (frames % 120) / 120f, getHeight() - dp(8), getWidth(), getHeight(), paint);
            }
        };
        animation.setContentDescription("Animated cyan circle and yellow frame progress bar");
        root.addView(animation, new LinearLayout.LayoutParams(-1, dp(64)));
        Button count = new Button(this);
        count.setText("Tap count: " + clicks);
        count.setOnClickListener(v -> count.setText("Tap count: " + (++clicks)));
        root.addView(count);
        input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT);
        input.setHint("TEST text only");
        input.setContentDescription("Test text input");
        root.addView(input);
        TextView echo = new TextView(this);
        echo.setTextSize(16);
        echo.setTextColor(Color.BLACK);
        echo.setSingleLine(true);
        root.addView(echo);
        input.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) { echo.setText("Echo: " + s); }
            public void afterTextChanged(Editable s) {}
        });
        input.setText(state == null ? "" : state.getString("text", ""));
        LinearLayout rotations = new LinearLayout(this);
        Button portrait = new Button(this);
        portrait.setText("Portrait");
        portrait.setOnClickListener(v -> setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
        rotations.addView(portrait, new LinearLayout.LayoutParams(0, -2, 1));
        Button landscape = new Button(this);
        landscape.setText("Landscape");
        landscape.setOnClickListener(v -> setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));
        rotations.addView(landscape, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(rotations);
        root.setFocusableInTouchMode(true);
        setContentView(root);
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    @Override protected void onResume() {
        super.onResume();
        running = true;
        handler.post(tick);
    }

    @Override protected void onPause() {
        running = false;
        handler.removeCallbacks(tick);
        super.onPause();
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        state.putLong("frames", frames);
        state.putInt("clicks", clicks);
        state.putString("text", input.getText().toString());
        super.onSaveInstanceState(state);
    }
}
