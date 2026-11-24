#!/usr/bin/env python3
"""Execute the emitted CPU words, not a reimplementation of the game rules."""
from pathlib import Path
import json, struct, argparse
from build_game import V, HP, BG

HERE=Path(__file__).resolve().parent
class Machine:
    def __init__(self):
        data=(HERE/'neon_breaker.bin').read_bytes()
        self.words=list(struct.unpack('<'+'I'*(len(data)//4),data))
        self.labels=json.loads((HERE/'symbols.json').read_text())['labels']
        self.regs=[None]*16;self.memory=[None]*131072
        self.pc=0;self.instructions=0;self.buttons=128;self.vsync=1
        self.writes=0;self.accesses=0;self.score=0
    def step(self):
        assert 0<=self.pc<len(self.words),f'PC {self.pc}'
        w=self.words[self.pc];op=w>>22;rd=(w>>17)&31;ra=(w>>12)&31;rb=(w>>7)&31;imm=w&131071
        self.pc+=1;self.instructions+=1
        r=self.regs
        if op==6:r[rd]=imm
        elif op<=5:
            assert r[ra] is not None and r[rb] is not None,'uninitialized operand'
            x,y=r[ra],r[rb]
            r[rd]=[lambda:x+y,lambda:x-y,lambda:x&y,lambda:x|y,lambda:x^y,lambda:x*y][op]()&0xffffffff
        elif op in (7,8):
            assert r[ra] is not None
            addr=r[ra]&131071;self.accesses+=1
            if op==8:
                assert r[rd] is not None
                if addr==0x1fffd:self.score=r[rd]
                else:
                    assert addr<19200 or 0x5000<=addr<0xcb00,hex(addr)
                    self.memory[addr]=r[rd]&7 if addr<19200 else r[rd]
                    if addr<19200:self.writes+=1
            elif addr==0x1ffff:r[rd]=self.buttons
            elif addr==0x1fffe:r[rd]=self.vsync
            elif addr==0x1fffd:r[rd]=self.score
            else:
                assert self.memory[addr] is not None,f'uninitialized load {addr:x} at PC {self.pc-1}'
                r[rd]=self.memory[addr]
        elif op==9:self.pc=imm
        elif op==10:
            assert r[rd] is not None
            if r[rd]==0:self.pc=imm
        else:raise AssertionError(f'opcode {op}')
    def until(self,label,limit=1000000):
        target=self.labels[label]
        for _ in range(limit):
            if self.pc==target:return
            self.step()
        raise AssertionError(f'Cannot reach {label}, pc={self.pc}')
    def start(self):self.until('frame_wait');return self
    def get(self,n):return self.memory[V[n]]
    def set(self,n,v):self.memory[V[n]]=v&0xffffffff
    def frame(self,buttons=128):
        assert self.pc==self.labels['frame_wait']
        self.buttons=buttons;self.vsync=1
        self.until('wait_low');self.vsync=0
        self.until('frame');self.vsync=1
        before=self.instructions;access=self.accesses;writes=self.writes
        self.step();self.until('frame_wait')
        return self.instructions-before,self.accesses-access,self.writes-writes
    def snapshot(self,name):
        # PPM is dependency-free. PNG conversion below is optional for previews.
        pixels=bytes(component*255 for c in self.memory[:19200] for component in ((c>>2)&1,(c>>1)&1,c&1))
        (HERE/(name+'.ppm')).write_bytes(b'P6\n160 120\n255\n'+pixels)
        try:
            from PIL import Image
            Image.frombytes('RGB',(160,120),pixels).resize((800,600),Image.Resampling.NEAREST).save(HERE/(name+'.png'))
        except ImportError:pass

def test():
    m=Machine().start();assert m.get('remain')==40 and m.get('mode')==0
    assert all(v is not None for v in m.memory[:19200])
    m.snapshot('preview_ready');print('PASS initialization, backing image, all 40 bricks')
    for _ in range(70):m.frame(129)
    assert m.get('px')==9
    for _ in range(90):m.frame(130)
    assert m.get('px')==127
    m.frame(128);m.frame(144);assert m.get('mode')==1
    print('PASS left/right clamps and launch edge')
    m.frame(128);m.frame(160);assert m.get('mode')==2
    position=(m.get('x'),m.get('y'))
    for _ in range(5):m.frame(160)
    assert (m.get('x'),m.get('y'))==position
    m.frame(128);m.frame(160);assert m.get('mode')==1
    print('PASS pause, held START does not toggle, resume')
    # Targeted boundary conditions through actual machine instructions.
    m.set('x',10);m.set('y',85);m.set('dx',-1);m.set('dy',-1);m.frame()
    assert m.get('dx')==1
    m.set('px',60);m.set('x',64);m.set('y',105);m.set('dx',1);m.set('dy',1);m.frame()
    assert m.get('dy')==0xffffffff and m.get('dx')==0xffffffff
    print('PASS wall and paddle collision / steering')
    m.set('x',20);m.set('y',72);m.set('dx',1);m.set('dy',-1)
    before=m.get('remain');m.frame()
    assert m.get('remain')==before-1 and m.memory[HP+32]==0 and m.score==1
    print('PASS brick collision, destruction, score and RAM state')
    m.snapshot('preview_play')
    # Natural play: follow the ball for multiple rallies, no state injection.
    m=Machine().start();m.frame(144)
    worst=(0,0,0);hits=0
    for i in range(1800):
        center=m.get('px')+12;x=m.get('x')
        buttons=128|(1 if x<center-1 else 2 if x>center+1 else 0)
        if m.get('mode')==0:buttons|=16 if i%2==0 else 0
        stats=m.frame(buttons)
        if stats[0]<20000 and stats[0]>worst[0]:worst=stats
        if i==250:m.snapshot('preview_rally')
    assert m.get('lives')>0 and m.score>=8,(m.get('lives'),m.score)
    print('PASS 1800 natural-play updates, hits=',m.score,'worst instructions/accesses/pixels=',worst)
    # Multi-hit brick / level transition / final victory.
    m=Machine().start();m.set('level',2);m.pc=m.labels['new_level'];m.until('frame_wait')
    assert m.memory[HP+32]==2
    m.frame(144);m.set('x',20);m.set('y',72);m.set('dx',1);m.set('dy',-1);m.frame()
    assert m.memory[HP+32]==1 and m.get('remain')==40
    m.set('x',20);m.set('y',72);m.set('dx',1);m.set('dy',-1);m.set('remain',1);m.frame()
    assert m.get('level')==3 and m.get('mode')==0 and m.get('remain')==40
    m.frame();m.frame(144);m.memory[HP+32]=1;m.set('remain',1)
    m.set('x',20);m.set('y',72);m.set('dx',1);m.set('dy',-1);m.frame()
    assert m.get('mode')==4;m.snapshot('preview_win')
    m.frame();m.frame(144);assert m.get('level')==1 and m.score==0
    print('PASS multi-hit bricks, level advance, victory and replay')
    m.frame();m.frame(144);m.set('lives',1);m.set('x',12);m.set('y',111);m.set('dy',1);m.frame()
    assert m.get('mode')==3
    m.frame();m.frame(144);assert m.get('lives')==3 and m.get('mode')==0
    m.frame(192);assert m.get('mode')==0
    print('PASS life loss, game over, retry and SELECT restart')
    (HERE/'software_test_results.txt').write_text('PASS encoded-ISA execution: initialization, bounds, controls, pause, collisions, scoring, 1800 natural-play updates, multi-hit bricks, levels, victory, game over, retry.\nWorst sampled update (instructions, accesses, framebuffer writes): '+str(worst)+'\nTiming is measured separately in RTL; this interpreter is functional only.\n')

if __name__=='__main__':test()
