"""Generate original, replaceable card art. Requires Pillow; not needed to run game."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'uno'
ROOT.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
COLORS = {'red':'#e85c69','yellow':'#efbd53','green':'#45b696','blue':'#598ddd','wild':'#25394c'}
SYMBOLS = {'skip':'SKIP','reverse':'TURN','draw_two':'+2','wild':'WILD','draw_four':'+4'}
def text(d, xy, value, size, color, anchor='mm'):
    d.text(xy, value, font=ImageFont.truetype(FONT,size),fill=color,anchor=anchor)
def card(color,value):
    im=Image.new('RGB',(400,560),'#e8ece1'); d=ImageDraw.Draw(im)
    ink=COLORS[color]
    d.rounded_rectangle((15,15,385,545),radius=27,fill=ink)
    d.rounded_rectangle((34,34,366,526),radius=20,outline='#ffffff',width=2)
    d.line((54,122,346,122),fill='#ffffff',width=2)
    d.line((54,438,346,438),fill='#ffffff',width=2)
    label=SYMBOLS.get(value,value)
    text(d,(53,79),label,33,'#ffffff','lm')
    text(d,(348,481),label,33,'#ffffff','rm')
    if color=='wild':
        for i,c in enumerate(['red','yellow','green','blue']):
            x=83+(i%2)*120;y=159+(i//2)*120
            d.rounded_rectangle((x,y,x+112,y+112),radius=22,fill=COLORS[c])
        d.rounded_rectangle((64,227,336,330),radius=18,fill='#172a3a')
    else:
        d.rounded_rectangle((59,160,341,400),radius=35,fill='#f1f1df')
    text(d,(200,277),label,108 if len(label)<3 else 66,'#f1f1df' if color=='wild' else '#172a3a')
    text(d,(200,410),color.upper(),18,'#ffffff')
    im.save(ROOT/f'{color}_{value}.png')
for c in ['red','yellow','green','blue']:
    for v in list(map(str,range(10)))+['skip','reverse','draw_two']: card(c,v)
for v in ['wild','draw_four']:card('wild',v)
im=Image.new('RGB',(400,560),'#e8ece1');d=ImageDraw.Draw(im)
d.rounded_rectangle((15,15,385,545),radius=27,fill='#193a43')
for inset in range(36,151,22):d.rounded_rectangle((inset,inset,400-inset,560-inset),radius=25,outline='#568c8e',width=3)
d.rounded_rectangle((55,214,345,347),radius=24,fill='#193a43')
text(d,(200,265),'SPECTRUM',37,'#e8ece1');text(d,(200,312),'CARD TABLE',18,'#9fc9c0')
im.save(ROOT/'back.png')
