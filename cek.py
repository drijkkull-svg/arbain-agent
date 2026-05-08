file = r"android\app\src\main\kotlin\com\example\arbain_agent\ArbainAccessibilityService.kt"
with open(file, "r", encoding="utf-8") as f:
    content = f.read()
print("File berhasil dibaca!")
print("Panjang:", len(content))
