#!/usr/bin/env python3
"""Select the ORIGINAL game for next power-on, without touching either Flash.
Run while V2 is still wired normally. Then power off and reconnect original
PMOD A on standard BIDIR and Tiny VGA on OUTPUT. Never rewire under power.
"""
from upload import Repl, save_durable, HERE
from pathlib import Path
import argparse, configparser, io, time

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--port');a=p.parse_args()
    if not a.port:
        ports=list(Path('/dev/serial/by-id').glob('*MicroPython*'))
        if len(ports)!=1:p.error('Connect exactly one board or use --port')
        a.port=str(ports[0])
    backup=HERE/'backups'/('switch_original_'+time.strftime('%Y%m%d_%H%M%S'));backup.mkdir(parents=True)
    r=Repl(a.port)
    try:
        old=bytes.fromhex(r.run("import os,binascii\nassert os.stat('/bitstreams/tt_um_neon_breaker.bin')[6]>50000\nprint(binascii.hexlify(open('/config.ini','rb').read()).decode())").strip())
        save_durable(backup/'config.ini',old)
        cp=configparser.ConfigParser();cp.read_string(old.decode());cp['DEFAULT']['project']='tt_um_neon_breaker'
        cp['tt_um_neon_breaker']={'mode':'ASIC_MANUAL_INPUTS','rp_clock_frequency':'126000000','clock_frequency':'25200000','start_in_reset':'no','uio_oe_pico':'0'}
        out=io.StringIO();cp.write(out)
        r.run("from machine import Pin\nfrom ttboard.demoboard import DemoBoard\nfrom ttboard.fpga import fabricfoxv2\nfrom ttboard.pins.gpio_map import GPIOMap\ntt=DemoBoard.get()\ntt.clock_project_stop()\nGPIOMap.get_raw_pin(fabricfoxv2.pin_indices()['reset'],Pin.OUT).value(0)")
        r.run("v=binascii.unhexlify('"+out.getvalue().encode().hex()+"')\nf=open('/config.ini.switch.tmp','wb')\nf.write(v)\nf.close()\nassert open('/config.ini.switch.tmp','rb').read()==v\nos.rename('/config.ini.switch.tmp','/config.ini')\nos.sync()")
        print('Original selected for NEXT BOOT. FPGA held in reset. POWER OFF, restore original wiring with PMOD A, then power on.')
    finally:r.close()

if __name__=='__main__':main()
