import QtQuick 2.12
import QtQuick.Window 2.12
import QtQuick.Layouts 1.12
import QtQuick.Controls 2.12
import CCTV_Viewer.Core 1.0

Window {
    id: instructionsWindow
    title: qsTr("CCTV Viewer 2 - Instrukcja Obsługi / Instructions")
    width: 750
    height: 800
    minimumWidth: 400
    minimumHeight: 500
    color: "#0f151b"

    property string rawMarkdownText: ""

    // Center window over the main rootWindow
    x: rootWindow.x + (rootWindow.width - width) / 2
    y: rootWindow.y + (rootWindow.height - height) / 2

    Component.onCompleted: {
        loadInstructions();
    }

    // Reload when language changes
    Connections {
        target: Context
        onLanguageChanged: {
            loadInstructions();
        }
    }

    function loadInstructions() {
        var xhr = new XMLHttpRequest();
        // Use a translated resource string to select correct file based on active locale
        var fileUrl = qsTr("qrc:/INSTRUKCJA.md");
        
        xhr.open("GET", fileUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    rawMarkdownText = xhr.responseText;
                    instructionsText.text = markdownToHtml(xhr.responseText);
                } else {
                    instructionsText.text = "<p style='color: #ff4d4d;'>" + qsTr("Błąd ładowania instrukcji.") + "</p>";
                }
            }
        }
        xhr.send();
    }

    function findHeaderIndex(anchor) {
        if (!rawMarkdownText) return -1;
        
        // Convert anchor to lowercase and remove hyphens/spaces
        var cleanAnchor = anchor.toLowerCase().replace(/[^a-z0-9ąéćęłńóśźż]/gi, "");
        if (!cleanAnchor) return -1;
        
        // Split raw markdown into lines to find the matching header line
        var lines = rawMarkdownText.split("\n");
        var charCount = 0;
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (line.startsWith("#")) {
                var cleanHeader = line.toLowerCase().replace(/[^a-z0-9ąéćęłńóśźż]/gi, "");
                // Match if either contains the other
                if (cleanHeader.indexOf(cleanAnchor) !== -1 || cleanAnchor.indexOf(cleanHeader) !== -1) {
                    return charCount;
                }
            }
            charCount += line.length + 1; // +1 for the newline
        }
        
        // Fallback to simple direct text search
        return rawMarkdownText.indexOf(anchor);
    }

    function markdownToHtml(md) {
        if (!md) return "";
        
        // Normalise line endings
        var content = md.replace(/\r\n/g, "\n").replace(/\n{3,}/g, "\n\n");
        
        // Escape HTML special characters to prevent QML parsing errors
        var html = content
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
            
        // Headers: # Header -> <h1>Header</h1> (lower margins to fix chapter spacing)
        html = html.replace(/^#\s+(.+)$/gm, "<h1 style='color: #00f5d4; font-size: 18px; font-weight: bold; margin-top: 14px; margin-bottom: 6px;'>$1</h1>");
        html = html.replace(/^##\s+(.+)$/gm, "<h2 style='color: #00f5d4; font-size: 15px; font-weight: bold; margin-top: 12px; margin-bottom: 4px;'>$1</h2>");
        html = html.replace(/^###\s+(.+)$/gm, "<h3 style='color: #ff7a00; font-size: 12px; font-weight: bold; margin-top: 10px; margin-bottom: 2px;'>$1</h3>");
        
        // Bold: **text** -> <b>text</b>
        html = html.replace(/\*\*(.*?)\*\*/g, "<b>$1</b>");
        
        // Markdown Links: [text](#link) -> <a href='#link'>text</a>
        html = html.replace(/\[(.*?)\]\((.*?)\)/g, "<a href='$2' style='color: #00f5d4; text-decoration: none; font-weight: bold;'>$1</a>");
        
        // Code blocks: ```bash ... ``` -> <pre>...</pre>
        html = html.replace(/```(?:bash|js|json)?([\s\S]*?)```/g, "<pre style='background-color: #141a21; color: #eeeeee; padding: 8px; border-radius: 4px; font-family: monospace; line-height: 130%;'>$1</pre>");
        
        // Inline code: `code` -> <code>code</code>
        html = html.replace(/`(.*?)`/g, "<code style='background-color: #141a21; color: #ff7a00; padding: 1px 3px; border-radius: 2px; font-family: monospace;'>$1</code>");
        
        // Numbered lists: 1. item -> <div style='color: #eeeeee; margin-left: 12px; margin-bottom: 3px;'>1. item</div>
        html = html.replace(/^\s*(\d+)\.\s+(.+)$/gm, "<div style='color: #eeeeee; margin-left: 12px; margin-bottom: 3px;'>$1. $2</div>");

        // Bullet lists: * item or - item -> <li>item</li>
        html = html.replace(/^\s*[\*\-]\s+(.+)$/gm, "<li style='color: #eeeeee; margin-left: 12px; margin-bottom: 3px;'>$1</li>");
        
        // Horizontal rule: --- -> <hr>
        html = html.replace(/^---$/gm, "<hr style='border: none; border-top: 1px solid #2a3540; margin: 10px 0;'/>");
        
        // Tighten paragraph line breaks (single <br/> for \n\n instead of double)
        html = html.replace(/\n\n/g, "<br/>");
        
        // Clean up redundant breaks around headers, code blocks and horizontal rules
        html = html.replace(/(<\/h[1-3]>|<\/pre>|<hr[^>]*\/?>)\s*(?:<br\s*\/?>\s*)+/gi, "$1");
        html = html.replace(/(?:<br\s*\/?>\s*)+(<h[1-3][^>]*>|<pre[^>]*>|<hr[^>]*\/?>)/gi, "$1");
        
        return html;
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: 20
        clip: true

        Text {
            id: instructionsText
            width: scroll.width - 24
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: "#eeeeee"
            font {
                pixelSize: 13
                family: "sans-serif"
            }
            lineHeight: 1.3
            
            onLinkActivated: {
                var anchor = link;
                if (anchor.indexOf("#") === 0) {
                    anchor = anchor.substring(1);
                }
                anchor = decodeURIComponent(anchor);
                
                var idx = findHeaderIndex(anchor);
                if (idx !== -1) {
                    var ratio = idx / rawMarkdownText.length;
                    scroll.contentItem.contentY = ratio * (scroll.contentItem.contentHeight - scroll.height);
                }
            }
        }
    }
}
