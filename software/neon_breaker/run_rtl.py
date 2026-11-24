#!/usr/bin/env python3
"""Run reproducible Icarus tests from any cwd; requires iverilog/vvp in PATH."""
from pathlib import Path
import argparse, subprocess, tempfile, shutil
from prepare_rtl import main as prepare

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
SRC=ROOT/'Microcontroller_V2/Microcontroller_V2.srcs/sources_1/new'
SIM=ROOT/'Microcontroller_V2/Microcontroller_V2.srcs/sim_1/new'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--all',action='store_true',help='Also run the original 12 regression tests')
    args=parser.parse_args()
    for tool in ('iverilog','vvp'):
        if not shutil.which(tool):parser.error(f'{tool} not found; activate OSS-CAD-Suite')
    prepare();logs=HERE/'verification';logs.mkdir(exist_ok=True)
    names=['tb_gamepad_input','tb_neon_cpu','tb_neon_qspi']
    if args.all:names=sorted(p.stem for p in SIM.glob('tb_*.sv'))
    with tempfile.TemporaryDirectory(prefix='neon_rtl_') as temp:
        for name in names:
            binary=Path(temp)/(name+'.vvp')
            files=list(SRC.glob('*.sv'))+[SIM/(name+'.sv')]
            if name in ('tb_top_simple','tb_top_stress','tb_neon_qspi'):files.append(SIM/'tb_qspi_ram_simple.sv')
            with (logs/(name+'_compile.log')).open('w') as f:
                subprocess.run(['iverilog','-g2012','-s',name,'-o',str(binary),*map(str,files)],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)
            with (logs/(name+'.log')).open('w') as f:
                subprocess.run(['vvp',str(binary)],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True,timeout=600)
            result=(logs/(name+'.log')).read_text()
            if 'PASS' not in result:raise RuntimeError(f'{name}: no PASS marker')
            print(result,flush=True)
    for name in ('checkpoint_ram.hex','checkpoint_regs.hex','init_expected.hex'):
        (HERE/name).unlink(missing_ok=True)

if __name__=='__main__':main()
