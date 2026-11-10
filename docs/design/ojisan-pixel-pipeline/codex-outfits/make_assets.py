from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).parent
GEN = Path('/Users/yamadahiroki/.codex/generated_images/01a11651-9ef6-7973-89f6-40ab50bd83e5')
sources = {
    'a_work': GEN / 'exec-bf493778-e4d9-401e-95c4-454ef8ba6f71.png',
    'b_kimono': GEN / 'exec-de962ea9-ce88-409c-b489-6c306a8181a5.png',
}
labels = {
    'a_work': [
        ('front_neutral', '前・真顔', 0, 0),
        ('right_neutral', '画面右向き・真顔', 1, 0),
        ('left_neutral', '画面左向き・真顔', 2, 0),
        ('back_neutral', '後ろ・真顔', 0, 1),
        ('carry_light_smile', '軽い荷物・笑顔', 1, 1),
        ('carry_heavy_pain_sweat', '重い荷物・痛い', 2, 1),
        ('limit_back_pain', '限界・腰を押さえる', 0, 2),
        ('fallen_face_down_crying', '倒れる・泣いてる', 1, 2),
    ],
    'b_kimono': [
        ('front_neutral', '前・真顔', 0, 0),
        ('right_neutral', '画面右向き・真顔', 1, 0),
        ('left_neutral', '画面左向き・真顔', 2, 0),
        ('back_neutral', '後ろ・真顔', 0, 1),
        ('bonsai_smile', '盆栽を眺める・笑顔', 1, 1),
        ('prune_right_neutral', '剪定・画面右向き・真顔', 2, 1),
        ('celebrate_front_smile', '大喜び・笑顔', 0, 2),
        ('disappointed_front_crying', 'がっかり・泣いてる', 1, 2),
    ],
}
font_path = '/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc'
font = ImageFont.truetype(font_path, 28)
small_font = ImageFont.truetype(font_path, 22)

for outfit, source in sources.items():
    out_dir = ROOT / outfit
    out_dir.mkdir(exist_ok=True)
    raw_img = Image.open(source).convert('RGBA')
    source_img = Image.alpha_composite(Image.new('RGBA', raw_img.size, 'white'), raw_img).convert('RGB')
    sw, sh = source_img.size
    cell_w, cell_h = sw // 3, sh // 3
    sheet = Image.new('RGB', (1600, 1220), 'white')
    draw = ImageDraw.Draw(sheet)
    title = '作業服' if outfit == 'a_work' else '和の着物'
    draw.text((50, 24), title, fill='#3b241b', font=font)
    for idx, (name, label, col, row) in enumerate(labels[outfit]):
        x0, y0 = col * cell_w, row * cell_h
        x1 = (col + 1) * cell_w if col < 2 else sw
        y1 = (row + 1) * cell_h if row < 2 else sh
        crop = source_img.crop((x0, y0, x1, y1))
        crop.save(out_dir / f'{name}.png')
        x = 20 + (idx % 4) * 395
        y = 85 + (idx // 4) * 555
        crop.thumbnail((360, 450), Image.Resampling.LANCZOS)
        sheet.paste(crop, (x + (360 - crop.width) // 2, y))
        box = draw.textbbox((0, 0), label, font=small_font)
        tw = box[2] - box[0]
        draw.text((x + (360 - tw) // 2, y + 455), label, fill='#3b241b', font=small_font)
    sheet.save(ROOT / f'sheet_{"a" if outfit == "a_work" else "b"}.png')
