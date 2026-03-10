import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null
    property var widgetSettings: null

    property string valueDirection:       widgetSettings?.data?.direction             ?? "up"
    property string valueMode:            widgetSettings?.data?.mode                  ?? "bars"
    property int    valueBarCount:        widgetSettings?.data?.barCount              ?? 32
    property int    valueFps:             widgetSettings?.data?.fps                   ?? 60
    property real   valueSensitivity:     widgetSettings?.data?.sensitivity           ?? 1.5
    property real   valueSmoothing:       widgetSettings?.data?.smoothing             ?? 0.18
    property bool   valueUseGradient:     widgetSettings?.data?.useGradient           ?? true
    property bool   valueFadeWhenIdle:    widgetSettings?.data?.fadeWhenIdle          ?? true
    property bool   valueUseCustomColors: widgetSettings?.data?.useCustomColors       ?? false
    property color  valueCustomPrimary:   widgetSettings?.data?.customPrimaryColor    ?? "#6750A4"
    property color  valueCustomSecondary: widgetSettings?.data?.customSecondaryColor  ?? "#625B71"
    property int    valueCustomWidth:     widgetSettings?.data?.customWidth           ?? 0
    property int    valueCustomHeight:    widgetSettings?.data?.customHeight          ?? 0

    // ── Direction ─────────────────────────────────────────────────────────────
    NComboBox {
        Layout.fillWidth: true
        label: "Direction"
        description: "Which way the visualizer grows"
        model: [
            { "key": "up",    "name": "Up"    },
            { "key": "down",  "name": "Down"  },
            { "key": "left",  "name": "Left"  },
            { "key": "right", "name": "Right" }
        ]
        currentKey: root.valueDirection
        onSelected: key => {
            root.valueDirection = key
            root.saveSettings()
        }
    }

    // ── Visualizer mode ───────────────────────────────────────────────────────
    NComboBox {
        Layout.fillWidth: true
        label: "Visualizer Mode"
        description: "How the audio is displayed"
        model: [
            { "key": "bars",   "name": "Bars"   },
            { "key": "wave",   "name": "Wave"   },
            { "key": "mirror", "name": "Mirror" }
        ]
        currentKey: root.valueMode
        onSelected: key => {
            root.valueMode = key
            root.saveSettings()
        }
    }

    // ── Bar count (bars + mirror only) ────────────────────────────────────────
    NValueSlider {
        Layout.fillWidth: true
        visible: root.valueMode !== "wave"
        label: "Bar Count"
        value: root.valueBarCount
        from: 8
        to: 64
        stepSize: 1
        defaultValue: 32
        onMoved: value => root.valueBarCount = Math.round(value)
        onPressedChanged: (pressed, value) => {
            if (!pressed) { root.valueBarCount = Math.round(value); root.saveSettings() }
        }
    }

    // ── Sensitivity ───────────────────────────────────────────────────────────
    NValueSlider {
        Layout.fillWidth: true
        label: "Sensitivity"
        value: root.valueSensitivity
        from: 0.5
        to: 3.0
        stepSize: 0.1
        defaultValue: 1.5
        onMoved: value => root.valueSensitivity = value
        onPressedChanged: (pressed, value) => {
            if (!pressed) { root.valueSensitivity = value; root.saveSettings() }
        }
    }

    // ── Smoothing ─────────────────────────────────────────────────────────────
    NValueSlider {
        Layout.fillWidth: true
        label: "Smoothing"
        description: "Higher = slower decay"
        value: root.valueSmoothing
        from: 0.02
        to: 0.5
        stepSize: 0.01
        defaultValue: 0.18
        onMoved: value => root.valueSmoothing = value
        onPressedChanged: (pressed, value) => {
            if (!pressed) { root.valueSmoothing = value; root.saveSettings() }
        }
    }

    // ── FPS ───────────────────────────────────────────────────────────────────
    NComboBox {
        Layout.fillWidth: true
        label: "Target FPS"
        model: [
            { "key": "24",  "name": "24 fps"  },
            { "key": "30",  "name": "30 fps"  },
            { "key": "60",  "name": "60 fps"  },
            { "key": "120", "name": "120 fps" },
            { "key": "144", "name": "144 fps" },
            { "key": "165", "name": "165 fps" },
            { "key": "180", "name": "180 fps" },
            { "key": "240", "name": "240 fps" }
        ]
        currentKey: String(root.valueFps)
        onSelected: key => {
            root.valueFps = parseInt(key)
            root.saveSettings()
        }
    }

    // ── Size ──────────────────────────────────────────────────────────────────
    NValueSlider {
        Layout.fillWidth: true
        label: "Custom Width"
        description: "0 = use default"
        value: root.valueCustomWidth
        from: 0
        to: 1920
        stepSize: 10
        defaultValue: 0
        onMoved: value => root.valueCustomWidth = Math.round(value)
        onPressedChanged: (pressed, value) => {
            if (!pressed) { root.valueCustomWidth = Math.round(value); root.saveSettings() }
        }
    }

    NValueSlider {
        Layout.fillWidth: true
        label: "Custom Height"
        description: "0 = use default"
        value: root.valueCustomHeight
        from: 0
        to: 1080
        stepSize: 10
        defaultValue: 0
        onMoved: value => root.valueCustomHeight = Math.round(value)
        onPressedChanged: (pressed, value) => {
            if (!pressed) { root.valueCustomHeight = Math.round(value); root.saveSettings() }
        }
    }

    // ── Toggles ───────────────────────────────────────────────────────────────
    NToggle {
        label: "Color Gradient"
        description: "Blend primary → secondary color"
        checked: root.valueUseGradient
        defaultValue: true
        onToggled: checked => {
            root.valueUseGradient = checked
            root.saveSettings()
        }
    }

    NToggle {
        label: "Fade When Idle"
        description: "Fade out when no audio is playing"
        checked: root.valueFadeWhenIdle
        defaultValue: true
        onToggled: checked => {
            root.valueFadeWhenIdle = checked
            root.saveSettings()
        }
    }

    NToggle {
        label: "Use Custom Colors"
        description: "Override theme colors with your own"
        checked: root.valueUseCustomColors
        defaultValue: false
        onToggled: checked => {
            root.valueUseCustomColors = checked
            root.saveSettings()
        }
    }

    // ── Custom color pickers ──────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: root.valueUseCustomColors
        spacing: Style.marginM
        NText { text: "Primary Color"; Layout.fillWidth: true }
        NColorPicker {
            screen: Screen
            selectedColor: root.valueCustomPrimary
            onColorSelected: color => {
                root.valueCustomPrimary = color
                root.saveSettings()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.valueUseCustomColors
        spacing: Style.marginM
        NText { text: "Secondary Color"; Layout.fillWidth: true }
        NColorPicker {
            screen: Screen
            selectedColor: root.valueCustomSecondary
            onColorSelected: color => {
                root.valueCustomSecondary = color
                root.saveSettings()
            }
        }
    }

    // ── Save ──────────────────────────────────────────────────────────────────
    function saveSettings() {
        if (widgetSettings == undefined || widgetSettings.data == undefined) return;
        widgetSettings.data.direction            = root.valueDirection;
        widgetSettings.data.mode                 = root.valueMode;
        widgetSettings.data.barCount             = root.valueBarCount;
        widgetSettings.data.fps                  = root.valueFps;
        widgetSettings.data.sensitivity          = root.valueSensitivity;
        widgetSettings.data.smoothing            = root.valueSmoothing;
        widgetSettings.data.useGradient          = root.valueUseGradient;
        widgetSettings.data.fadeWhenIdle         = root.valueFadeWhenIdle;
        widgetSettings.data.useCustomColors      = root.valueUseCustomColors;
        widgetSettings.data.customPrimaryColor   = root.valueCustomPrimary.toString();
        widgetSettings.data.customSecondaryColor = root.valueCustomSecondary.toString();
        widgetSettings.data.customWidth          = root.valueCustomWidth;
        widgetSettings.data.customHeight         = root.valueCustomHeight;
        widgetSettings.save();
    }
}
