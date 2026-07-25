import io

with io.open('lib/main.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix step icons
text = text.replace("Ã¢Â Â°", "⏰")
text = text.replace("Ã¢â‚¬\"", "-")
text = text.replace("Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬ App Tile Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬", "─── App Tile ─────────────────────────────────────────────────────────────────")
text = text.replace("Ã¢\" â‚¬Ã¢\" â‚¬Ã¢\" â‚¬ App Tile Ã¢\"", "─── App Tile ──")

# Fix Enable Accessibility Service arrow
text = text.replace("Enable Accessibility Service Ã¢â€\u00a0â€™", "Enable Accessibility Service →")
text = text.replace("Settings Ã¢â€\u00a0â€™ Accessibility Ã¢â€\u00a0â€™ Downloaded Apps Ã¢â€\u00a0â€™ Lucid", "Settings → Accessibility → Downloaded Apps → Lucid")

text = text.replace("Ã¢â€\u00a0â€™", "→")
text = text.replace("Ã¢â€ \u00a0â€™", "→")

with io.open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(text)
