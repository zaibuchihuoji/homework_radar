# 合成一张课表截图（青果风格格子：课程名/教师/周次[节次]/教室），
# 用于 OCR 导入端到端验证。小字 + 短边 900，触发 app 内的放大预处理。
from PIL import Image, ImageDraw, ImageFont

W, H = 900, 1400
GUTTER = 90
COLW = (W - GUTTER) / 7
ROW_TOP = 110
ROWH = 240

font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 17)
font_header = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 22)

days = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]

def wrap(s, n=7):
    return [s[i:i + n] for i in range(0, len(s), n)]

# (星期, 大节行0-4, 多门课；每门课 3-4 行文本)
cells = [
    (0, 0, [["网络系统管理A", "陆文静", "1-5,8-19[1-2]", "三教107"]]),
    (0, 1, [["软件工程A", "宋卫卫", "1-5,8-15[3-4]", "三教409"]]),
    (0, 2, [["数字图像处理导论", "徐修如", "1-5,8-15[5-6]", "三教202"]]),
    (1, 1, [["计算机网络A", "李世奇 黄连树", "1-5,8-16[3-4]", "二教815"]]),
    (1, 2, [["科技文献检索", "兰张奇", "1-5,8-10[5-6]", "三教106"]]),
    (1, 3, [["毛泽东思想概论", "徐静娴", "1-5,8,14[7-8]", "三教405"]]),
    (2, 0, [["计算机组成原理", "胡伟华", "1-5,8-10[1-2]", "三教404"]]),
    (2, 2, [["算法设计与分析A", "苏牧", "1-5,8-13双[5-6]", "三教407"]]),
    (3, 0, [["毛泽东思想概论", "涂海燕", "1-5,8,14双[1-2]", "三教407"],
            ["软件工程B", "全雪松", "1-5,8-15单[1-2]", "三教407"]]),
    (4, 0, [["画法设计与分析A", "翁修焓", "1-5,8-19[1-2]", "三教109"]]),
    (4, 1, [["大学语文", "边加强", "1-5,8-10[3-4]", "三教409"]]),
    (4, 2, [["计算机组成原理", "鲍军生", "1-5,8-10[5-6]", "三教404"]]),
]

img = Image.new("RGB", (W, H), "#f7f8fa")
d = ImageDraw.Draw(img)

for i, name in enumerate(days):
    cx = GUTTER + COLW * (i + 0.5)
    d.text((cx, 60), name, font=font_header, fill="#333", anchor="mm")

for r in range(5):
    y = ROW_TOP + ROWH * r + ROWH / 2
    d.text((GUTTER - 40, y), str(r + 1), font=font, fill="#666", anchor="mm")
d.text((14, 320), "上午", font=font, fill="#999")
d.text((14, 830), "下午", font=font, fill="#999")
d.text((14, 1250), "晚上", font=font, fill="#999")

for day, row, courses in cells:
    x0 = GUTTER + COLW * day + 4
    y0 = ROW_TOP + ROWH * row + 8
    bg = ["#fdeef0", "#eef7ee", "#eef4fa", "#fdf6ea"][(day + row) % 4]
    d.rounded_rectangle([x0, y0, x0 + COLW - 8, y0 + ROWH - 12], 8, fill=bg)
    y = y0 + 6
    for lines in courses:
        for line in lines:
            for seg in wrap(line):
                d.text((x0 + 6, y), seg, font=font, fill="#333")
                y += 24
        y += 6

img.save(r"D:\opencode-sessions\work-note\homework_radar\tool\e2e_mock\mock_kebiao.png")
print("saved", img.size)
