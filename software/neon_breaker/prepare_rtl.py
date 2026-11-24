#!/usr/bin/env python3
"""Regenerate RTL test fixtures from the built image. Run before RTL tests."""
from check_game import Machine, HERE
from build_game import V

def main():
    m=Machine().start()
    (HERE/'init_expected.hex').write_text(''.join(f'{(x if x is not None else 0xdeadbeef):08x}\n' for x in m.memory))
    m.frame(144)
    while m.get('y')>77:m.frame()
    physical=bytearray(262144)
    for addr,v in enumerate(m.memory):
        if v is None:continue
        if addr<19200:physical[addr]=v
        else:physical[addr*4:addr*4+4]=v.to_bytes(4,'little')
    (HERE/'checkpoint_ram.hex').write_text(''.join(f'{v:02x}\n' for v in physical))
    (HERE/'checkpoint_regs.hex').write_text(''.join(f'{(v or 0):08x}\n' for v in m.regs))
    constants={'NEON_WORDS':len(m.words),'NEON_FRAME_PC':m.labels['frame'],
               'NEON_WAIT_PC':m.labels['frame_wait'],'NEON_X':V['x'],'NEON_Y':V['y'],'NEON_PX':V['px']}
    (HERE/'test_constants.vh').write_text(''.join(f'`define {k} {v}\n' for k,v in constants.items()))
    print('RTL fixtures prepared: cold boot expectation and valid mid-game checkpoint.')

if __name__=='__main__':main()
