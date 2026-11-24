#!/usr/bin/env python3
"""NEON BREAKER. Compile a complete game to the project's 26-bit CPU ISA.

No host runtime or graphics accelerator is used on the board. Python only
assembles instructions; every game rule and framebuffer write runs on cpu_core.
"""
from pathlib import Path
import json
from contextlib import contextmanager

HERE = Path(__file__).resolve().parent
BG = 0x8000                         # word-addressed backing image (19200 words)
HP, BX, BY, XMAP, YMAP = 0x5100, 0x5200, 0x5300, 0x5400, 0x5500
BC, BL, BS = 0x5600, 0x5700, 0x5800
# Deliberate 8-color palette, not truncation of RGB222.
PALETTE = {0:0,1:0,2:1,5:1,6:1,8:2,10:3,11:3,12:2,15:3,22:3,26:3,29:7,31:7,33:4,34:4,40:4,50:5,51:5,60:6,63:7}
NAMES = 'px x y dx dy tx ty mode lives level remain units tens hundreds buttons previous edges index hp bx by row oldrow steps trailx traily ticks body light shadow drawn_px paddle_valid'.split()
V = {name: 0x5000+i for i,name in enumerate(NAMES)}
OPS = {'ADD':0,'SUB':1,'AND':2,'OR':3,'XOR':4,'MUL':5,'LOADC':6,'LOAD':7,'STORE':8,'JUMP':9,'JZ':10,'NOP':15}

class Assembler:
    def __init__(self): self.code=[]; self.labels={}; self.serial=0
    def unique(self, name='L'):
        self.serial+=1; return f'{name}_{self.serial}'
    def label(self,name):
        assert name not in self.labels, name
        self.labels[name]=len(self.code)
    def emit(self,op,*args): self.code.append((op,args))
    def c(self,r,v): self.emit('LOADC',r,v)
    def jump(self,l): self.emit('JUMP',l)
    def val(self,r,v):
        if isinstance(v,str):
            self.c(12,V[v]); self.emit('LOAD',r,12)
        else:
            if v<0:
                self.c(r,-v); self.emit('SUB',r,0,r)
            else:self.c(r,v)
    def save(self,v,r): self.c(12,V[v]); self.emit('STORE',r,12)
    def set(self,v,x): self.val(3,x); self.save(v,3)
    def calc(self,v,op,a,b):
        self.val(3,a);self.val(4,b);self.emit(op,3,3,4);self.save(v,3)
    def branch(self,op,a,b,label):
        self.val(3,a); self.val(4,b)
        if op in ('>','<='): self.emit('SUB',5,4,3)
        else: self.emit('SUB',5,3,4)
        if op=='==':self.emit('JZ',5,label)
        elif op=='!=':
            skip=self.unique();self.emit('JZ',5,skip);self.jump(label);self.label(skip)
        else:
            self.emit('AND',5,5,2)
            if op in ('>=','<='):self.emit('JZ',5,label)
            else:
                skip=self.unique();self.emit('JZ',5,skip);self.jump(label);self.label(skip)
    @contextmanager
    def when(self,op,a,b):
        end=self.unique('endif'); inverse={'==':'!=','!=':'==','<':'>=','>':'<=','>=':'<','<=':'>'}
        self.branch(inverse[op],a,b,end)
        yield
        self.label(end)
    def rect(self,x,y,w,h,color=1,back=True,restore=False,ox=0,oy=0):
        # Scratch r3..r11; r0=0 r1=1 r2=sign r13=160 r14=backing-base.
        if isinstance(x,int) and isinstance(y,int):self.c(7,(y+oy)*160+x+ox)
        else:
            self.val(3,x);self.val(4,y)
            if ox:self.val(5,ox);self.emit('ADD',3,3,5)
            if oy:self.val(5,oy);self.emit('ADD',4,4,5)
            self.emit('MUL',4,4,13);self.emit('ADD',7,3,4)
        if not restore:self.val(5,PALETTE[color] if isinstance(color,int) else color)
        if h>1:self.c(6,h)
        row=self.unique('row');self.label(row)
        self.emit('ADD',3,7,0)
        if back or restore:self.emit('ADD',10,3,14)
        def pixel():
            if restore:self.emit('LOAD',11,10);self.emit('STORE',11,3)
            else:
                self.emit('STORE',5,3)
                if back:self.emit('STORE',5,10)
            self.emit('ADD',3,3,1)
            if back or restore:self.emit('ADD',10,10,1)
        if w<=32:
            for _ in range(w):pixel()
        else:
            self.c(8,w);col=self.unique('col');end=self.unique('col_end');self.label(col)
            pixel();self.emit('SUB',8,8,1);self.emit('JZ',8,end);self.jump(col);self.label(end)
        if h>1:
            end=self.unique('rect_end');self.emit('ADD',7,7,13);self.emit('SUB',6,6,1)
            self.emit('JZ',6,end);self.jump(row);self.label(end)
    def text(self,text,x,y,color=63,back=True):
        for k,ch in enumerate(text):
            for dy,row in enumerate(FONT[ch]):
                dx=0
                while dx<3:
                    if row[dx]=='1':
                        end=dx+1
                        while end<3 and row[end]=='1':end+=1
                        self.rect(x+4*k+dx,y+dy,end-dx,1,color,back)
                        dx=end
                    else:dx+=1
    def resolve(self):
        words=[]
        for op,args in self.code:
            n=OPS[op]
            if op=='JUMP':w=(n<<22)|self.labels[args[0]]
            elif op=='JZ':w=(n<<22)|(args[0]<<17)|self.labels[args[1]]
            elif op=='LOADC':
                r,v=args;assert 0<=v<131072;w=(n<<22)|(r<<17)|v
            else:
                rd,ra,*rb=args;w=(n<<22)|(rd<<17)|(ra<<12)|((rb[0] if rb else 0)<<7)
            assert w<1<<26;words.append(w)
        assert len(words)<131072, 'Flash instruction address overflow'
        return words

FONT={}
for c,rows in {
 ' ':'000 000 000 000 000','A':'010 101 111 101 101','B':'110 101 110 101 110',
 'C':'011 100 100 100 011','D':'110 101 101 101 110','E':'111 100 110 100 111',
 'F':'111 100 110 100 100','G':'011 100 101 101 011','H':'101 101 111 101 101',
 'I':'111 010 010 010 111','J':'001 001 001 101 010','K':'101 101 110 101 101',
 'L':'100 100 100 100 111','M':'101 111 111 101 101','N':'101 111 111 111 101',
 'O':'010 101 101 101 010','P':'110 101 110 100 100','Q':'010 101 101 011 001',
 'R':'110 101 110 101 101','S':'011 100 010 001 110','T':'111 010 010 010 010',
 'U':'101 101 101 101 111','V':'101 101 101 101 010','W':'101 101 111 111 101',
 'X':'101 101 010 101 101','Y':'101 101 010 010 010','Z':'111 001 010 100 111',
 '0':'111 101 101 101 111','1':'010 110 010 010 111','2':'110 001 010 100 111',
 '3':'110 001 010 001 110','4':'101 101 111 001 001','5':'111 100 110 001 110',
 '6':'011 100 111 101 111','7':'111 001 010 010 010','8':'111 101 111 101 111',
 '9':'111 101 111 001 110','-':'000 000 111 000 000',':':'000 010 000 010 000'
}.items(): FONT[c]=rows.split()

def build():
    a=Assembler()
    a.c(0,0);a.c(1,1);a.c(2,65536);a.c(3,32768);a.emit('MUL',2,2,3)
    a.c(13,160);a.c(14,BG)
    # Collision lookup tables: index 255 denotes empty space.
    for x in range(160):
        # Ball radius is one pixel: expand the 15-pixel brick by one per side.
        col=(x-11)//17 if 11<=x<147 else 255
        a.c(3,XMAP+x);a.c(4,col);a.emit('STORE',4,3)
    for y in range(120):
        row=((y-23)//10)*8 if 23<=y<72 and (y-23)%10<9 else 255
        a.c(3,YMAP+y);a.c(4,row);a.emit('STORE',4,3)
    for i in range(40):
        body,light,shadow=[(51,63,34),(50,63,33),(11,31,6),(12,29,8),(60,63,40)][i//8]
        for base,value in [(BX,12+(i%8)*17),(BY,24+(i//8)*10),(BC,body),(BL,light),(BS,shadow)]:
            a.c(3,base+i);a.c(4,PALETTE[value] if base in (BC,BL,BS) else value);a.emit('STORE',4,3)
    a.label('new_game')
    for name in NAMES:a.set(name,0)
    a.set('lives',3);a.set('level',1)
    a.label('new_level')
    a.set('remain',40);a.set('px',68);a.set('mode',0);a.set('paddle_valid',0)
    a.rect(0,0,160,120,1)
    # Chrome framing, inset playfield, status panel, luminous rails.
    for x,y,w,h,c in [(0,0,160,14,5),(0,0,160,1,15),(0,13,160,1,10),
                       (0,14,6,100,0),(154,14,6,100,0),(6,16,148,1,22),
                       (6,17,2,97,6),(152,17,2,97,6),(7,17,1,96,15),
                       (152,17,1,96,15),(8,113,144,1,22),(0,114,160,6,0)]:a.rect(x,y,w,h,c)
    for y in range(20,110,9):
        a.rect(2,y,2,3,11);a.rect(156,y,2,3,11)
    a.text('NEON',5,3,15);a.text('BREAKER',24,3,63)
    a.text('SCORE',69,3,26);a.text('LV',109,3,26)
    a.text('A LAUNCH',12,115,26);a.text('START PAUSE',103,115,26)
    # Low-contrast constellation is part of the saved background, not animation.
    for i in range(24):
        sx=12+(i*47)%132;sy=78+(i*13)%24
        a.rect(sx,sy,1,1,6 if i%3==0 else 2)
    a.text('N E O N',66,85,6);a.text('V A U L T',62,92,2)
    a.set('index',0)
    a.label('init_bricks')
    a.val(3,'index');a.c(4,HP);a.emit('ADD',4,4,3)
    a.val(5,'level');a.emit('STORE',5,4)
    a.calc('index','ADD','index',1)
    a.branch('<','index',40,'init_bricks')
    a.set('index',0)
    a.label('draw_initial_brick')
    # Common renderer uses a continuation ID, stored in RAM because it uses scratch registers.
    a.set('ticks',0);a.jump('brick_render')
    a.label('initial_brick_return')
    a.calc('index','ADD','index',1);a.branch('<','index',40,'draw_initial_brick')
    a.jump('hud')

    a.label('brick_render')
    for var,base in [('bx',BX),('by',BY),('hp',HP),('body',BC),('light',BL),('shadow',BS)]:
        a.val(3,'index');a.c(4,base);a.emit('ADD',4,4,3);a.emit('LOAD',5,4);a.save(var,5)
    with a.when('!=','ticks',0):
        with a.when('>','hp',0):
            # A damaged brick only loses one lit pip; its bevel does not change.
            for pip in (1,2):
                with a.when('==','hp',pip):a.rect('bx','by',1,1,'body',ox=5+2*pip,oy=4)
            a.jump('hit_return')
    a.rect('bx','by',15,7,1)
    with a.when('>','hp',0):
        a.rect('bx','by',15,7,'shadow')
        a.rect('bx','by',13,5,'body',ox=1,oy=1)
        a.rect('bx','by',13,1,'light',ox=1)
        a.rect('bx','by',1,4,'light',oy=1)
        a.rect('bx','by',7,1,'light',ox=3,oy=2)
        for pip in range(3):
            with a.when('>','hp',pip):a.rect('bx','by',1,1,63,ox=5+2*pip,oy=4)
    a.branch('==','ticks',0,'initial_brick_return');a.jump('hit_return')

    a.label('hud')
    for var,x in [('hundreds',91),('tens',95),('units',99)]:
        skip=a.unique('digit_unchanged')
        with a.when('==','mode',1):
            if var!='units':a.branch('!=','units',0,skip)
            if var=='hundreds':a.branch('!=','tens',0,skip)
        a.rect(x,3,3,5,5)
        for digit in range(10):
            with a.when('==',var,digit):a.text(str(digit),x,3,63)
        a.label(skip)
    a.branch('==','mode',1,'score_register')
    a.rect(119,2,5,7,5)
    for level in range(1,4):
        with a.when('==','level',level):a.text(str(level),120,3,60)
    a.rect(130,2,25,8,5)
    for life in range(3):
        with a.when('>','lives',life):
            x=132+life*8
            a.rect(x,3,2,2,51);a.rect(x+3,3,2,2,51);a.rect(x,5,5,1,51);a.rect(x+1,6,3,1,51);a.rect(x+2,7,1,1,63)
    a.label('score_register')
    a.val(3,'hundreds');a.c(4,100);a.emit('MUL',3,3,4)
    a.val(5,'tens');a.c(4,10);a.emit('MUL',5,5,4);a.emit('ADD',3,3,5)
    a.val(5,'units');a.emit('ADD',3,3,5);a.c(4,0x1fffd);a.emit('STORE',3,4)
    a.branch('==','mode',1,'post_hit')
    a.branch('==','mode',3,'game_over_panel')
    a.jump('serve_setup')

    a.label('serve_setup')
    a.set('mode',0);a.calc('x','ADD','px',12);a.set('y',104)
    a.set('dx',1);a.set('dy',-1);a.set('trailx','x');a.set('traily','y')
    a.jump('render')

    # One falling VSYNC edge per update. Full frame writes are never attempted here.
    a.label('frame_wait')
    a.c(12,0x1fffe)
    a.label('wait_high');a.emit('LOAD',3,12);a.emit('JZ',3,'wait_high')
    a.label('wait_low');a.emit('LOAD',3,12);a.emit('JZ',3,'frame');a.jump('wait_low')
    a.label('frame')
    a.c(12,0x1ffff);a.emit('LOAD',3,12);a.save('buttons',3)
    a.val(4,'previous');a.emit('XOR',4,3,4);a.emit('AND',4,3,4);a.save('edges',4);a.save('previous',3)
    a.calc('tx','AND','edges',64);a.branch('!=','tx',0,'new_game')
    a.branch('>=','mode',3,'end_input')
    a.calc('tx','AND','edges',32)
    with a.when('!=','tx',0):
        a.branch('==','mode',2,'resume')
        a.branch('==','mode',1,'pause')
    a.branch('==','mode',2,'frame_wait')
    a.rect('trailx','traily',3,3,restore=True,ox=-1,oy=-1)
    a.rect('x','y',3,3,restore=True,ox=-1,oy=-1)
    # Clamp after two-pixel paddle steps, rather than relying on exact equality.
    a.calc('tx','AND','buttons',1)
    with a.when('!=','tx',0):a.calc('px','SUB','px',2)
    a.calc('tx','AND','buttons',2)
    with a.when('!=','tx',0):a.calc('px','ADD','px',2)
    with a.when('<','px',9):a.set('px',9)
    with a.when('>','px',127):a.set('px',127)
    a.branch('==','mode',0,'serve_input')
    a.set('trailx','x');a.set('traily','y')
    # Two one-pixel collision steps per update; later levels use three.
    a.set('steps',2)
    with a.when('>','level',1):a.set('steps',3)
    a.label('physics')
    a.val(3,'y');a.c(4,YMAP);a.emit('ADD',4,4,3);a.emit('LOAD',5,4);a.save('oldrow',5)
    a.calc('x','ADD','x','dx');a.calc('y','ADD','y','dy')
    with a.when('<=','x',10):a.set('x',10);a.set('dx',1)
    with a.when('>=','x',149):a.set('x',149);a.set('dx',-1)
    with a.when('<=','y',19):a.set('y',19);a.set('dy',1)
    with a.when('==','dy',1):
        with a.when('==','y',106):
            a.calc('tx','SUB','x','px')
            with a.when('>=','tx',-1):
                with a.when('<=','tx',24):
                    a.set('dy',-1)
                    a.set('dx',1)
                    with a.when('<','tx',12):a.set('dx',-1)
    a.branch('>=','y',112,'lost_ball')
    # Bounded lookup: both coordinates have been clamped before table access.
    a.val(3,'y');a.c(4,YMAP);a.emit('ADD',4,4,3);a.emit('LOAD',5,4);a.save('row',5)
    a.branch('==','row',255,'post_hit')
    a.val(3,'x');a.c(4,XMAP);a.emit('ADD',4,4,3);a.emit('LOAD',5,4);a.save('tx',5)
    a.branch('==','tx',255,'post_hit')
    a.calc('index','ADD','row','tx')
    a.val(3,'index');a.c(4,HP);a.emit('ADD',4,4,3);a.emit('LOAD',5,4)
    a.emit('JZ',5,'post_hit');a.emit('SUB',5,5,1);a.emit('STORE',5,4);a.save('hp',5)
    with a.when('==','hp',0):a.calc('remain','SUB','remain',1)
    a.branch('==','row','oldrow','bounce_x')
    a.calc('dy','SUB',0,'dy');a.jump('score_hit')
    a.label('bounce_x');a.calc('dx','SUB',0,'dx')
    a.label('score_hit')
    # Move the ball out of the just-hit cell, preventing repeated same-cell hits.
    a.calc('x','ADD','x','dx');a.calc('y','ADD','y','dy')
    a.calc('units','ADD','units',1)
    with a.when('==','units',10):
        a.set('units',0);a.calc('tens','ADD','tens',1)
        with a.when('==','tens',10):a.set('tens',0);a.calc('hundreds','ADD','hundreds',1)
    a.set('ticks',1);a.jump('brick_render')
    a.label('hit_return');a.jump('hud')
    a.label('post_hit')
    a.branch('==','remain',0,'level_complete')
    a.calc('steps','SUB','steps',1);a.branch('>','steps',0,'physics')
    a.jump('render')
    a.label('serve_input')
    a.calc('x','ADD','px',12);a.set('trailx','x');a.set('traily','y')
    a.calc('tx','AND','edges',48)
    with a.when('!=','tx',0):a.set('mode',1)
    a.jump('render')
    a.label('lost_ball')
    a.calc('lives','SUB','lives',1);a.set('mode',0)
    a.branch('==','lives',0,'game_over');a.jump('hud')
    a.label('level_complete')
    a.branch('==','level',3,'victory');a.calc('level','ADD','level',1);a.jump('new_level')
    a.label('pause')
    a.set('mode',2)
    a.rect(49,80,62,13,5,back=False);a.rect(49,80,62,1,15,back=False)
    a.text('PAUSED',68,84,63,back=False);a.jump('frame_wait')
    a.label('resume')
    a.rect(49,80,62,13,restore=True);a.set('mode',1);a.jump('render')
    a.label('game_over')
    a.set('mode',3);a.jump('hud')
    a.label('game_over_panel')
    a.rect(38,80,84,22,5);a.rect(38,80,84,1,51)
    a.text('GAME OVER',62,84,51);a.text('A TO RETRY',60,93,63);a.jump('frame_wait')
    a.label('victory')
    a.set('mode',4);a.rect(31,80,98,22,5);a.rect(31,80,98,1,60)
    a.text('VAULT CLEARED',54,84,60);a.text('A TO REPLAY',58,93,63);a.jump('frame_wait')
    a.label('end_input')
    a.calc('tx','AND','edges',48);a.branch('!=','tx',0,'new_game');a.jump('frame_wait')
    a.label('render')
    # Glowing motion trail, small highlight, and a three-tone chrome paddle.
    with a.when('==','mode',1):a.rect('trailx','traily',3,3,6,back=False,ox=-1,oy=-1)
    a.rect('x','y',3,3,60,back=False,ox=-1,oy=-1)
    a.rect('x','y',2,1,63,back=False,ox=-1,oy=-1)
    # Write each paddle pixel in its final color: never blank the whole sprite
    # or temporarily cover its bright face with a darker base rectangle.
    # Redraw also repairs any ball/trail pixels overlapping the paddle edge.
    a.rect('px',108,1,3,6,back=False)
    a.rect('px',108,1,3,6,back=False,ox=23)
    a.rect('px',108,22,1,63,back=False,ox=1)
    a.rect('px',109,1,2,6,back=False,ox=1)
    a.rect('px',109,1,2,6,back=False,ox=22)
    a.rect('px',109,3,2,51,back=False,ox=2)
    a.rect('px',109,14,2,15,back=False,ox=5)
    a.rect('px',109,3,2,51,back=False,ox=19)
    a.rect('px',111,24,1,6,back=False)
    # Only restore columns outside the NEW paddle. The overlap stays visible.
    a.branch('==','paddle_valid',0,'paddle_done')
    a.label('paddle_clear_left')
    a.branch('>=','drawn_px','px','paddle_clear_right')
    a.rect('drawn_px',108,1,4,restore=True)
    a.calc('drawn_px','ADD','drawn_px',1);a.jump('paddle_clear_left')
    a.label('paddle_clear_right')
    a.branch('<=','drawn_px','px','paddle_done')
    a.rect('drawn_px',108,1,4,restore=True,ox=23)
    a.calc('drawn_px','SUB','drawn_px',1);a.jump('paddle_clear_right')
    a.label('paddle_done')
    a.set('drawn_px','px');a.set('paddle_valid',1)
    a.jump('frame_wait')
    return a

def main():
    a=build();words=a.resolve();data=b''.join(w.to_bytes(4,'little') for w in words)
    (HERE/'neon_breaker.bin').write_bytes(data)
    (HERE/'neon_breaker.hex').write_text(''.join(f'{w:08x}\n' for w in words))
    (HERE/'neon_breaker.lst').write_text('\n'.join(f'{i:05d} {words[i]:08x} {op} '+', '.join(map(str,args)) for i,(op,args) in enumerate(a.code))+'\n')
    (HERE/'symbols.json').write_text(json.dumps({'labels':a.labels,'variables':V,'words':len(words)},indent=2)+'\n')
    print(f'Built {len(words)} instructions, {len(data)} bytes; 3 levels, 40 bricks, 8-color RGB111 framebuffer.')

if __name__=='__main__':main()
