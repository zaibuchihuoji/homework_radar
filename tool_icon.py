"""Reproducible pixel-book identity, refined from the selected concept C.

Marks use a strict 32-cell visible grid. Adaptive layers keep the same mark
inside Android's 66-unit safe circle. Pillow is the only dependency.
"""
from argparse import ArgumentParser
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
YELLOW, INK, GOLD = '#FFE044', '#151B2B', '#AD7000'
SS = 4
COVER = [(6,15),(26,15),(26,16),(27,16),(27,17),(28,17),(28,23),(27,23),(27,25),(23,25),(23,26),(18,26),(18,27),(14,27),(14,26),(9,26),(9,25),(5,25),(5,23),(4,23),(4,17),(5,17),(5,16),(6,16)]
BACK_CUT = [(6,18),(8,18),(8,23),(11,23),(11,24),(13,24),(13,25),(10,25),(10,24),(6,24)]
PAGE = [(7,12),(10,12),(10,13),(12,13),(12,14),(14,14),(14,15),(16,15),(16,26),(14,26),(14,25),(12,25),(12,24),(9,24),(9,23),(7,23)]
PAGE_CUT = [(8,13),(9,13),(9,14),(11,14),(11,15),(13,15),(13,16),(15,16),(15,24),(14,24),(14,23),(12,23),(12,22),(8,22)]
STAR = [(15,5),(17,5),(17,7),(20,7),(20,8),(19,8),(19,9),(18,9),(18,10),(19,10),(19,12),(17,12),(17,11),(15,11),(15,12),(13,12),(13,10),(14,10),(14,9),(13,9),(13,8),(12,8),(12,7),(15,7)]


def mirror(points):
    return [(32-x,y) for x,y in points]


def mark_polygons(monochrome=False):
    ink = 'white' if monochrome else INK
    cut = (0,0,0,0) if monochrome else YELLOW
    return [(COVER,ink),(BACK_CUT,cut),(mirror(BACK_CUT),cut),
            (PAGE,ink),(mirror(PAGE),ink),(PAGE_CUT,cut),
            (mirror(PAGE_CUT),cut),(STAR,'white' if monochrome else GOLD)]


def draw_mark(size, adaptive=False, monochrome=False):
    image = Image.new('RGBA',(size,size))
    draw = ImageDraw.Draw(image)
    for points,color in mark_polygons(monochrome):
        # Half-open scanline spans keep every pixel cell equally wide. Pillow's
        # inclusive polygon bounds would otherwise thicken one side by 1px.
        for row in range(32):
            y=row+.5
            xs=sorted(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1])
                      for a,b in zip(points,points[1:]+points[:1])
                      if min(a[1],b[1]) <= y < max(a[1],b[1]))
            for left,right in zip(xs[::2],xs[1::2]):
                if adaptive:
                    coords=[(18+left*2.25)/108*size,(18+row*2.25)/108*size,
                            (18+right*2.25)/108*size,(18+(row+1)*2.25)/108*size]
                else:
                    coords=[left/32*size,row/32*size,right/32*size,(row+1)/32*size]
                x0,y0,x1,y1=map(round,coords)
                draw.rectangle((x0,y0,x1-1,y1-1),fill=color)
    return image


def foreground(size=1024, monochrome=False):
    return draw_mark(size,adaptive=True,monochrome=monochrome)


def square_icon(size=1024):
    image=Image.new('RGBA',(size,size),YELLOW)
    image.alpha_composite(draw_mark(size))
    return image


def rounded_icon(square):
    size=square.width
    mask=Image.new('L',(size*SS,size*SS))
    ImageDraw.Draw(mask).rounded_rectangle((0,0,size*SS-1,size*SS-1),radius=size*SS*.225,fill=255)
    result=square.copy()
    result.putalpha(mask.resize(square.size,Image.Resampling.LANCZOS))
    return result


def svg(content, viewbox='0 0 108 108'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewbox}" shape-rendering="crispEdges">\n{content}\n</svg>\n'


def vector_mark(monochrome=False):
    def path(points):
        return 'M'+'L'.join(f'{18+x*2.25:g} {18+y*2.25:g}' for x,y in points)+'Z'
    if monochrome:
        paths=''.join(f'<path d="{path(points)}" fill="'+('black' if isinstance(color,tuple) else 'white')+'"/>' for points,color in mark_polygons(True))
        return '<defs><mask id="mark"><rect width="108" height="108" fill="black"/>'+paths+'</mask></defs><rect width="108" height="108" fill="white" mask="url(#mark)"/>'
    return '\n'.join(f'<path d="{path(points)}" fill="{color}"/>' for points,color in mark_polygons())


def wordmark(font_path):
    badge=Image.new('RGBA',(720*SS,720*SS))
    badge.alpha_composite(rounded_icon(square_icon(252*SS)),(234*SS,175*SS))
    draw=ImageDraw.Draw(badge)
    font=ImageFont.truetype(str(font_path),84*SS)
    box=draw.textbbox((0,0),'作业通',font=font)
    draw.text(((720*SS-box[2]+box[0])/2-box[0],482*SS-box[1]),'作业通',font=font,fill=INK)
    # Match the 288dp image box observed on the Android system launch screen.
    return badge.resize((864,864),Image.Resampling.LANCZOS)


def slogan(font_path):
    image=Image.new('RGBA',(960*SS,450*SS))
    draw=ImageDraw.Draw(image)
    font=ImageFont.truetype(str(font_path),96*SS)
    for text,top in [('该交的作业',75),('一份不落',224)]:
        box=draw.textbbox((0,0),text,font=font)
        draw.text(((960*SS-box[2]+box[0])/2-box[0],top*SS-box[1]),text,font=font,fill=INK)
    return image.resize((960,450),Image.Resampling.LANCZOS)


def main():
    parser=ArgumentParser(description=__doc__)
    parser.add_argument('--font',type=Path,default=Path('C:/Windows/Fonts/msyhbd.ttc'))
    args=parser.parse_args()
    if not args.font.is_file():
        parser.error('Use --font with a Chinese bold TTF/TTC for launch typography')
    icons=ROOT/'assets/icon'
    icons.mkdir(parents=True,exist_ok=True)
    square=square_icon()
    square.convert('RGB').save(icons/'icon_square.png')
    rounded_icon(square).save(icons/'icon_rounded.png')
    foreground().save(icons/'icon_foreground.png')
    foreground(monochrome=True).save(icons/'icon_monochrome.png')
    mark=vector_mark()
    (icons/'icon_foreground.svg').write_text(svg(mark),encoding='utf-8')
    (icons/'icon_square.svg').write_text(svg(f'<rect x="18" y="18" width="72" height="72" fill="{YELLOW}"/>{mark}','18 18 72 72'),encoding='utf-8')
    (icons/'icon_rounded.svg').write_text(svg(f'<defs><clipPath id="tile"><rect x="18" y="18" width="72" height="72" rx="16.2"/></clipPath></defs><g clip-path="url(#tile)"><rect x="18" y="18" width="72" height="72" fill="{YELLOW}"/>{mark}</g>','18 18 72 72'),encoding='utf-8')
    (icons/'icon_monochrome.svg').write_text(svg(vector_mark(True)),encoding='utf-8')
    badge=wordmark(args.font)
    badge.save(ROOT/'assets/splash/splash_badge.png')
    slogan(args.font).save(ROOT/'assets/splash/splash_slogan.png')
    res=ROOT/'android/app/src/main/res'
    badge.save(res/'drawable-xxhdpi/splash_badge.png')
    badge.resize((288,288),Image.Resampling.LANCZOS).save(res/'drawable/splash_badge.png')
    launch=ROOT/'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    for scale,suffix in [(1,''),(2,'@2x'),(3,'@3x')]:
        badge.resize((288*scale,288*scale),Image.Resampling.LANCZOS).save(launch/f'LaunchImage{suffix}.png')
    (ROOT/'tool/splash_mark.svg').write_text(svg(mark),encoding='utf-8')
    print('Generated pixel-book icons and matching Android/iOS/Flutter launch artwork')


if __name__=='__main__':
    main()
