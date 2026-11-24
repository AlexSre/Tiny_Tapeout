"""Regression: observe every framebuffer STORE executed by the CPU program."""
from check_game import Machine
from build_game import BG, PALETTE

class ObservedMachine(Machine):
    def __init__(self):
        super().__init__();self.paddle_writes=[]
    def step(self):
        w=self.words[self.pc]
        if w>>22==8:
            addr=self.regs[(w>>12)&31]
            if addr is not None and 108*160 <= addr < 112*160:
                self.paddle_writes.append((addr,self.regs[(w>>17)&31]&7))
        super().step()

def verify(m):
    px=m.get('px')
    rows=[[6]+[63]*22+[6], [6]*2+[51]*3+[15]*14+[51]*3+[6]*2,
          [6]*2+[51]*3+[15]*14+[51]*3+[6]*2, [6]*24]
    rows=[[PALETTE[c] for c in row] for row in rows]
    for y in range(108,112):
        for x in range(160):
            expected=rows[y-108][x-px] if px<=x<px+24 else m.memory[BG+y*160+x]
            assert m.memory[y*160+x]==expected,(x,y,px)
    # At no point may the new paddle area be erased or painted an intermediate color.
    for addr,color in m.paddle_writes:
        y,x=divmod(addr,160)
        if px<=x<px+24:
            assert color==rows[y-108][x-px],('transient paddle color',x,y,color)

m=ObservedMachine().start();m.paddle_writes=[];verify(m)
for buttons in [128]*4+[129]*70+[128]*4+[130]*90+[131]*4+[128]*4:
    m.paddle_writes=[];m.frame(buttons);verify(m)
print('PASS paddle: every STORE checked; stationary, both directions, one-pixel clamps, simultaneous buttons; exact sprite and restored background')
m.set('level',2);m.pc=m.labels['new_level'];m.paddle_writes=[];m.until('frame_wait')
m.paddle_writes=[];verify(m)
print('PASS paddle redraw after level background reset')
