import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  property string editCurrentProvider: "youtube"
  property string editDefaultSort: "date"
  property string editYtPlayerClient: "android"
  property string editDownloadDirectory: Quickshell.env("HOME") + "/Music/Noctalia"
  property int editDownloadCacheMaxMb: 0
  property string editPreviewMetadataMode: "always"
  property bool editShowUploaderMetadata: true
  property bool editShowAlbumMetadata: true
  property bool editShowDurationMetadata: true
  property bool editShowRatingMetadata: true
  property bool editShowTagMetadata: true
  property bool editShowPlayStatsMetadata: true
  property bool editShowStatusMetadata: true
  property bool editShowPreviewChips: true
  property string editPreviewThumbnailSize: "comfortable"
  property bool editShowHomeRecent: true
  property bool editShowHomeTop: true
  property bool editShowHomeTags: true
  property bool editShowHomeArtists: true
  property bool editShowHomePlaylists: true
  property bool editAutoSaveMp3AfterPlayback: false

  spacing: Style.marginL

  function loadSettings() {
    editCurrentProvider = pluginApi?.mainInstance?.currentProvider || "youtube";
    editDefaultSort = pluginApi?.mainInstance?.currentSortBy || "date";
    editYtPlayerClient = pluginApi?.mainInstance?.ytPlayerClient || "android";
    editDownloadDirectory = pluginApi?.mainInstance?.downloadDirectory || (Quickshell.env("HOME") + "/Music/Noctalia");
    editDownloadCacheMaxMb = Number(pluginApi?.mainInstance?.downloadCacheMaxMb || 0);
    editPreviewMetadataMode = pluginApi?.pluginSettings?.previewMetadataMode
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.previewMetadataMode
        ?? "always";
    editShowUploaderMetadata = pluginApi?.pluginSettings?.showUploaderMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showUploaderMetadata
        ?? true;
    editShowAlbumMetadata = pluginApi?.pluginSettings?.showAlbumMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showAlbumMetadata
        ?? true;
    editShowDurationMetadata = pluginApi?.pluginSettings?.showDurationMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showDurationMetadata
        ?? true;
    editShowRatingMetadata = pluginApi?.pluginSettings?.showRatingMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showRatingMetadata
        ?? true;
    editShowTagMetadata = pluginApi?.pluginSettings?.showTagMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showTagMetadata
        ?? true;
    editShowPlayStatsMetadata = pluginApi?.pluginSettings?.showPlayStatsMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showPlayStatsMetadata
        ?? true;
    editShowStatusMetadata = pluginApi?.pluginSettings?.showStatusMetadata
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showStatusMetadata
        ?? true;
    editShowPreviewChips = pluginApi?.pluginSettings?.showPreviewChips
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showPreviewChips
        ?? true;
    editPreviewThumbnailSize = pluginApi?.pluginSettings?.previewThumbnailSize
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.previewThumbnailSize
        ?? "comfortable";
    editShowHomeRecent = pluginApi?.pluginSettings?.showHomeRecent
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showHomeRecent
        ?? true;
    editShowHomeTop = pluginApi?.pluginSettings?.showHomeTop
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showHomeTop
        ?? true;
    editShowHomeTags = pluginApi?.pluginSettings?.showHomeTags
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showHomeTags
        ?? true;
    editShowHomeArtists = pluginApi?.pluginSettings?.showHomeArtists
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showHomeArtists
        ?? true;
    editShowHomePlaylists = pluginApi?.pluginSettings?.showHomePlaylists
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.showHomePlaylists
        ?? true;
    editAutoSaveMp3AfterPlayback = pluginApi?.pluginSettings?.autoSaveMp3AfterPlayback
        ?? pluginApi?.manifest?.metadata?.defaultSettings?.autoSaveMp3AfterPlayback
        ?? false;
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("MusicSearch", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.previewMetadataMode = editPreviewMetadataMode;
    pluginApi.pluginSettings.showUploaderMetadata = editShowUploaderMetadata;
    pluginApi.pluginSettings.showAlbumMetadata = editShowAlbumMetadata;
    pluginApi.pluginSettings.showDurationMetadata = editShowDurationMetadata;
    pluginApi.pluginSettings.showRatingMetadata = editShowRatingMetadata;
    pluginApi.pluginSettings.showTagMetadata = editShowTagMetadata;
    pluginApi.pluginSettings.showPlayStatsMetadata = editShowPlayStatsMetadata;
    pluginApi.pluginSettings.showStatusMetadata = editShowStatusMetadata;
    pluginApi.pluginSettings.showPreviewChips = editShowPreviewChips;
    pluginApi.pluginSettings.previewThumbnailSize = editPreviewThumbnailSize;
    pluginApi.pluginSettings.showHomeRecent = editShowHomeRecent;
    pluginApi.pluginSettings.showHomeTop = editShowHomeTop;
    pluginApi.pluginSettings.showHomeTags = editShowHomeTags;
    pluginApi.pluginSettings.showHomeArtists = editShowHomeArtists;
    pluginApi.pluginSettings.showHomePlaylists = editShowHomePlaylists;
    pluginApi.pluginSettings.autoSaveMp3AfterPlayback = editAutoSaveMp3AfterPlayback;
    pluginApi.saveSettings();
    pluginApi.mainInstance?.refreshPreviewMetadataMode();
    pluginApi.mainInstance?.refreshDisplaySettings();
  }

  function applyDownloadDirectory() {
    var target = String(editDownloadDirectory || "").trim();
    if (target.length === 0) {
      return;
    }
    pluginApi?.mainInstance?.setDownloadDirectory(target);
  }

  function applyCacheLimit() {
    var target = Math.max(0, Math.floor(Number(editDownloadCacheMaxMb || 0)));
    editDownloadCacheMaxMb = target;
    pluginApi?.mainInstance?.setDownloadCacheMaxMb(target);
  }

  onPluginApiChanged: {
    if (pluginApi) {
      loadSettings();
    }
  }

  Component.onCompleted: {
    if (pluginApi) {
      loadSettings();
    }
  }

  Connections {
    target: pluginApi?.mainInstance || null

    function onCurrentProviderChanged() {
      root.editCurrentProvider = pluginApi?.mainInstance?.currentProvider || "youtube";
    }

    function onCurrentSortByChanged() {
      root.editDefaultSort = pluginApi?.mainInstance?.currentSortBy || "date";
    }

    function onDownloadDirectoryChanged() {
      root.editDownloadDirectory = pluginApi?.mainInstance?.downloadDirectory || root.editDownloadDirectory;
    }

    function onDownloadCacheMaxMbChanged() {
      root.editDownloadCacheMaxMb = Number(pluginApi?.mainInstance?.downloadCacheMaxMb || 0);
    }

    function onYtPlayerClientChanged() {
      root.editYtPlayerClient = pluginApi?.mainInstance?.ytPlayerClient || "android";
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.provider.label") || "Global provider"
    description: pluginApi?.tr("settings.provider.desc") || ""
    model: [
      {"key": "youtube", "name": pluginApi?.tr("providers.youtube") || "YouTube"},
      {"key": "soundcloud", "name": pluginApi?.tr("providers.soundcloud") || "SoundCloud"},
      {"key": "local", "name": pluginApi?.tr("providers.local") || "Local"}
    ]
    currentKey: root.editCurrentProvider
    defaultValue: "youtube"
    onSelected: key => {
      root.editCurrentProvider = key;
      pluginApi?.mainInstance?.setProvider(key);
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.sort.label") || "Default sort"
    description: pluginApi?.tr("settings.sort.desc") || ""
    model: [
      {"key": "date", "name": pluginApi?.tr("sort.savedDate") || "Saved date"},
      {"key": "title", "name": pluginApi?.tr("sort.title") || "Title"},
      {"key": "duration", "name": pluginApi?.tr("sort.duration") || "Duration"},
      {"key": "rating", "name": pluginApi?.tr("sort.rating") || "Rating"}
    ]
    currentKey: root.editDefaultSort
    defaultValue: "date"
    onSelected: key => {
      root.editDefaultSort = key;
      pluginApi?.mainInstance?.setSortBy(key);
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.ytClient.label") || "YouTube player client"
    description: pluginApi?.tr("settings.ytClient.desc") || ""
    model: [
      {"key": "android", "name": pluginApi?.tr("settings.ytClient.android") || "Android"},
      {"key": "web", "name": pluginApi?.tr("settings.ytClient.web") || "Web"},
      {"key": "default", "name": pluginApi?.tr("settings.ytClient.default") || "Default (yt-dlp decides)"}
    ]
    currentKey: root.editYtPlayerClient
    defaultValue: "android"
    onSelected: key => {
      root.editYtPlayerClient = key;
      pluginApi?.mainInstance?.setYtPlayerClient(key);
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.downloads.title") || "Downloads"
    pointSize: Style.fontSizeM
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.downloads.currentFolder", {"path": root.editDownloadDirectory}) || ("Current folder: " + root.editDownloadDirectory)
    wrapMode: Text.Wrap
    pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NButton {
      text: pluginApi?.tr("settings.downloads.chooseFolder") || "Choose MP3 folder"
      onClicked: downloadFolderPicker.open()
    }

    NButton {
      text: pluginApi?.tr("settings.downloads.applyFolder") || "Apply folder"
      enabled: String(root.editDownloadDirectory || "").trim().length > 0
      onClicked: root.applyDownloadDirectory()
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: pluginApi?.tr("settings.cache.label") || "Max MP3 cache size"
      description: pluginApi?.tr("settings.cache.desc") || ""
    }

    NSpinBox {
      from: 0
      to: 500000
      stepSize: 128
      value: root.editDownloadCacheMaxMb
      onValueChanged: if (value !== root.editDownloadCacheMaxMb) root.editDownloadCacheMaxMb = value
    }

    NButton {
      text: pluginApi?.tr("settings.cache.apply") || "Apply cache limit"
      onClicked: root.applyCacheLimit()
    }
  }

  NToggle {
    label: pluginApi?.tr("settings.autoSave.label") || "Save remote tracks as mp3 after playback starts"
    description: pluginApi?.tr("settings.autoSave.desc") || ""
    checked: root.editAutoSaveMp3AfterPlayback
    onToggled: {
      root.editAutoSaveMp3AfterPlayback = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.autoSaveMp3AfterPlayback ?? false
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.home.title") || "Home"
    pointSize: Style.fontSizeM
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
  }

  NToggle {
    label: pluginApi?.tr("settings.home.recent.label") || "Show Recently Played"
    description: pluginApi?.tr("settings.home.recent.desc") || ""
    checked: root.editShowHomeRecent
    onToggled: {
      root.editShowHomeRecent = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showHomeRecent ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.home.top.label") || "Show Most Played"
    description: pluginApi?.tr("settings.home.top.desc") || ""
    checked: root.editShowHomeTop
    onToggled: {
      root.editShowHomeTop = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showHomeTop ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.home.tags.label") || "Show Tags"
    description: pluginApi?.tr("settings.home.tags.desc") || ""
    checked: root.editShowHomeTags
    onToggled: {
      root.editShowHomeTags = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showHomeTags ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.home.artists.label") || "Show Artists"
    description: pluginApi?.tr("settings.home.artists.desc") || ""
    checked: root.editShowHomeArtists
    onToggled: {
      root.editShowHomeArtists = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showHomeArtists ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.home.playlists.label") || "Show Playlists"
    description: pluginApi?.tr("settings.home.playlists.desc") || ""
    checked: root.editShowHomePlaylists
    onToggled: {
      root.editShowHomePlaylists = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showHomePlaylists ?? true
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.preview.title") || "Preview"
    pointSize: Style.fontSizeM
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.preview.metadata.label") || "Rich Preview Metadata"
    description: pluginApi?.tr("settings.preview.metadata.desc") || ""
    model: [
      {"key": "always", "name": pluginApi?.tr("settings.preview.metadata.all") || "All previews"},
      {"key": "playing", "name": pluginApi?.tr("settings.preview.metadata.playing") || "Only playing track"},
      {"key": "never", "name": pluginApi?.tr("settings.preview.metadata.disabled") || "Disabled"}
    ]
    currentKey: root.editPreviewMetadataMode
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.previewMetadataMode ?? "always"
    onSelected: key => {
      root.editPreviewMetadataMode = key;
      root.saveSettings();
    }
  }

  NText {
    Layout.fillWidth: true
    text: {
      if (root.editPreviewMetadataMode === "never") {
        return pluginApi?.tr("settings.preview.metadata.neverHint") || "Preview panels will stay lightweight and use only the metadata already present in the launcher results.";
      }
      if (root.editPreviewMetadataMode === "playing") {
        return pluginApi?.tr("settings.preview.metadata.playingHint") || "Only the currently playing item will fetch richer preview data. Saved and search results stay fast.";
      }
      return pluginApi?.tr("settings.preview.metadata.alwaysHint") || "Every preview can fetch richer metadata, including thumbnails and long-form details.";
    }
    wrapMode: Text.Wrap
    pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.preview.thumbnail.label") || "Thumbnail size"
    description: pluginApi?.tr("settings.preview.thumbnail.desc") || ""
    model: [
      {"key": "small", "name": pluginApi?.tr("settings.preview.thumbnail.small") || "Small"},
      {"key": "comfortable", "name": pluginApi?.tr("settings.preview.thumbnail.comfortable") || "Comfortable"},
      {"key": "large", "name": pluginApi?.tr("settings.preview.thumbnail.large") || "Large"}
    ]
    currentKey: root.editPreviewThumbnailSize
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.previewThumbnailSize ?? "comfortable"
    onSelected: key => {
      root.editPreviewThumbnailSize = key;
      root.saveSettings();
    }
  }

  NToggle {
    label: pluginApi?.tr("settings.preview.chips.label") || "Show preview chips"
    description: pluginApi?.tr("settings.preview.chips.desc") || ""
    checked: root.editShowPreviewChips
    onToggled: {
      root.editShowPreviewChips = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showPreviewChips ?? true
  }

  NDivider {
    Layout.fillWidth: true
  }

  NText {
    Layout.fillWidth: true
    text: pluginApi?.tr("settings.metadata.title") || "Visible Metadata"
    pointSize: Style.fontSizeM
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.uploader.label") || "Show uploader"
    description: pluginApi?.tr("settings.metadata.uploader.desc") || ""
    checked: root.editShowUploaderMetadata
    onToggled: {
      root.editShowUploaderMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showUploaderMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.album.label") || "Show album"
    description: pluginApi?.tr("settings.metadata.album.desc") || ""
    checked: root.editShowAlbumMetadata
    onToggled: {
      root.editShowAlbumMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showAlbumMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.duration.label") || "Show duration"
    description: pluginApi?.tr("settings.metadata.duration.desc") || ""
    checked: root.editShowDurationMetadata
    onToggled: {
      root.editShowDurationMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showDurationMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.rating.label") || "Show ratings"
    description: pluginApi?.tr("settings.metadata.rating.desc") || ""
    checked: root.editShowRatingMetadata
    onToggled: {
      root.editShowRatingMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showRatingMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.tags.label") || "Show tags"
    description: pluginApi?.tr("settings.metadata.tags.desc") || ""
    checked: root.editShowTagMetadata
    onToggled: {
      root.editShowTagMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showTagMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.playStats.label") || "Show play stats"
    description: pluginApi?.tr("settings.metadata.playStats.desc") || ""
    checked: root.editShowPlayStatsMetadata
    onToggled: {
      root.editShowPlayStatsMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showPlayStatsMetadata ?? true
  }

  NToggle {
    label: pluginApi?.tr("settings.metadata.status.label") || "Show status"
    description: pluginApi?.tr("settings.metadata.status.desc") || ""
    checked: root.editShowStatusMetadata
    onToggled: {
      root.editShowStatusMetadata = checked;
      root.saveSettings();
    }
    defaultValue: pluginApi?.manifest?.metadata?.defaultSettings?.showStatusMetadata ?? true
  }

  NFilePicker {
    id: downloadFolderPicker
    selectionMode: "folders"
    title: pluginApi?.tr("settings.downloads.folderPickerTitle") || "Choose MP3 download folder"
    initialPath: root.editDownloadDirectory || (Quickshell.env("HOME") + "/Music")
    onAccepted: paths => {
      if (paths.length > 0) {
        root.editDownloadDirectory = paths[0];
        root.applyDownloadDirectory();
      }
    }
  }
}
