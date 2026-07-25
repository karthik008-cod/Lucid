import io
import re

with io.open('lib/main.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix emojis by replacing the garbled text between quotes
text = re.sub(r"'Opening App Info\.\.\. Please allow restricted settings\.', '.*?'", r"'Opening App Info... Please allow restricted settings.', '⚙️'", text)
text = re.sub(r"'Opening Accessibility Settings\.\.\. Please enable Lucid!', '.*?'", r"'Opening Accessibility Settings... Please enable Lucid!', '♿'", text)
text = re.sub(r"'Opening Usage Access Settings\.\.\. Please grant access!', '.*?'", r"'Opening Usage Access Settings... Please grant access!', '📊'", text)
text = re.sub(r"'Please grant both permissions to continue!', '.*?'", r"'Please grant both permissions to continue!', '⚠️'", text)

text = re.sub(r"'Warning timer updated to (.*?)!', '.*?'", r"'Warning timer updated to \1!', '⏰'", text)
text = re.sub(r"'Warning timer set to (.*?)!', '.*?'", r"'Warning timer set to \1!', '⏰'", text)

text = re.sub(r"icon: '.*?',\n\s*title: 'Allow Restricted Settings'", r"icon: '⚙️',\n                        title: 'Allow Restricted Settings'", text)
text = re.sub(r"icon: '.*?',\n\s*title: 'Accessibility Service'", r"icon: '♿',\n                        title: 'Accessibility Service'", text)
text = re.sub(r"icon: '.*?',\n\s*title: 'Usage Access'", r"icon: '📊',\n                        title: 'Usage Access'", text)

text = re.sub(r"the top-right .*? menu", r"the top-right ⋮ menu", text)

text = re.sub(r"'Get Started .*?'", r"'Get Started →'", text)

# For HomeScreen toggle
text = re.sub(r"from monitored apps', value \? '.*?' : '.*?'\)\;", r"from monitored apps', value ? '✅' : '❌');", text)

with io.open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(text)
