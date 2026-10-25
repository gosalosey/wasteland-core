import sys, os
from PIL import Image, ImageDraw
files = sys.argv[2:]; out = sys.argv[1]
cols = 4; W, H = 480, 360
rows = (len(files) + cols - 1) // cols
sheet = Image.new('RGB', (cols * W, rows * (H + 24)), (20, 22, 19)); d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    x, y = (i % cols) * W, (i // cols) * (H + 24)
    sheet.paste(Image.open(f).convert('RGB'), (x, y))
    d.text((x + 8, y + H + 6), os.path.basename(f)[6:-4].replace('_', ' '), fill=(230, 230, 220))
sheet.save(out)
