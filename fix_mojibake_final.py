import io

with io.open('lib/main.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Exact string replacements for the final remaining double mojibake!
text = text.replace('Get Started â†’', 'Get Started →')
text = text.replace('âœ…', '✅')
text = text.replace('âš™ï¸ ', '⚙️')
text = text.replace('â™¿', '♿')
text = text.replace('ðŸ“±', '📱')
text = text.replace('âš ï¸ ', '⚠️')
text = text.replace('â °', '⏰')
text = text.replace('â†’', '→')

with io.open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(text)
