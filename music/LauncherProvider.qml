import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "MusicUtils.js" as MusicUtils

Item {
  id: root

  property var pluginApi: null
  property var launcher: null
  property string name: pluginApi?.tr("common.music") || "music-search"
  property bool handleSearch: false
  property string supportedLayouts: "list"
  property string iconMode: Settings.data.appLauncher.iconMode
  property bool hasPreview: true
  property bool previewNeedsGlobalToggle: false
  property url previewComponentPath: Qt.resolvedUrl("MusicPreview.qml")

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property string helperPath: mainInstance?.helperPath || Qt.resolvedUrl("musicctl.sh").toString().replace("file://", "")
  readonly property string commandName: ">" + (pluginApi?.manifest?.metadata?.commandPrefix || "music-search")

  property string activeSearchQuery: ""
  property string pendingSearchQuery: ""
  property string lastCompletedQuery: ""
  property bool searchBusy: false
  property string searchError: ""
  property var searchResults: []
  property var previewDetailCache: ({})
  property string runningSearchQuery: ""
  property string runningSearchProvider: ""
  property int searchEpoch: 0
  property int runningSearchEpoch: 0
  property bool pendingSearchRestart: false
  property string playlistPickerEntryId: ""
  property string playlistPickerEntryTitle: ""
  property string playlistRenameId: ""
  property string playlistRenameTitle: ""
  property string tagEditorEntryId: ""
  property string tagEditorEntryTitle: ""
  property string metadataEditorEntryId: ""
  property string metadataEditorEntryTitle: ""
  property string metadataEditorField: ""

  Process {
    id: searchProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      var completedQuery = root.runningSearchQuery;
      var staleSearch = root.runningSearchEpoch !== root.searchEpoch;

      root.searchBusy = false;
      root.searchError = "";

      if (!staleSearch && exitCode === 0) {
        try {
          var parsed = JSON.parse(String(searchProcess.stdout.text || "[]"));
          root.searchResults = Array.isArray(parsed) ? parsed : [];
          root.lastCompletedQuery = completedQuery;
        } catch (error) {
          root.searchResults = [];
          root.lastCompletedQuery = completedQuery;
          root.searchError = pluginApi?.tr("errors.searchMalformed") || "Search results were malformed.";
          Logger.w("MusicSearchLauncher", "Failed to parse search results:", error);
        }
      } else if (!staleSearch) {
        root.searchResults = [];
        root.lastCompletedQuery = completedQuery;
        root.searchError = String(searchProcess.stderr.text || "").trim() || pluginApi?.tr("search.failed") || "Search failed.";
      }

      root.runningSearchQuery = "";
      root.runningSearchProvider = "";

      if (root.pendingSearchQuery && (root.pendingSearchRestart || root.pendingSearchQuery !== completedQuery)) {
        var nextQuery = root.pendingSearchQuery;
        root.pendingSearchQuery = "";
        root.pendingSearchRestart = false;
        root.startSearch(nextQuery);
        return;
      }

      if (launcher) {
        launcher.updateResults();
      }
    }
  }

  Connections {
    target: mainInstance

    function onIsPlayingChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onIsPausedChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onCurrentSortByChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onPlaylistEntriesChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onCurrentProviderChanged() {
      root.searchEpoch += 1;
      root.searchResults = [];
      root.lastCompletedQuery = "";
      root.searchError = "";
      if (root.searchBusy && root.activeSearchQuery.length > 0) {
        if (root.pendingSearchQuery.length === 0) {
          root.pendingSearchQuery = root.activeSearchQuery;
        }
        root.pendingSearchRestart = true;
      }
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onLibraryEntriesChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onLastErrorChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }

    function onLastNoticeChanged() {
      if (launcher) {
        launcher.updateResults();
      }
    }
  }

  function handleCommand(searchText) {
    return searchText.startsWith(commandName);
  }

  function commands() {
    return [
          {
            "name": commandName,
            "description": pluginApi?.tr("command.description", {"provider": mainInstance?.providerLabel() || "YouTube"}) || ("Search music (" + (mainInstance?.providerLabel() || "YouTube") + "), play audio, and save favorites."),
            "icon": "music",
            "isTablerIcon": true,
            "isImage": false,
            "onActivate": function () {
              launcher.setSearchText(commandName + " ");
            }
          }
        ];
  }

  function normalizeToken(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  }

  function looksLikeUrl(value) {
    var trimmed = String(value || "").trim();
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed) || /^www\./i.test(trimmed);
  }

  function parseSearchProviderQuery(query) {
    var raw = String(query || "");
    var match = raw.match(/^(yt|youtube|sc|soundcloud|local):\s*(.*)$/i);
    if (!match) {
      return {
        "provider": mainInstance?.currentProvider || "youtube",
        "query": raw,
        "explicit": false
      };
    }

    var prefix = String(match[1] || "").toLowerCase();
    var provider = "youtube";
    if (prefix === "sc" || prefix === "soundcloud") {
      provider = "soundcloud";
    } else if (prefix === "local") {
      provider = "local";
    }

    return {
      "provider": provider,
      "query": String(match[2] || "").trim(),
      "explicit": true
    };
  }

  function formatRating(rating) {
    var r = Number(rating || 0);
    if (r <= 0) return "";
    var stars = "";
    for (var i = 0; i < r; i++) stars += "\u2605";
    return stars;
  }

  function formatPlayCount(count) {
    var plays = Number(count || 0);
    if (!isFinite(plays) || plays <= 0) {
      return "";
    }
    return plays === 1 ? (pluginApi?.tr("common.onePlay") || "1 play") : (pluginApi?.tr("common.plays", {"count": plays}) || (plays + " plays"));
  }

  function buildDescription(entry, prefix) {
    var parts = [];
    if (prefix) {
      parts.push(prefix);
    }
    if (mainInstance?.showUploaderMetadata !== false && entry.uploader) {
      parts.push(entry.uploader);
    }
    if (mainInstance?.showAlbumMetadata !== false && entry.album) {
      parts.push(entry.album);
    }
    var durationLabel = MusicUtils.formatDuration(entry.duration);
    if (mainInstance?.showDurationMetadata !== false && durationLabel) {
      parts.push(durationLabel);
    }
    var ratingLabel = formatRating(entry.rating);
    if (mainInstance?.showRatingMetadata !== false && ratingLabel) {
      parts.push(ratingLabel);
    }
    var tags = entry.tags || [];
    if (mainInstance?.showTagMetadata !== false && tags.length > 0) {
      parts.push(tags.map(function(t) { return "#" + t; }).join(" "));
    }
    return parts.join(" • ");
  }

  function buildSectionItem(name, description, icon) {
    return {
      "id": "section:" + String(name || "").toLowerCase(),
      "name": name,
      "description": description || "",
      "icon": icon || "music",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "section",
      "onActivate": function () {}
    };
  }

  function buildLibraryResultItem(entry, options) {
    var title = entry?.title || entry?.name || pluginApi?.tr("common.untitled") || "Untitled";
    var description = options?.description || buildDescription(entry, options?.prefix || pluginApi?.tr("library.saved") || "Saved");
    var isCurrent = ((entry?.id && entry?.id === mainInstance?.currentEntryId) || (!!entry?.url && entry?.url === mainInstance?.currentUrl));
    var activePlayback = mainInstance?.isPlaying === true || mainInstance?.playbackStarting === true;
    var icon = options?.icon || (isCurrent && activePlayback ? "disc" : "bookmark");
    var kind = options?.kind || "library";

    return {
      "id": entry?.id || "",
      "name": title,
      "description": description,
      "icon": icon,
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": kind,
      "url": entry?.url || "",
      "uploader": entry?.uploader || "",
      "duration": entry?.duration || 0,
      "savedAt": entry?.savedAt || "",
      "providerName": entry?.provider || "",
      "album": entry?.album || "",
      "localPath": entry?.localPath || "",
      "tags": entry?.tags || [],
      "rating": entry?.rating || 0,
      "playCount": entry?.playCount || 0,
      "lastPlayedAt": entry?.lastPlayedAt || "",
      "playlistId": options?.playlistId || entry?.playlistId || "",
      "onActivate": function () {
        if (launcher) {
          launcher.close();
        }
        mainInstance?.playEntry(entry);
      }
    };
  }

  function parseTagTerms(tagQuery) {
    var seen = ({});
    var terms = [];
    var rawTerms = String(tagQuery || "").split(/\s+/);

    for (var i = 0; i < rawTerms.length; i++) {
      var normalized = normalizeTagValue(rawTerms[i]);
      var key = normalized.toLowerCase();
      if (key.length === 0 || seen[key]) {
        continue;
      }
      seen[key] = true;
      terms.push(normalized);
    }

    return terms;
  }

  function parseNumericComparison(value) {
    var trimmed = String(value || "").trim();
    var match = trimmed.match(/^(<=|>=|=|<|>)?\s*(-?\d+(?:\.\d+)?)$/);
    if (!match) {
      return null;
    }
    return {
      "operator": match[1] || "=",
      "value": Number(match[2])
    };
  }

  function matchesNumericComparison(actual, comparison) {
    if (!comparison) {
      return true;
    }
    var number = Number(actual || 0);
    var target = Number(comparison.value || 0);
    if (!isFinite(number) || !isFinite(target)) {
      return false;
    }
    if (comparison.operator === ">") {
      return number > target;
    }
    if (comparison.operator === ">=") {
      return number >= target;
    }
    if (comparison.operator === "<") {
      return number < target;
    }
    if (comparison.operator === "<=") {
      return number <= target;
    }
    return number === target;
  }

  function parseRecentWindow(value) {
    var trimmed = String(value || "").trim().toLowerCase();
    var match = trimmed.match(/^(\d+)([smhdwy])?$/);
    if (!match) {
      return 0;
    }
    var amount = Number(match[1] || 0);
    var unit = match[2] || "d";
    var secondsPerUnit = 86400;
    if (unit === "s") secondsPerUnit = 1;
    else if (unit === "m") secondsPerUnit = 60;
    else if (unit === "h") secondsPerUnit = 3600;
    else if (unit === "d") secondsPerUnit = 86400;
    else if (unit === "w") secondsPerUnit = 604800;
    else if (unit === "y") secondsPerUnit = 31536000;
    return amount > 0 ? amount * secondsPerUnit : 0;
  }

  function isStructuredLibraryFilterToken(token) {
    var lower = String(token || "").toLowerCase();
    return lower.startsWith("rating:")
        || lower.startsWith("plays:")
        || lower.startsWith("playcount:")
        || lower.startsWith("recent:")
        || lower.startsWith("album:")
        || lower.startsWith("provider:")
        || lower.startsWith("saved:")
        || lower.startsWith("tag:")
        || lower.startsWith("#");
  }

  function parseSavedFilterValue(value) {
    var normalized = String(value || "").trim().toLowerCase();
    if (["true", "yes", "1", "saved"].indexOf(normalized) >= 0) {
      return true;
    }
    if (["false", "no", "0", "unsaved", "playlist-only"].indexOf(normalized) >= 0) {
      return false;
    }
    if (["any", "all", "*"].indexOf(normalized) >= 0) {
      return "any";
    }
    return null;
  }

  function parseLibraryFilterQuery(query) {
    var rawTerms = String(query || "").trim().split(/\s+/).filter(function (term) {
      return String(term || "").trim().length > 0;
    });
    var parsed = {
      "hasStructuredFilters": false,
      "textQuery": "",
      "textTerms": [],
      "tagTerms": [],
      "albumTerms": [],
      "provider": "",
      "saved": null,
      "rating": null,
      "plays": null,
      "recentSeconds": 0,
      "includeHidden": false
    };

    for (var i = 0; i < rawTerms.length; i++) {
      var token = String(rawTerms[i] || "");
      var lower = token.toLowerCase();

      if (token.startsWith("#")) {
        var hashTag = normalizeTagValue(token.substring(1));
        if (hashTag.length > 0) {
          parsed.tagTerms.push(hashTag);
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("tag:")) {
        var tagValue = normalizeTagValue(token.substring(4));
        if (tagValue.length > 0) {
          parsed.tagTerms.push(tagValue);
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("album:")) {
        var albumValue = String(token.substring(6) || "").trim();
        while (i + 1 < rawTerms.length && !isStructuredLibraryFilterToken(rawTerms[i + 1])) {
          albumValue += (albumValue.length > 0 ? " " : "") + String(rawTerms[i + 1] || "").trim();
          i += 1;
        }
        albumValue = String(albumValue || "").trim();
        if (albumValue.length > 0) {
          parsed.albumTerms.push(albumValue);
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("provider:")) {
        var providerValue = String(token.substring(9) || "").trim().toLowerCase();
        if (["youtube", "soundcloud", "local"].indexOf(providerValue) >= 0) {
          parsed.provider = providerValue;
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("saved:")) {
        var savedValue = parseSavedFilterValue(token.substring(6));
        if (savedValue !== null) {
          parsed.saved = savedValue;
          parsed.includeHidden = savedValue === false || savedValue === "any";
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("rating:")) {
        var ratingComparison = parseNumericComparison(token.substring(7));
        if (ratingComparison) {
          parsed.rating = ratingComparison;
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("plays:")) {
        var playsComparison = parseNumericComparison(token.substring(6));
        if (playsComparison) {
          parsed.plays = playsComparison;
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("playcount:")) {
        var playCountComparison = parseNumericComparison(token.substring(10));
        if (playCountComparison) {
          parsed.plays = playCountComparison;
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      if (lower.startsWith("recent:")) {
        var recentSeconds = parseRecentWindow(token.substring(7));
        if (recentSeconds > 0) {
          parsed.recentSeconds = recentSeconds;
          parsed.hasStructuredFilters = true;
          continue;
        }
      }

      parsed.textTerms.push(token);
    }

    parsed.textQuery = parsed.textTerms.join(" ").trim();
    return parsed;
  }

  function libraryFilterQueryActive(query) {
    return parseLibraryFilterQuery(query).hasStructuredFilters;
  }

  function entryActivityTimestamp(entry) {
    var activity = String(entry?.lastPlayedAt || entry?.savedAt || "").trim();
    if (activity.length === 0) {
      return 0;
    }
    var parsed = Date.parse(activity);
    return isFinite(parsed) ? parsed : 0;
  }

  function entryMatchesLibraryFilters(entry, filters) {
    if (!entry) {
      return false;
    }

    if (filters.saved === true && entry.isSaved === false) {
      return false;
    }
    if (filters.saved === false && entry.isSaved !== false) {
      return false;
    }

    if (filters.provider.length > 0 && String(entry.provider || "").trim().toLowerCase() !== filters.provider) {
      return false;
    }

    if (!matchesNumericComparison(entry.rating, filters.rating)) {
      return false;
    }

    if (!matchesNumericComparison(entry.playCount, filters.plays)) {
      return false;
    }

    if (filters.recentSeconds > 0) {
      var activityTime = entryActivityTimestamp(entry);
      if (activityTime <= 0) {
        return false;
      }
      var ageSeconds = (Date.now() - activityTime) / 1000;
      if (ageSeconds > filters.recentSeconds) {
        return false;
      }
    }

    if (filters.albumTerms.length > 0) {
      var albumText = String(entry.album || "").toLowerCase();
      for (var i = 0; i < filters.albumTerms.length; i++) {
        if (albumText.indexOf(String(filters.albumTerms[i] || "").toLowerCase()) === -1) {
          return false;
        }
      }
    }

    if (filters.tagTerms.length > 0 && !entryMatchesTagTerms(entry, filters.tagTerms)) {
      return false;
    }

    return true;
  }

  function entryMatchesTagTerms(entry, tagTerms) {
    if (!entry || tagTerms.length === 0) {
      return false;
    }

    var normalizedTags = (entry.tags || []).map(function (tag) {
      return normalizeTagValue(tag).toLowerCase();
    });

    for (var i = 0; i < tagTerms.length; i++) {
      var term = normalizeTagValue(tagTerms[i]).toLowerCase();
      var matchedTerm = false;
      for (var j = 0; j < normalizedTags.length; j++) {
        if (normalizedTags[j].indexOf(term) === 0 || normalizedTags[j].indexOf(term) >= 0) {
          matchedTerm = true;
          break;
        }
      }
      if (!matchedTerm) {
        return false;
      }
    }

    return true;
  }

  function collectTagStats() {
    var seen = ({});
    var stats = [];
    var library = mainInstance?.visibleLibraryEntries() || [];

    for (var i = 0; i < library.length; i++) {
      var entryTags = library[i].tags || [];
      for (var j = 0; j < entryTags.length; j++) {
        var normalizedTag = normalizeTagValue(entryTags[j]);
        var key = normalizedTag.toLowerCase();
        if (key.length === 0) {
          continue;
        }
        if (!seen[key]) {
          seen[key] = {
            "tag": normalizedTag,
            "count": 0
          };
          stats.push(seen[key]);
        }
        seen[key].count += 1;
      }
    }

    stats.sort(function (a, b) {
      if (b.count !== a.count) {
        return b.count - a.count;
      }
      return a.tag.localeCompare(b.tag);
    });
    return stats;
  }

  function collectKnownTags() {
    return collectTagStats().map(function (item) {
      return item.tag;
    });
  }

  function collectArtistStats() {
    var seen = ({});
    var stats = [];
    var library = mainInstance?.visibleLibraryEntries() || [];

    for (var i = 0; i < library.length; i++) {
      var artist = String(library[i].uploader || "").trim();
      var key = artist.toLowerCase();
      if (key.length === 0) {
        continue;
      }
      if (!seen[key]) {
        seen[key] = {
          "name": artist,
          "count": 0,
          "playCount": 0,
          "lastPlayedAt": ""
        };
        stats.push(seen[key]);
      }
      seen[key].count += 1;
      seen[key].playCount += Number(library[i].playCount || 0);
      var playedAt = String(library[i].lastPlayedAt || "");
      if (playedAt.length > 0 && playedAt > seen[key].lastPlayedAt) {
        seen[key].lastPlayedAt = playedAt;
      }
    }

    stats.sort(function (a, b) {
      if (b.count !== a.count) {
        return b.count - a.count;
      }
      if (b.playCount !== a.playCount) {
        return b.playCount - a.playCount;
      }
      return a.name.localeCompare(b.name);
    });
    return stats;
  }

  function recentPlayedEntries(limit) {
    var library = (mainInstance?.visibleLibraryEntries() || []).filter(function (entry) {
      return String(entry.lastPlayedAt || "").trim().length > 0;
    }).slice();

    library.sort(function (a, b) {
      return String(b.lastPlayedAt || "").localeCompare(String(a.lastPlayedAt || ""));
    });

    return limit > 0 ? library.slice(0, limit) : library;
  }

  function topPlayedEntries(limit) {
    var library = (mainInstance?.visibleLibraryEntries() || []).filter(function (entry) {
      return Number(entry.playCount || 0) > 0;
    }).slice();

    library.sort(function (a, b) {
      if (Number(b.playCount || 0) !== Number(a.playCount || 0)) {
        return Number(b.playCount || 0) - Number(a.playCount || 0);
      }
      return String(b.lastPlayedAt || "").localeCompare(String(a.lastPlayedAt || ""));
    });

    return limit > 0 ? library.slice(0, limit) : library;
  }

  function buildTagBrowseItem(tagStat) {
    var tagName = String(tagStat?.tag || "").trim();
    var count = Number(tagStat?.count || 0);
    return {
      "id": "tag-browse:" + tagName.toLowerCase(),
      "name": "#" + tagName,
      "description": count === 1 ? (pluginApi?.tr("library.oneTrack") || "1 saved track") : (pluginApi?.tr("library.trackCount", {"count": count}) || (count + " saved tracks")),
      "icon": "tag",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "tag-browse",
      "onActivate": function () {
        if (launcher) {
          launcher.setSearchText(commandName + " #" + tagName);
        }
      }
    };
  }

  function buildArtistBrowseItem(artistStat) {
    var artistName = String(artistStat?.name || "").trim();
    var count = Number(artistStat?.count || 0);
    var parts = [count === 1 ? (pluginApi?.tr("library.oneTrack") || "1 saved track") : (pluginApi?.tr("library.trackCount", {"count": count}) || (count + " saved tracks"))];
    var playCountLabel = formatPlayCount(artistStat?.playCount || 0);
    if (playCountLabel) {
      parts.push(playCountLabel);
    }
    return {
      "id": "artist-browse:" + artistName.toLowerCase(),
      "name": artistName,
      "description": parts.join(" • "),
      "icon": "microphone-2",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "artist-browse",
      "onActivate": function () {
        if (launcher) {
          launcher.setSearchText(commandName + " artist:" + artistName);
        }
      }
    };
  }

  function buildSavedBrowseItem() {
    var savedCount = (mainInstance?.visibleLibraryEntries() || []).length;
    return {
      "id": "saved-browse",
      "name": pluginApi?.tr("library.savedTracks") || "Saved tracks",
      "description": savedCount === 0 ? (pluginApi?.tr("library.libraryEmpty") || "Your library is empty.") : (savedCount === 1 ? (pluginApi?.tr("library.oneTrack") || "1 saved track") : (pluginApi?.tr("library.trackCount", {"count": savedCount}) || (savedCount + " saved tracks"))),
      "icon": "bookmark",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "saved-browse",
      "onActivate": function () {
        if (launcher) {
          launcher.setSearchText(commandName + " saved:");
        }
      }
    };
  }

  function buildImportFolderPromptItem() {
    return {
      "id": "import-folder-prompt",
      "name": pluginApi?.tr("import.title") || "Import folder as playlist",
      "description": pluginApi?.tr("import.desc") || "Use `import: /path/to/folder` to turn local audio into a playlist.",
      "icon": "folder-plus",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "import-folder-prompt",
      "onActivate": function () {
        if (launcher) {
          launcher.setSearchText(commandName + " import: ");
        }
      }
    };
  }

  function buildImportFolderItem(folderPath) {
    var targetFolder = String(folderPath || "").trim();
    var segments = targetFolder.split("/").filter(function (part) { return part.length > 0; });
    var playlistName = segments.length > 0 ? segments[segments.length - 1] : targetFolder;
    return {
      "id": "import-folder:" + targetFolder,
      "name": pluginApi?.tr("import.title") || "Import folder as playlist",
      "description": playlistName.length > 0
          ? (pluginApi?.tr("import.createPlaylist", {"name": playlistName, "path": targetFolder}) || ("Create playlist \"" + playlistName + "\" from " + targetFolder))
          : targetFolder,
      "icon": "folder-plus",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "import-folder",
      "folderPath": targetFolder,
      "_score": 9,
      "onActivate": function () {
        mainInstance?.importFolderAsPlaylist(targetFolder, "");
      }
    };
  }

  function buildSpeedItem(value) {
    var target = Number(value);
    var speedLabel = isFinite(target) ? target.toFixed(2) + "x" : String(value || "");
    return {
      "id": "speed:" + speedLabel,
      "name": pluginApi?.tr("speed.setTo", {"speed": speedLabel}) || ("Set speed to " + speedLabel),
      "description": pluginApi?.tr("speed.desc") || "Adjust current playback speed.",
      "icon": "gauge",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "speed",
      "onActivate": function () {
        mainInstance?.setSpeed(target);
      }
    };
  }

  function buildSpeedItems(speedQuery) {
    if (mainInstance?.isPlaying !== true) {
      return [
            buildSearchHintItem(pluginApi?.tr("speed.noPlayback") || "Start playback first, then use `speed:1.05` or the preview buttons.")
          ];
    }

    var currentSpeed = Number(mainInstance?.currentSpeed || 1);
    var queryText = String(speedQuery || "").trim();
    var items = [
          buildSectionItem(pluginApi?.tr("speed.title") || "Playback Speed", pluginApi?.tr("speed.current", {"speed": currentSpeed.toFixed(2) + "x"}) || ("Current: " + currentSpeed.toFixed(2) + "x"), "gauge")
        ];

    if (queryText.length === 0) {
      var presets = [0.90, 0.95, 1.00, 1.05, 1.10, 1.25];
      for (var i = 0; i < presets.length; i++) {
        items.push(buildSpeedItem(presets[i]));
      }
      return items;
    }

    var target = Number(queryText);
    if (!isFinite(target)) {
      items.push(buildSearchHintItem(pluginApi?.tr("speed.useNumber") || "Use a number like `speed:1.05`."));
      return items;
    }

    target = Math.max(0.25, Math.min(4, target));
    items.push(buildSpeedItem(target));
    return items;
  }

  function buildQueueActionItem(name, description, icon, score, activate) {
    return {
      "id": "queue-action:" + String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-"),
      "name": name,
      "description": description,
      "icon": icon,
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "queue-action",
      "_score": score || 0,
      "onActivate": activate
    };
  }

  function buildQueueEntryItem(entry, index) {
    var prefix = index === 0 ? "Next up" : "Queued";
    return {
      "id": entry?.id || ("queue:" + index),
      "name": entry?.title || pluginApi?.tr("common.untitled") || "Untitled",
      "description": buildDescription(entry, prefix),
      "icon": index === 0 ? "player-track-next" : "playlist",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "queue-entry",
      "url": entry?.url || "",
      "uploader": entry?.uploader || "",
      "duration": entry?.duration || 0,
      "providerName": entry?.provider || "",
      "queuedAt": entry?.queuedAt || "",
      "position": index,
      "onActivate": function () {
        if (launcher) {
          launcher.close();
        }
        mainInstance?.playQueueEntryNow(entry);
      }
    };
  }

  function buildQueueItems(queueQuery) {
    var queryText = String(queueQuery || "").trim().toLowerCase();
    var queueEntries = mainInstance?.queueEntries || [];
    var queuedCount = queueEntries.length;
    var items = [
          buildSectionItem("Queue",
                           mainInstance?.lastError
                               ? ("Last error: " + mainInstance.lastError)
                               : (mainInstance?.lastNotice || (mainInstance?.queueActive ? "Queue is active and waiting for the next finish." : "Queue is idle.")),
                           mainInstance?.queueActive ? "list-check" : "playlist")
        ];

    if (queryText === "start") {
      items.push(buildQueueActionItem("Start queue", "Begin queued playback now.", "player-play", 20, function () {
                                        mainInstance?.startQueue();
                                        if (launcher) {
                                          launcher.close();
                                        }
                                      }));
      return items;
    }

    if (queryText === "stop") {
      items.push(buildQueueActionItem("Stop queue", "Pause queue mode without clearing the list.", "player-pause", 19, function () {
                                        mainInstance?.stopQueue();
                                      }));
      return items;
    }

    if (queryText === "skip") {
      items.push(buildQueueActionItem("Skip to next", "Start the next queued track now.", "player-skip-forward", 18, function () {
                                        mainInstance?.skipQueue();
                                      }));
      return items;
    }

    if (queryText === "clear") {
      items.push(buildQueueActionItem("Clear queue", "Remove all queued tracks.", "trash", 18, function () {
                                        mainInstance?.clearQueue();
                                      }));
      return items;
    }

    if (queryText === "saved" || queryText === "library" || queryText === "autoplay") {
      items.push(buildQueueActionItem("Autoplay saved tracks", "Load the saved library into queue and start playing it.", "bookmark", 17, function () {
                                        mainInstance?.autoplaySavedTracks(false);
                                        if (launcher) {
                                          launcher.close();
                                        }
                                      }));
      return items;
    }

    if (queryText === "saved shuffle" || queryText === "library shuffle" || queryText === "autoplay shuffle" || queryText === "shuffle saved") {
      items.push(buildQueueActionItem("Autoplay saved tracks (shuffle)", "Shuffle the saved library into queue and start playing it.", "arrows-shuffle", 16, function () {
                                        mainInstance?.autoplaySavedTracks(true);
                                        if (launcher) {
                                          launcher.close();
                                        }
                                      }));
      return items;
    }

    items.push(buildQueueActionItem("Start queue", "Arm the queue or start the first queued track.", "player-play", 8, function () {
                                      mainInstance?.startQueue();
                                    }));
    items.push(buildQueueActionItem("Stop queue", "Disable auto-advance and keep queued tracks.", "player-pause", 7, function () {
                                      mainInstance?.stopQueue();
                                    }));
    items.push(buildQueueActionItem("Skip to next", "Jump to the next queued track.", "player-skip-forward", 7, function () {
                                      mainInstance?.skipQueue();
                                    }));
    items.push(buildQueueActionItem("Autoplay saved tracks", "Turn your saved music library into the active queue.", "bookmark", 6, function () {
                                      mainInstance?.autoplaySavedTracks(false);
                                    }));
    items.push(buildQueueActionItem("Autoplay saved tracks (shuffle)", "Shuffle your saved music library into the active queue.", "arrows-shuffle", 5, function () {
                                      mainInstance?.autoplaySavedTracks(true);
                                    }));
    items.push(buildQueueActionItem("Clear queue", "Empty the queue list.", "trash", 6, function () {
                                      mainInstance?.clearQueue();
                                    }));

    if (queuedCount === 0) {
      items.push({
                   "id": "queue-empty",
                   "name": "Queue is empty",
                   "description": "Use save, playlists, or inline queue actions to add tracks.",
                   "icon": "playlist-off",
                   "isTablerIcon": true,
                   "isImage": false,
                   "provider": root,
                   "kind": "queue-empty",
                   "onActivate": function () {}
                 });
      return items;
    }

    for (var i = 0; i < queueEntries.length; i++) {
      items.push(buildQueueEntryItem(queueEntries[i], i));
    }

    return items;
  }

  function buildHomeItems() {
    var items = [];
    var recentEntries = recentPlayedEntries(3);
    var topEntries = topPlayedEntries(3);
    var tagStats = collectTagStats().slice(0, 4);
    var artistStats = collectArtistStats().slice(0, 4);
    var playlists = (mainInstance?.playlistEntries || []).slice(0, 3);

    items.push(buildSavedBrowseItem());
    items.push(buildImportFolderPromptItem());

    if (mainInstance?.showHomeRecent !== false && recentEntries.length > 0) {
      items.push(buildSectionItem(pluginApi?.tr("home.recentlyPlayed") || "Recently Played", pluginApi?.tr("home.recentlyPlayedDesc") || "Your latest saved listens.", "history"));
      for (var i = 0; i < recentEntries.length; i++) {
        var relativeTime = MusicUtils.formatRelativeTime(recentEntries[i].lastPlayedAt);
        items.push(buildLibraryResultItem(recentEntries[i], {
                                            "prefix": mainInstance?.showPlayStatsMetadata !== false && relativeTime ? ((pluginApi?.tr("home.recent") || "Recent") + " • " + relativeTime) : (pluginApi?.tr("home.recent") || "Recent"),
                                            "icon": recentEntries[i].id === mainInstance?.currentEntryId && mainInstance?.isPlaying ? "disc" : "history"
                                          }));
      }
    }

    if (mainInstance?.showHomeTop !== false && topEntries.length > 0) {
      items.push(buildSectionItem(pluginApi?.tr("home.mostPlayed") || "Most Played", pluginApi?.tr("home.mostPlayedDesc") || "The tracks you come back to most.", "chart-bar"));
      for (var j = 0; j < topEntries.length; j++) {
        items.push(buildLibraryResultItem(topEntries[j], {
                                            "prefix": mainInstance?.showPlayStatsMetadata !== false
                                                ? ((pluginApi?.tr("home.top") || "Top") + " • " + formatPlayCount(topEntries[j].playCount || 0))
                                                : (pluginApi?.tr("home.top") || "Top"),
                                            "icon": topEntries[j].id === mainInstance?.currentEntryId && mainInstance?.isPlaying ? "disc" : "chart-bar"
                                          }));
      }
    }

    if (mainInstance?.showHomeTags !== false && tagStats.length > 0) {
      items.push(buildSectionItem(pluginApi?.tr("home.tags") || "Tags", pluginApi?.tr("home.tagsDesc") || "Browse your library by mood and theme.", "tag"));
      for (var k = 0; k < tagStats.length; k++) {
        items.push(buildTagBrowseItem(tagStats[k]));
      }
    }

    if (mainInstance?.showHomeArtists !== false && artistStats.length > 0) {
      items.push(buildSectionItem(pluginApi?.tr("home.artists") || "Artists", pluginApi?.tr("home.artistsDesc") || "Jump through your saved library by uploader.", "microphone-2"));
      for (var m = 0; m < artistStats.length; m++) {
        items.push(buildArtistBrowseItem(artistStats[m]));
      }
    }

    if (mainInstance?.showHomePlaylists !== false && playlists.length > 0) {
      items.push(buildSectionItem(pluginApi?.tr("home.playlists") || "Playlists", pluginApi?.tr("home.playlistsDesc") || "Quick launch your saved lists.", "playlist"));
      for (var n = 0; n < playlists.length; n++) {
        items.push(buildPlaylistHeaderItem(playlists[n]));
      }
    }

    if (items.length === 0) {
      items = items.concat(buildLibraryItems("", 8));
    }

    return items;
  }

  function buildArtistItems(artistQuery) {
    var queryText = String(artistQuery || "").trim();
    var queryLower = queryText.toLowerCase();
    var artistStats = collectArtistStats();

    if (artistStats.length === 0) {
      return [
            buildSearchHintItem(pluginApi?.tr("artists.noArtists") || "Save tracks with uploader metadata to browse artists here.")
          ];
    }

    if (queryLower.length === 0) {
      return artistStats.map(function (artistStat) {
        return buildArtistBrowseItem(artistStat);
      });
    }

    var matchedArtists = artistStats.filter(function (artistStat) {
      return String(artistStat.name || "").toLowerCase().indexOf(queryLower) >= 0;
    });

    if (matchedArtists.length === 0) {
      return [
            buildSearchHintItem(pluginApi?.tr("artists.noMatch", {"query": queryText}) || ("No saved artists matched \"" + queryText + "\"."))
          ];
    }

    var targetArtist = matchedArtists.length === 1
        ? matchedArtists[0]
        : matchedArtists.find(function (artistStat) {
            return String(artistStat.name || "").toLowerCase() === queryLower;
          });

    if (!targetArtist) {
      return matchedArtists.map(function (artistStat) {
        return buildArtistBrowseItem(artistStat);
      });
    }

    var artistEntries = (mainInstance?.visibleLibraryEntries() || []).filter(function (entry) {
      return String(entry.uploader || "").trim().toLowerCase() === String(targetArtist.name || "").trim().toLowerCase();
    }).slice();

    artistEntries.sort(function (a, b) {
      if (String(b.lastPlayedAt || "") !== String(a.lastPlayedAt || "")) {
        return String(b.lastPlayedAt || "").localeCompare(String(a.lastPlayedAt || ""));
      }
      return String(b.savedAt || "").localeCompare(String(a.savedAt || ""));
    });

    var items = [
          buildSectionItem(targetArtist.name,
                           mainInstance?.showPlayStatsMetadata !== false
                               ? (formatPlayCount(targetArtist.playCount || 0) || (targetArtist.count + " saved tracks"))
                               : (targetArtist.count + " saved tracks"),
                           "microphone-2")
        ];
    for (var i = 0; i < artistEntries.length; i++) {
      var artistPrefix = mainInstance?.showPlayStatsMetadata !== false && String(artistEntries[i].lastPlayedAt || "").length > 0
          ? ((pluginApi?.tr("home.artist") || "Artist") + " • " + MusicUtils.formatRelativeTime(artistEntries[i].lastPlayedAt))
          : (pluginApi?.tr("home.artist") || "Artist");
      items.push(buildLibraryResultItem(artistEntries[i], {
                                          "prefix": artistPrefix,
                                          "icon": artistEntries[i].id === mainInstance?.currentEntryId && mainInstance?.isPlaying ? "disc" : "music"
                                        }));
    }
    return items;
  }

  function itemProviderKey(item) {
    var explicitProvider = String(item?.providerName || "").trim().toLowerCase();
    if (explicitProvider === "youtube" || explicitProvider === "soundcloud" || explicitProvider === "local") {
      return explicitProvider;
    }

    var rawProvider = item?.provider;
    if (typeof rawProvider === "string") {
      var normalizedProvider = String(rawProvider || "").trim().toLowerCase();
      if (normalizedProvider === "youtube" || normalizedProvider === "soundcloud" || normalizedProvider === "local") {
        return normalizedProvider;
      }
    }

    return String(mainInstance?.currentProvider || "youtube");
  }

  function getPreviewData(item) {
    if (!item) {
      return null;
    }

    var previewItem = {};
    for (var key in item) {
      previewItem[key] = item[key];
    }

    previewItem.isSaved = mainInstance?.isSaved(item) === true;
    previewItem.isPlaying = mainInstance?.isPlaying === true && ((item.id && mainInstance?.currentEntryId === item.id) || (!!item.url && mainInstance?.currentUrl === item.url));
    previewItem.isStarting = mainInstance?.playbackStarting === true && ((item.id && mainInstance?.currentEntryId === item.id) || (!!item.url && mainInstance?.currentUrl === item.url));
    previewItem.isPaused = mainInstance?.isPaused === true;
    previewItem.currentUrl = mainInstance?.currentUrl || "";
    previewItem.lastError = mainInstance?.lastError || "";
    previewItem.helperPath = helperPath;
    previewItem.previewDelayMs = 500;
    previewItem.previewMetadataMode = mainInstance?.previewMetadataMode || pluginApi?.pluginSettings?.previewMetadataMode || pluginApi?.manifest?.metadata?.defaultSettings?.previewMetadataMode || "always";
    previewItem.sourceLabel = item.kind === "library"
        ? (pluginApi?.tr("library.label") || "Library")
        : (item.kind === "queue-entry"
               ? "Queue"
        : (item.kind === "search"
               ? (mainInstance?.providerLabel(itemProviderKey(item)) || "YouTube")
               : (item.kind === "custom-url" || item.kind === "save-url" ? (pluginApi?.tr("common.customUrl") || "Custom URL") : (pluginApi?.tr("common.music") || "music-search"))));
    return previewItem;
  }

  function getResults(searchText) {
    if (!searchText.startsWith(commandName)) {
      return [];
    }

    var query = searchText.substring(commandName.length).trim();
    var commandQuery = normalizeToken(query);
    var rawQueryLower = String(query || "").toLowerCase();
    var results = [];

    if (root.playlistPickerEntryId.length > 0 && !rawQueryLower.startsWith("playlist:")) {
      root.clearPlaylistSelection();
    }
    if (root.playlistRenameId.length > 0 && !rawQueryLower.startsWith("playlist:")) {
      root.clearPlaylistRename();
    }
    if (root.tagEditorEntryId.length > 0 && !rawQueryLower.startsWith("tag:")) {
      root.clearTagEditor();
    }
    if (root.metadataEditorEntryId.length > 0 && !rawQueryLower.startsWith("edit:")) {
      root.clearMetadataEditor();
    }

    results.push(buildStatusItem());

    if ((mainInstance?.isPlaying || mainInstance?.playbackStarting) && (query.length === 0 || (commandQuery.length > 0 && "stop".indexOf(commandQuery) === 0))) {
      results.push(buildStopItem());
    }

    if (commandQuery === "stop") {
      if (!mainInstance?.isPlaying && !mainInstance?.playbackStarting) {
        results.push(buildIdleStopItem());
      }
      return results;
    }

    if (query.length === 0) {
      results = results.concat(buildHomeItems());
      results.push(buildSearchHintItem());
      return results;
    }

    if (rawQueryLower.startsWith("saved:") && !libraryFilterQueryActive(query)) {
      var savedQuery = query.substring(6).trim();
      var libraryCount = (mainInstance?.visibleLibraryEntries() || []).length;
      results = results.concat(buildLibraryItems(savedQuery, savedQuery.length > 0 ? Math.max(libraryCount, 1) : 0));
      if (results.length <= 1) {
        results.push(buildSearchHintItem(savedQuery.length > 0
                                             ? (pluginApi?.tr("library.noMatches", {"query": savedQuery}) || ("No saved tracks matched \"" + savedQuery + "\"."))
                                             : (pluginApi?.tr("library.savedEmpty") || "Your saved library is empty.")));
      }
      return results;
    }

    if (rawQueryLower.startsWith("speed:")) {
      var speedQuery = query.substring(6).trim();
      results = results.concat(buildSpeedItems(speedQuery));
      return results;
    }

    if (rawQueryLower === "queue" || rawQueryLower.startsWith("queue ")) {
      var queueQuery = rawQueryLower === "queue" ? "" : query.substring(6).trim();
      results = results.concat(buildQueueItems(queueQuery));
      return results;
    }

    if (query.startsWith("#")) {
      var tagQuery = query.substring(1).trim();
      if (tagQuery.length > 0) {
        results = results.concat(buildTagFilteredItems(tagQuery));
      }
      if (results.length <= 1) {
        results.push(buildSearchHintItem(pluginApi?.tr("library.noTagged", {"tag": tagQuery}) || ("No tracks tagged \"" + tagQuery + "\".")));
      }
      return results;
    }

    if (rawQueryLower.startsWith("tag:")) {
      var manageTagQuery = query.substring(4).trim();
      results = results.concat(buildTagEditorItems(manageTagQuery));
      return results;
    }

    if (rawQueryLower.startsWith("edit:")) {
      var editQuery = query.substring(5).trim();
      results = results.concat(buildMetadataEditorItems(editQuery));
      return results;
    }

    if (rawQueryLower.startsWith("import:")) {
      var importFolderQuery = query.substring(7).trim();
      if (importFolderQuery.length === 0) {
        results.push(buildImportFolderPromptItem());
        results.push(buildSearchHintItem(pluginApi?.tr("import.hint") || "Type `import: /path/to/folder` to import local audio files as a playlist."));
        return results;
      }
      results.push(buildImportFolderItem(importFolderQuery));
      return results;
    }

    if (rawQueryLower.startsWith("playlist:")) {
      var playlistQuery = query.substring(9).trim();
      results = results.concat(root.playlistRenameId
                                   ? buildPlaylistRenameItems(playlistQuery)
                                   : (root.playlistPickerEntryId ? buildPlaylistPickerItems(playlistQuery) : buildPlaylistItems(playlistQuery)));
      return results;
    }

    if (rawQueryLower.startsWith("artist:")) {
      var artistQuery = query.substring(7).trim();
      results = results.concat(buildArtistItems(artistQuery));
      return results;
    }

    if (looksLikeUrl(query)) {
      results.push(buildPlayUrlItem(query));
      results.push(buildSaveUrlItem(query));
      results.push(buildDownloadUrlItem(query));
      results = results.concat(buildLibraryItems(query, 4));
      return results;
    }

    if (libraryFilterQueryActive(query)) {
      var filterLibraryCount = (mainInstance?.libraryEntries || []).length;
      results = results.concat(buildLibraryItems(query, filterLibraryCount > 0 ? filterLibraryCount : 0));
      if (results.length <= 1) {
        results.push(buildSearchHintItem(pluginApi?.tr("library.noFilterMatches") || "No saved tracks matched your filters."));
      }
      return results;
    }

    var searchContext = parseSearchProviderQuery(query);
    var searchQuery = String(searchContext.query || "").trim();
    var searchProvider = String(searchContext.provider || mainInstance?.currentProvider || "youtube");
    var searchProviderLabel = mainInstance?.providerLabel(searchProvider) || "YouTube";

    if (searchContext.explicit && searchQuery.length === 0) {
      results.push(buildSearchHintItem(pluginApi?.tr("search.typeMore", {"provider": searchProviderLabel}) || ("Type at least 2 characters to search " + searchProviderLabel + ".")));
      return results;
    }

    results = results.concat(buildLibraryItems(searchQuery, 5));

    if (searchQuery.length < 2) {
      results.push(buildSearchHintItem(pluginApi?.tr("search.typeMore", {"provider": searchProviderLabel}) || ("Type at least 2 characters to search " + searchProviderLabel + ".")));
      return results;
    }

    ensureSearch(query);

    if (searchBusy && lastCompletedQuery !== query) {
      results.push(buildLoadingItem(searchQuery, searchProvider));
      return results;
    }

    if (lastCompletedQuery === query && searchError) {
      results.push(buildSearchErrorItem(searchError));
      return results;
    }

    if (lastCompletedQuery === query) {
      for (var i = 0; i < searchResults.length; i++) {
        results.push(buildSearchResultItem(searchResults[i]));
      }
    }

    if (results.length === 1 || (results.length === 2 && results[1].kind === "loading")) {
      results.push(buildSearchHintItem(pluginApi?.tr("search.noResults", {"query": searchQuery}) || ("No saved or search results for \"" + searchQuery + "\".")));
    }

    return results;
  }

  function ensureSearch(query) {
    if (query === lastCompletedQuery && !searchBusy) {
      return;
    }

    if (searchBusy) {
      pendingSearchQuery = query;
      return;
    }

    startSearch(query);
  }

  function startSearch(query) {
    if (!helperPath) {
      return;
    }

    var searchContext = parseSearchProviderQuery(query);
    var provider = searchContext.provider;
    var resolvedQuery = String(searchContext.query || "").trim();
    activeSearchQuery = query;
    pendingSearchQuery = "";
    pendingSearchRestart = false;
    searchBusy = true;
    runningSearchQuery = query;
    runningSearchProvider = provider;
    runningSearchEpoch = searchEpoch;
    searchProcess.exec({
                         "command": ["bash", helperPath, "search", resolvedQuery, provider]
                       });
  }

  function clearPlaylistSelection() {
    playlistPickerEntryId = "";
    playlistPickerEntryTitle = "";
  }

  function clearPlaylistRename() {
    playlistRenameId = "";
    playlistRenameTitle = "";
  }

  function clearTagEditor() {
    tagEditorEntryId = "";
    tagEditorEntryTitle = "";
  }

  function clearMetadataEditor() {
    metadataEditorEntryId = "";
    metadataEditorEntryTitle = "";
    metadataEditorField = "";
  }

  function startPlaylistSelection(entry) {
    var savedEntry = mainInstance?.findSavedEntry(entry);
    var targetEntry = savedEntry || entry;
    var entryId = String(targetEntry?.id || "").trim();
    if (entryId.length === 0) {
      return;
    }

    playlistPickerEntryId = entryId;
    playlistPickerEntryTitle = targetEntry?.title || targetEntry?.name || pluginApi?.tr("common.untitled") || "Untitled";
    root.clearPlaylistRename();
    root.clearMetadataEditor();
    if (launcher) {
      launcher.setSearchText(commandName + " playlist:");
    }
  }

  function startPlaylistRename(playlist) {
    var playlistId = String(playlist?.id || "").trim();
    if (playlistId.length === 0) {
      return;
    }

    playlistRenameId = playlistId;
    playlistRenameTitle = playlist?.name || pluginApi?.tr("playlists.untitled") || "Untitled Playlist";
    root.clearPlaylistSelection();
    root.clearMetadataEditor();
    if (launcher) {
      launcher.setSearchText(commandName + " playlist:" + playlistRenameTitle);
    }
  }

  function normalizeTagValue(value) {
    return String(value || "").replace(/^#+/, "").replace(/\s+/g, " ").trim();
  }

  function currentTagEditorEntry() {
    if (tagEditorEntryId.length === 0) {
      return null;
    }

    var library = mainInstance?.visibleLibraryEntries() || [];
    for (var i = 0; i < library.length; i++) {
      if (String(library[i].id || "") === tagEditorEntryId) {
        return library[i];
      }
    }

    return null;
  }

  function entryHasTag(entry, tag) {
    var normalizedTag = normalizeTagValue(tag).toLowerCase();
    if (!entry || normalizedTag.length === 0) {
      return false;
    }

    var tags = entry.tags || [];
    for (var i = 0; i < tags.length; i++) {
      if (normalizeTagValue(tags[i]).toLowerCase() === normalizedTag) {
        return true;
      }
    }

    return false;
  }

  function startTagEditing(entry) {
    var savedEntry = mainInstance?.findSavedEntry(entry);
    var targetEntry = savedEntry || entry;
    var entryId = String(targetEntry?.id || "").trim();
    if (entryId.length === 0) {
      return;
    }

    tagEditorEntryId = entryId;
    tagEditorEntryTitle = targetEntry?.title || targetEntry?.name || pluginApi?.tr("common.untitled") || "Untitled";
    root.clearMetadataEditor();
    if (launcher) {
      launcher.setSearchText(commandName + " tag:");
    }
  }

  function metadataFieldLabel(field) {
    var normalized = String(field || "").trim().toLowerCase();
    if (normalized === "title") return pluginApi?.tr("metadata.titleField") || "Title";
    if (normalized === "artist" || normalized === "uploader") return pluginApi?.tr("metadata.artistField") || "Artist";
    if (normalized === "album") return pluginApi?.tr("metadata.albumField") || "Album";
    return pluginApi?.tr("metadata.label") || "Metadata";
  }

  function normalizeMetadataField(field) {
    var normalized = String(field || "").trim().toLowerCase();
    if (normalized === "artist") return "uploader";
    if (normalized === "uploader") return "uploader";
    if (normalized === "album") return "album";
    if (normalized === "title") return "title";
    return "";
  }

  function currentMetadataEditorEntry() {
    if (metadataEditorEntryId.length === 0) {
      return null;
    }

    var library = mainInstance?.libraryEntries || [];
    for (var i = 0; i < library.length; i++) {
      if (String(library[i].id || "") === metadataEditorEntryId) {
        return library[i];
      }
    }
    return null;
  }

  function startMetadataEditing(entry, preferredField) {
    var targetEntry = mainInstance?.findLibraryEntry(entry);
    var entryId = String(targetEntry?.id || "").trim();
    if (entryId.length === 0) {
      return;
    }

    metadataEditorEntryId = entryId;
    metadataEditorEntryTitle = targetEntry?.title || targetEntry?.name || pluginApi?.tr("common.untitled") || "Untitled";
    metadataEditorField = normalizeMetadataField(preferredField);
    root.clearPlaylistSelection();
    root.clearPlaylistRename();
    root.clearTagEditor();
    if (launcher) {
      launcher.setSearchText(commandName + " edit:" + (metadataEditorField.length > 0 ? (metadataEditorField + " ") : ""));
    }
  }

  function buildStatusItem() {
    var playing = mainInstance?.isPlaying === true;
    var starting = mainInstance?.playbackStarting === true;
    var title = playing || starting ? (mainInstance?.currentTitle || (starting ? (pluginApi?.tr("status.starting") || "Starting playback") : (pluginApi?.tr("status.nowPlaying") || "Now playing"))) : (pluginApi?.tr("status.ready") || "music-search ready");
    var savedCurrentEntry = mainInstance?.findSavedEntry({
                                                   "id": mainInstance?.currentEntryId || "",
                                                   "url": mainInstance?.currentUrl || ""
                                                 }) || null;
    var currentEntry = {
      "id": mainInstance?.currentEntryId || "",
      "title": title,
      "url": mainInstance?.currentUrl || "",
      "uploader": mainInstance?.currentUploader || "",
      "duration": mainInstance?.currentDuration || 0,
      "tags": savedCurrentEntry?.tags || []
    };
    var providerName = mainInstance?.providerLabel() || "YouTube";
    var description = playing ? buildDescription({
                                                  "uploader": mainInstance?.currentUploader || "",
                                                  "duration": mainInstance?.currentDuration || 0
                                                }, pluginApi?.tr("status.backgroundPlayback") || "Background mpv playback") : (starting
                                                     ? (mainInstance?.playbackStartingMessage || (pluginApi?.tr("status.startingProviderPlayback", {"provider": mainInstance?.providerLabel() || "music"}) || ("Starting " + (mainInstance?.providerLabel() || "music") + " playback...")))
                                                     : (mainInstance?.lastError ? (pluginApi?.tr("errors.lastError", {"error": mainInstance.lastError}) || ("Last error: " + mainInstance.lastError)) : (mainInstance?.lastNotice || (pluginApi?.tr("status.searchPrompt", {"provider": providerName}) || ("Search " + providerName + ", paste a URL, or open a saved track.")))));

    return {
      "id": currentEntry.id,
      "name": title,
      "title": currentEntry.title,
      "description": description,
      "icon": playing ? (mainInstance?.isPaused ? "player-pause" : "disc") : (starting ? "disc" : "music"),
      "isTablerIcon": true,
      "isImage": false,
      "badgeIcon": (playing || starting) && mainInstance?.isSaved(currentEntry) ? "bookmark-filled" : "",
      "provider": root,
      "kind": playing || starting ? "status" : "status-idle",
      "url": currentEntry.url,
      "uploader": currentEntry.uploader,
      "duration": currentEntry.duration,
      "onActivate": function () {}
    };
  }

  function buildStopItem() {
    return {
      "name": pluginApi?.tr("actions.stopMusic") || "Stop music",
      "description": mainInstance?.currentTitle ? (pluginApi?.tr("actions.stopTitle", {"title": mainInstance.currentTitle}) || ("Stop " + mainInstance.currentTitle)) : (pluginApi?.tr("actions.stopDesc") || "Stop background playback."),
      "icon": "player-stop",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "_score": 5,
      "onActivate": function () {
        if (launcher) {
          launcher.close();
        }
        mainInstance?.stopPlayback();
      }
    };
  }

  function buildIdleStopItem() {
    return {
      "name": pluginApi?.tr("actions.alreadyStopped") || "Music already stopped",
      "description": pluginApi?.tr("actions.nothingPlaying") || "Nothing is currently playing.",
      "icon": "player-stop",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "onActivate": function () {}
    };
  }

  function buildLoadingItem(query, provider) {
    return {
      "name": pluginApi?.tr("search.searching", {"provider": mainInstance?.providerLabel(provider) || "YouTube"}) || ("Searching " + (mainInstance?.providerLabel(provider) || "YouTube")),
      "description": query,
      "icon": "search",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "loading",
      "onActivate": function () {}
    };
  }

  function buildSearchErrorItem(message) {
    return {
      "name": pluginApi?.tr("search.failed") || "Search failed",
      "description": message || pluginApi?.tr("search.failedDefault") || "yt-dlp could not resolve results.",
      "icon": "alert-circle",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "onActivate": function () {}
    };
  }

  function buildSearchHintItem(message) {
    return {
      "name": pluginApi?.tr("search.title") || "Search music",
      "description": message || pluginApi?.tr("search.hint") || "Try `>music-search burial`, `yt: burial`, `sc: artist`, `local: song`, `queue`, `#night`, `artist:name`, `rating:>=4`, `provider:local`, `playlist:name`, `speed:1.05`, or paste a URL.",
      "icon": "search",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "onActivate": function () {}
    };
  }

  function buildPlayUrlItem(urlText) {
    return {
      "name": pluginApi?.tr("actions.playUrl") || "Play URL",
      "description": String(urlText || "").trim(),
      "icon": "player-play",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "custom-url",
      "url": String(urlText || "").trim(),
      "_score": 10,
      "onActivate": function () {
        if (launcher) {
          launcher.close();
        }
        mainInstance?.playUrl(urlText, pluginApi?.tr("common.customUrl") || "Custom URL");
      }
    };
  }

  function buildSaveUrlItem(urlText) {
    return {
      "name": pluginApi?.tr("actions.saveUrl") || "Save URL to library",
      "description": String(urlText || "").trim(),
      "icon": "bookmark-plus",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "save-url",
      "url": String(urlText || "").trim(),
      "_score": 9,
      "onActivate": function () {
        mainInstance?.saveUrl(urlText);
      }
    };
  }

  function buildDownloadUrlItem(urlText) {
    return {
      "name": pluginApi?.tr("actions.saveUrlMp3") || "Save URL as mp3",
      "description": pluginApi?.tr("actions.downloadDesc") || "Download to ~/Music/Noctalia",
      "icon": "download",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "download-url",
      "url": String(urlText || "").trim(),
      "_score": 8,
      "onActivate": function () {
        mainInstance?.downloadUrl(urlText, pluginApi?.tr("common.downloadedTrack") || "Downloaded Track");
      }
    };
  }

  function buildLibraryItems(query, limit) {
    var filters = parseLibraryFilterQuery(query);
    var library = filters.includeHidden ? (mainInstance?.libraryEntries || []) : (mainInstance?.visibleLibraryEntries() || []);
    if (library.length === 0) {
      if (query.length === 0) {
        return [
              {
                "name": pluginApi?.tr("library.empty") || "Library is empty",
                "description": pluginApi?.tr("library.emptyDesc") || "Save search results and they will show up here next time.",
                "icon": "bookmark-off",
                "isTablerIcon": true,
                "isImage": false,
                "provider": root,
                "onActivate": function () {}
              }
            ];
      }
      return [];
    }

    var entries = library.filter(function (entry) {
      return entryMatchesLibraryFilters(entry, filters);
    }).slice();
    var sortBy = mainInstance?.currentSortBy || "date";
    entries.sort(function (a, b) {
      if (sortBy === "title") {
        return String(a.title || "").localeCompare(String(b.title || ""));
      }
      if (sortBy === "duration") {
        return (Number(b.duration) || 0) - (Number(a.duration) || 0);
      }
      if (sortBy === "rating") {
        return (Number(b.rating) || 0) - (Number(a.rating) || 0);
      }
      return String(b.savedAt || "").localeCompare(String(a.savedAt || ""));
    });

    var matchedEntries = entries;
    if (filters.textQuery.length > 0) {
      matchedEntries = FuzzySort.go(filters.textQuery, entries.map(function (entry) {
                                     return {
                                       "entry": entry,
                                       "title": entry.title || "",
                                       "uploader": entry.uploader || "",
                                       "album": entry.album || "",
                                       "localPath": entry.localPath || "",
                                       "url": entry.url || ""
                                     };
                                   }), {
                                     "keys": ["title", "uploader", "album", "localPath", "url"],
                                     "limit": limit > 0 ? limit : entries.length
                                   }).map(function (match) {
                                            return match.obj.entry;
                                          });
    } else if (limit > 0) {
      matchedEntries = entries.slice(0, limit);
    }

    return matchedEntries.map(function (entry) {
      return buildLibraryResultItem(entry, {
                                      "prefix": entry?.isSaved === false ? (pluginApi?.tr("library.playlistOnly") || "Playlist-only") : (pluginApi?.tr("library.saved") || "Saved")
                                    });
    });
  }

  function buildTagFilteredItems(tagQuery) {
    var library = mainInstance?.libraryEntries || [];
    var tagTerms = parseTagTerms(tagQuery);
    var tagLabel = tagTerms.map(function (tag) {
      return "#" + tag;
    }).join(" ");

    var matched = library.filter(function (entry) {
      return entryMatchesTagTerms(entry, tagTerms);
    }).slice();

    matched.sort(function (a, b) {
      if (Number(b.playCount || 0) !== Number(a.playCount || 0)) {
        return Number(b.playCount || 0) - Number(a.playCount || 0);
      }
      if (String(b.lastPlayedAt || "") !== String(a.lastPlayedAt || "")) {
        return String(b.lastPlayedAt || "").localeCompare(String(a.lastPlayedAt || ""));
      }
      return String(b.savedAt || "").localeCompare(String(a.savedAt || ""));
    });

    return matched.map(function (entry) {
      return buildLibraryResultItem(entry, {
                                      "prefix": tagLabel || "#tag",
                                      "icon": entry.id === mainInstance?.currentEntryId && mainInstance?.isPlaying ? "disc" : "tag"
                                    });
    });
  }

  function buildTagEditorHeaderItem(entry) {
    var tags = entry?.tags || [];
    var countLabel = tags.length === 0 ? (pluginApi?.tr("tags.noTags") || "No tags yet") : (tags.length === 1 ? (pluginApi?.tr("tags.oneTag") || "1 tag") : (pluginApi?.tr("tags.tagCount", {"count": tags.length}) || (tags.length + " tags")));

    return {
      "id": entry?.id || "tag-editor",
      "name": pluginApi?.tr("tags.manage") || "Manage tags",
      "description": (entry?.title || tagEditorEntryTitle || pluginApi?.tr("common.untitled") || "Untitled") + " • " + countLabel,
      "icon": "tag",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "tag-header",
      "url": entry?.url || "",
      "uploader": entry?.uploader || "",
      "duration": entry?.duration || 0,
      "tags": tags,
      "rating": entry?.rating || 0,
      "onActivate": function () {}
    };
  }

  function buildTagEditorHintItem(message) {
    return {
      "name": pluginApi?.tr("tags.editor") || "Tag editor",
      "description": message,
      "icon": "tag",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "tag-hint",
      "onActivate": function () {}
    };
  }

  function buildTagActionItem(entry, tag, assigned) {
    var normalizedTag = normalizeTagValue(tag);
    return {
      "id": (entry?.id || "tag") + ":" + normalizedTag.toLowerCase() + ":" + (assigned ? "remove" : "add"),
      "name": assigned ? (pluginApi?.tr("tags.remove", {"tag": normalizedTag}) || ("Remove #" + normalizedTag)) : (pluginApi?.tr("tags.add", {"tag": normalizedTag}) || ("Add #" + normalizedTag)),
      "description": assigned ? (pluginApi?.tr("tags.removeFrom", {"title": entry?.title || tagEditorEntryTitle || "this track"}) || ("Remove from " + (entry?.title || tagEditorEntryTitle || "this track"))) : (pluginApi?.tr("tags.applyTo", {"title": entry?.title || tagEditorEntryTitle || "this track"}) || ("Apply to " + (entry?.title || tagEditorEntryTitle || "this track"))),
      "icon": assigned ? "x" : "tag",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": assigned ? "tag-remove" : "tag-add",
      "url": entry?.url || "",
      "uploader": entry?.uploader || "",
      "duration": entry?.duration || 0,
      "tags": entry?.tags || [],
      "rating": entry?.rating || 0,
      "onActivate": function () {
        if (assigned) {
          mainInstance?.untagEntry(entry?.id || "", normalizedTag);
        } else {
          mainInstance?.tagEntry(entry?.id || "", normalizedTag);
        }
        if (launcher) {
          launcher.setSearchText(commandName + " tag:");
        }
      }
    };
  }

  function buildTagEditorItems(tagQuery) {
    var entry = currentTagEditorEntry();
    if (!entry) {
      return [
            buildTagEditorHintItem(pluginApi?.tr("tags.chooseTrack") || "Choose a saved track first, then use the tag action to edit its tags.")
          ];
    }

    var items = [buildTagEditorHeaderItem(entry)];
    var normalizedQuery = normalizeTagValue(tagQuery);
    var normalizedQueryLower = normalizedQuery.toLowerCase();
    var seenKeys = ({});
    var currentTags = (entry.tags || []).slice().sort(function (a, b) {
      return normalizeTagValue(a).localeCompare(normalizeTagValue(b));
    });

    function pushTagItem(tag, assigned) {
      var normalizedTag = normalizeTagValue(tag);
      var key = normalizedTag.toLowerCase() + ":" + (assigned ? "remove" : "add");
      if (normalizedTag.length === 0 || seenKeys[key]) {
        return;
      }
      seenKeys[key] = true;
      items.push(buildTagActionItem(entry, normalizedTag, assigned));
    }

    if (normalizedQueryLower.length > 0) {
      pushTagItem(normalizedQuery, entryHasTag(entry, normalizedQuery));
    }

    for (var i = 0; i < currentTags.length; i++) {
      var existingTag = normalizeTagValue(currentTags[i]);
      if (normalizedQueryLower.length > 0 && existingTag.toLowerCase().indexOf(normalizedQueryLower) === -1) {
        continue;
      }
      pushTagItem(existingTag, true);
    }

    var suggestionCount = 0;
    var knownTags = collectKnownTags();
    for (var j = 0; j < knownTags.length; j++) {
      var knownTag = normalizeTagValue(knownTags[j]);
      if (entryHasTag(entry, knownTag)) {
        continue;
      }
      if (normalizedQueryLower.length > 0 && knownTag.toLowerCase().indexOf(normalizedQueryLower) === -1) {
        continue;
      }
      pushTagItem(knownTag, false);
      suggestionCount += 1;
      if (normalizedQueryLower.length === 0 && suggestionCount >= 6) {
        break;
      }
    }

    if (items.length === 1) {
      items.push(buildTagEditorHintItem(normalizedQuery.length > 0
                                            ? (pluginApi?.tr("tags.noMatch", {"query": normalizedQuery}) || ("No tag matches \"" + normalizedQuery + "\" yet. Select the add action to create it."))
                                            : (pluginApi?.tr("tags.hint") || "Type after `tag:` to add a new tag, or select an existing tag to remove it.")));
    }

    return items;
  }

  function buildMetadataEditorHeaderItem(entry, field) {
    var label = metadataFieldLabel(field);
    var currentValue = "";
    if (field === "title") {
      currentValue = String(entry?.title || "");
    } else if (field === "uploader") {
      currentValue = String(entry?.uploader || "");
    } else if (field === "album") {
      currentValue = String(entry?.album || "");
    }

    return {
      "id": entry?.id || "metadata-editor",
      "name": pluginApi?.tr("metadata.fieldEditor", {"field": label}) || (label + " editor"),
      "description": (entry?.title || metadataEditorEntryTitle || (pluginApi?.tr("common.untitled") || "Untitled")) + (currentValue.length > 0 ? (" • " + currentValue) : (" • " + (pluginApi?.tr("metadata.currentlyEmpty") || "currently empty"))),
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "metadata-header",
      "onActivate": function () {}
    };
  }

  function buildMetadataEditorHintItem(message) {
    return {
      "name": pluginApi?.tr("metadata.edit") || "Edit metadata",
      "description": message,
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "metadata-hint",
      "onActivate": function () {}
    };
  }

  function buildMetadataFieldItem(entry, field) {
    var normalizedField = normalizeMetadataField(field);
    var value = "";
    if (normalizedField === "title") {
      value = String(entry?.title || "");
    } else if (normalizedField === "uploader") {
      value = String(entry?.uploader || "");
    } else if (normalizedField === "album") {
      value = String(entry?.album || "");
    }

    return {
      "id": String(entry?.id || "") + ":metadata:" + normalizedField,
      "name": pluginApi?.tr("metadata.editField", {"field": metadataFieldLabel(normalizedField)}) || ("Edit " + metadataFieldLabel(normalizedField)),
      "description": value.length > 0 ? value : (pluginApi?.tr("metadata.empty") || "Currently empty"),
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "metadata-field",
      "onActivate": function () {
        metadataEditorField = normalizedField;
        if (launcher) {
          launcher.setSearchText(commandName + " edit:" + normalizedField + " ");
        }
      }
    };
  }

  function buildMetadataApplyItem(entry, field, value) {
    var normalizedField = normalizeMetadataField(field);
    var targetValue = String(value || "");
    var label = metadataFieldLabel(normalizedField);
    var description = targetValue.trim().length > 0 ? targetValue : (pluginApi?.tr("metadata.clearValue") || "Clear value");

    return {
      "id": String(entry?.id || "") + ":metadata:" + normalizedField + ":" + description.toLowerCase(),
      "name": targetValue.trim().length > 0 ? (pluginApi?.tr("metadata.setField", {"field": label}) || ("Set " + label)) : (pluginApi?.tr("metadata.clearField", {"field": label}) || ("Clear " + label)),
      "description": description,
      "icon": "check",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "metadata-apply",
      "onActivate": function () {
        mainInstance?.editMetadata(String(entry?.id || ""), normalizedField, targetValue);
        root.clearMetadataEditor();
        if (launcher) {
          launcher.setSearchText(commandName + " ");
        }
      }
    };
  }

  function buildMetadataEditorItems(editQuery) {
    var entry = currentMetadataEditorEntry();
    if (!entry) {
      return [
            buildMetadataEditorHintItem(pluginApi?.tr("metadata.chooseTrack") || "Choose a library track first, then use the edit action to update title, artist, or album.")
          ];
    }

    var queryText = String(editQuery || "").trim();
    var field = metadataEditorField;
    var value = "";

    if (queryText.length > 0) {
      var spaceIndex = queryText.indexOf(" ");
      var firstToken = spaceIndex >= 0 ? queryText.substring(0, spaceIndex) : queryText;
      var normalizedToken = normalizeMetadataField(firstToken);
      if (normalizedToken.length > 0) {
        field = normalizedToken;
        metadataEditorField = normalizedToken;
        value = spaceIndex >= 0 ? queryText.substring(spaceIndex + 1) : "";
      } else if (field.length > 0) {
        value = queryText;
      }
    }

    if (field.length === 0) {
      return [
            buildMetadataEditorHintItem(pluginApi?.tr("metadata.chooseField", {"title": entry?.title || metadataEditorEntryTitle || "this track"}) || ("Choose which field to edit for \"" + (entry?.title || metadataEditorEntryTitle || "this track") + "\".")),
            buildMetadataFieldItem(entry, "title"),
            buildMetadataFieldItem(entry, "artist"),
            buildMetadataFieldItem(entry, "album")
          ];
    }

    var items = [buildMetadataEditorHeaderItem(entry, field)];
    var trimmedValue = String(value || "").trim();
    if (trimmedValue.length === 0) {
      items.push(buildMetadataEditorHintItem(
                   field === "album"
                       ? (pluginApi?.tr("metadata.albumHint") || "Type a new album name, or choose the clear action to remove it.")
                       : (pluginApi?.tr("metadata.typeNew", {"field": metadataFieldLabel(field).toLowerCase()}) || ("Type a new " + metadataFieldLabel(field).toLowerCase() + " value."))
                 ));
      if (field === "album" && String(entry?.album || "").trim().length > 0) {
        items.push(buildMetadataApplyItem(entry, field, ""));
      }
    } else {
      items.push(buildMetadataApplyItem(entry, field, value));
    }

    if (field !== "title") {
      items.push(buildMetadataFieldItem(entry, "title"));
    }
    if (field !== "uploader") {
      items.push(buildMetadataFieldItem(entry, "artist"));
    }
    if (field !== "album") {
      items.push(buildMetadataFieldItem(entry, "album"));
    }

    return items;
  }

  function findPlaylistMatches(playlistQuery) {
    var playlists = mainInstance?.playlistEntries || [];
    var queryLower = String(playlistQuery || "").toLowerCase();

    if (queryLower.length === 0) {
      return playlists.slice();
    }

    var exact = [];
    var prefix = [];
    for (var i = 0; i < playlists.length; i++) {
      var playlist = playlists[i];
      var nameLower = String(playlist.name || "").toLowerCase();
      if (nameLower === queryLower) {
        exact.push(playlist);
      } else if (nameLower.indexOf(queryLower) === 0) {
        prefix.push(playlist);
      }
    }

    return exact.concat(prefix);
  }

  function currentPlaylistRenameTarget() {
    var playlists = mainInstance?.playlistEntries || [];
    for (var i = 0; i < playlists.length; i++) {
      if (String(playlists[i].id || "") === String(playlistRenameId || "")) {
        return playlists[i];
      }
    }
    return null;
  }

  function playlistNameTaken(targetPlaylistId, name) {
    var targetName = String(name || "").trim().toLowerCase();
    if (targetName.length === 0) {
      return false;
    }

    var playlists = mainInstance?.playlistEntries || [];
    for (var i = 0; i < playlists.length; i++) {
      if (String(playlists[i].id || "") === String(targetPlaylistId || "")) {
        continue;
      }
      if (String(playlists[i].name || "").trim().toLowerCase() === targetName) {
        return true;
      }
    }

    return false;
  }

  function buildPlaylistHeaderItem(playlist) {
    var playlistId = playlist.id || "";
    var playlistName = playlist.name || pluginApi?.tr("playlists.untitled") || "Untitled Playlist";
    var entryCount = (playlist.entryIds || []).length;
    var sourceType = String(playlist.sourceType || "").trim();
    var sourceFolder = String(playlist.sourceFolder || "").trim();
    var description = entryCount === 1 ? (pluginApi?.tr("playlists.oneTrack") || "1 track") : (pluginApi?.tr("playlists.trackCount", {"count": entryCount}) || (entryCount + " tracks"));
    if (sourceType === "folder" && sourceFolder.length > 0) {
      description += " • " + (pluginApi?.tr("playlists.syncedFolder") || "synced folder");
    }

    return {
      "id": playlistId,
      "name": playlistName,
      "description": description,
      "icon": "playlist",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-header",
      "sourceType": sourceType,
      "sourceFolder": sourceFolder,
      "onActivate": function () {
        if (launcher) {
          launcher.setSearchText(commandName + " playlist:" + playlistName);
        }
      }
    };
  }

  function buildPlaylistRenameHeaderItem(playlist) {
    return {
      "id": playlist?.id || "playlist-rename",
      "name": pluginApi?.tr("playlists.rename") || "Rename playlist",
      "description": playlist?.name || playlistRenameTitle || pluginApi?.tr("playlists.untitled") || "Untitled Playlist",
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-rename-header",
      "onActivate": function () {}
    };
  }

  function buildPlaylistRenameHintItem(message) {
    return {
      "name": pluginApi?.tr("playlists.renameTitle") || "Playlist rename",
      "description": message,
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-rename-hint",
      "onActivate": function () {}
    };
  }

  function buildPlaylistRenameItem(playlist, name) {
    var targetName = String(name || "").trim();
    return {
      "id": String(playlist?.id || "") + ":rename:" + targetName.toLowerCase(),
      "name": pluginApi?.tr("playlists.renameTo", {"name": targetName}) || ("Rename to \"" + targetName + "\""),
      "description": pluginApi?.tr("playlists.updateTitle") || "Update playlist title.",
      "icon": "pencil",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-rename",
      "onActivate": function () {
        mainInstance?.renamePlaylist(String(playlist?.id || ""), targetName);
        root.clearPlaylistRename();
        if (launcher) {
          launcher.setSearchText(commandName + " playlist:" + targetName);
        }
      }
    };
  }

  function buildPlaylistTrackItem(entry, playlist) {
    var playlistName = playlist.name || pluginApi?.tr("playlists.untitled") || "Untitled Playlist";
    var playlistId = playlist.id || "";
    return buildLibraryResultItem(entry, {
                                    "prefix": playlistName,
                                    "icon": entry?.id === mainInstance?.currentEntryId && mainInstance?.isPlaying ? "disc" : "music",
                                    "playlistId": playlistId
                                  });
  }

  function buildCreatePlaylistItem(playlistName) {
    var targetName = String(playlistName || "").trim();
    var pendingEntryId = playlistPickerEntryId;
    var pendingEntryTitle = playlistPickerEntryTitle;

    return {
      "name": pendingEntryId ? (pluginApi?.tr("playlists.createAndAdd", {"name": targetName}) || ("Create playlist \"" + targetName + "\" and add track")) : (pluginApi?.tr("playlists.create", {"name": targetName}) || ("Create playlist \"" + targetName + "\"")),
      "description": pendingEntryId ? (pluginApi?.tr("playlists.addAfterCreate", {"title": pendingEntryTitle}) || ("Add " + pendingEntryTitle + " after creating it.")) : (pluginApi?.tr("playlists.createNew") || "Create a new playlist."),
      "icon": "playlist",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-create",
      "onActivate": function () {
        mainInstance?.createPlaylist(targetName, pendingEntryId);
        root.clearPlaylistSelection();
        if (launcher) {
          launcher.setSearchText(commandName + " playlist:" + targetName);
        }
      }
    };
  }

  function buildPlaylistPickerItem(playlist) {
    var playlistId = playlist.id || "";
    var playlistName = playlist.name || pluginApi?.tr("playlists.untitled") || "Untitled Playlist";
    var entryCount = (playlist.entryIds || []).length;
    var pendingEntryId = playlistPickerEntryId;

    return {
      "id": playlistId,
      "name": pluginApi?.tr("playlists.addTo", {"name": playlistName}) || ("Add to " + playlistName),
      "description": entryCount === 1 ? (pluginApi?.tr("playlists.oneTrack") || "1 track") : (pluginApi?.tr("playlists.trackCount", {"count": entryCount}) || (entryCount + " tracks")),
      "icon": "playlist",
      "isTablerIcon": true,
      "isImage": false,
      "provider": root,
      "kind": "playlist-select",
      "onActivate": function () {
        mainInstance?.addToPlaylist(playlistId, pendingEntryId);
        root.clearPlaylistSelection();
        if (launcher) {
          launcher.setSearchText(commandName + " playlist:" + playlistName);
        }
      }
    };
  }

  function buildPlaylistRenameItems(playlistQuery) {
    var playlist = currentPlaylistRenameTarget();
    if (!playlist) {
      return [
            buildPlaylistRenameHintItem(pluginApi?.tr("playlists.chooseFirst") || "Choose a playlist first, then use the rename action.")
          ];
    }

    var items = [buildPlaylistRenameHeaderItem(playlist)];
    var targetName = String(playlistQuery || "").trim();
    if (targetName.length === 0) {
      items.push(buildPlaylistRenameHintItem(pluginApi?.tr("playlists.typeNewName", {"name": playlist.name || playlistRenameTitle || "this playlist"}) || ("Type a new name for \"" + (playlist.name || playlistRenameTitle || "this playlist") + "\".")));
      return items;
    }

    if (String(playlist.name || "").trim().toLowerCase() === targetName.toLowerCase()) {
      items.push(buildPlaylistRenameHintItem(pluginApi?.tr("playlists.typeDifferent") || "Type a different name to rename this playlist."));
      return items;
    }

    if (playlistNameTaken(playlist.id, targetName)) {
      items.push(buildPlaylistRenameHintItem(pluginApi?.tr("playlists.alreadyExists", {"name": targetName}) || ("Playlist \"" + targetName + "\" already exists.")));
      return items;
    }

    items.push(buildPlaylistRenameItem(playlist, targetName));
    return items;
  }

  function buildPlaylistItems(playlistQuery) {
    var playlists = mainInstance?.playlistEntries || [];
    var library = mainInstance?.libraryEntries || [];
    var items = [];

    if (playlistQuery.length === 0) {
      if (playlists.length === 0) {
        items.push({
                     "name": pluginApi?.tr("playlists.none") || "No playlists",
                     "description": pluginApi?.tr("playlists.createHint") || "Type `playlist:name` to create one.",
                     "icon": "playlist",
                     "isTablerIcon": true,
                     "isImage": false,
                     "provider": root,
                     "onActivate": function () {}
                   });
      } else {
        for (var i = 0; i < playlists.length; i++) {
          items.push(buildPlaylistHeaderItem(playlists[i]));
        }
      }
      return items;
    }

    var matches = findPlaylistMatches(playlistQuery);
    var targetPlaylist = matches.length > 0 ? matches[0] : null;

    if (!targetPlaylist) {
      items.push(buildCreatePlaylistItem(playlistQuery));
      return items;
    }

    items.push(buildPlaylistHeaderItem(targetPlaylist));

    var entryIds = targetPlaylist.entryIds || [];
    for (var m = 0; m < entryIds.length; m++) {
      var entryId = entryIds[m];
      for (var n = 0; n < library.length; n++) {
        if (library[n].id === entryId) {
          items.push(buildPlaylistTrackItem(library[n], targetPlaylist));
          break;
        }
      }
    }

    return items;
  }

  function buildPlaylistPickerItems(playlistQuery) {
    var items = [];
    var matches = findPlaylistMatches(playlistQuery);
    var queryText = String(playlistQuery || "").trim();
    var exactMatch = false;

    if (matches.length > 0) {
      for (var i = 0; i < matches.length; i++) {
        if (String(matches[i].name || "").toLowerCase() === queryText.toLowerCase()) {
          exactMatch = true;
        }
        items.push(buildPlaylistPickerItem(matches[i]));
      }
    }

    if (queryText.length > 0 && !exactMatch) {
      items.unshift(buildCreatePlaylistItem(queryText));
    }

    if (items.length === 0) {
      items.push({
                   "name": pluginApi?.tr("playlists.choose") || "Choose a playlist",
                   "description": pluginApi?.tr("playlists.chooseFor", {"title": playlistPickerEntryTitle}) || ("Type a playlist name to create one for " + playlistPickerEntryTitle + "."),
                   "icon": "playlist",
                   "isTablerIcon": true,
                   "isImage": false,
                   "provider": root,
                   "onActivate": function () {}
                 });
    }

    return items;
  }

  function buildSearchResultItem(entry) {
    var saved = mainInstance?.isSaved(entry) === true;
    var badge = saved ? "bookmark-filled" : "";
    var entryProvider = String(entry.provider || entry.providerName || mainInstance?.currentProvider || "youtube");

    return {
      "id": entry.id || "",
      "name": entry.title || pluginApi?.tr("common.untitled") || "Untitled",
      "description": buildDescription(entry, mainInstance?.providerLabel(entryProvider) || "YouTube"),
      "icon": "music",
      "isTablerIcon": true,
      "isImage": false,
      "badgeIcon": badge,
      "provider": root,
      "kind": "search",
      "url": entry.url || "",
      "uploader": entry.uploader || "",
      "duration": entry.duration || 0,
      "providerName": entryProvider,
      "album": entry.album || "",
      "localPath": entry.localPath || "",
      "playCount": entry.playCount || 0,
      "lastPlayedAt": entry.lastPlayedAt || "",
      "onActivate": function () {
        if (launcher) {
          launcher.close();
        }
        mainInstance?.playEntry(entry);
      }
    };
  }

  function canSaveAsMp3(item) {
    if (!item || !item.url) {
      return false;
    }
    return mainInstance?.isLocalEntry(item) !== true;
  }

  function getItemActions(item) {
    if (!item) {
      return [];
    }

    if (item.kind === "queue-entry") {
      return [
            {
              "icon": "player-play",
              "tooltip": "Play now",
              "action": function () {
                mainInstance?.playQueueEntryNow(item);
                if (launcher) {
                  launcher.close();
                }
              }
            },
            {
              "icon": "x",
              "tooltip": "Remove from queue",
              "action": function () {
                mainInstance?.removeQueueEntry(item.id, true);
              }
            }
          ];
    }

    if (item.kind === "status-idle") {
      return [
            {
              "icon": "arrows-sort",
              "tooltip": pluginApi?.tr("tooltip.sort", {"sort": mainInstance?.sortLabel() || "Date"}) || ("Sort: " + (mainInstance?.sortLabel() || "Date")),
              "action": function () {
                mainInstance?.cycleSortBy();
              }
            },
            {
              "icon": "switch-horizontal",
              "tooltip": pluginApi?.tr("tooltip.switchProvider", {"provider": mainInstance?.providerLabel() || "YouTube"}) || ("Switch provider (" + (mainInstance?.providerLabel() || "YouTube") + ")"),
              "action": function () {
                mainInstance?.cycleProvider();
              }
            }
          ];
    }

    if (item.kind === "status") {
      if (!item.url) {
        return [];
      }

      var statusLibraryEntry = mainInstance?.findLibraryEntry(item);
      var statusSavedEntry = mainInstance?.findSavedEntry(item);
      var statusActions = [
            {
              "icon": "playlist-add",
              "tooltip": pluginApi?.tr("tooltip.addToQueue") || "Add to queue",
              "action": function () {
                mainInstance?.enqueueEntry(item);
              }
            }
          ];

      if (!statusSavedEntry) {
        statusActions.unshift({
                                "icon": "bookmark-plus",
                                "tooltip": pluginApi?.tr("tooltip.saveToLibrary") || "Save to library",
                                "action": function () {
                                  mainInstance?.saveEntry(statusLibraryEntry || item);
                                }
                              });
      }

      if (canSaveAsMp3(statusLibraryEntry || item)) {
        statusActions.splice(statusActions.length > 0 ? 1 : 0, 0, {
                               "icon": "download",
                               "tooltip": pluginApi?.tr("tooltip.saveMp3Current") || "Save current track as mp3",
                               "action": function () {
                                 mainInstance?.downloadCurrentTrack();
                               }
                             });
      }

      if (mainInstance?.isPaused) {
        statusActions.unshift({
                                "icon": "player-play",
                                "tooltip": pluginApi?.tr("tooltip.resume") || "Resume",
                                "action": function () {
                                  mainInstance?.resumePlayback();
                                }
                              });
      } else {
        statusActions.unshift({
                                "icon": "player-pause",
                                "tooltip": pluginApi?.tr("tooltip.pause") || "Pause",
                                "action": function () {
                                  mainInstance?.pausePlayback();
                                }
                              });
      }

      if (statusLibraryEntry) {
        statusActions.push({
                             "icon": "pencil",
                             "tooltip": pluginApi?.tr("tooltip.editMetadata") || "Edit metadata",
                             "action": function () {
                               root.startMetadataEditing(statusLibraryEntry, "");
                             }
                           });
      }

      if (statusSavedEntry) {
        statusActions.push({
                             "icon": "tag",
                             "tooltip": pluginApi?.tr("tooltip.manageTags") || "Manage tags",
                             "action": function () {
                               root.startTagEditing(statusSavedEntry);
                             }
                           });
        statusActions.push({
                             "icon": "playlist",
                             "tooltip": pluginApi?.tr("tooltip.addSavedToPlaylist") || "Add saved track to playlist",
                             "action": function () {
                               root.startPlaylistSelection(statusSavedEntry);
                             }
                           });
      }

      statusActions.push({
                           "icon": "switch-horizontal",
                           "tooltip": pluginApi?.tr("tooltip.switchProvider", {"provider": mainInstance?.providerLabel() || "YouTube"}) || ("Switch provider (" + (mainInstance?.providerLabel() || "YouTube") + ")"),
                           "action": function () {
                             mainInstance?.cycleProvider();
                           }
                         });

      return statusActions;
    }

    if (item.kind === "search") {
      var savedEntry = mainInstance?.findSavedEntry(item);
      if (savedEntry) {
        var savedActions = [
              {
                "icon": "playlist-add",
                "tooltip": pluginApi?.tr("tooltip.addToQueue") || "Add to queue",
                "action": function () {
                  mainInstance?.enqueueEntry(item);
                }
              },
              {
                "icon": "pencil",
                "tooltip": pluginApi?.tr("tooltip.editMetadata") || "Edit metadata",
                "action": function () {
                  root.startMetadataEditing(savedEntry, "");
                }
              },
              {
                "icon": "tag",
                "tooltip": pluginApi?.tr("tooltip.manageTags") || "Manage tags",
                "action": function () {
                  root.startTagEditing(savedEntry);
                }
              },
              {
                "icon": "playlist",
                "tooltip": pluginApi?.tr("tooltip.addToPlaylist") || "Add to playlist",
                "action": function () {
                  root.startPlaylistSelection(savedEntry);
                }
              },
              {
                "icon": "bookmark-off",
                "tooltip": pluginApi?.tr("tooltip.removeFromLibrary") || "Remove from library",
                "action": function () {
                  mainInstance?.removeEntry(savedEntry.id);
                }
              }
            ];
        if (canSaveAsMp3(savedEntry)) {
          savedActions.splice(1, 0, {
                               "icon": "download",
                               "tooltip": pluginApi?.tr("tooltip.saveMp3") || "Save as mp3",
                               "action": function () {
                                 mainInstance?.downloadEntry(item);
                               }
                             });
        }
        return savedActions;
      }

      var searchActions = [
              {
                "icon": "playlist-add",
                "tooltip": pluginApi?.tr("tooltip.addToQueue") || "Add to queue",
                "action": function () {
                  mainInstance?.enqueueEntry(item);
              }
            },
            {
              "icon": "bookmark-plus",
              "tooltip": pluginApi?.tr("tooltip.saveToLibrary") || "Save to library",
              "action": function () {
                mainInstance?.saveEntry(item);
              }
            },
              {
                "icon": "playlist",
                "tooltip": pluginApi?.tr("tooltip.saveFirst") || "Save first, then add to a playlist",
                "action": function () {
                  mainInstance?.saveEntry(item);
                }
              }
            ];
      if (canSaveAsMp3(item)) {
        searchActions.splice(2, 0, {
                                "icon": "download",
                                "tooltip": pluginApi?.tr("tooltip.saveMp3") || "Save as mp3",
                                "action": function () {
                                  mainInstance?.downloadEntry(item);
                                }
                              });
      }
      return searchActions;
    }

    if (item.kind === "library") {
      var libraryActions = [
            {
              "icon": "star",
              "tooltip": pluginApi?.tr("tooltip.rate", {"rating": formatRating(item.rating || 0) + (item.rating ? "" : "unrated")}) || ("Rate (" + formatRating(item.rating || 0) + (item.rating ? "" : "unrated") + ")"),
              "action": function () {
                mainInstance?.cycleRating(item.id);
              }
            },
            {
              "icon": "pencil",
              "tooltip": pluginApi?.tr("tooltip.editMetadata") || "Edit metadata",
              "action": function () {
                root.startMetadataEditing(item, "");
              }
            },
            {
              "icon": "tag",
              "tooltip": pluginApi?.tr("tooltip.manageTags") || "Manage tags",
              "action": function () {
                root.startTagEditing(item);
              }
            },
            {
              "icon": "playlist-add",
              "tooltip": pluginApi?.tr("tooltip.addToQueue") || "Add to queue",
              "action": function () {
                mainInstance?.enqueueEntry(item);
              }
            },
            {
              "icon": "playlist",
              "tooltip": pluginApi?.tr("tooltip.addToPlaylist") || "Add to playlist",
              "action": function () {
                root.startPlaylistSelection(item);
              }
            }
          ];

      if (canSaveAsMp3(item)) {
        libraryActions.push({
                              "icon": "download",
                              "tooltip": pluginApi?.tr("tooltip.saveMp3") || "Save as mp3",
                              "action": function () {
                                mainInstance?.downloadEntry(item);
                              }
                            });
      }

      if (item.playlistId) {
        libraryActions.push({
                              "icon": "playlist-x",
                              "tooltip": pluginApi?.tr("tooltip.removeFromPlaylist") || "Remove from playlist",
                              "action": function () {
                                mainInstance?.removeFromPlaylist(item.playlistId, item.id);
                              }
                            });
      }

      libraryActions.push({
                            "icon": "bookmark-off",
                            "tooltip": pluginApi?.tr("tooltip.removeFromLibrary") || "Remove from library",
                            "action": function () {
                              mainInstance?.removeEntry(item.id);
                            }
                          });

      return libraryActions;
    }

    if (item.kind === "playlist-header") {
      var playlistActions = [
            {
              "icon": "player-play",
              "tooltip": pluginApi?.tr("tooltip.playPlaylist") || "Play playlist",
              "action": function () {
                if (launcher) {
                  launcher.close();
                }
                mainInstance?.playPlaylist(item.id, false);
              }
            },
            {
              "icon": "arrows-shuffle",
              "tooltip": pluginApi?.tr("tooltip.shufflePlay") || "Shuffle play",
              "action": function () {
                if (launcher) {
                  launcher.close();
                }
                mainInstance?.playPlaylist(item.id, true);
              }
            },
            {
              "icon": "playlist-add",
              "tooltip": pluginApi?.tr("tooltip.queuePlaylist") || "Queue playlist",
              "action": function () {
                mainInstance?.queuePlaylist(item.id, false);
              }
            },
            {
              "icon": "pencil",
              "tooltip": pluginApi?.tr("tooltip.renamePlaylist") || "Rename playlist",
              "action": function () {
                root.startPlaylistRename(item);
              }
            },
            {
              "icon": "trash",
              "tooltip": pluginApi?.tr("tooltip.deletePlaylist") || "Delete playlist",
              "action": function () {
                root.clearPlaylistRename();
                root.clearPlaylistSelection();
                if (launcher) {
                  launcher.setSearchText(commandName + " playlist:");
                }
                mainInstance?.deletePlaylist(item.id);
              }
            }
          ];

      if (String(item.sourceType || "") === "folder" && String(item.sourceFolder || "").trim().length > 0) {
        playlistActions.splice(3, 0, {
                                "icon": "refresh",
                                "tooltip": pluginApi?.tr("tooltip.syncFolder") || "Sync folder playlist",
                                "action": function () {
                                  mainInstance?.syncFolderPlaylist(item.id);
                                }
                              });
      }

      return playlistActions;
    }

    if (item.kind === "custom-url") {
      return [
            {
              "icon": "playlist-add",
              "tooltip": pluginApi?.tr("tooltip.addToQueue") || "Add to queue",
              "action": function () {
                mainInstance?.enqueueUrl(item.url, pluginApi?.tr("common.queuedUrl") || "Queued URL");
              }
            },
            {
              "icon": "bookmark-plus",
              "tooltip": pluginApi?.tr("tooltip.saveUrlToLibrary") || "Save URL to library",
              "action": function () {
                mainInstance?.saveUrl(item.url);
              }
            },
            {
              "icon": "download",
              "tooltip": pluginApi?.tr("tooltip.saveMp3") || "Save as mp3",
              "action": function () {
                mainInstance?.downloadUrl(item.url, pluginApi?.tr("common.downloadedTrack") || "Downloaded Track");
              }
            }
          ];
    }

    return [];
  }
}
