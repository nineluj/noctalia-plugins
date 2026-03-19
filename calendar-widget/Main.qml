import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var pluginApi: null

    Logger {
        id: logger
        name: "CalendarPlugin"
    }


    JsonSettings {
        id: calendarSettings
        source: Qt.resolvedUrl("settings.json")
        defaults: { "startOnMonday": true }
    }

    Component.onCompleted: {
        if (pluginApi && pluginApi.registerDesktopWidget) {
            pluginApi.registerDesktopWidget(
                "calendar-widget",
                "Monthly Calendar",
                "calendar-month",
                Qt.resolvedUrl("DesktopWidget.qml"),
                Qt.resolvedUrl("Settings.qml") 
            );
            logger.info("Calendar widget registered with settings support.");
        }
    }
}
