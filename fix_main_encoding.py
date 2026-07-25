import io

with io.open('lib/main.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix common double-mojibake resulting from CP1252 reading UTF-8 encoded text
text = text.replace('Ã¢â€ â€™', '→')
text = text.replace('Ã¢â‚¬â€œ', '-')
text = text.replace('Ã¢Å“â€œ', '✅')
text = text.replace('Ã¢Â Â³', '⏳')
text = text.replace('Ã¢Å¡â„¢Ã¯Â¸Â ', '⚙️')
text = text.replace('Ã¢â„¢Â¿', '♿')
text = text.replace('Ã°Å¸â€œÅ ', '📊')
text = text.replace('Ã°Å¸â€œÂ±', '📱')
text = text.replace('â€œ', '"')
text = text.replace('â€', '"')
text = text.replace('â€™', "'")

# The title had this
text = text.replace('Lucid Ã¢â‚¬â€œ Mindful Screen Time', 'Lucid - Mindful Screen Time')
text = text.replace('Lucid â€“ Mindful Screen Time', 'Lucid - Mindful Screen Time')

with io.open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(text)
