#!/usr/bin/env python3
"""Renders `tmux capture-pane -e -p` output (ANSI truecolor/256) to a PNG.

Usage: ansi2png.py capture.ans out.png [columns]
Half blocks (▀ ▄ █) are drawn as pixels so the pixel art reads correctly.
"""
import sys, re
from PIL import Image, ImageDraw, ImageFont
text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
out = sys.argv[2]
font = ImageFont.truetype('/System/Library/Fonts/Menlo.ttc', 16)
CW, CH = 10, 20
BG = (22, 25, 30)
lines = text.split('\n')
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 60
img = Image.new('RGB', (cols*CW, len(lines)*CH), BG)
d = ImageDraw.Draw(img)
pal256 = []
base = [(0,0,0),(205,0,0),(0,205,0),(205,205,0),(0,0,238),(205,0,205),(0,205,205),(229,229,229),(127,127,127),(255,0,0),(0,255,0),(255,255,0),(92,92,255),(255,0,255),(0,255,255),(255,255,255)]
pal256 += base
lv=[0,95,135,175,215,255]
for r in lv:
    for g in lv:
        for b in lv: pal256.append((r,g,b))
for i in range(24): v=8+i*10; pal256.append((v,v,v))
tok = re.compile(r'\x1b\[([0-9;]*)m|\x1b\[[0-9;?]*[A-Za-z]|(.)', re.S)
for y, line in enumerate(lines):
    fg=(214,214,214); bg=None; bold=False; x=0
    for m in tok.finditer(line):
        if m.group(2) is not None:
            ch = m.group(2)
            if bg: d.rectangle([x*CW, y*CH, (x+1)*CW-1, (y+1)*CH-1], fill=bg)
            if ch == '▀':
                d.rectangle([x*CW, y*CH, (x+1)*CW-1, y*CH+CH//2-1], fill=fg)
            elif ch == '▄':
                d.rectangle([x*CW, y*CH+CH//2, (x+1)*CW-1, (y+1)*CH-1], fill=fg)
            elif ch == '█':
                d.rectangle([x*CW, y*CH, (x+1)*CW-1, (y+1)*CH-1], fill=fg)
            elif ch != ' ':
                d.text((x*CW, y*CH), ch, font=font, fill=fg)
            x += 1
        elif m.group(1) is not None:
            ps = [int(p) if p else 0 for p in m.group(1).split(';')] if m.group(1) else [0]
            i=0
            while i < len(ps):
                p=ps[i]
                if p==0: fg=(214,214,214); bg=None; bold=False
                elif p==1: bold=True
                elif p==38 and ps[i+1]==2: fg=tuple(ps[i+2:i+5]); i+=4
                elif p==48 and ps[i+1]==2: bg=tuple(ps[i+2:i+5]); i+=4
                elif p==38 and ps[i+1]==5: fg=pal256[ps[i+2]]; i+=2
                elif p==48 and ps[i+1]==5: bg=pal256[ps[i+2]]; i+=2
                elif p==39: fg=(214,214,214)
                elif p==49: bg=None
                i+=1
img.save(out)
