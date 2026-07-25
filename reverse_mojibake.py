import io
import re

with io.open('lib/main.dart', 'r', encoding='utf-8') as f:
    text = f.read()

def fix_match(m):
    # Try to decode the corrupted text back to original
    try:
        return m.group(0).encode('cp1252').decode('utf-8')
    except:
        return m.group(0)

# Find any sequence of 2 or more characters that start with Ã
text = re.sub(r'Ã[^\s]+', fix_match, text)

# Also fix the weird quotes
text = text.replace('â€œ', '"')
text = text.replace('â€', '"')
text = text.replace('â€™', "'")
text = text.replace('â€“', "-")

with io.open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(text)
