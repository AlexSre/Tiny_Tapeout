#!/usr/bin/env python3
"""Linux USB uploader for TTDBv3/FabricFox, using only Python's standard library.

Stages the V2 game via STANDARD BIDIR wiring and selects the next-boot image.
Leaves FPGA held in reset: POWER OFF and REWIRE V2 before restarting.
Every touched Flash sector and config.ini are backed up locally BEFORE mutation.
Close Commander/Flasher/serial terminals before running. Do not remove power
while this tool is writing. No bootloader or MicroPython firmware is changed.
"""
import argparse, configparser, fcntl, hashlib, io, json, os
from pathlib import Path
import select, termios, time

HERE=Path(__file__).resolve().parent
NAME='tt_um_neon_breaker_v2'

class Repl:
    def __init__(self,port):
        self.fd=os.open(port,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
        self.old=termios.tcgetattr(self.fd)
        try:
            fcntl.ioctl(self.fd,termios.TIOCEXCL)
            c=termios.tcgetattr(self.fd)
            c[0]=c[1]=c[3]=0;c[2]=termios.CS8|termios.CREAD|termios.CLOCAL
            c[4]=c[5]=termios.B115200
            termios.tcsetattr(self.fd,termios.TCSANOW,c)
            self.send(b'\x03\x03\x02');self.read(.3)
            self.send(b'\x01')
            if b'raw REPL' not in self.read(.5):raise RuntimeError('Cannot enter MicroPython raw REPL')
        except BaseException:
            self.close();raise
    def send(self,data):
        while data:
            if not select.select([],[self.fd],[],5)[1]:raise TimeoutError('Serial write timeout')
            try:n=os.write(self.fd,data[:256])
            except BlockingIOError:continue
            data=data[n:];time.sleep(.002)
    def read(self,seconds):
        data=b'';end=time.monotonic()+seconds
        while time.monotonic()<end:
            if select.select([self.fd],[],[],max(0,end-time.monotonic()))[0]:
                try:
                    part=os.read(self.fd,65536)
                    if not part:break
                    data+=part
                except BlockingIOError:pass
        return data
    def run(self,code,timeout=30):
        self.send(code.encode('ascii')+b'\x04')
        result=b'';end=time.monotonic()+timeout
        while time.monotonic()<end:
            result+=self.read(.05)
            if result.count(b'\x04')>=2 and result.endswith(b'>'):break
        else:raise TimeoutError('Board command timed out: '+repr(result[-400:]))
        if not result.startswith(b'OK'):raise RuntimeError(repr(result))
        out,err,_=result[2:].split(b'\x04',2)
        if err:raise RuntimeError(out.decode(errors='replace')+err.decode(errors='replace'))
        return out.decode()
    def close(self):
        try:os.write(self.fd,b'\x02')
        except OSError:pass
        try:termios.tcsetattr(self.fd,termios.TCSANOW,self.old)
        except OSError:pass
        try:fcntl.ioctl(self.fd,termios.TIOCNXCL)
        except OSError:pass
        os.close(self.fd)

FLASH_SETUP=r'''
from machine import Pin,SoftSPI
from ttboard.fpga import fabricfoxv2
from ttboard.pins.gpio_map import GPIOMap
tt.clock_project_stop()
fpga_reset=GPIOMap.get_raw_pin(fabricfoxv2.pin_indices()['reset'],Pin.OUT)
fpga_reset.value(0)
time.sleep_ms(20)
cs=tt.pins.uio0.raw_pin
cs.init(Pin.OUT,value=1)
tt.pins.uio6.raw_pin.init(Pin.OUT,value=1)
tt.pins.uio7.raw_pin.init(Pin.OUT,value=1)
tt.pins.uio4.raw_pin.init(Pin.IN,Pin.PULL_UP)
tt.pins.uio5.raw_pin.init(Pin.IN,Pin.PULL_UP)
spi=SoftSPI(baudrate=100000,polarity=0,phase=0,sck=tt.pins.uio3.raw_pin,mosi=tt.pins.uio1.raw_pin,miso=tt.pins.uio2.raw_pin)
def command(data,n=0):
 cs.value(0)
 try:
  spi.write(data)
  return spi.read(n) if n else None
 finally:cs.value(1)
def ready():
 start=time.ticks_ms()
 while command(bytes([5]),1)[0]&1:
  if time.ticks_diff(time.ticks_ms(),start)>10000:raise RuntimeError('Flash busy timeout')
  time.sleep_ms(1)
def addr_cmd(op,addr):return bytes([op,(addr>>16)&255,(addr>>8)&255,addr&255])
def wren():
 command(bytes([6]))
 assert command(bytes([5]),1)[0]&2,'Flash WEL not set'
command(bytes([171]));time.sleep_ms(1)
assert command(bytes([159]),3)==bytes([239,112,24]),'Expected Flash JEDEC EF7018'
ready()
assert command(bytes([5]),1)[0]&124==0,'Flash block protection active'
'''
FLASH_RELEASE="cs.value(1)\nspi.deinit()\nfor i in range(8):getattr(tt.pins,'uio%d'%i).raw_pin.init(Pin.IN)"

def save_durable(path,data):
    with path.open('xb') as f:f.write(data);f.flush();os.fsync(f.fileno())

def upload_file(r,name,data):
    path='/bitstreams/'+name+'.bin'
    r.run("f=open("+repr(path+'.tmp')+",'wb')")
    for pos in range(0,len(data),1024):
        block=data[pos:pos+1024]
        r.run("assert f.write(binascii.unhexlify('"+block.hex()+"'))=="+str(len(block)))
    digest=hashlib.sha256(data).hexdigest()
    r.run("f.close()\nh=hashlib.sha256()\nf=open("+repr(path+'.tmp')+",'rb')\nwhile True:\n b=f.read(1024)\n if not b:break\n h.update(b)\nf.close()\nassert binascii.hexlify(h.digest()).decode()=='"+digest+"'\nos.rename("+repr(path+'.tmp')+','+repr(path)+")\nos.sync()")
    print('FPGA image copied and SHA256 verified.',flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port',help='Prefer /dev/serial/by-id/...; autodetects a single MicroPython board')
    p.add_argument('--program',type=Path,default=HERE/'neon_breaker.bin')
    p.add_argument('--bitstream',type=Path,default=HERE/'tt_um_neon_breaker_v2.bin')
    p.add_argument('--staging-wiring-confirmed', action='store_true', help='Flash PMOD alone on standard BIDIR, V2 wiring disconnected')
    args=p.parse_args()
    if not args.staging_wiring_confirmed:p.error('Use --staging-wiring-confirmed only after following TESTARE.txt: Flash PMOD on standard BIDIR; no V2 wiring')
    program=args.program.read_bytes();bitstream=args.bitstream.read_bytes()
    if not program or len(program)%4 or len(program)>524288:p.error('Invalid CPU image size')
    if not bitstream or len(bitstream)<50000:p.error('Invalid FPGA image size')
    if not args.port:
        ports=list(Path('/dev/serial/by-id').glob('*MicroPython*'))
        if len(ports)!=1:p.error('Connect the board by USB, or specify --port')
        args.port=str(ports[0])
    backup=HERE/'backups'/time.strftime('%Y%m%d_%H%M%S');backup.mkdir(parents=True,exist_ok=False)
    r=Repl(args.port);flash_open=False
    try:
        config_hex=r.run("import os,time,binascii,hashlib\nfrom ttboard.demoboard import DemoBoard\ntt=DemoBoard.get()\nassert tt.shuttle.run=='FPGA'\nprint('CONFIG='+binascii.hexlify(open('/config.ini','rb').read()).decode())")
        config=bytes.fromhex(config_hex.split('CONFIG=')[1].splitlines()[0])
        save_durable(backup/'config.ini',config)
        upload_file(r,NAME,bitstream)
        # Read and persist ALL sectors before the first erase, preserving the tail.
        flash_open=True;r.run(FLASH_SETUP)
        size=(len(program)+4095)//4096*4096
        original=bytearray()
        for addr in range(0,size,4096):
            value=r.run(f"print(binascii.hexlify(command(addr_cmd(3,{addr}),4096)).decode())")
            block=bytes.fromhex(value.strip());assert len(block)==4096;original.extend(block)
        save_durable(backup/'flash_original.bin',original)
        save_durable(backup/'manifest.json',json.dumps({'offset':0,'length':size,'program_sha256':hashlib.sha256(program).hexdigest(),'bitstream_sha256':hashlib.sha256(bitstream).hexdigest()},indent=2).encode())
        expected=program+original[len(program):]
        for addr in range(0,size,4096):
            sector=expected[addr:addr+4096]
            if sector==original[addr:addr+4096]:continue
            r.run(f"assert command(addr_cmd(3,{addr}),4096)==binascii.unhexlify('{original[addr:addr+4096].hex()}')\nwren()\ncommand(addr_cmd(32,{addr}))\nready()\nassert command(addr_cmd(3,{addr}),4096)==bytes([255])*4096")
            for offset in range(0,4096,256):
                page=sector[offset:offset+256]
                if page==bytes([255])*256:continue
                r.run(f"wren()\ncommand(addr_cmd(2,{addr+offset})+binascii.unhexlify('{page.hex()}'))\nready()")
            actual=bytes.fromhex(r.run(f"print(binascii.hexlify(command(addr_cmd(3,{addr}),4096)).decode())").strip())
            if actual!=sector:raise RuntimeError(f'Sector verification failed at {addr:#x}; backup: {backup}')
            print(f'Flash sector {addr//4096+1}/{size//4096} written and read back.',flush=True)
        r.run(FLASH_RELEASE);flash_open=False
        cp=configparser.ConfigParser();cp.read_string(config.decode())
        cp['DEFAULT']['project']=NAME
        cp[NAME]={'mode':'ASIC_MANUAL_INPUTS','rp_clock_frequency':'126000000','clock_frequency':'25200000','start_in_reset':'no','uio_oe_pico':'0'}
        stream=io.StringIO();cp.write(stream);updated=stream.getvalue().encode()
        r.run("config=binascii.unhexlify('"+updated.hex()+"')\nf=open('/config.ini.neon.tmp','wb')\nf.write(config)\nf.close()\nassert open('/config.ini.neon.tmp','rb').read()==config\nos.rename('/config.ini.neon.tmp','/config.ini')\nos.sync()")
        print('Written and verified. FPGA HELD IN RESET. Disconnect USB/power, rewire V2 per TESTARE.txt, then power on. Backups:',backup,flush=True)
    finally:
        if flash_open:
            try:r.run(FLASH_RELEASE)
            except Exception:pass
        r.close()
if __name__=='__main__':main()
