import urllib.request
import re

url = "https://raw.githubusercontent.com/thewh1teagle/kokoro-onnx/main/kokoro_onnx/kokoro.py"
req = urllib.request.urlopen(url)
code = req.read().decode('utf-8')

# Search for how style is sliced or accessed
lines = code.split('\n')
for i, line in enumerate(lines):
    if 'style' in line or 'voices' in line:
        print(f"L{i}: {line.strip()}")
