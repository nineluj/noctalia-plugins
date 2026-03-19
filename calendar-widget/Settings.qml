import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
    id: root
    
    implicitWidth: 450
    implicitHeight: 250

    property var pluginApi: null
    
    property var cfg: pluginApi ? pluginApi.pluginSettings : ({})
    property var defaults: (pluginApi && pluginApi.manifest && pluginApi.manifest.metadata) 
                           ? pluginApi.manifest.metadata.defaultSettings 
                           : ({"startOnMonday": true})
    
    property bool startOnMonday: cfg.startOnMonday ?? defaults.startOnMonday ?? true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        NText {
            text: "Calendar Settings"
            font.bold: true
            font.pointSize: 14
            color: Color.mPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Color.mOutlineVariant
            opacity: 0.5
        }

        RowLayout {
            Layout.fillWidth: true
            
            NText { 
                text: "Start week on Monday"
                Layout.fillWidth: true
                color: Color.mOnSurface
            }
            
            // Using standard QtQuick CheckBox
            CheckBox { 
                checked: root.startOnMonday
                onToggled: {
                    root.startOnMonday = checked
                }
                
                // Optional: Force a specific height if it looks weird
                implicitHeight: 32
            }
        }

        NText {
            text: "Changes will be applied when you click 'Apply' or 'OK'."
            font.pointSize: 9
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true } 
    }

    function saveSettings() {
        if (pluginApi && pluginApi.pluginSettings) {
            pluginApi.pluginSettings.startOnMonday = root.startOnMonday;
            pluginApi.saveSettings();
        }
    }
}
