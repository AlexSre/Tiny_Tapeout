#!/usr/bin/env python3
"""Build only; never programs hardware. Supply the PCF for the confirmed board."""
from pathlib import Path
import argparse, shutil, subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pcf', type=Path, required=True, help='Verified pin constraints for this board revision')
    args = parser.parse_args()
    pcf = args.pcf.resolve()
    if not pcf.is_file(): parser.error('PCF file not found')
    for tool in ['yosys', 'nextpnr-ice40', 'icepack']:
        if not shutil.which(tool): parser.error(f'{tool} missing; activate OSS-CAD-Suite first')
    here = Path(__file__).resolve().parent
    src = here.parent / 'Microcontroller_V2/Microcontroller_V2.srcs/sources_1/new'
    names = ['cpu_core','input_sync','memory_map','qspi_clock','qspi_flash_controller','qspi_ram_controller','ram_arbiter','top','vga_timing','video_line_buffer']
    files = [here/'tt_fpga_top.v'] + [src/(name+'.sv') for name in names]
    if not all(p.is_file() for p in files): parser.error('Missing RTL source')
    build = here/'build'; build.mkdir(exist_ok=True)
    def quote(path): return '"'+str(path).replace('\\','\\\\').replace('"','\\"')+'"'
    script = build/'synth.ys'
    script.write_text('read_verilog -sv '+' '.join(quote(p) for p in files)+'\nsynth_ice40 -dsp -top tt_fpga_top -json '+quote(build/'design.json')+'\ncheck -assert\nstat\n')
    image = build/'tt_um_microcontroller_v2.bin'
    # A previous image must not be mistaken for a newly successful build.
    if image.exists(): image.unlink()
    subprocess.run(['yosys','-DSYNTH','-l',str(build/'synth.log'),'-s',str(script)],check=True)
    subprocess.run(['nextpnr-ice40','--up5k','--package','sg48','--json',str(build/'design.json'),'--pcf',str(pcf),'--asc',str(build/'design.asc'),'--freq','25.25','--seed','10','--report',str(build/'timing.json'),'--log',str(build/'nextpnr.log')],check=True)
    subprocess.run(['icepack',str(build/'design.asc'),str(image)],check=True)
    print('Bitstream ready:',image)

if __name__=='__main__': main()
