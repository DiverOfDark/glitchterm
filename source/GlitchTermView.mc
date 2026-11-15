import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.Weather;

// Stacked glitch time with terminal-style readouts. Layout is defined on a
// 454px reference screen and scaled to the actual one.
class GlitchTermView extends WatchUi.WatchFace {

    private const C_BLACK = 0x000000;
    private const C_WHITE = 0xFFFFFF;
    private const C_MAGENTA = 0xFF2BD6;
    private const C_CYAN = 0x00E5FF;
    private const C_LIME = 0xC8FF00;
    private const C_GREEN = 0x39FF88;
    private const C_GREEN_DIM = 0x1F9D57;
    private const C_GREEN_AOD = 0x14693A;

    // Glitch animation while the watch is awake: short bursts of displaced
    // slices, separated by calm stretches. One burst per heartbeat when the
    // watch has a heart rate; random bursts otherwise.
    private const FRAME_MS = 80;
    private const BEAT_MIN_FRAMES = 2;   // burst length per heartbeat
    private const BEAT_EXTRA_FRAMES = 2;
    private const BURST_CHANCE = 6;      // no heart rate: percent per frame, about one burst every 1.3 s
    private const BURST_MIN_FRAMES = 3;
    private const BURST_EXTRA_FRAMES = 6;
    private const SCANLINES = true;

    private const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

    private var _big as FontResource?;
    private var _outline as FontResource?;
    private var _mono as FontResource?;
    private var _mid as FontResource?;
    private var _midH as Number = 26;
    private var _row1 as Number = 96;
    private var _row2 as Number = 218;

    private var _timer as Timer.Timer?;
    private var _burst as Number = 0;            // frames left in the current burst
    private var _bpm as Number = 0;              // 0 when the watch has no reading
    private var _sinceBeat as Number = 0;        // ms since the last heartbeat burst
    private var _slices as Array<Array<Number> > = [];   // [y, height, dx]
    private var _split as Number = 6;            // colour-split distance
    private var _shake as Number = 0;            // sideways shift of the whole screen

    // What the current frame shows; filled in by drawActive.
    private var _hh as String = "";
    private var _mm as String = "";
    private var _ss as String = "";
    private var _date as String = "";
    private var _batteryLine as Array = [];
    private var _stepLine as Array = [];
    private var _asleep as Boolean = false;

    private var _w as Number = 454;
    private var _cx as Number = 227;
    private var _scale as Float = 1.0;
    private var _bigH as Number = 94;
    private var _charW as Number = 10;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _big = WatchUi.loadResource(Rez.Fonts.Big) as FontResource;
        _outline = WatchUi.loadResource(Rez.Fonts.BigOutline) as FontResource;
        _mono = WatchUi.loadResource(Rez.Fonts.Mono) as FontResource;
        _mid = WatchUi.loadResource(Rez.Fonts.Mid) as FontResource;

        _w = dc.getWidth();
        _cx = _w / 2;
        _scale = _w / 454.0;
        _bigH = dc.getFontHeight(_big as FontResource);
        _charW = dc.getTextWidthInPixels("0", _mono as FontResource);
        _midH = dc.getFontHeight(_mid as FontResource);
        _row1 = px(190) - _bigH;
        _row2 = px(312) - _bigH;
        calm();
    }

    function onUpdate(dc as Dc) as Void {
        dc.clearClip();
        dc.setColor(C_BLACK, C_BLACK);
        dc.clear();

        var clock = System.getClockTime();
        var hh = clock.hour.format("%02d");   // always 24-hour
        var mm = clock.min.format("%02d");

        if (_asleep) {
            drawAlwaysOn(dc, hh, mm, clock.min);
        } else {
            drawActive(dc, hh, mm, clock.sec);
        }
    }

    function onShow() as Void {
        if (!_asleep) {
            startAnimation();
        }
    }

    function onHide() as Void {
        stopAnimation();
    }

    function onEnterSleep() as Void {
        _asleep = true;
        stopAnimation();
        WatchUi.requestUpdate();
    }

    // Wrist raised: always open with a burst.
    function onExitSleep() as Void {
        _asleep = false;
        startAnimation();
        _burst = BURST_MIN_FRAMES + BURST_EXTRA_FRAMES;
        scramble();
        WatchUi.requestUpdate();
    }

    // ---- glitch animation ----

    private function startAnimation() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onFrame), FRAME_MS, true);
        }
    }

    private function stopAnimation() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
        calm();
    }

    // Only redraws when the picture changes, so calm stretches cost nothing.
    function onFrame() as Void {
        var beat = false;
        if (_bpm > 0) {
            // Carry the remainder over, so the average rate matches the pulse
            // even though frames are 80 ms apart.
            var interval = 60000 / _bpm;
            _sinceBeat += FRAME_MS;
            if (_sinceBeat >= interval) {
                _sinceBeat -= interval;
                beat = true;
            }
        } else {
            beat = (_burst == 0) && (rand(100) < BURST_CHANCE);
        }

        if (beat) {
            _burst = (_bpm > 0)
                ? BEAT_MIN_FRAMES + rand(BEAT_EXTRA_FRAMES)
                : BURST_MIN_FRAMES + rand(BURST_EXTRA_FRAMES);
            scramble();
            WatchUi.requestUpdate();
        } else if (_burst > 0) {
            _burst--;
            if (_burst == 0) {
                calm();
            } else {
                scramble();
            }
            WatchUi.requestUpdate();
        }
    }

    // Current heart rate, or 0 when there is no believable reading.
    private function heartRate() as Number {
        var bpm = null;
        var info = Activity.getActivityInfo();
        if (info != null) {
            bpm = info.currentHeartRate;
        }
        if (bpm == null) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                bpm = sample.heartRate;
            }
        }
        if (bpm == null || bpm < 30 || bpm > 230) {
            return 0;
        }
        return bpm;
    }

    private function calm() as Void {
        _burst = 0;
        _slices = [];
        _split = px(5);
        _shake = 0;
    }

    // New random slices, colour split and shake for one frame of a burst.
    private function scramble() as Void {
        var top = px(24);
        var span = px(396);              // slices can land anywhere on the screen
        var count = 3 + rand(5);
        var slices = [] as Array<Array<Number> >;
        for (var i = 0; i < count; i++) {
            var h = px(4 + rand(22));
            var dx = px(8 + rand(28));
            if (rand(2) == 0) {
                dx = -dx;
            }
            slices.add([top + rand(span - h), h, dx]);
        }
        _slices = slices;
        _split = px(3 + rand(10));
        _shake = (rand(3) == 0) ? px(rand(13) - 6) : 0;
    }

    private function rand(limit as Number) as Number {
        var value = Math.rand() % limit;
        return (value < 0) ? -value : value;
    }

    // ---- active (wrist raised) ----

    private function drawActive(dc as Dc, hh as String, mm as String, sec as Number) as Void {
        _bpm = heartRate();   // refreshed on every redraw
        _hh = hh;
        _mm = mm;
        _ss = sec.format("%02d");
        _date = dateString(true);

        var battery = System.getSystemStats().battery;
        var filled = ((battery + 5) / 10).toNumber();
        if (filled > 10) {
            filled = 10;
        }
        _batteryLine = [
            ["bat [", C_GREEN],
            [repeat("#", filled), C_LIME],
            [repeat("-", 10 - filled), C_GREEN],
            ["] " + battery.format("%d") + "%", C_GREEN]
        ];

        var steps = ActivityMonitor.getInfo().steps;
        var stepText = (steps != null) ? steps.format("%05d") : "-----";
        _stepLine = [
            ["stp " + stepText, C_GREEN],
            [" | ", C_GREEN_DIM],
            [weatherString(), C_CYAN]
        ];

        drawScene(dc, _shake);

        // Each slice is a full-width band of the whole screen, redrawn shifted.
        for (var i = 0; i < _slices.size(); i++) {
            var slice = _slices[i];
            dc.setClip(0, slice[0], _w, slice[1]);
            dc.setColor(C_BLACK, C_BLACK);
            dc.fillRectangle(0, slice[0], _w, slice[1]);
            drawScene(dc, _shake + slice[2]);
            dc.clearClip();
        }

        if (SCANLINES) {
            // Semi-transparent where the device supports it, so the digits
            // stay bright; solid black lines otherwise.
            dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
            if (dc has :setStroke) {
                dc.setStroke(Graphics.createColor(110, 0, 0, 0));
            }
            dc.setPenWidth(1);
            for (var y = _row1; y < _row2 + _bigH; y += 4) {
                dc.drawLine(0, y, _w, y);
            }
        }
    }

    // Everything on the active face, shifted sideways by dx.
    private function drawScene(dc as Dc, dx as Number) as Void {
        var mono = _mono as FontResource;
        var centered = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var cx = _cx + dx;

        // Colour-split time: magenta left, cyan right, white on top.
        var big = _big as FontResource;
        var layers = [[-_split, C_MAGENTA], [_split, C_CYAN], [0, C_WHITE]];
        for (var i = 0; i < layers.size(); i++) {
            var x = cx + (layers[i][0] as Number);
            dc.setColor(layers[i][1] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, _row1, big, _hh, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(x, _row2, big, _mm, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Seconds, bottom-aligned with the minutes.
        drawText(dc, px(352) + dx, _row2 + _bigH - _midH, _mid as FontResource, _ss,
            C_GREEN, Graphics.TEXT_JUSTIFY_LEFT);

        // "$ date" and the date chip.
        drawText(dc, cx, px(38), mono, "$ date", C_GREEN_DIM, centered);
        var chipW = _date.length() * _charW + px(26);
        var chipH = px(26);
        dc.setColor(C_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - chipW / 2, px(52), chipW, chipH);
        dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, px(52) + chipH / 2, mono, _date, centered);

        drawSegments(dc, cx, px(344), _batteryLine);
        drawSegments(dc, cx, px(370), _stepLine);

        // Prompt with cursor.
        var promptY = px(396);
        drawText(dc, cx - px(4), promptY, mono, "~$", C_GREEN_DIM,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(C_MAGENTA, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx + px(4), promptY - px(7), px(9), px(14));
    }

    // Text that picks up magenta and cyan ghosts while a burst is running.
    private function drawText(dc as Dc, x as Number, y as Number, font as FontResource,
            text as String, color as Number, justify as Number) as Void {
        if (_burst > 0) {
            var ghost = _split / 2;
            dc.setColor(C_MAGENTA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x - ghost, y, font, text, justify);
            dc.setColor(C_CYAN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + ghost, y, font, text, justify);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    // One centred line of monospaced text made of differently coloured parts.
    private function drawSegments(dc as Dc, cx as Number, y as Number, parts as Array) as Void {
        var mono = _mono as FontResource;
        var chars = 0;
        for (var i = 0; i < parts.size(); i++) {
            chars += ((parts[i] as Array)[0] as String).length();
        }
        var x = cx - chars * _charW / 2;
        for (var i = 0; i < parts.size(); i++) {
            var part = parts[i] as Array;
            var text = part[0] as String;
            drawText(dc, x, y, mono, text, part[1] as Number,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += text.length() * _charW;
        }
    }

    // ---- always-on (wrist down) ----

    // Thin outlines only, nudged a few pixels each minute so nothing stays lit
    // in the same place.
    private function drawAlwaysOn(dc as Dc, hh as String, mm as String, min as Number) as Void {
        var outline = _outline as FontResource;
        var ox = (min % 5 - 2) * 2;
        var oy = (min % 3 - 1) * 2;
        var row1 = px(190) - _bigH + oy;
        var row2 = px(312) - _bigH + oy;

        dc.setColor(C_GREEN_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + ox, row1, outline, hh, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(_cx + ox, row2, outline, mm, Graphics.TEXT_JUSTIFY_CENTER);

        // One displaced band, to keep the glitch look.
        var y = row1 + px(36);
        var h = px(18);
        dc.setClip(0, y, _w, h);
        dc.setColor(C_BLACK, C_BLACK);
        dc.fillRectangle(0, y, _w, h);
        dc.setColor(C_GREEN_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + ox + px(18), row1, outline, hh, Graphics.TEXT_JUSTIFY_CENTER);
        dc.clearClip();

        var line = dateString(false) + "  bat " + System.getSystemStats().battery.format("%d") + "%";
        dc.setColor(C_GREEN_AOD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + ox, px(356) + oy, _mono as FontResource, line,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- data helpers ----

    // "SUN_15.11.26" for the chip, "sun 15.11" for always-on.
    private function dateString(full as Boolean) as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var day = DAYS[(info.day_of_week as Number) - 1];
        var dd = (info.day as Number).format("%02d");
        var mo = (info.month as Number).format("%02d");
        if (full) {
            return day + "_" + dd + "." + mo + "." + ((info.year as Number) % 100).format("%02d");
        }
        return day.toLower() + " " + dd + "." + mo;
    }

    // "12°c rain". Weather comes from the phone, so it can be missing.
    private function weatherString() as String {
        var now = Weather.getCurrentConditions();
        if (now == null || now.temperature == null) {
            return "wx --";
        }
        var temp = now.temperature as Numeric;
        var unit = "c";
        if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
            temp = temp * 9 / 5 + 32;
            unit = "f";
        }
        var text = temp.format("%d") + "°" + unit;
        var word = conditionWord(now.condition);
        if (word.length() > 0) {
            text += " " + word;
        }
        return text;
    }

    private function conditionWord(condition as Number?) as String {
        if (condition == null) {
            return "";
        }
        switch (condition) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_FAIR:
                return "clear";
            case Weather.CONDITION_PARTLY_CLOUDY:
            case Weather.CONDITION_PARTLY_CLEAR:
            case Weather.CONDITION_THIN_CLOUDS:
                return "partly";
            case Weather.CONDITION_MOSTLY_CLOUDY:
            case Weather.CONDITION_CLOUDY:
                return "cloud";
            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_DRIZZLE:
            case Weather.CONDITION_FREEZING_RAIN:
            case Weather.CONDITION_UNKNOWN_PRECIPITATION:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
                return "rain";
            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_SCATTERED_SHOWERS:
                return "shower";
            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_ICE_SNOW:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
                return "snow";
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
            case Weather.CONDITION_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_SLEET:
                return "sleet";
            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
            case Weather.CONDITION_TROPICAL_STORM:
            case Weather.CONDITION_HURRICANE:
            case Weather.CONDITION_TORNADO:
            case Weather.CONDITION_SQUALL:
                return "storm";
            case Weather.CONDITION_WINDY:
                return "wind";
            case Weather.CONDITION_FOG:
            case Weather.CONDITION_MIST:
                return "fog";
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_HAZE:
            case Weather.CONDITION_SMOKE:
                return "haze";
            case Weather.CONDITION_DUST:
            case Weather.CONDITION_SAND:
            case Weather.CONDITION_SANDSTORM:
            case Weather.CONDITION_VOLCANIC_ASH:
                return "dust";
            case Weather.CONDITION_HAIL:
                return "hail";
            case Weather.CONDITION_ICE:
                return "ice";
            default:
                return "";
        }
    }

    private function repeat(ch as String, count as Number) as String {
        var out = "";
        for (var i = 0; i < count; i++) {
            out += ch;
        }
        return out;
    }

    // Reference-screen pixels to real pixels.
    private function px(value as Number) as Number {
        return (value * _scale + 0.5).toNumber();
    }
}
