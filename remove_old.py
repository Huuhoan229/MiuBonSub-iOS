import re

with open('ios/App/App/NativeApp.swift', 'r', encoding='utf-8') as f:
    content = f.read()

# The old VideoPlayerSheet starts at 3192 and ends before "struct SeriesCard: View {"
start_old = content.rfind("struct VideoPlayerSheet: View {")
end_old = content.find("struct SeriesCard: View {", start_old)

if start_old != -1 and end_old != -1:
    content = content[:start_old] + content[end_old:]
    with open('ios/App/App/NativeApp.swift', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Deleted old VideoPlayerSheet.")
else:
    print("Not found.")
