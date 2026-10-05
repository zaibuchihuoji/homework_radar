# -*- coding: utf-8 -*-
"""「作业通」启动图标 v3：
纯色靛蓝底 + 微倾的作业清单纸（题目行 + 橙色勾选）+ 截止时钟角标。
4x 超采样，LANCZOS 缩小。"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4
W = S * SS

INDIGO = (79, 70, 229, 255)        # 4F46E5 背景
PAPER = (255, 255, 255, 255)
LINE = (201, 206, 249, 255)        # 纸上题目行 C9CEF9
ORANGE_TOP = (255, 146, 62)
ORANGE_BOT = (243, 104, 26)
SHADOW = (22, 18, 88)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def paper_layer(u):
    """画一张清单纸（含题目行与勾选），返回 RGBA 图，稍后整体旋转。"""
    pw, ph = int(352 * u), int(430 * u)
    layer = Image.new("RGBA", (int(pw * 1.6), int(ph * 1.6)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = (layer.size[0] - pw) // 2, (layer.size[1] - ph) // 2

    # 纸
    d.rounded_rectangle((ox, oy, ox + pw, oy + ph), radius=40 * u, fill=PAPER)

    # 行内容（左右留白 44）
    lx, rx = ox + 44 * u, ox + pw - 44 * u
    row_y = [oy + 78 * u, oy + 178 * u, oy + 278 * u]

    # 行1：橙色勾选圆 + 行
    ccx, ccy, cr = lx + 26 * u, row_y[0] + 10 * u, 26 * u
    d.ellipse((ccx - cr, ccy - cr, ccx + cr, ccy + cr), fill=ORANGE_TOP)
    chk = [(ccx - 12 * u, ccy + 1 * u), (ccx - 3 * u, ccy + 11 * u), (ccx + 14 * u, ccy - 9 * u)]
    d.line(chk, fill=(255, 255, 255, 255), width=int(8 * u), joint="curve")
    d.line([(ccx + 56 * u, row_y[0] + 10 * u), (rx, row_y[0] + 10 * u)],
           fill=LINE, width=int(20 * u))

    # 行2 / 行3
    d.rounded_rectangle((lx, row_y[1], rx, row_y[1] + 20 * u), radius=10 * u, fill=LINE)
    d.rounded_rectangle((lx, row_y[2], lx + 210 * u, row_y[2] + 20 * u), radius=10 * u, fill=LINE)

    return layer


def paper_and_badge(d, mark_cx, mark_cy, u):
    """在 draw 目标上画：投影 + 旋转-6°的纸 + 右下角时钟角标。"""
    # 纸层 → 旋转 -6°
    layer = paper_layer(u)
    layer = layer.rotate(-6, resample=Image.Resampling.BICUBIC, expand=True)

    # 柔投影：用纸的 alpha 做剪影
    alpha = layer.split()[3]
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    tint = Image.new("RGBA", layer.size, SHADOW + (60,))
    sh.paste(tint, (int(4 * u), int(14 * u)), alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(9 * u))

    px = int(mark_cx - layer.size[0] / 2)
    py = int(mark_cy - layer.size[1] / 2)

    d._image.alpha_composite(sh, (px, py))
    d._image.alpha_composite(layer, (px, py))

    # ---- 时钟角标（纸右下角，重叠）----
    bx = mark_cx + 168 * u
    by = mark_cy + 158 * u
    br = 84 * u

    sh2 = Image.new("RGBA", d._image.size, (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(sh2)
    sd2.ellipse((bx - br + 3 * u, by - br + 8 * u, bx + br + 3 * u, by + br + 8 * u),
                fill=SHADOW + (46,))
    sh2 = sh2.filter(ImageFilter.GaussianBlur(8 * u))
    d._image.alpha_composite(sh2)

    # 背景色环（从背景“抠出”的分离感）
    d.ellipse((bx - br, by - br, bx + br, by + br), fill=INDIGO)
    face = br - 12 * u

    bw = int(face * 2)
    badge = Image.new("RGB", (bw, bw))
    bd = ImageDraw.Draw(badge)
    for y in range(bw):
        bd.line([(0, y), (bw, y)], fill=lerp(ORANGE_TOP, ORANGE_BOT, y / bw))
    mask = Image.new("L", (bw, bw), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, bw - 1, bw - 1), fill=255)
    d._image.paste(badge, (int(bx - face), int(by - face)), mask)

    lw = int(12 * u)
    d.line([(int(bx), int(by)), (int(bx), int(by - 44 * u))], fill=(255, 255, 255, 255), width=lw)
    d.line([(int(bx), int(by)), (int(bx + 32 * u), int(by + 20 * u))], fill=(255, 255, 255, 255), width=lw)
    cr = int(8 * u)
    d.ellipse((bx - cr, by - cr, bx + cr, by + cr), fill=(255, 255, 255, 255))


def compose(path):
    img = Image.new("RGBA", (W, W), INDIGO)
    d = ImageDraw.Draw(img)
    paper_and_badge(d, W * 0.49, W * 0.5, u=W / 1024)
    img.resize((S, S), Image.Resampling.LANCZOS).save(path)


import os
os.makedirs("assets/icon", exist_ok=True)

compose("assets/icon/icon_rounded.png")
compose("assets/icon/icon_square.png")

fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
dfg = ImageDraw.Draw(fg)
paper_and_badge(dfg, W * 0.49, W * 0.5, u=W / 1024)
fg.resize((S, S), Image.Resampling.LANCZOS).save("assets/icon/icon_foreground.png")

print("v3 icons written")
